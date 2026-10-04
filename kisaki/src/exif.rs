use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use czkawka_core::tools::exif_remover::core::clean_exif_tags;
use rayon::prelude::*;
use slint::ComponentHandle;

use crate::common::format_bytes;
use crate::state::{AppStore, RowData, SharedState};
use crate::{AppState, MainWindow, PendingAction, Phase, fli};

const PLAN_PREVIEW_ROWS: usize = 12;

/// What the engine said about one file: the tags to remove, or why it could not say. The engine
/// already took the user's ignored tags out of this list, so nothing here re-reads the file.
struct Found {
    tags: Vec<(u16, String)>,
    error: Option<String>,
}

/// Side-file spelling the engine itself produces; the original file is never rewritten here.
fn side_file(path: &Path) -> PathBuf {
    let extension = path.extension().and_then(|ext| ext.to_str()).unwrap_or("");
    path.with_extension(format!("czkawka_cleaned_exif.{extension}"))
}

/// The spelling both sides are reduced to before they are compared. The engine reports canonical
/// paths while a selection can carry a symlinked prefix (macOS `/var` is really `/private/var`).
fn resolved(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

fn engine_report(store: &AppStore) -> HashMap<PathBuf, Found> {
    let Some(tool) = store.models.exif_remover.as_ref() else {
        return HashMap::new();
    };
    tool.get_exif_files()
        .iter()
        .map(|entry| {
            let found = Found {
                tags: entry.exif_tags.iter().map(|tag| (tag.code, tag.group.clone())).collect(),
                error: entry.error.clone(),
            };
            (resolved(&entry.path), found)
        })
        .collect()
}

/// Splits the selection into files the engine can vouch for and files to leave alone.
fn pick_targets(selection: &[PathBuf], report: &HashMap<PathBuf, Found>) -> (Vec<(PathBuf, Vec<(u16, String)>)>, usize) {
    let mut targets = Vec::new();
    let mut left_alone = 0usize;
    for path in selection {
        match report.get(&resolved(path)) {
            Some(found) if found.error.is_none() && !found.tags.is_empty() => targets.push((path.clone(), found.tags.clone())),
            _ => left_alone += 1,
        }
    }
    (targets, left_alone)
}

/// Human readable preview of the copies that would be written. Touches no files.
fn build_plan(rows: &[&RowData], targets: &[(PathBuf, Vec<(u16, String)>)], left_alone: usize) -> String {
    if targets.is_empty() {
        return fli!("status_exif_no_tags", count = rows.len());
    }
    let bytes: u64 = targets
        .iter()
        .filter_map(|(path, _)| rows.iter().find(|row| row.path == *path).map(|row| row.size_bytes))
        .sum();
    let mut lines = vec![fli!("plan_header", count = targets.len(), size = format_bytes(bytes), verb = fli!("plan_verb_strip_exif"))];
    for (path, tags) in targets.iter().take(PLAN_PREVIEW_ROWS) {
        let name = path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
        let target = side_file(path);
        let target = target.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
        lines.push(format!("  {name}  ->  {target}  ({})", tags.len()));
    }
    if targets.len() > PLAN_PREVIEW_ROWS {
        let hidden: usize = targets.len() - PLAN_PREVIEW_ROWS;
        lines.push(fli!("plan_more", count = hidden));
    }
    if left_alone > 0 {
        lines.push(fli!("plan_exif_left_alone", count = left_alone));
    }
    lines.join("\n")
}

/// Opens the confirmation overlay behind the same gate the delete verb uses.
pub fn ask(app: &MainWindow, state: &SharedState) {
    let globals = app.global::<AppState>();
    let (plan, targets, selected) = {
        let store = state.lock().expect("App state mutex poisoned");
        let rows: Vec<&RowData> = store.rows.iter().filter(|row| store.selection.contains(&row.path)).collect();
        let paths: Vec<PathBuf> = rows.iter().map(|row| row.path.clone()).collect();
        let (targets, left_alone) = pick_targets(&paths, &engine_report(&store));
        (build_plan(&rows, &targets, left_alone), targets.len(), paths.len())
    };

    if targets == 0 {
        globals.set_status_text(plan.as_str().into());
        return;
    }

    globals.set_pending_action(PendingAction::StripExif);
    globals.set_confirm_title(fli!("confirm_strip_title").into());
    let body = if globals.get_dry_run() {
        fli!("confirm_dry_run_strip_body", count = selected)
    } else {
        fli!("confirm_strip_body", count = selected)
    };
    globals.set_confirm_body(body.as_str().into());
    globals.set_action_summary(plan.as_str().into());
    globals.set_confirm_open(true);
}

/// Writes one metadata-free copy per target, leaving every original untouched. The tags come from
/// the engine's stored result, so a dry run needs no file access at all and reports exactly the set
/// the real run will act on.
pub fn run(app: &MainWindow, state: &SharedState) {
    let globals = app.global::<AppState>();
    let (targets, selected, dry_run) = {
        let store = state.lock().expect("App state mutex poisoned");
        let selection: Vec<PathBuf> = store.selection.iter().cloned().collect();
        let (targets, _) = pick_targets(&selection, &engine_report(&store));
        (targets, selection.len(), globals.get_dry_run())
    };

    if dry_run {
        globals.set_status_text(fli!("status_exif_planned", count = targets.len(), total = selected).as_str().into());
        return;
    }
    if targets.is_empty() {
        globals.set_status_text(fli!("status_exif_no_tags", count = selected).as_str().into());
        return;
    }

    globals.set_phase(Phase::Running);
    globals.set_progress_all(0);
    globals.set_status_text(fli!("status_stripping").into());

    let weak = app.as_weak();
    std::thread::spawn(move || {
        let total = targets.len();
        let step = (total / 100).max(1);
        let completed = AtomicUsize::new(0);
        let outcomes: Vec<(u32, Option<String>)> = targets
            .into_par_iter()
            .map(|(path, tags)| {
                let removed = clean_exif_tags(&path.to_string_lossy(), &tags, false);
                let done = completed.fetch_add(1, Ordering::Relaxed) + 1;
                if done == total || done.is_multiple_of(step) {
                    let percent = ((done * 100) / total.max(1)) as i32;
                    let _ = weak.clone().upgrade_in_event_loop(move |app| {
                        app.global::<AppState>().set_progress_all(percent);
                    });
                }
                match removed {
                    Ok(removed) => (removed, None),
                    Err(error) => {
                        log::error!("Failed to strip EXIF from {}: {error}", path.display());
                        (0, Some(format!("{}: {error}", path.display())))
                    }
                }
            })
            .collect();

        let written = outcomes.iter().filter(|(removed, _)| *removed > 0).count();
        let tags: u32 = outcomes.iter().map(|(removed, _)| *removed).sum();
        let failures: Vec<String> = outcomes.iter().filter_map(|(_, error)| error.clone()).collect();

        let _ = weak.upgrade_in_event_loop(move |app| {
            let globals = app.global::<AppState>();
            globals.set_phase(Phase::Completed);
            globals.set_progress_all(100);
            globals.set_progress_current(-1);
            let message = if failures.is_empty() {
                fli!("status_exif_all", count = written, tags = tags)
            } else {
                globals.set_error_text(failures.join("\n").as_str().into());
                globals.set_errors_open(true);
                fli!("status_exif_partial", written = written, failed = failures.len())
            };
            globals.set_status_text(message.as_str().into());
            globals.set_action_summary("".into());
        });
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(path: &Path, size_bytes: u64) -> RowData {
        RowData {
            path: path.to_path_buf(),
            name: path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default(),
            directory: String::new(),
            cells: Vec::new(),
            sort_keys: Vec::new(),
            size_bytes,
            mtime: 0,
            group_index: 0,
            group_size: 1,
            is_group_start: true,
            is_reference: false,
            checked: true,
        }
    }

    fn tags(count: usize) -> Vec<(u16, String)> {
        (0..count).map(|index| (index as u16, "Group".to_string())).collect()
    }

    /// Scratch directory unique to this call; the crate has no dev-dependencies to lean on.
    fn scratch(label: &str) -> PathBuf {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("system clock is behind the epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("kisaki_exif_{label}_{nanos}"));
        std::fs::create_dir_all(&dir).expect("failed to create the scratch dir");
        dir
    }

    #[test]
    fn the_side_file_name_is_the_ones_the_engine_writes() {
        assert_eq!(side_file(Path::new("/a/photo.jpg")), PathBuf::from("/a/photo.czkawka_cleaned_exif.jpg"));
        assert_eq!(side_file(Path::new("/a/no_extension")), PathBuf::from("/a/no_extension.czkawka_cleaned_exif."));
    }

    #[test]
    fn only_files_the_engine_vouched_for_become_targets() {
        let root = scratch("pick");
        let reported = root.join("reported.jpg");
        let empty = root.join("empty.jpg");
        let broken = root.join("broken.jpg");
        let unknown = root.join("unknown.jpg");
        for path in [&reported, &empty, &broken, &unknown] {
            std::fs::write(path, b"not a jpeg").expect("failed to write the fixture");
        }

        // The engine keys its report by canonical paths, so the fixture spells the keys the same
        // way while the selection below keeps the symlinked spelling it arrives with.
        let mut report = HashMap::new();
        report.insert(resolved(&reported), Found { tags: tags(3), error: None });
        report.insert(resolved(&empty), Found { tags: tags(0), error: None });
        report.insert(
            resolved(&broken),
            Found {
                tags: tags(1),
                error: Some("cannot read".to_string()),
            },
        );

        let selection = vec![reported.clone(), empty, broken, unknown];
        let (targets, left_alone) = pick_targets(&selection, &report);
        std::fs::remove_dir_all(&root).expect("failed to remove the scratch dir");

        assert_eq!(targets.len(), 1, "only the file the engine reported may be written");
        assert_eq!(targets[0].0, reported);
        assert_eq!(targets[0].1.len(), 3);
        assert_eq!(left_alone, 3, "tagless, unreadable and unreported all stay alone");
    }

    #[test]
    fn the_plan_caps_its_preview_and_shows_what_is_left_alone() {
        let rows: Vec<RowData> = (0..20).map(|index| row(Path::new("/a").join(format!("photo_{index}.jpg")).as_path(), 1_024)).collect();
        let refs: Vec<&RowData> = rows.iter().collect();
        let targets: Vec<(PathBuf, Vec<(u16, String)>)> = rows.iter().map(|row| (row.path.clone(), tags(1))).collect();

        let plan = build_plan(&refs, &targets, 4);
        // One header line, twelve previews, one overflow line and one left-alone line.
        assert_eq!(plan.lines().count(), PLAN_PREVIEW_ROWS + 3, "unexpected: {plan}");
        assert_eq!(plan.matches("->").count(), PLAN_PREVIEW_ROWS, "unexpected: {plan}");
        assert!(plan.contains("(1)"), "the tag count should be visible per file: {plan}");

        assert_eq!(build_plan(&refs, &[], 20), fli!("status_exif_no_tags", count = 20));
    }
}
