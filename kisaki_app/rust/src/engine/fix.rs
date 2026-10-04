use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use czkawka_core::common::traits::Search;
use czkawka_core::tools::bad_extensions::BadExtensions;
use czkawka_core::tools::bad_names::NameIssues;
use czkawka_core::tools::bad_names::core::check_and_generate_new_name;

use crate::api::types::{RenameItem, RenameOutcome, RenameRequest, RenameStatus, ScanRequest};
use crate::engine::config::apply_common;
use crate::engine::{FieldStore, flat, options, runner};

/// Renames the selected files to what the engine considers correct. The decision is always core's:
/// bad names go through its own name generator, bad extensions through a fresh content scan.
/// Only the apply step lives here, because the engine keeps its results private and fixes every
/// row it holds, while the board acts on a selection.
pub fn rename(request: &RenameRequest) -> Result<RenameOutcome, String> {
    rename_stopping(request, &runner::operation_stop())
}

/// The same run against a flag the caller owns, so stopping is testable without shared state.
pub(crate) fn rename_stopping(request: &RenameRequest, stop: &AtomicBool) -> Result<RenameOutcome, String> {
    if request.paths.is_empty() {
        return Err("No files selected".to_string());
    }
    let store = options::store(&request.scan);
    let plans = match request.tool.as_str() {
        "bad_names" => name_plans(&store, &request.paths),
        "bad_extensions" => extension_plans(request, &store)?,
        other => return Err(format!("{other} has no rename fix")),
    };
    Ok(apply(&plans, request.dry_run, stop))
}

/// What the engine wants one selected file to become. `to` is absent when the file needs no change.
struct Plan {
    from: PathBuf,
    to: Option<PathBuf>,
    detail: String,
}

fn name_plans(store: &FieldStore, paths: &[String]) -> Vec<Plan> {
    let issues = flat::name_issues(store);
    paths.iter().map(|raw| name_plan(Path::new(raw), &issues)).collect()
}

fn name_plan(from: &Path, issues: &NameIssues) -> Plan {
    let Some(new_name) = check_and_generate_new_name(from, issues) else {
        return Plan {
            from: from.to_path_buf(),
            to: None,
            detail: "Name already satisfies the checked rules".to_string(),
        };
    };
    Plan {
        from: from.to_path_buf(),
        to: Some(from.with_file_name(new_name)),
        detail: String::new(),
    }
}

fn extension_plans(request: &RenameRequest, store: &FieldStore) -> Result<Vec<Plan>, String> {
    let proper = extension_of(&request.scan, store, &request.paths)?;
    Ok(request.paths.iter().map(|raw| extension_plan(Path::new(raw), &proper)).collect())
}

fn extension_plan(from: &Path, proper: &HashMap<PathBuf, String>) -> Plan {
    let Some(extension) = proper.get(&resolved(from)) else {
        return Plan {
            from: from.to_path_buf(),
            to: None,
            detail: "The scan did not flag this file".to_string(),
        };
    };
    Plan {
        from: from.to_path_buf(),
        to: Some(from.with_extension(extension)),
        detail: String::new(),
    }
}

/// The engine reports paths with symlinks resolved, so a selection that spells the same file
/// differently - "/tmp" against "/private/tmp" on macOS - is still recognised.
/// The one spelling a scan result and a user selection are compared under.
///
/// The engine reports paths it canonicalized itself, while a selection arrives exactly as the host
/// wrote it. On Windows the two differ by a verbatim prefix, by case and by the 8.3 short form, so
/// matching a raw selection string against an engine key answers "the engine did not ask about this
/// file" for every one of them. Both sides come through here; a path that cannot be canonicalized
/// stays as given, so a missing file is still reported as missing.
pub(crate) fn resolved(path: &Path) -> PathBuf {
    fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

/// Re-runs the extension check over the folders holding the selection, because the correct extension
/// is read from the file's own bytes and only the engine can say it. Every selected file sits
/// directly inside its parent, so scanning those parents non-recursively still visits all of them.
/// A file the narrowed scan does not report is left unrenamed rather than guessed at.
fn extension_of(request: &ScanRequest, store: &FieldStore, paths: &[String]) -> Result<HashMap<PathBuf, String>, String> {
    let mut scan = request.clone();
    scan.included = parent_dirs(paths);
    scan.reference = Vec::new();
    scan.recursive = false;
    if scan.included.is_empty() {
        return Err("No folder to scan".to_string());
    }

    let mut tool = BadExtensions::new(flat::bad_extension_params(store));
    apply_common(&mut tool, &scan);
    tool.search(&Arc::new(AtomicBool::new(false)), None);

    Ok(tool
        .get_bad_extensions_files()
        .iter()
        .map(|entry| (resolved(&entry.path), entry.proper_extension.clone()))
        .collect())
}

/// Distinct folders of a selection, as strings the engine can use as scan roots.
pub(crate) fn parent_dirs(paths: &[String]) -> Vec<String> {
    let mut dirs: Vec<String> = paths
        .iter()
        .filter_map(|path| Path::new(path).parent().map(|parent| parent.to_string_lossy().into_owned()))
        .collect();
    dirs.sort_unstable();
    dirs.dedup();
    dirs
}

/// Applies the plans in request order. The dry run uses the same blocking rules as the real run, so
/// its plan is what the filesystem would have accepted at the same moment.
fn apply(plans: &[Plan], dry_run: bool, stop: &AtomicBool) -> RenameOutcome {
    let mut items = Vec::with_capacity(plans.len());
    let mut claimed: HashSet<PathBuf> = HashSet::new();
    let (mut renamed, mut planned, mut failed, mut skipped) = (0_i32, 0_i32, 0_i32, 0_i32);

    for plan in plans {
        if stop.load(Ordering::Relaxed) {
            skipped += 1;
            items.push(item(plan, RenameStatus::Skipped, "The run was stopped".to_string()));
            continue;
        }

        let Some(to) = plan.to.clone() else {
            skipped += 1;
            items.push(item(plan, RenameStatus::Skipped, String::new()));
            continue;
        };

        let outcome = match blocked(plan, &to, &claimed) {
            Some(reason) => {
                failed += 1;
                (RenameStatus::Failed, reason)
            }
            None if dry_run => {
                planned += 1;
                claimed.insert(to.clone());
                (RenameStatus::Planned, String::new())
            }
            None => match fs::rename(&plan.from, &to) {
                Ok(()) => {
                    renamed += 1;
                    claimed.insert(to.clone());
                    (RenameStatus::Renamed, String::new())
                }
                Err(error) => (RenameStatus::Failed, format!("Failed to rename {} to {}: {error}", plan.from.display(), to.display())),
            },
        };
        items.push(item(plan, outcome.0, outcome.1));
    }

    RenameOutcome {
        renamed,
        planned,
        failed,
        skipped,
        messages: format!("{renamed} renamed, {planned} planned, {failed} failed, {skipped} left as they are"),
        items,
    }
}

/// The two ways a rename cannot happen: a name already on disk, and a name an earlier row of this
/// same selection is about to take. The second guard has no engine counterpart, because the engine
/// fixes its whole result set in parallel and cannot order the attempts.
fn blocked(plan: &Plan, to: &Path, claimed: &HashSet<PathBuf>) -> Option<String> {
    if claimed.contains(to) {
        return Some(format!(
            "Cannot rename {} to {}: another selected file already takes this name",
            plan.from.display(),
            to.display()
        ));
    }
    if to.exists() && !same_file(&plan.from, to) {
        return Some(format!("Cannot rename {} to {}: target file already exists", plan.from.display(), to.display()));
    }
    None
}

/// A target name that already exists blocks the rename, except when it only differs from the source
/// by case: on a case-insensitive volume "REPORT.pdf" resolves to the source file "REPORT.PDF"
/// itself, and the case fix would otherwise be impossible on macOS and Windows. Canonicalising gives
/// the names the filesystem actually stores, so a genuinely different file still blocks the rename.
fn same_file(from: &Path, to: &Path) -> bool {
    match (fs::canonicalize(from), fs::canonicalize(to)) {
        (Ok(from), Ok(to)) => from == to,
        _ => false,
    }
}

fn item(plan: &Plan, status: RenameStatus, detail: String) -> RenameItem {
    RenameItem {
        from: plan.from.to_string_lossy().into_owned(),
        to: plan.to.as_ref().map_or_else(String::new, |to| to.to_string_lossy().into_owned()),
        detail: if detail.is_empty() { plan.detail.clone() } else { detail },
        status,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_dry_run_plans_without_touching_the_disk() {
        let dir = scratch("dry_run");
        let path = write(&dir, "clip .MP4", "video");

        let outcome = rename(&request("bad_names", std::slice::from_ref(&path), true)).expect("dry run");
        assert_eq!((outcome.planned, outcome.renamed, outcome.failed), (1, 0, 0));
        assert_eq!(outcome.items[0].to, dir.join("clip.mp4").to_string_lossy());
        assert_eq!(outcome.items[0].status, RenameStatus::Planned);
        assert_eq!(path.extension().and_then(|ext| ext.to_str()), Some("MP4"), "a dry run must not rename");

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn a_case_only_rename_still_happens_on_a_case_insensitive_volume() {
        let dir = scratch("case_only");
        write(&dir, "REPORT.PDF", "pdf");

        let outcome = rename(&request("bad_names", &[dir.join("REPORT.PDF")], false)).expect("run");
        assert_eq!((outcome.renamed, outcome.failed), (1, 0), "unexpected: {:?}", outcome.items);
        assert_eq!(names(&dir), vec!["REPORT.pdf".to_string()], "the engine only lowercases the extension");

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn a_real_run_renames_only_the_selection() {
        let dir = scratch("selection");
        let chosen = write(&dir, "note .TXT", "one");
        let ignored = write(&dir, "other .TXT", "two");

        let outcome = rename(&request("bad_names", std::slice::from_ref(&chosen), false)).expect("rename runs");
        assert_eq!((outcome.renamed, outcome.failed), (1, 0));
        assert_eq!(outcome.items[0].status, RenameStatus::Renamed);
        assert!(!chosen.exists(), "the selected file lost its old name");
        assert_eq!(fs::read_to_string(dir.join("note.txt")).expect("content survives a rename"), "one");
        assert!(ignored.exists(), "a file outside the selection keeps its name");

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn a_stopped_rename_keeps_every_name() {
        let dir = scratch("rename_stopped");
        let chosen = write(&dir, "note .TXT", "one");
        let stop = AtomicBool::new(true);

        let outcome = rename_stopping(&request("bad_names", std::slice::from_ref(&chosen), false), &stop).expect("stopped run");
        assert_eq!((outcome.renamed, outcome.failed, outcome.skipped), (0, 0, 1));
        assert_eq!(outcome.items[0].detail, "The run was stopped");
        assert!(chosen.exists(), "a stopped rename must leave the file where it is");

        // An idle flag renames the same file, so the assertions above cannot pass vacuously.
        let idle = AtomicBool::new(false);
        let outcome = rename_stopping(&request("bad_names", std::slice::from_ref(&chosen), false), &idle).expect("idle run");
        assert_eq!((outcome.renamed, outcome.skipped), (1, 0));

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn an_occupied_target_is_refused_and_the_source_survives() {
        let dir = scratch("occupied");
        let source = write(&dir, "russian .TXT", "new");
        write(&dir, "russian.txt", "existing");

        let outcome = rename(&request("bad_names", std::slice::from_ref(&source), false)).expect("failure is reported");
        assert_eq!((outcome.renamed, outcome.failed), (0, 1));
        assert!(outcome.items[0].detail.contains("target file already exists"), "unexpected: {}", outcome.items[0].detail);
        assert!(source.exists(), "a refused rename must leave the source alone");
        assert_eq!(fs::read_to_string(&source).expect("read the source back"), "new");

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn two_files_cleaning_to_the_same_name_leave_the_second_one_alone() {
        let dir = scratch("collision");
        // The allowed character set drops both punctuation marks, so the two names collide.
        let first = write(&dir, "a!.txt", "1");
        let second = write(&dir, "a?.txt", "2");

        let outcome = rename(&request("bad_names", &[first, second], false)).expect("run");
        assert_eq!((outcome.renamed, outcome.failed), (1, 1), "unexpected: {:?}", outcome.items);
        assert!(outcome.items[1].detail.contains("already takes this name"), "unexpected: {}", outcome.items[1].detail);
        assert!(dir.join("a.txt").exists(), "the first cleaned name must be on disk");
        assert!(dir.join("a?.txt").exists(), "the colliding file must keep its own name");

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn a_file_the_rules_accept_is_counted_as_unchanged() {
        let dir = scratch("clean_name");
        let path = write(&dir, "report.txt", "text");

        let outcome = rename(&request("bad_names", &[path], true)).expect("dry run");
        assert_eq!((outcome.planned, outcome.skipped), (0, 1));
        assert_eq!(outcome.items[0].status, RenameStatus::Skipped);
        assert_eq!(outcome.items[0].to, "");

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn a_bad_extension_is_taken_from_the_file_contents_not_its_name() {
        let dir = scratch("extension");
        let path = write_bytes(&dir, "photo.jpg", &png_header());

        let outcome = rename(&request("bad_extensions", std::slice::from_ref(&path), true)).expect("dry run");
        assert_eq!(outcome.planned, 1, "unexpected: {:?}", outcome.items);
        assert_eq!(outcome.items[0].to, dir.join("photo.png").to_string_lossy());

        let outcome = rename(&request("bad_extensions", &[path], false)).expect("rename runs");
        assert_eq!((outcome.renamed, outcome.failed), (1, 0));
        assert!(dir.join("photo.png").exists(), "the file should have the detected extension");
        assert_eq!(fs::read(dir.join("photo.png")).expect("bytes survive"), png_header());

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn a_file_the_scan_did_not_flag_is_left_alone() {
        let dir = scratch("unflagged");
        let path = write(&dir, "notes.txt", "plain text has no signature");

        let outcome = rename(&request("bad_extensions", &[path], false)).expect("run");
        assert_eq!((outcome.renamed, outcome.skipped), (0, 1));
        assert_eq!(outcome.items[0].detail, "The scan did not flag this file");

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    #[test]
    fn only_the_two_rename_tools_are_accepted() {
        let dir = scratch("unknown_tool");
        let path = dir.join("file.bin");

        let error = rename(&request("duplicate_files", &[path], true)).expect_err("no rename fix exists");
        assert!(error.contains("duplicate_files"), "unexpected: {error}");
        let error = rename(&request("bad_names", &[], true)).expect_err("an empty selection is refused");
        assert!(error.contains("No files selected"), "unexpected: {error}");

        fs::remove_dir_all(&dir).expect("remove scratch directory");
    }

    fn request(tool: &str, paths: &[PathBuf], dry_run: bool) -> RenameRequest {
        RenameRequest {
            tool: tool.to_string(),
            scan: scan_request(),
            paths: paths.iter().map(|path| path.to_string_lossy().into_owned()).collect(),
            dry_run,
        }
    }

    /// The scan block a rename needs is the one that produced the rows; the tests use its defaults,
    /// which is exactly the unconfigured request the board sends for the two name tools.
    fn scan_request() -> ScanRequest {
        ScanRequest {
            tool: String::new(),
            included: Vec::new(),
            reference: Vec::new(),
            excluded_paths: Vec::new(),
            excluded_items: Vec::new(),
            allowed_extensions: Vec::new(),
            excluded_extensions: Vec::new(),
            recursive: true,
            use_cache: false,
            min_size_kib: String::new(),
            max_size_kib: String::new(),
            fields: Vec::new(),
        }
    }

    fn write(dir: &Path, name: &str, content: &str) -> PathBuf {
        let path = dir.join(name);
        fs::write(&path, content).expect("write fixture");
        path
    }

    fn write_bytes(dir: &Path, name: &str, content: &[u8]) -> PathBuf {
        let path = dir.join(name);
        fs::write(&path, content).expect("write fixture");
        path
    }

    /// The signature `infer` recognises as PNG; the file name deliberately disagrees with it.
    fn png_header() -> Vec<u8> {
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89".to_vec()
    }

    /// The names the filesystem actually stores, so a case-only rename is checked on every platform.
    fn names(dir: &Path) -> Vec<String> {
        let mut found: Vec<String> = fs::read_dir(dir)
            .expect("read scratch directory")
            .map(|entry| entry.expect("read entry").file_name().to_string_lossy().into_owned())
            .collect();
        found.sort();
        found
    }

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("kisaki_bridge_fix_{name}"));
        if dir.exists() {
            fs::remove_dir_all(&dir).expect("clear a stale scratch directory");
        }
        fs::create_dir_all(&dir).expect("create scratch directory");
        dir
    }
}
