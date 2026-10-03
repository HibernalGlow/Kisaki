use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use czkawka_core::common::traits::Search;
use czkawka_core::tools::exif_remover::ExifRemover;
use czkawka_core::tools::exif_remover::core::clean_exif_tags;

use crate::api::types::{ExifItem, ExifOutcome, ExifRequest, ExifStatus, ScanRequest};
use crate::engine::config::apply_common;
use crate::engine::{FieldStore, fix, flat, options, runner};

/// Removes EXIF tags from the selected files. The tag list is the engine's own - a fresh scan over
/// the folders holding the selection, because which tags a file carries (and which the user asked to
/// keep) is the scanner's decision - and each removal goes through the engine's own
/// `clean_exif_tags`. By default the original survives and a side file is written, since metadata
/// cannot be recovered once it is gone.
pub fn strip(request: &ExifRequest) -> Result<ExifOutcome, String> {
    strip_stopping(request, &runner::operation_stop())
}

/// The same run against a flag the caller owns, so stopping is testable without shared state.
pub(crate) fn strip_stopping(request: &ExifRequest, stop: &AtomicBool) -> Result<ExifOutcome, String> {
    if request.paths.is_empty() {
        return Err("No files selected".to_string());
    }
    let store = options::store(&request.scan);
    let found = scan_tags(&request.scan, &store, &request.paths)?;

    let items: Vec<ExifItem> = request.paths.iter().map(|path| strip_one(request, Path::new(path), &found, stop)).collect();
    Ok(summarise(items))
}

/// What the engine reported about one file: the tags to remove, or why it could not say.
struct Found {
    tags: Vec<(u16, String)>,
    error: Option<String>,
}

fn strip_one(request: &ExifRequest, path: &Path, found: &HashMap<PathBuf, Found>, stop: &AtomicBool) -> ExifItem {
    if stop.load(Ordering::Relaxed) {
        return item(path, None, 0, ExifStatus::Skipped, "The run was stopped".to_string());
    }
    let Some(entry) = found.get(&fix::resolved(path)) else {
        return item(path, None, 0, ExifStatus::Skipped, "The scan found no EXIF tags to remove".to_string());
    };
    if let Some(error) = &entry.error {
        return item(path, None, 0, ExifStatus::Failed, error.clone());
    }

    let target = write_target(path, request.override_file);
    let planned = entry.tags.len() as i32;
    if request.dry_run {
        return item(path, Some(&target), planned, ExifStatus::Planned, String::new());
    }

    match clean_exif_tags(&path.to_string_lossy(), &entry.tags, request.override_file) {
        Ok(removed) => {
            let status = if request.override_file { ExifStatus::Stripped } else { ExifStatus::Candidate };
            item(path, Some(&target), removed as i32, status, String::new())
        }
        Err(error) => item(path, Some(&target), 0, ExifStatus::Failed, error),
    }
}

/// Re-runs the EXIF check over the folders holding the selection, so the tags to remove are the
/// engine's list with the user's ignored tags already taken out. Every selected file sits directly
/// inside its parent, so a non-recursive scan of those parents still reaches all of them.
fn scan_tags(request: &ScanRequest, store: &FieldStore, paths: &[String]) -> Result<HashMap<PathBuf, Found>, String> {
    let mut scan = request.clone();
    scan.included = fix::parent_dirs(paths);
    scan.reference = Vec::new();
    scan.recursive = false;
    if scan.included.is_empty() {
        return Err("No folder to scan".to_string());
    }

    let mut tool = ExifRemover::new(flat::exif_params(store));
    apply_common(&mut tool, &scan);
    tool.search(&Arc::new(AtomicBool::new(false)), None);

    Ok(tool
        .get_exif_files()
        .iter()
        .map(|entry| {
            let tags = entry.exif_tags.iter().map(|tag| (tag.code, tag.group.clone())).collect();
            (entry.path.clone(), Found { tags, error: entry.error.clone() })
        })
        .collect())
}

/// The engine spells a side file `name.czkawka_cleaned_exif.ext`; an in-place clean keeps the path.
fn write_target(path: &Path, override_file: bool) -> PathBuf {
    if override_file {
        return path.to_path_buf();
    }
    let extension = path.extension().and_then(|ext| ext.to_str()).unwrap_or("");
    path.with_extension(format!("czkawka_cleaned_exif.{extension}"))
}

fn item(path: &Path, target: Option<&Path>, tags_removed: i32, status: ExifStatus, detail: String) -> ExifItem {
    ExifItem {
        path: path.to_string_lossy().into_owned(),
        target: target.map_or_else(String::new, |target| target.to_string_lossy().into_owned()),
        tags_removed,
        status,
        detail,
    }
}

/// Counts come out of the per-file log, so an entry and its counter can never disagree.
fn summarise(items: Vec<ExifItem>) -> ExifOutcome {
    let count = |wanted: &ExifStatus| items.iter().filter(|item| &item.status == wanted).count() as i32;
    let (stripped, candidates, planned, skipped, failed) = (
        count(&ExifStatus::Stripped),
        count(&ExifStatus::Candidate),
        count(&ExifStatus::Planned),
        count(&ExifStatus::Skipped),
        count(&ExifStatus::Failed),
    );
    let messages = if planned > 0 {
        format!("Planned {planned} file(s); {skipped} skipped.")
    } else {
        format!("Cleaned {} file(s); {failed} failed.", stripped + candidates)
    };
    ExifOutcome {
        stripped,
        candidates,
        planned,
        skipped,
        failed,
        items,
        messages,
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use czkawka_core::tools::exif_remover::core::extract_exif_tags_public;

    use super::*;

    #[test]
    fn a_dry_run_reports_the_tags_and_writes_nothing() {
        let root = scratch("dry_run");
        let photo = copy_fixture(&root, "photo.jpg");

        let outcome = strip(&request(std::slice::from_ref(&photo), false, true)).expect("dry run");
        assert_eq!((outcome.planned, outcome.stripped, outcome.failed), (1, 0, 0), "unexpected: {:?}", outcome.items);
        assert!(outcome.items[0].tags_removed > 0, "the fixture must really carry tags");
        assert_eq!(outcome.items[0].target, root.join("photo.czkawka_cleaned_exif.jpg").to_string_lossy());
        assert!(!root.join("photo.czkawka_cleaned_exif.jpg").exists(), "a dry run writes no side file");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn the_default_keeps_the_original_and_writes_a_cleaned_side_file() {
        let root = scratch("candidate");
        let photo = copy_fixture(&root, "photo.jpg");
        let before = extract_exif_tags_public(&photo).expect("read the fixture tags").len();
        assert!(before > 0, "the fixture must really carry tags");

        let outcome = strip(&request(std::slice::from_ref(&photo), false, false)).expect("run");
        assert_eq!((outcome.candidates, outcome.stripped, outcome.failed), (1, 0, 0), "unexpected: {:?}", outcome.items);

        let side = root.join("photo.czkawka_cleaned_exif.jpg");
        assert!(side.exists(), "the cleaned copy should be on disk");
        let remaining = extract_exif_tags_public(&side).expect("the side file is still readable").len();
        assert!(remaining < before, "the side file should carry fewer tags: {remaining} against {before}");
        assert_eq!(extract_exif_tags_public(&photo).expect("the original is untouched").len(), before);

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn overwriting_strips_the_original_in_place() {
        let root = scratch("override");
        let photo = copy_fixture(&root, "photo.jpg");
        let before = extract_exif_tags_public(&photo).expect("read the fixture tags").len();

        let outcome = strip(&request(std::slice::from_ref(&photo), true, false)).expect("run");
        assert_eq!((outcome.stripped, outcome.candidates, outcome.failed), (1, 0, 0), "unexpected: {:?}", outcome.items);
        assert_eq!(outcome.items[0].target, photo.to_string_lossy());
        assert!(!root.join("photo.czkawka_cleaned_exif.jpg").exists(), "an in-place clean writes no side file");
        assert!(
            extract_exif_tags_public(&photo).expect("read the file back").len() < before,
            "the original should carry fewer tags than its {before}"
        );

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn a_file_without_exif_is_skipped_rather_than_written() {
        let root = scratch("no_exif");
        fs::create_dir_all(&root).expect("create scratch directory");
        let plain = root.join("notes.txt");
        fs::write(&plain, "plain text").expect("write fixture");

        let outcome = strip(&request(std::slice::from_ref(&plain), false, false)).expect("run");
        assert_eq!((outcome.stripped, outcome.candidates, outcome.skipped), (0, 0, 1));
        assert_eq!(outcome.items[0].detail, "The scan found no EXIF tags to remove");
        assert_eq!(outcome.items[0].target, "");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn an_empty_selection_is_refused() {
        let error = strip(&request(&[], false, true)).expect_err("nothing selected");
        assert!(error.contains("No files selected"), "unexpected: {error}");
    }

    #[test]
    fn a_stopped_exif_run_writes_nothing() {
        let root = scratch("exif_stopped");
        let photo = copy_fixture(&root, "photo.jpg");
        let stop = AtomicBool::new(true);

        let outcome = strip_stopping(&request(std::slice::from_ref(&photo), false, false), &stop).expect("stopped run");
        assert_eq!((outcome.stripped, outcome.candidates, outcome.failed, outcome.skipped), (0, 0, 0, 1));
        assert_eq!(outcome.items[0].detail, "The run was stopped");
        assert!(!root.join("photo.czkawka_cleaned_exif.jpg").exists(), "a stopped run writes no side file");

        // The same request with an idle flag does produce the side file, so the check is not vacuous.
        let idle = AtomicBool::new(false);
        let outcome = strip_stopping(&request(std::slice::from_ref(&photo), false, false), &idle).expect("idle run");
        assert_eq!((outcome.candidates, outcome.skipped), (1, 0));
        assert!(root.join("photo.czkawka_cleaned_exif.jpg").exists(), "the idle run writes the side file");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    fn request(paths: &[PathBuf], override_file: bool, dry_run: bool) -> ExifRequest {
        ExifRequest {
            scan: scan_request(),
            paths: paths.iter().map(|path| path.to_string_lossy().into_owned()).collect(),
            override_file,
            dry_run,
        }
    }

    /// The options block a real request carries; empty means the engine's own defaults, which is
    /// what the board sends when the user has not touched the EXIF tab.
    fn scan_request() -> ScanRequest {
        ScanRequest {
            tool: "exif_remover".to_string(),
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

    /// The image the engine's own EXIF tests use, so the fixture and the expectations cannot drift
    /// apart into different files.
    fn copy_fixture(dir: &Path, name: &str) -> PathBuf {
        let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../czkawka_core/test_resources/images/normal.jpg");
        let bytes = fs::read(&source).unwrap_or_else(|error| panic!("read the EXIF fixture at {}: {error}", source.display()));
        fs::create_dir_all(dir).expect("create scratch directory");
        let path = dir.join(name);
        fs::write(&path, bytes).expect("write the fixture");
        path
    }

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("kisaki_bridge_exif_{name}"));
        if dir.exists() {
            fs::remove_dir_all(&dir).expect("clear a stale scratch directory");
        }
        fs::create_dir_all(&dir).expect("create scratch directory");
        dir
    }
}
