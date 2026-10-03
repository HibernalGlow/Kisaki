use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::thread;

use czkawka_core::common::fs_ops::{remove_folder_if_contains_only_empty_folders, remove_single_file, remove_single_folder};
use czkawka_core::common::model::ToolType;

use crate::api::types::{DeleteOutcome, DeleteRequest, ExportRequest, ScanRow, ToolSpec};
use crate::engine::registry;

/// What a delete run decides to do with one requested row.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Role {
    Delete,
    SkipReference,
    SpareKeeper,
}

/// How a logged row contributes to the reported counters.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Disposition {
    Planned,
    Removed,
    Failed,
    Protected,
}

/// Deletes or trashes rows through the engine's own file operations so trash behaviour matches
/// the other frontends. Ported from the Slint frontend's action module.
pub fn delete(request: DeleteRequest) -> Result<DeleteOutcome, String> {
    let tool_type = registry::tool_type(&request.tool).ok_or_else(|| format!("Unknown scanner '{}'", request.tool))?;
    let roles = classify(&request.rows);

    if request.dry_run {
        // The plan is built from row data alone: no path is stat'd, opened or modified.
        let results: Vec<Option<Result<(), String>>> = (0..request.rows.len()).map(|_| None).collect();
        return Ok(assemble(&request, &roles, &results));
    }

    let targets: Vec<usize> = roles.iter().enumerate().filter(|(_, role)| **role == Role::Delete).map(|(index, _)| index).collect();
    let folders = matches!(tool_type, ToolType::EmptyFolders);
    let removals = remove_rows(&request.rows, &targets, folders, request.delete_to_trash);

    let mut results: Vec<Option<Result<(), String>>> = (0..request.rows.len()).map(|_| None).collect();
    for (index, result) in removals {
        if let Some(slot) = results.get_mut(index) {
            *slot = Some(result);
        }
    }
    Ok(assemble(&request, &roles, &results))
}

/// Reference rows are read-only and only counted, never removed. A group without a reference row
/// spares one copy - the largest member, ties going to the first of them - which is the same split
/// `engine::convert` prices as reclaimable, so `reclaimed_bytes` can never overstate a run.
fn classify(rows: &[ScanRow]) -> Vec<Role> {
    let mut roles: Vec<Role> = rows.iter().map(|row| if row.is_reference { Role::SkipReference } else { Role::Delete }).collect();
    let mut keepers: HashMap<i32, (usize, i64)> = HashMap::new();
    let mut referenced: HashSet<i32> = HashSet::new();

    for (index, row) in rows.iter().enumerate() {
        if row.is_reference {
            if row.group_index >= 0 {
                referenced.insert(row.group_index);
            }
            continue;
        }
        // Rows without a group belong to a flat tool, where every result is reclaimable.
        if row.group_index < 0 {
            continue;
        }
        let keep_current = keepers.get(&row.group_index).is_some_and(|(_, size)| *size >= row.size_bytes);
        if !keep_current {
            keepers.insert(row.group_index, (index, row.size_bytes));
        }
    }

    for (group, (keeper, _)) in keepers {
        if referenced.contains(&group) {
            continue;
        }
        if let Some(role) = roles.get_mut(keeper) {
            *role = Role::SpareKeeper;
        }
    }
    roles
}

/// Removes targets on several threads because deletion is I/O bound, and returns one result per
/// attempted row index. A panicked worker is reported as a failure for its whole chunk, so its
/// bytes can never be counted as freed.
fn remove_rows(rows: &[ScanRow], targets: &[usize], folders: bool, to_trash: bool) -> Vec<(usize, Result<(), String>)> {
    if targets.is_empty() {
        return Vec::new();
    }
    let chunk_size = targets.len().div_ceil(worker_count(targets.len()));
    let chunks: Vec<Vec<usize>> = targets.chunks(chunk_size).map(<[usize]>::to_vec).collect();
    let mut removals: Vec<(usize, Result<(), String>)> = Vec::with_capacity(targets.len());

    thread::scope(|scope| {
        let handles: Vec<_> = chunks
            .iter()
            .map(|chunk| {
                let job = chunk.clone();
                scope.spawn(move || {
                    job.into_iter()
                        .filter_map(|index| rows.get(index).map(|row| (index, remove_row(row, folders, to_trash))))
                        .collect::<Vec<(usize, Result<(), String>)>>()
                })
            })
            .collect();

        for (chunk, handle) in chunks.iter().zip(handles) {
            match handle.join() {
                Ok(reported) => removals.extend(reported),
                Err(_) => removals.extend(chunk.iter().map(|&index| (index, Err("deletion worker panicked".to_string())))),
            }
        }
    });

    removals
}

fn worker_count(items: usize) -> usize {
    let cpus = thread::available_parallelism().map(|count| count.get()).unwrap_or(1);
    items.min(cpus).max(1)
}

/// Same dispatch the Slint frontend uses: empty folder results go through the engine's emptiness
/// check, and anything that is a directory on disk is removed recursively instead of as a file.
fn remove_row(row: &ScanRow, folders: bool, to_trash: bool) -> Result<(), String> {
    let path = Path::new(&row.path);
    let text = path.to_string_lossy().to_string();
    if folders {
        return remove_folder_if_contains_only_empty_folders(&text, to_trash);
    }
    if path.is_dir() { remove_single_folder(&text, to_trash) } else { remove_single_file(path, to_trash) }
}

/// Turns per-row decisions into the reported outcome: one log line per row, in request order.
fn assemble(request: &DeleteRequest, roles: &[Role], results: &[Option<Result<(), String>>]) -> DeleteOutcome {
    let mut log = Vec::with_capacity(request.rows.len());
    let mut affected = 0_i32;
    let mut errors = 0_i32;
    let mut reclaimed_bytes = 0_i64;

    for ((index, row), result) in request.rows.iter().enumerate().zip(results) {
        let role = roles.get(index).copied().unwrap_or(Role::Delete);
        let line = log_line(request, row, role, result.as_ref());
        match line.1 {
            Disposition::Planned | Disposition::Removed => {
                affected += 1;
                reclaimed_bytes = reclaimed_bytes.saturating_add(row.size_bytes.max(0));
            }
            Disposition::Failed => errors += 1,
            Disposition::Protected => {}
        }
        log.push(line.0);
    }

    DeleteOutcome {
        affected,
        errors,
        reclaimed_bytes,
        messages: summarize(request, roles, affected, errors, reclaimed_bytes),
        log,
    }
}

fn log_line(request: &DeleteRequest, row: &ScanRow, role: Role, result: Option<&Result<(), String>>) -> (String, Disposition) {
    match role {
        Role::SkipReference => (format!("Skipped reference {}", row.name), Disposition::Protected),
        Role::SpareKeeper => (format!("Kept one copy {}", row.name), Disposition::Protected),
        Role::Delete => match (request.dry_run, result) {
            (true, _) => (format!("{} {}", action(request.delete_to_trash, true), row.name), Disposition::Planned),
            (false, Some(Ok(()))) => (format!("{} {}", action(request.delete_to_trash, false), row.name), Disposition::Removed),
            (false, Some(Err(error))) => (format!("Failed to {} \"{}\": {error}", plain(request.delete_to_trash), row.path), Disposition::Failed),
            (false, None) => (
                format!("Failed to {} \"{}\": removal was not attempted", plain(request.delete_to_trash), row.path),
                Disposition::Failed,
            ),
        },
    }
}

fn action(to_trash: bool, planned: bool) -> &'static str {
    match (to_trash, planned) {
        (true, true) => "Would trash",
        (true, false) => "Trashed",
        (false, true) => "Would delete",
        (false, false) => "Deleted",
    }
}

fn plain(to_trash: bool) -> &'static str {
    if to_trash { "trash" } else { "delete" }
}

fn summarize(request: &DeleteRequest, roles: &[Role], affected: i32, errors: i32, reclaimed_bytes: i64) -> String {
    let action = action(request.delete_to_trash, request.dry_run);
    let mut text = format!("{action} {affected} items, {} ({reclaimed_bytes} bytes)", human_size(reclaimed_bytes));
    let references = count_role(roles, Role::SkipReference);
    let spared = count_role(roles, Role::SpareKeeper);
    if references > 0 {
        text = format!("{text}, {references} reference rows kept");
    }
    if spared > 0 {
        text = format!("{text}, {spared} group keepers spared");
    }
    if errors > 0 {
        text = format!("{text}, {errors} failed");
    }
    text
}

fn count_role(roles: &[Role], role: Role) -> usize {
    roles.iter().filter(|current| **current == role).count()
}

/// Binary units, matching the size column the frontends show. `humansize` is not a dependency of
/// this crate, so the formatting lives here.
fn human_size(bytes: i64) -> String {
    const UNITS: [&str; 5] = ["B", "KiB", "MiB", "GiB", "TiB"];
    let mut value = bytes.unsigned_abs() as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit + 1 < UNITS.len() {
        value /= 1024.0;
        unit += 1;
    }
    let number = if unit == 0 { format!("{value:.0}") } else { format!("{value:.1}") };
    let sign = if bytes < 0 { "-" } else { "" };
    format!("{sign}{number} {}", UNITS[unit])
}

/// Writes the result set as JSON or CSV. The engine's `PrintResults` implementations only see
/// their own private result fields, which cannot be rebuilt from rows crossing the FFI, so the
/// document is written from the rows themselves in the same grouped or flat shape.
pub fn export(request: ExportRequest) -> Result<String, String> {
    let spec = registry::spec(&request.tool).ok_or_else(|| format!("Unknown scanner '{}'", request.tool))?;
    let format = parse_format(&request.format, &request.tool)?;
    if request.rows.is_empty() {
        return Err(format!("Scanner '{}' has no rows to export", request.tool));
    }

    let document = match format {
        Format::Json => json_document(&request),
        Format::Csv => csv_document(&request, &spec),
    };
    let destination = resolve_destination(&request.path, format, &request.tool);
    write_document(&destination, &document, &request.tool)?;
    Ok(destination.to_string_lossy().into_owned())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Format {
    Json,
    Csv,
}

impl Format {
    fn extension(self) -> &'static str {
        match self {
            Self::Json => "json",
            Self::Csv => "csv",
        }
    }
}

fn parse_format(text: &str, tool: &str) -> Result<Format, String> {
    match text.trim().to_lowercase().as_str() {
        "json" => Ok(Format::Json),
        "csv" => Ok(Format::Csv),
        other => Err(format!("Scanner '{tool}' cannot export as \"{other}\", supported formats are json and csv")),
    }
}

/// The Slint frontend picked a folder and generated the file names itself, so a folder destination
/// keeps that behaviour instead of failing to open a directory as a file.
fn resolve_destination(path: &str, format: Format, tool: &str) -> PathBuf {
    let destination = PathBuf::from(path);
    if destination.is_dir() {
        return destination.join(format!("kisaki_{tool}.{}", format.extension()));
    }
    destination
}

fn write_document(destination: &Path, document: &str, tool: &str) -> Result<(), String> {
    let display = destination.to_string_lossy().to_string();
    let file = File::create(destination).map_err(|error| write_error(tool, &display, &error))?;
    let mut writer = BufWriter::new(file);
    writer.write_all(document.as_bytes()).map_err(|error| write_error(tool, &display, &error))?;
    writer.flush().map_err(|error| write_error(tool, &display, &error))
}

fn write_error(tool: &str, destination: &str, error: &std::io::Error) -> String {
    format!("Scanner '{tool}' failed to write the export to \"{destination}\": {error}")
}

/// Groups rows by `group_index` in first-seen order; rows without a group become single item groups.
fn group_rows(rows: &[ScanRow]) -> Vec<Vec<&ScanRow>> {
    let mut groups: Vec<Vec<&ScanRow>> = Vec::new();
    let mut positions: HashMap<i32, usize> = HashMap::new();
    for row in rows {
        if row.group_index < 0 {
            groups.push(vec![row]);
            continue;
        }
        match positions.get(&row.group_index) {
            Some(index) => groups[*index].push(row),
            None => {
                positions.insert(row.group_index, groups.len());
                groups.push(vec![row]);
            }
        }
    }
    groups
}

fn json_document(request: &ExportRequest) -> String {
    let mut text = String::from("{\n");
    text.push_str(&format!("  \"tool\": {},\n", json_string(&request.tool)));
    text.push_str(&format!("  \"grouped\": {},\n", request.grouped));
    text.push_str(&format!("  \"row_count\": {},\n", request.rows.len()));

    if request.grouped {
        let groups = group_rows(&request.rows);
        text.push_str(&format!("  \"group_count\": {},\n", groups.len()));
        text.push_str("  \"groups\": [\n");
        for (position, group) in groups.iter().enumerate() {
            let index = group.first().copied().map_or(-1, |row| i64::from(row.group_index));
            text.push_str("    {\n");
            text.push_str(&format!("      \"index\": {index},\n"));
            text.push_str(&format!("      \"size\": {},\n", group.len()));
            text.push_str("      \"rows\": [\n");
            text.push_str(&json_rows(group, 8));
            text.push_str("      ]\n");
            text.push_str("    }");
            if position + 1 < groups.len() {
                text.push(',');
            }
            text.push('\n');
        }
        text.push_str("  ]\n");
    } else {
        let rows: Vec<&ScanRow> = request.rows.iter().collect();
        text.push_str("  \"rows\": [\n");
        text.push_str(&json_rows(&rows, 4));
        text.push_str("  ]\n");
    }

    text.push_str("}\n");
    text
}

fn json_rows(rows: &[&ScanRow], indent: usize) -> String {
    let padding = " ".repeat(indent);
    let mut text = String::new();
    for (position, row) in rows.iter().copied().enumerate() {
        text.push_str(&padding);
        text.push_str(&json_row(row));
        if position + 1 < rows.len() {
            text.push(',');
        }
        text.push('\n');
    }
    text
}

fn json_row(row: &ScanRow) -> String {
    let cells: Vec<String> = row.cells.iter().map(|cell| json_string(cell)).collect();
    format!(
        "{{\"path\": {}, \"name\": {}, \"directory\": {}, \"cells\": [{}], \"size_bytes\": {}, \"modified_ts\": {}, \"group_index\": {}, \"group_size\": {}, \"is_group_start\": {}, \"is_reference\": {}}}",
        json_string(&row.path),
        json_string(&row.name),
        json_string(&row.directory),
        cells.join(", "),
        row.size_bytes,
        row.modified_ts,
        row.group_index,
        row.group_size,
        row.is_group_start,
        row.is_reference
    )
}

fn json_string(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for character in text.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            control if (control as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", control as u32)),
            other => out.push(other),
        }
    }
    out.push('"');
    out
}

fn csv_document(request: &ExportRequest, spec: &ToolSpec) -> String {
    let headers = csv_headers(request, spec);
    let cell_width = headers.len().saturating_sub(if request.grouped { 7 } else { 6 });
    let mut text = headers.join(",");
    text.push('\n');

    let groups: Vec<Vec<&ScanRow>> = if request.grouped {
        group_rows(&request.rows)
    } else {
        request.rows.iter().map(|row| vec![row]).collect()
    };
    for group in &groups {
        for row in group.iter().copied() {
            let group_value = if request.grouped { vec![row.group_index.to_string()] } else { Vec::new() };
            text.push_str(&csv_row(row, cell_width, &group_value));
            text.push('\n');
        }
    }
    text
}

/// Column keys come from the tool spec, so an export names its own extra cells instead of
/// inventing headers the analysis lane cannot recognise.
fn csv_headers(request: &ExportRequest, spec: &ToolSpec) -> Vec<String> {
    let keys: Vec<String> = spec.columns.iter().map(|column| column.key.clone()).collect();
    let width = keys.len().max(request.rows.iter().map(|row| row.cells.len()).max().unwrap_or(0));
    let cells: Vec<String> = keys
        .iter()
        .cloned()
        .chain((keys.len()..width).map(|index| format!("cell_{index}")))
        .map(|key| csv_field(&key))
        .collect();

    let mut headers: Vec<String> = Vec::with_capacity(width + 7);
    if request.grouped {
        headers.push(csv_field("group"));
    }
    headers.push(csv_field("name"));
    headers.push(csv_field("directory"));
    headers.push(csv_field("path"));
    headers.extend(cells);
    headers.push(csv_field("size_bytes"));
    headers.push(csv_field("modified_ts"));
    headers.push(csv_field("is_reference"));
    headers
}

fn csv_row(row: &ScanRow, cell_width: usize, group_value: &[String]) -> String {
    let mut fields: Vec<String> = Vec::with_capacity(cell_width + 7);
    fields.extend_from_slice(group_value);
    fields.push(csv_field(&row.name));
    fields.push(csv_field(&row.directory));
    fields.push(csv_field(&row.path));

    let mut cells: Vec<String> = row.cells.iter().map(|cell| csv_field(cell)).collect();
    // Every row needs the same column count as the header, so narrower rows get empty tail cells.
    cells.resize(cell_width, String::new());
    fields.append(&mut cells);

    fields.push(row.size_bytes.to_string());
    fields.push(row.modified_ts.to_string());
    fields.push(row.is_reference.to_string());
    fields.join(",")
}

fn csv_field(text: &str) -> String {
    if text.contains(',') || text.contains('"') || text.contains('\n') || text.contains('\r') {
        return format!("\"{}\"", text.replace('"', "\"\""));
    }
    text.to_string()
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;

    fn row(name: &str, size: i64, group: i32, reference: bool) -> ScanRow {
        ScanRow {
            path: format!("/x/{group}/{name}"),
            name: name.to_string(),
            directory: format!("/x/{group}"),
            cells: vec![format!("{size}")],
            size_bytes: size,
            modified_ts: 0,
            group_index: group,
            group_size: if group < 0 { 1 } else { 3 },
            is_group_start: false,
            is_reference: reference,
            sort_keys: vec![size],
        }
    }

    fn delete_request(rows: Vec<ScanRow>, dry_run: bool, to_trash: bool) -> DeleteRequest {
        DeleteRequest { tool: "duplicate_files".to_string(), rows, delete_to_trash: to_trash, dry_run }
    }

    fn export_request(rows: Vec<ScanRow>, path: &str, format: &str, grouped: bool) -> ExportRequest {
        ExportRequest { tool: "duplicate_files".to_string(), rows, path: path.to_string(), format: format.to_string(), grouped }
    }

    #[test]
    fn reference_rows_are_never_deletion_targets() {
        let rows = vec![row("copy", 10, 0, false), row("original", 20, 0, true)];
        let roles = classify(&rows);
        assert_eq!(roles, vec![Role::Delete, Role::SkipReference]);
    }

    #[test]
    fn plain_group_spares_its_largest_copy() {
        let rows = vec![row("small", 10, 0, false), row("big", 300, 0, false), row("middle", 20, 0, false)];
        let roles = classify(&rows);
        assert_eq!(roles, vec![Role::Delete, Role::SpareKeeper, Role::Delete]);
    }

    #[test]
    fn tied_sizes_spare_the_first_member() {
        let rows = vec![row("first", 50, 0, false), row("second", 50, 0, false)];
        let roles = classify(&rows);
        assert_eq!(roles, vec![Role::SpareKeeper, Role::Delete]);
    }

    #[test]
    fn referenced_group_loses_every_ordinary_copy() {
        let rows = vec![row("a", 500, 0, false), row("b", 200, 0, false), row("ref", 10, 0, true)];
        let roles = classify(&rows);
        assert_eq!(roles, vec![Role::Delete, Role::Delete, Role::SkipReference]);

        let outcome = delete(delete_request(rows, true, false)).expect("dry run plans");
        assert_eq!(outcome.affected, 2, "reference rows are counted, not deleted");
        assert_eq!(outcome.reclaimed_bytes, 700);
        assert_eq!(outcome.errors, 0);
        assert_eq!(outcome.log, vec!["Would delete a".to_string(), "Would delete b".to_string(), "Skipped reference ref".to_string()]);
    }

    #[test]
    fn flat_rows_are_all_targets() {
        let rows = vec![row("a", 10, -1, false), row("b", 20, -1, false)];
        assert_eq!(classify(&rows), vec![Role::Delete, Role::Delete]);
    }

    #[test]
    fn dry_run_reclaims_only_the_deletable_bytes() {
        let rows = vec![row("small", 10, 0, false), row("big", 30, 0, false), row("orphan", 5, -1, false)];
        let outcome = delete(delete_request(rows, true, true)).expect("dry run plans");
        assert_eq!(outcome.affected, 2, "the spare keeper and nothing else is planned");
        assert_eq!(outcome.reclaimed_bytes, 15);
        assert_eq!(outcome.log[0], "Would trash small");
        assert_eq!(outcome.log[1], "Kept one copy big");
        assert_eq!(outcome.log[2], "Would trash orphan");
    }

    #[test]
    fn dry_run_touches_no_filesystem() {
        let missing = std::env::temp_dir().join("kisaki_bridge_ops_missing/ghost.bin");
        let text = missing.to_string_lossy().into_owned();
        let mut ghost = row("ghost.bin", 4096, -1, false);
        ghost.path = text;

        let outcome = delete(delete_request(vec![ghost], true, false)).expect("dry run plans");
        assert_eq!(outcome.affected, 1);
        assert_eq!(outcome.errors, 0, "planning must not report a filesystem failure");
        assert!(!missing.exists(), "a dry run must not create anything");
    }

    #[test]
    fn unknown_scanner_is_reported_with_its_name() {
        let error = delete(DeleteRequest { tool: "nope".to_string(), rows: Vec::new(), delete_to_trash: false, dry_run: true })
            .expect_err("unknown scanner must fail");
        assert!(error.contains("nope"), "missing scanner name in: {error}");

        let export_error = export(ExportRequest {
            tool: "nope".to_string(),
            rows: vec![row("a", 1, -1, false)],
            path: "/tmp/a.json".to_string(),
            format: "json".to_string(),
            grouped: false,
        })
        .expect_err("unknown scanner must fail");
        assert!(export_error.contains("nope"), "missing scanner name in: {export_error}");
    }

    #[test]
    fn empty_selection_is_reported_not_an_error() {
        let outcome = delete(delete_request(Vec::new(), true, false)).expect("nothing selected is a valid run");
        assert_eq!(outcome.affected, 0);
        assert_eq!(outcome.errors, 0);
        assert!(outcome.log.is_empty());
    }

    #[test]
    fn export_rejects_an_unknown_format() {
        let error = export(export_request(vec![row("a", 1, -1, false)], "/tmp/a.xml", "xml", false)).expect_err("xml is not supported");
        assert!(error.contains("xml"), "missing format in: {error}");
        assert!(error.contains("duplicate_files"), "missing scanner in: {error}");
    }

    #[test]
    fn export_refuses_an_empty_result_set() {
        let error = export(export_request(Vec::new(), "/tmp/a.json", "json", false)).expect_err("nothing to export");
        assert!(error.contains("no rows"), "unexpected: {error}");
    }

    #[test]
    fn json_groups_rows_by_group() {
        let rows = vec![row("a", 10, 1, false), row("b", 20, 0, false), row("c", 30, 1, false)];
        let text = json_document(&export_request(rows.clone(), "/tmp/a.json", "json", true));
        assert!(text.contains("\"group_count\": 2,"), "unexpected: {text}");
        assert!(text.contains("\"index\": 1"), "unexpected: {text}");
        assert!(text.contains("\"size\": 2"), "unexpected: {text}");

        let flat = json_document(&export_request(rows, "/tmp/a.json", "json", false));
        assert!(!flat.contains("\"groups\""), "a flat export must not group: {flat}");
        assert!(flat.contains("\"rows\": ["), "unexpected: {flat}");
    }

    #[test]
    fn json_escapes_the_path() {
        let mut row_data = row("we\"ird", 1, -1, false);
        row_data.path = "/tmp/we\"ird\nline".to_string();
        let text = json_document(&export_request(vec![row_data], "/tmp/a.json", "json", false));
        assert!(text.contains("\"path\": \"/tmp/we\\\"ird\\nline\""), "unexpected: {text}");
        assert!(text.contains("\"name\": \"we\\\"ird\""), "unexpected: {text}");
        // The positive checks need the escaped forms; this one fails if a raw quote leaks into the
        // document, where it would end the JSON string early.
        assert!(!text.contains("/tmp/we\"ird"), "an unescaped quote reached the document: {text}");
    }

    #[test]
    fn csv_uses_spec_column_keys_and_quotes_delimiters() {
        let mut row_data = row("na,me", 10, 0, false);
        row_data.cells = vec!["1.5 KiB".to_string(), "2024-01-01".to_string()];
        let request = export_request(vec![row_data], "/tmp/a.csv", "csv", true);
        let spec = registry::spec("duplicate_files").expect("known scanner");
        let text = csv_document(&request, &spec);

        assert_eq!(text.lines().next().expect("header line"), "group,name,directory,path,size,modified,size_bytes,modified_ts,is_reference");
        assert!(text.contains("\"na,me\""), "unexpected: {text}");
    }

    #[test]
    fn group_rows_keeps_first_seen_order_and_isolates_flat_rows() {
        let rows = vec![row("a", 1, 1, false), row("b", 2, 0, false), row("c", 3, 1, false), row("d", 4, -1, false)];
        let groups = group_rows(&rows);
        assert_eq!(groups.iter().map(|group| group.len()).collect::<Vec<_>>(), vec![2, 1, 1]);
        assert_eq!(groups[0][0].name, "a");
        assert_eq!(groups[1][0].name, "b");
    }

    #[test]
    fn human_size_uses_binary_units() {
        assert_eq!(human_size(2048), "2.0 KiB");
        assert_eq!(human_size(512), "512 B");
        assert_eq!(human_size(0), "0 B");
    }

    #[test]
    fn export_writes_the_document_and_spares_no_detail() {
        let dir = scratch("export");
        let file = dir.join("results.json");
        let written = export(export_request(
            vec![row("a", 10, 0, false), row("b", 20, 0, false)],
            file.to_string_lossy().as_ref(),
            "JSON",
            true,
        ))
        .expect("json export");

        assert_eq!(written, file.to_string_lossy());
        let text = fs::read_to_string(&file).expect("read the export back");
        assert!(text.contains("\"group_count\": 1,"), "unexpected: {text}");
        assert!(text.contains("/x/0/a"), "missing row in: {text}");
        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn export_into_a_directory_uses_a_generated_name() {
        let dir = scratch("folder_export");
        let written = export(export_request(vec![row("a", 10, -1, false)], dir.to_string_lossy().as_ref(), "csv", false)).expect("csv export");
        let path = PathBuf::from(&written);
        assert_eq!(path.parent(), Some(dir.as_path()), "unexpected: {written}");
        assert_eq!(path.extension().and_then(|ext| ext.to_str()), Some("csv"), "unexpected: {written}");
        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn real_delete_removes_targets_and_keeps_one_copy() {
        let dir = scratch("delete");
        let mut keeper = row("keeper.bin", 300, 0, false);
        let mut copy = row("copy.bin", 100, 0, false);
        // A reference row makes its whole group deletable, so it needs a group of its own here.
        let mut reference = row("reference.bin", 50, 1, true);
        for (index, row_data) in [&mut copy, &mut keeper, &mut reference].iter_mut().enumerate() {
            let path = dir.join(row_data.name.clone());
            fs::write(&path, vec![b'x'; index * 10 + 1]).expect("write fixture");
            row_data.path = path.to_string_lossy().into_owned();
        }

        let outcome = delete(delete_request(vec![copy.clone(), keeper.clone(), reference.clone()], false, false)).expect("delete runs");
        assert_eq!(outcome.affected, 1, "one copy is always spared");
        assert_eq!(outcome.reclaimed_bytes, 100);
        assert_eq!(outcome.errors, 0);
        assert_eq!(
            outcome.log,
            vec!["Deleted copy.bin".to_string(), "Kept one copy keeper.bin".to_string(), "Skipped reference reference.bin".to_string()]
        );
        assert!(!Path::new(&copy.path).exists(), "the target must be gone");
        assert!(Path::new(&keeper.path).exists(), "the spared copy must survive");
        assert!(Path::new(&reference.path).exists(), "a reference row must survive");

        let missing = PathBuf::from(dir.join("ghost.bin").to_string_lossy().into_owned());
        let mut ghost = row("ghost.bin", 7, -1, false);
        ghost.path = missing.to_string_lossy().into_owned();
        let failed = delete(delete_request(vec![ghost], false, false)).expect("failure is reported, not raised");
        assert_eq!((failed.affected, failed.errors), (0, 1));
        assert!(failed.messages.contains("1 failed"), "unexpected: {}", failed.messages);

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("kisaki_bridge_ops_{name}"));
        if dir.exists() {
            fs::remove_dir_all(&dir).expect("clear a stale scratch directory");
        }
        fs::create_dir_all(&dir).expect("create scratch directory");
        dir
    }
}
