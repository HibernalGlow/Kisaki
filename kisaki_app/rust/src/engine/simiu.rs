use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use czkawka_core::common::fs_ops::{remove_folder_if_contains_only_empty_folders, remove_single_file};
use serde_json::{Value, json};

use crate::api::types::{SimiuApplyOutcome, SimiuApplyRequest, SimiuItem, SimiuMode, SimiuOperation, SimiuStatus, SimiuUndoOutcome, SimiuUndoRequest};
use crate::engine::flat;

/// Performs and undoes the board's "sort these images into set folders" decisions. Which images form
/// a set is a judgement about scan results, so it is made where the sets are visible; what lives here
/// is the mutation, its undo journal, and the rule that nothing is ever written over an existing
/// file. One journal per scanned root, written after the operations it records.
pub fn apply(request: &SimiuApplyRequest) -> Result<SimiuApplyOutcome, String> {
    if request.operations.is_empty() {
        return Err("No Simiu set operations were supplied".to_string());
    }
    let mut recorder = Recorder::new(request.mode.clone(), request.dry_run);
    let items: Vec<SimiuItem> = request.operations.iter().map(|operation| recorder.run(operation)).collect();
    let journals = if request.dry_run { Vec::new() } else { recorder.write_journals()? };
    Ok(summarise(items, journals))
}

/// Reverses one journal: newest operation first, so a folder emptied last is restored last.
pub fn undo(request: &SimiuUndoRequest) -> Result<SimiuUndoOutcome, String> {
    let journal = read_journal(Path::new(&request.journal))?;
    let mut claimed: HashSet<String> = HashSet::new();
    let items: Vec<SimiuItem> = journal.operations.iter().rev().map(|logged| undo_one(request, logged, &mut claimed)).collect();

    if request.clean_empty_directories && !request.dry_run {
        cleanup_directories(&journal.created_directories);
    }

    let (mut done, mut planned, mut failed) = (0_i32, 0_i32, 0_i32);
    for item in &items {
        match item.status {
            SimiuStatus::Planned => planned += 1,
            SimiuStatus::Failed => failed += 1,
            _ => done += 1,
        }
    }
    Ok(SimiuUndoOutcome {
        done,
        planned,
        failed,
        messages: format!("Restored {done} operation(s); {failed} failed."),
        items,
    })
}

/// A name is taken if the disk holds it or if this run already handed it out - the filesystem only
/// learns about the first file when the second one is about to be written.
struct Recorder {
    mode: SimiuMode,
    dry_run: bool,
    claimed: HashSet<String>,
    logged: HashMap<PathBuf, Vec<LoggedOperation>>,
    created: HashMap<PathBuf, Vec<PathBuf>>,
}

/// One completed operation, as it is written to the journal.
#[derive(Debug, Clone)]
struct LoggedOperation {
    mode: &'static str,
    src: PathBuf,
    dst: PathBuf,
}

impl Recorder {
    fn new(mode: SimiuMode, dry_run: bool) -> Recorder {
        Recorder {
            mode,
            dry_run,
            claimed: HashSet::new(),
            logged: HashMap::new(),
            created: HashMap::new(),
        }
    }

    fn run(&mut self, operation: &SimiuOperation) -> SimiuItem {
        let source = PathBuf::from(&operation.source);
        let root = PathBuf::from(&operation.root);
        let target = free_path(&PathBuf::from(&operation.target), &mut self.claimed);

        if self.dry_run {
            return item(&source, Some(&target), SimiuStatus::Planned, String::new());
        }

        let directory = match target.parent() {
            Some(directory) => directory.to_path_buf(),
            None => return item(&source, Some(&target), SimiuStatus::Failed, "The target has no parent folder".to_string()),
        };
        let preexisting = directory.exists();
        if let Err(error) = fs::create_dir_all(&directory) {
            return item(&source, Some(&target), SimiuStatus::Failed, format!("Cannot create {}: {error}", directory.display()));
        }
        if !preexisting {
            self.created.entry(root.clone()).or_default().push(directory);
        }

        match self.perform(&source, &target) {
            Ok(status) => {
                self.logged.entry(root).or_default().push(LoggedOperation {
                    mode: mode_name(&self.mode),
                    src: source.clone(),
                    dst: target.clone(),
                });
                item(&source, Some(&target), status, String::new())
            }
            Err(error) => item(&source, Some(&target), SimiuStatus::Failed, error),
        }
    }

    /// Removals stay on the engine's own file operations. The link is created with std because the
    /// engine's `make_hard_link` is documented to require an already existing destination, which a
    /// set folder never has.
    fn perform(&self, source: &Path, target: &Path) -> Result<SimiuStatus, String> {
        match self.mode {
            SimiuMode::Move => fs::rename(source, target)
                .map(|()| SimiuStatus::Moved)
                .map_err(|error| format!("Failed to move {} to {}: {error}", source.display(), target.display())),
            SimiuMode::Copy => fs::copy(source, target)
                .map(|_| SimiuStatus::Copied)
                .map_err(|error| format!("Failed to copy {} to {}: {error}", source.display(), target.display())),
            SimiuMode::Link => fs::hard_link(source, target)
                .map(|()| SimiuStatus::Linked)
                .map_err(|error| format!("Failed to link {} to {}: {error}", source.display(), target.display())),
        }
    }

    /// The journal is written after the work it describes, so a crash mid-run cannot claim more than
    /// actually happened. Roots are ordered by name to keep the output stable.
    fn write_journals(&self) -> Result<Vec<String>, String> {
        let mut roots: Vec<&PathBuf> = self.logged.keys().collect();
        roots.sort();

        let mut written = Vec::with_capacity(roots.len());
        let created_at = flat::format_timestamp(now_seconds());
        for root in roots {
            let mut claimed = HashSet::new();
            let path = free_path(&root.join(format!(".simiu-undo-{}.json", stamp(&created_at))), &mut claimed);
            let journal = Journal {
                root: root.clone(),
                created_at: created_at.clone(),
                operations: self.logged.get(root).cloned().unwrap_or_default(),
                created_directories: self.created.get(root).cloned().unwrap_or_default(),
            };
            write_journal(&journal, &path)?;
            written.push(path.to_string_lossy().into_owned());
        }
        Ok(written)
    }
}

fn undo_one(request: &SimiuUndoRequest, logged: &LoggedOperation, claimed: &mut HashSet<String>) -> SimiuItem {
    if !logged.dst.exists() {
        return item(&logged.dst, Some(&logged.src), SimiuStatus::Failed, "Target path no longer exists".to_string());
    }
    // Claimed in both directions, so a dry run predicts exactly the name the real run would use.
    let restored = free_path(&logged.src, claimed);
    if request.dry_run {
        return item(&logged.dst, Some(&restored), SimiuStatus::Planned, String::new());
    }

    match logged.mode {
        "move" => match fs::rename(&logged.dst, &restored) {
            Ok(()) => item(&logged.dst, Some(&restored), SimiuStatus::Restored, String::new()),
            Err(error) => item(
                &logged.dst,
                Some(&restored),
                SimiuStatus::Failed,
                format!("Failed to restore {}: {error}", logged.dst.display()),
            ),
        },
        // A copy or a link is undone by removing the result: the original was never touched.
        _ => match remove_single_file(&logged.dst, false) {
            Ok(()) => item(&logged.dst, None, SimiuStatus::Removed, String::new()),
            Err(error) => item(&logged.dst, None, SimiuStatus::Failed, error),
        },
    }
}

/// Longest paths first, so a nested set folder is gone before its parent is tested for emptiness.
/// Anything that is not empty any more is left alone, exactly as the reference frontend does.
fn cleanup_directories(directories: &[PathBuf]) {
    let mut sorted: Vec<&PathBuf> = directories.iter().collect();
    sorted.sort_by_key(|directory| std::cmp::Reverse(directory.as_os_str().len()));
    for directory in sorted {
        let _ = remove_folder_if_contains_only_empty_folders(directory, false);
    }
}

fn free_path(path: &Path, claimed: &mut HashSet<String>) -> PathBuf {
    let wanted = path.to_path_buf();
    let mut candidate = wanted.clone();
    let mut index = 1_u32;
    while claimed.contains(&key(&candidate)) || candidate.exists() {
        candidate = with_suffix(&wanted, index);
        index += 1;
    }
    claimed.insert(key(&candidate));
    candidate
}

/// `name.ext` becomes `name_01.ext`, then `_02`, matching the naming the reference frontend writes.
fn with_suffix(path: &Path, index: u32) -> PathBuf {
    let name = path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
    let parent = path.parent().unwrap_or_else(|| Path::new(""));
    match name.rfind('.') {
        Some(dot) if dot > 0 => parent.join(format!("{}_{:02}{}", &name[..dot], index, &name[dot..])),
        _ => parent.join(format!("{name}_{index:02}")),
    }
}

fn key(path: &Path) -> String {
    path.to_string_lossy().to_lowercase()
}

fn mode_name(mode: &SimiuMode) -> &'static str {
    match mode {
        SimiuMode::Move => "move",
        SimiuMode::Copy => "copy",
        SimiuMode::Link => "link",
    }
}

/// The only modes a journal may name. Anything else is rejected rather than replayed, so a hand
/// edited or future log cannot make undo delete or overwrite something it never recorded.
fn logged_mode(mode: &str) -> Option<&'static str> {
    match mode {
        "move" => Some("move"),
        "copy" => Some("copy"),
        "link" => Some("link"),
        _ => None,
    }
}

fn item(from: &Path, to: Option<&Path>, status: SimiuStatus, detail: String) -> SimiuItem {
    SimiuItem {
        from: from.to_string_lossy().into_owned(),
        to: to.map_or_else(String::new, |to| to.to_string_lossy().into_owned()),
        status,
        detail,
    }
}

/// Counts come out of the per-file log rather than a running total, so an entry and its counter can
/// never disagree.
fn summarise(items: Vec<SimiuItem>, journals: Vec<String>) -> SimiuApplyOutcome {
    let count = |wanted: &SimiuStatus| items.iter().filter(|item| &item.status == wanted).count() as i32;
    let (planned, failed) = (count(&SimiuStatus::Planned), count(&SimiuStatus::Failed));
    let done = items.len() as i32 - planned - failed;
    let messages = if planned > 0 {
        format!("Planned {planned} Simiu set operation(s); {failed} failed.")
    } else {
        format!("Applied {done} Simiu set operation(s); {failed} failed.")
    };
    SimiuApplyOutcome {
        done,
        planned,
        failed,
        items,
        journals,
        messages,
    }
}

fn now_seconds() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|elapsed| elapsed.as_secs()).unwrap_or_default()
}

/// `2026-10-03 19:52:00` becomes `20261003-195200`, the file name spelling the reference uses.
fn stamp(created_at: &str) -> String {
    let (date, time) = created_at.split_once(' ').unwrap_or((created_at, ""));
    format!("{}-{}", date.replace('-', ""), time.replace(':', ""))
}

struct Journal {
    root: PathBuf,
    created_at: String,
    operations: Vec<LoggedOperation>,
    created_directories: Vec<PathBuf>,
}

fn write_journal(journal: &Journal, path: &Path) -> Result<(), String> {
    let payload = json!({
        "version": 1,
        "createdAt": journal.created_at,
        "root": journal.root.to_string_lossy(),
        "operations": journal.operations.iter().map(|logged| json!({ "mode": logged.mode, "src": logged.src.to_string_lossy(), "dst": logged.dst.to_string_lossy() })).collect::<Vec<Value>>(),
        "createdDirectories": journal.created_directories.iter().map(|directory| directory.to_string_lossy().into_owned()).collect::<Vec<String>>(),
    });
    fs::write(path, format!("{}\n", serde_json::to_string_pretty(&payload).map_err(|error| error.to_string())?))
        .map_err(|error| format!("Cannot write {}: {error}", path.display()))
}

/// Reading is strict on purpose: a journal this bridge cannot describe exactly must not be replayed.
/// The field names are the ones the reference implementation writes, so a journal is readable by both.
fn read_journal(path: &Path) -> Result<Journal, String> {
    let text = fs::read_to_string(path).map_err(|error| format!("Cannot read {}: {error}", path.display()))?;
    let value: Value = serde_json::from_str(&text).map_err(|error| format!("Invalid Simiu undo log: {error}"))?;

    let version = value.get("version").and_then(Value::as_i64).ok_or("Invalid Simiu undo log")?;
    if version != 1 {
        return Err("Invalid Simiu undo log".to_string());
    }
    let root = value.get("root").and_then(Value::as_str).ok_or("Invalid Simiu undo log")?;
    let entries = value.get("operations").and_then(Value::as_array).ok_or("Invalid Simiu undo log")?;

    let mut operations = Vec::with_capacity(entries.len());
    for entry in entries {
        let mode = entry.get("mode").and_then(Value::as_str).and_then(logged_mode);
        let src = entry.get("src").and_then(Value::as_str);
        let dst = entry.get("dst").and_then(Value::as_str);
        let (Some(mode), Some(src), Some(dst)) = (mode, src, dst) else {
            return Err("Invalid Simiu undo log operations".to_string());
        };
        operations.push(LoggedOperation {
            mode,
            src: PathBuf::from(src),
            dst: PathBuf::from(dst),
        });
    }

    let created_directories = value
        .get("createdDirectories")
        .and_then(Value::as_array)
        .map(|entries| entries.iter().filter_map(Value::as_str).map(PathBuf::from).collect())
        .unwrap_or_default();

    Ok(Journal {
        root: PathBuf::from(root),
        created_at: value.get("createdAt").and_then(Value::as_str).unwrap_or_default().to_string(),
        operations,
        created_directories,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apply_moves_files_into_set_folders_and_journals_the_result() {
        let root = scratch("apply");
        let first = write(&root.join("loose"), "one.png", b"1");
        let second = write(&root.join("loose"), "two.png", b"2");
        let set = root.join("sets/set-001");

        let outcome = apply(&apply_request(&[
            operation(&root, &first, &set.join("one.png")),
            operation(&root, &second, &set.join("two.png")),
        ]))
        .expect("apply runs");

        assert_eq!((outcome.done, outcome.failed), (2, 0), "unexpected: {:?}", outcome.items);
        assert!(set.join("one.png").exists() && set.join("two.png").exists(), "both files should be in the set");
        assert!(!first.exists(), "a move leaves nothing behind");
        assert_eq!(outcome.journals.len(), 1, "one root, one journal");

        let journal = read_journal(Path::new(&outcome.journals[0])).expect("the journal reads back");
        assert_eq!(journal.operations.len(), 2);
        assert_eq!(journal.operations[0].mode, "move");
        assert_eq!(journal.created_directories, vec![set.clone()], "the set folder was created by this run");
        assert!(outcome.journals[0].contains(".simiu-undo-"), "unexpected: {}", outcome.journals[0]);

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn a_dry_run_moves_nothing_and_writes_no_journal() {
        let root = scratch("dry_run");
        let source = write(&root.join("loose"), "one.png", b"1");

        let request = SimiuApplyRequest {
            mode: SimiuMode::Move,
            operations: vec![operation(&root, &source, &root.join("sets/set-001/one.png"))],
            dry_run: true,
        };
        let outcome = apply(&request).expect("dry run");

        assert_eq!((outcome.planned, outcome.done, outcome.journals.len()), (1, 0, 0));
        assert!(source.exists(), "a planned move must not touch the file");
        assert!(!root.join("sets").exists(), "a planned move must not even create the folder");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn undo_puts_a_moved_set_back_and_removes_the_emptied_folder() {
        let root = scratch("undo_move");
        let source = write(&root.join("loose"), "one.png", b"payload");
        let target = root.join("sets/set-001/one.png");

        let applied = apply(&apply_request(&[operation(&root, &source, &target)])).expect("apply runs");
        let undone = undo(&undo_request(&applied.journals[0], true)).expect("undo runs");

        assert_eq!((undone.done, undone.failed), (1, 0), "unexpected: {:?}", undone.items);
        assert_eq!(undone.items[0].to, source.to_string_lossy());
        assert_eq!(fs::read(source).expect("the file is back"), b"payload");
        assert!(!root.join("sets/set-001").exists(), "the folder this run created should be gone");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn undo_removes_a_copied_file_and_keeps_the_original() {
        let root = scratch("undo_copy");
        let source = write(&root.join("loose"), "one.png", b"keep me");

        let applied = apply(&copy_request(&[operation(&root, &source, &root.join("sets/set-001/one.png"))])).expect("apply runs");
        let undone = undo(&undo_request(&applied.journals[0], false)).expect("undo runs");

        assert_eq!((undone.done, undone.failed), (1, 0), "unexpected: {:?}", undone.items);
        assert_eq!(undone.items[0].status, SimiuStatus::Removed);
        assert!(!root.join("sets/set-001/one.png").exists(), "the copy should be gone");
        assert_eq!(fs::read(source).expect("the original survives"), b"keep me");
        assert!(root.join("sets/set-001").exists(), "cleanup was not asked for");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn two_files_naming_the_same_target_do_not_overwrite_each_other() {
        let root = scratch("collision");
        let one = write(&root.join("a"), "same.png", b"1");
        let two = write(&root.join("b"), "same.png", b"2");
        let set = root.join("sets/set-001");

        let outcome = apply(&apply_request(&[
            operation(&root, &one, &set.join("same.png")),
            operation(&root, &two, &set.join("same.png")),
        ]))
        .expect("apply runs");

        assert_eq!((outcome.done, outcome.failed), (2, 0));
        assert_eq!(outcome.items[1].to, set.join("same_01.png").to_string_lossy());
        assert_eq!(fs::read(set.join("same.png")).expect("first keeps the name"), b"1");
        assert_eq!(fs::read(set.join("same_01.png")).expect("second gets the next slot"), b"2");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn undo_refuses_a_file_that_is_no_longer_where_the_journal_says() {
        let root = scratch("vanished");
        let source = write(&root.join("loose"), "one.png", b"1");
        let target = root.join("sets/set-001/one.png");

        let applied = apply(&apply_request(&[operation(&root, &source, &target)])).expect("apply runs");
        fs::remove_file(&target).expect("remove the moved file");

        let undone = undo(&undo_request(&applied.journals[0], false)).expect("the failure is reported");
        assert_eq!((undone.done, undone.failed), (0, 1));
        assert_eq!(undone.items[0].detail, "Target path no longer exists");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn a_journal_this_bridge_cannot_describe_is_not_replayed() {
        let root = scratch("bad_journal");
        let junk = root.join(".simiu-undo-bad.json");
        fs::write(&junk, "{ not json }").expect("write junk");
        assert!(undo(&undo_request(junk.to_string_lossy().as_ref(), false)).is_err());

        let wrong_version = root.join(".simiu-undo-v2.json");
        fs::write(&wrong_version, r#"{"version":2,"root":"/x","operations":[]}"#).expect("write v2");
        assert!(undo(&undo_request(wrong_version.to_string_lossy().as_ref(), false)).is_err());

        let bad_mode = root.join(".simiu-undo-bad-mode.json");
        fs::write(&bad_mode, r#"{"version":1,"root":"/x","operations":[{"mode":"delete","src":"/a","dst":"/b"}]}"#).expect("write bad mode");
        let error = undo(&undo_request(bad_mode.to_string_lossy().as_ref(), false)).expect_err("an unknown mode must not run");
        assert!(error.contains("operations"), "unexpected: {error}");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn link_mode_shares_the_bytes_and_the_original_stays() {
        let root = scratch("link");
        let source = write(&root.join("loose"), "one.png", b"shared");

        let request = SimiuApplyRequest {
            mode: SimiuMode::Link,
            operations: vec![operation(&root, &source, &root.join("sets/set-001/one.png"))],
            dry_run: false,
        };
        let outcome = apply(&request).expect("link runs");

        assert_eq!((outcome.done, outcome.failed), (1, 0), "unexpected: {:?}", outcome.items);
        assert_eq!(fs::read(source).expect("the original stays"), b"shared");
        assert_eq!(fs::read(root.join("sets/set-001/one.png")).expect("read the link"), b"shared");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn an_empty_operation_list_is_refused() {
        let error = apply(&apply_request(&[])).expect_err("nothing to do");
        assert!(error.contains("No Simiu set operations"), "unexpected: {error}");
    }

    #[test]
    fn the_journal_stamp_drops_the_calendar_separators() {
        assert_eq!(stamp("2026-10-03 19:52:00"), "20261003-195200");
    }

    #[test]
    fn a_journal_written_by_the_reference_frontend_is_replayable() {
        let root = scratch("interop");
        let set = root.join("sets/set-001");
        fs::create_dir_all(&set).expect("create the set folder");
        fs::create_dir_all(root.join("loose")).expect("create the folder the file came from");
        let moved = write(&set, "one.png", b"payload");
        let original = root.join("loose/one.png");

        // Written by hand in the exact spelling the reference implementation uses. The paths go
        // through the JSON writer rather than into the template raw, because a Windows path is full
        // of backslashes and `\U` is not a legal JSON escape - the parser under test is right to
        // reject that, so the fixture has to be the well-formed thing the real frontend writes.
        let journal = root.join(".simiu-undo-20261003-195200.json");
        fs::write(
            &journal,
            format!(
                "{{\n  \"version\": 1,\n  \"createdAt\": \"2026-10-03T19:52:00.000Z\",\n  \"root\": {root},\n  \"operations\": [{{ \"mode\": \"move\", \"src\": {original}, \"dst\": {moved} }}],\n  \"createdDirectories\": [{set}]\n}}\n",
                root = serde_json::to_string(&root.to_string_lossy()).expect("json string"),
                original = serde_json::to_string(&original.to_string_lossy()).expect("json string"),
                moved = serde_json::to_string(&moved.to_string_lossy()).expect("json string"),
                set = serde_json::to_string(&set.to_string_lossy()).expect("json string"),
            ),
        )
        .expect("write the reference journal");

        let undone = undo(&undo_request(journal.to_string_lossy().as_ref(), true)).expect("undo runs");
        assert_eq!((undone.done, undone.failed), (1, 0), "unexpected: {:?}", undone.items);
        assert_eq!(fs::read(original).expect("the file is back where the log says"), b"payload");

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    #[test]
    fn the_written_journal_uses_the_reference_field_names() {
        let root = scratch("journal_shape");
        let source = write(&root.join("loose"), "one.png", b"1");

        let applied = apply(&apply_request(&[operation(&root, &source, &root.join("sets/set-001/one.png"))])).expect("apply runs");
        let text = fs::read_to_string(&applied.journals[0]).expect("read the journal");
        for field in [
            "\"version\": 1",
            "\"createdAt\"",
            "\"root\"",
            "\"operations\"",
            "\"createdDirectories\"",
            "\"mode\": \"move\"",
            "\"src\"",
            "\"dst\"",
        ] {
            assert!(text.contains(field), "missing {field} in: {text}");
        }

        fs::remove_dir_all(&root).expect("remove scratch directory");
    }

    fn operation(root: &Path, source: &Path, target: &Path) -> SimiuOperation {
        SimiuOperation {
            root: root.to_string_lossy().into_owned(),
            source: source.to_string_lossy().into_owned(),
            target: target.to_string_lossy().into_owned(),
        }
    }

    fn apply_request(operations: &[SimiuOperation]) -> SimiuApplyRequest {
        SimiuApplyRequest {
            mode: SimiuMode::Move,
            operations: operations.to_vec(),
            dry_run: false,
        }
    }

    fn copy_request(operations: &[SimiuOperation]) -> SimiuApplyRequest {
        SimiuApplyRequest {
            mode: SimiuMode::Copy,
            operations: operations.to_vec(),
            dry_run: false,
        }
    }

    fn undo_request(journal: &str, clean: bool) -> SimiuUndoRequest {
        SimiuUndoRequest {
            journal: journal.to_string(),
            clean_empty_directories: clean,
            dry_run: false,
        }
    }

    fn write(dir: &Path, name: &str, content: &[u8]) -> PathBuf {
        fs::create_dir_all(dir).expect("create the fixture directory");
        let path = dir.join(name);
        fs::write(&path, content).expect("write fixture");
        path
    }

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("kisaki_bridge_simiu_{name}"));
        if dir.exists() {
            fs::remove_dir_all(&dir).expect("clear a stale scratch directory");
        }
        fs::create_dir_all(&dir).expect("create scratch directory");
        dir
    }
}
