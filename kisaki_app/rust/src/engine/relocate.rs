use std::collections::HashSet;
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use czkawka_core::common::fs_ops::remove_single_file;

use crate::api::types::{ConflictPolicy, MoveAction, MoveItem, MoveOutcome, MoveRequest, MoveStatus};
use crate::engine::runner;

/// Moves or copies the selection into one destination folder. The engine owns no move API - its
/// `fs_ops` only removes, links and symlinks - so this verb is frontend-owned by necessity, and a
/// dry run plans without touching disk.
pub fn apply(request: &MoveRequest) -> Result<MoveOutcome, String> {
    apply_stopping(request, &runner::operation_stop())
}

/// The same run against a flag the caller owns, so stopping is testable without shared state.
pub(crate) fn apply_stopping(request: &MoveRequest, stop: &AtomicBool) -> Result<MoveOutcome, String> {
    if request.paths.is_empty() {
        return Err("No files selected".to_string());
    }
    if request.destination.trim().is_empty() {
        return Err("A destination directory is required".to_string());
    }
    let root = PathBuf::from(request.destination.trim());
    let mut claimed: HashSet<String> = HashSet::new();

    let items: Vec<MoveItem> = request.paths.iter().map(|path| relocate_one(request, &root, Path::new(path), &mut claimed, stop)).collect();
    Ok(summarise(items))
}

/// Where a file lands: the requested name, or a refusal with the reason the user has to see.
enum Decision {
    Go(PathBuf),
    Skip(PathBuf),
    Fail(PathBuf, String),
}

fn relocate_one(request: &MoveRequest, root: &Path, from: &Path, claimed: &mut HashSet<String>, stop: &AtomicBool) -> MoveItem {
    if stop.load(Ordering::Relaxed) {
        return item(from, None, MoveStatus::Skipped, "The run was stopped".to_string());
    }
    if !from.exists() {
        return item(from, None, MoveStatus::Failed, "Source path no longer exists".to_string());
    }

    let wanted = wanted_target(root, from, request.preserve_structure);
    if wanted == from {
        return item(from, Some(&wanted), MoveStatus::Skipped, "Path already uses the requested name".to_string());
    }

    let target = match resolve(request, &wanted, claimed) {
        Decision::Go(target) => target,
        Decision::Skip(target) => return item(from, Some(&target), MoveStatus::Skipped, "Target already exists".to_string()),
        Decision::Fail(target, reason) => return item(from, Some(&target), MoveStatus::Failed, reason),
    };

    if request.dry_run {
        claimed.insert(key(&target));
        return item(from, Some(&target), MoveStatus::Planned, String::new());
    }

    match perform(request, from, &target) {
        Ok(()) => {
            claimed.insert(key(&target));
            let status = match request.action {
                MoveAction::Move => MoveStatus::Moved,
                MoveAction::Copy => MoveStatus::Copied,
            };
            item(from, Some(&target), status, String::new())
        }
        Err(reason) => item(from, Some(&target), MoveStatus::Failed, reason),
    }
}

fn resolve(request: &MoveRequest, wanted: &Path, claimed: &HashSet<String>) -> Decision {
    if !claimed.contains(&key(wanted)) && !wanted.exists() {
        return Decision::Go(wanted.to_path_buf());
    }
    match request.conflict {
        ConflictPolicy::Skip => Decision::Skip(wanted.to_path_buf()),
        ConflictPolicy::Error => Decision::Fail(wanted.to_path_buf(), "Target already exists".to_string()),
        // Replacing is only allowed for a name the batch itself has not just taken over.
        ConflictPolicy::Overwrite if claimed.contains(&key(wanted)) => Decision::Fail(wanted.to_path_buf(), "Another selected file uses the same target path".to_string()),
        ConflictPolicy::Overwrite => Decision::Go(wanted.to_path_buf()),
        ConflictPolicy::Rename => free_name(wanted, claimed).map_or_else(|| Decision::Fail(wanted.to_path_buf(), "No free target name left".to_string()), Decision::Go),
    }
}

/// `name (1).ext`, `name (2).ext`, ... The dot only starts an extension after the first character,
/// so a dotfile like ".keep" keeps its whole name as the stem.
fn free_name(wanted: &Path, claimed: &HashSet<String>) -> Option<PathBuf> {
    let name = wanted.file_name()?.to_string_lossy().into_owned();
    let (stem, extension) = match name.rfind('.') {
        Some(dot) if dot > 0 => (name[..dot].to_string(), name[dot..].to_string()),
        _ => (name.clone(), String::new()),
    };
    let parent = wanted.parent()?;
    for suffix in 1..100_000 {
        let candidate = parent.join(format!("{stem} ({suffix}){extension}"));
        if !claimed.contains(&key(&candidate)) && !candidate.exists() {
            return Some(candidate);
        }
    }
    None
}

fn perform(request: &MoveRequest, from: &Path, to: &Path) -> Result<(), String> {
    if let Some(parent) = to.parent() {
        fs::create_dir_all(parent).map_err(|error| format!("Cannot create {}: {error}", parent.display()))?;
    }
    if request.conflict == ConflictPolicy::Overwrite && to.exists() {
        remove_single_file(to, false).map_err(|error| format!("Cannot replace {}: {error}", to.display()))?;
    }
    match request.action {
        // A move across mounts is left as the failure the operating system reports: `MoveAction::Copy`
        // is the way to relocate a file between volumes.
        MoveAction::Move => fs::rename(from, to).map_err(|error| format!("Failed to move {} to {}: {error}", from.display(), to.display())),
        MoveAction::Copy => fs::copy(from, to)
            .map(|_| ())
            .map_err(|error| format!("Failed to copy {} to {}: {error}", from.display(), to.display())),
    }
}

fn wanted_target(root: &Path, from: &Path, preserve_structure: bool) -> PathBuf {
    let name = from.file_name().unwrap_or(from.as_os_str());
    if !preserve_structure {
        return root.join(name);
    }
    let mut trail = PathBuf::new();
    for part in from.components().filter(|component| matches!(component, Component::Normal(_))) {
        trail.push(part.as_os_str());
    }
    // The file name is not part of the folder trail it should mirror.
    trail.pop();
    root.join(trail).join(name)
}

/// Claimed names compare case-insensitively, because the destination filesystem may not
/// distinguish cases and a second file must not be planned onto a name it cannot get.
fn key(path: &Path) -> String {
    path.to_string_lossy().to_lowercase()
}

fn item(from: &Path, to: Option<&Path>, status: MoveStatus, detail: String) -> MoveItem {
    MoveItem {
        from: from.to_string_lossy().into_owned(),
        to: to.map_or_else(String::new, |to| to.to_string_lossy().into_owned()),
        status,
        detail,
    }
}

/// Counts come out of the per-file log rather than a running total, so an entry and its counter can
/// never disagree.
fn summarise(items: Vec<MoveItem>) -> MoveOutcome {
    let count = |wanted: &MoveStatus| items.iter().filter(|item| &item.status == wanted).count() as i32;
    let (moved, copied, planned, skipped, failed) = (
        count(&MoveStatus::Moved),
        count(&MoveStatus::Copied),
        count(&MoveStatus::Planned),
        count(&MoveStatus::Skipped),
        count(&MoveStatus::Failed),
    );
    let messages = if planned > 0 {
        format!("Planned {} operation(s); {skipped} skipped.", moved + copied + planned)
    } else {
        format!("Completed {} operation(s); {failed} failed.", moved + copied)
    };
    MoveOutcome {
        moved,
        copied,
        planned,
        skipped,
        failed,
        items,
        messages,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_dry_run_plans_the_move_without_touching_disk() {
        let root = scratch("dry_run");
        let source = write(&root.join("in"), "clip.mp4", "movie");
        let destination = root.join("out");

        let outcome = apply(&request(std::slice::from_ref(&source), &destination, MoveAction::Move, ConflictPolicy::Skip, false, true)).expect("dry run");
        assert_eq!((outcome.planned, outcome.moved, outcome.copied), (1, 0, 0));
        assert_eq!(outcome.items[0].to, destination.join("clip.mp4").to_string_lossy());
        assert!(source.exists(), "a planned move must leave the file alone");
        assert!(!destination.exists(), "a planned move must not even create the folder");

        let outcome = apply(&request(std::slice::from_ref(&source), &destination, MoveAction::Move, ConflictPolicy::Skip, false, false)).expect("move runs");
        assert_eq!((outcome.moved, outcome.failed), (1, 0));
        assert!(!source.exists(), "a move leaves nothing behind");
        assert_eq!(fs::read_to_string(destination.join("clip.mp4")).expect("read the moved file"), "movie");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn a_copy_keeps_the_original() {
        let root = scratch("copy");
        let source = write(&root.join("in"), "photo.png", "bytes");
        let destination = root.join("out");

        let outcome = apply(&request(std::slice::from_ref(&source), &destination, MoveAction::Copy, ConflictPolicy::Skip, false, false)).expect("copy runs");
        assert_eq!((outcome.copied, outcome.moved), (1, 0));
        assert!(source.exists(), "a copy keeps the original");
        assert_eq!(fs::read_to_string(destination.join("photo.png")).expect("read the copy"), "bytes");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn a_stopped_run_moves_nothing() {
        let root = scratch("stopped");
        let source = write(&root.join("in"), "clip.mp4", "movie");
        let destination = root.join("out");
        let stop = AtomicBool::new(true);

        let outcome = apply_stopping(
            &request(std::slice::from_ref(&source), &destination, MoveAction::Move, ConflictPolicy::Skip, false, false),
            &stop,
        )
        .expect("stopped run");
        assert_eq!((outcome.moved, outcome.copied, outcome.skipped), (0, 0, 1));
        assert_eq!(outcome.items[0].detail, "The run was stopped");
        assert!(source.exists(), "a stopped run must leave the file where it is");
        assert!(!destination.exists(), "a stopped run must not even create the folder");

        // The same request with an idle flag does move it, so the assertion above cannot pass vacuously.
        let idle = AtomicBool::new(false);
        let outcome = apply_stopping(
            &request(std::slice::from_ref(&source), &destination, MoveAction::Move, ConflictPolicy::Skip, false, false),
            &idle,
        )
        .expect("idle run");
        assert_eq!((outcome.moved, outcome.skipped), (1, 0));

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn the_default_policy_skips_a_name_that_is_already_taken() {
        let root = scratch("skip");
        let source = write(&root.join("in"), "keep.txt", "new");
        let destination = root.join("out");
        let occupant = write(&destination, "keep.txt", "existing");

        let outcome = apply(&request(std::slice::from_ref(&source), &destination, MoveAction::Move, ConflictPolicy::Skip, false, false)).expect("run");
        assert_eq!((outcome.moved, outcome.skipped, outcome.failed), (0, 1, 0));
        assert_eq!(outcome.items[0].detail, "Target already exists");
        assert!(source.exists(), "a skipped move keeps the source where it is");
        assert_eq!(fs::read_to_string(occupant).expect("the occupant survives"), "existing");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn an_error_policy_reports_the_collision_as_a_failure() {
        let root = scratch("error");
        let source = write(&root.join("in"), "notes.txt", "new");
        let destination = root.join("out");
        write(&destination, "notes.txt", "existing");

        let outcome = apply(&request(&[source], &destination, MoveAction::Move, ConflictPolicy::Error, false, false)).expect("run");
        assert_eq!((outcome.moved, outcome.failed), (0, 1));
        assert_eq!(outcome.items[0].detail, "Target already exists");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn a_rename_conflict_takes_the_next_free_suffix() {
        let root = scratch("rename");
        let source = write(&root.join("in"), "photo.png", "new");
        let destination = root.join("out");
        write(&destination, "photo.png", "one");
        write(&destination, "photo (1).png", "two");

        let outcome = apply(&request(&[source], &destination, MoveAction::Copy, ConflictPolicy::Rename, false, false)).expect("run");
        assert_eq!((outcome.copied, outcome.failed), (1, 0));
        assert_eq!(outcome.items[0].to, destination.join("photo (2).png").to_string_lossy());
        assert_eq!(fs::read_to_string(destination.join("photo (2).png")).expect("read the copy"), "new");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn overwrite_replaces_an_occupant_but_never_a_name_this_batch_just_took() {
        let root = scratch("overwrite");
        let first = write(&root.join("a"), "same.txt", "1");
        let second = write(&root.join("b"), "same.txt", "2");
        let destination = root.join("out");
        write(&destination, "same.txt", "was here");

        let outcome = apply(&request(&[first, second], &destination, MoveAction::Move, ConflictPolicy::Overwrite, false, false)).expect("run");
        assert_eq!((outcome.moved, outcome.failed), (1, 1), "unexpected: {:?}", outcome.items);
        assert!(outcome.items[1].detail.contains("Another selected file"), "unexpected: {}", outcome.items[1].detail);
        assert_eq!(fs::read_to_string(destination.join("same.txt")).expect("the winner is on disk"), "1");
        assert!(root.join("b/same.txt").exists(), "the refused file keeps its own name and place");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn preserve_structure_mirrors_the_trail_below_the_filesystem_root() {
        let root = scratch("trail");
        let source = write(&root.join("in/a/b"), "deep.txt", "nested");
        let destination = root.join("out");
        // The rule is relative to the filesystem root, so the leading "/" is dropped and everything
        // below it is recreated - stated independently of the code under test.
        let mirrored = source.strip_prefix("/").expect("the fixture is an absolute path");

        let outcome = apply(&request(std::slice::from_ref(&source), &destination, MoveAction::Move, ConflictPolicy::Skip, true, true)).expect("dry run");
        assert_eq!(outcome.items[0].to, destination.join(mirrored).to_string_lossy());

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn a_missing_source_is_reported_and_the_run_continues() {
        let root = scratch("ghost");
        let real = write(&root.join("in"), "live.txt", "content");
        let destination = root.join("out");

        let outcome = apply(&request(
            &[real, root.join("in").join("ghost.txt")],
            &destination,
            MoveAction::Move,
            ConflictPolicy::Skip,
            false,
            false,
        ))
        .expect("failures are reported, not raised");
        assert_eq!((outcome.moved, outcome.failed), (1, 1));
        assert_eq!(outcome.items[1].detail, "Source path no longer exists");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn the_destination_is_required_and_so_is_the_selection() {
        let root = scratch("guards");
        let file = write(&root, "one.txt", "a");

        let error = apply(&request(std::slice::from_ref(&file), Path::new("  "), MoveAction::Move, ConflictPolicy::Skip, false, true)).expect_err("no destination");
        assert!(error.contains("destination"), "unexpected: {error}");
        let error = apply(&request(&[], Path::new("/tmp"), MoveAction::Move, ConflictPolicy::Skip, false, true)).expect_err("no selection");
        assert!(error.contains("No files selected"), "unexpected: {error}");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    fn request(paths: &[PathBuf], destination: &Path, action: MoveAction, conflict: ConflictPolicy, preserve: bool, dry_run: bool) -> MoveRequest {
        MoveRequest {
            paths: paths.iter().map(|path| path.to_string_lossy().into_owned()).collect(),
            destination: destination.to_string_lossy().into_owned(),
            action,
            conflict,
            preserve_structure: preserve,
            dry_run,
        }
    }

    fn write(dir: &Path, name: &str, content: &str) -> PathBuf {
        fs::create_dir_all(dir).expect("create the fixture directory");
        let path = dir.join(name);
        fs::write(&path, content).expect("write fixture");
        path
    }

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("kisaki_bridge_move_{name}"));
        if dir.exists() {
            fs::remove_dir_all(&dir).expect("clear a stale scratch directory");
        }
        fs::create_dir_all(&dir).expect("create scratch directory");
        dir
    }
}
