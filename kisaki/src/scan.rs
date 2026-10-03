pub mod scan_flat;
pub mod scan_grouped;

use std::cmp::Reverse;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;

use crossbeam_channel::Sender;
use czkawka_core::common::consts::DEFAULT_THREAD_SIZE;
use czkawka_core::common::path_utils::split_path_compare;
use czkawka_core::common::progress_data::ProgressData;
use czkawka_core::common::tool_data::CommonData;
use czkawka_core::helpers::messages::MessageLimit;
use rayon::prelude::*;
use slint::{ComponentHandle, Weak};

use crate::common::{format_bytes, parse_kib_to_bytes, split_list};
use crate::fields::FieldStore;
use crate::state::{AppStore, Conditions, RowData, SharedState};
use crate::tools::ToolSpec;
use crate::{AppState, MainWindow, Phase, fli};

pub struct ScanCtx {
    pub weak: Weak<MainWindow>,
    pub state: SharedState,
    pub progress_sender: Sender<ProgressData>,
    pub stop_flag: Arc<AtomicBool>,
    pub conditions: Conditions,
    pub fields: FieldStore,
    pub tool: &'static ToolSpec,
}

pub struct Outcome {
    pub rows: Vec<RowData>,
    pub status: String,
    pub messages: String,
    pub phase: Phase,
}

pub fn start_scan(app: &MainWindow, state: &SharedState, progress_sender: Sender<ProgressData>, stop_flag: Arc<AtomicBool>) {
    let (conditions, tool, fields) = {
        let guard = state.lock().expect("App state mutex poisoned");
        let Some(tool) = crate::tools::spec(guard.tool) else {
            return;
        };
        (collect_conditions(app, &guard), tool, guard.fields.clone())
    };

    if conditions.included.is_empty() && conditions.reference.is_empty() {
        set_failure(app, &fli!("rust_no_included_paths"));
        return;
    }

    stop_flag.store(false, Ordering::Relaxed);
    reset_progress(app);

    // Drop the previous result for this tool before rescanning, so export and delete can never
    // act on data that predates the run the user just started.
    {
        let mut guard = state.lock().expect("App state mutex poisoned");
        guard.clear_rows();
        guard.models.clear_results_for(tool.id);
        crate::results::refresh(app, &mut guard);
    }

    let ctx = ScanCtx {
        weak: app.as_weak(),
        state: Arc::clone(state),
        progress_sender,
        stop_flag,
        conditions,
        fields,
        tool,
    };

    if let Err(error) = thread::Builder::new().stack_size(DEFAULT_THREAD_SIZE).spawn(move || run_scan(ctx)) {
        set_failure(app, &format!("Failed to start scanning thread: {error}"));
    }
}

fn set_failure(app: &MainWindow, message: &str) {
    let globals = app.global::<AppState>();
    globals.set_phase(Phase::Error);
    globals.set_status_text(message.into());
}

fn reset_progress(app: &MainWindow) {
    let globals = app.global::<AppState>();
    globals.set_phase(Phase::Running);
    globals.set_progress_all(0);
    globals.set_progress_current(-1);
    globals.set_progress_label("".into());
    globals.set_error_text("".into());
    globals.set_status_text(fli!("status_scanning").into());
}

pub fn collect_conditions(app: &MainWindow, store: &AppStore) -> Conditions {
    let globals = app.global::<AppState>();
    Conditions {
        included: store.included.iter().filter(|entry| !entry.is_reference).map(|entry| entry.path.clone()).collect(),
        excluded: store.excluded.iter().map(|entry| entry.path.clone()).collect(),
        reference: reference_paths_for(store),
        recursive: globals.get_recursive_search(),
        use_cache: globals.get_use_cache(),
        minimal_bytes: parse_kib_to_bytes(globals.get_min_size_kib().as_ref()),
        maximal_bytes: parse_kib_to_bytes(globals.get_max_size_kib().as_ref()),
        excluded_items: split_list(globals.get_excluded_items().as_ref()),
        allowed_extensions: split_list(globals.get_allowed_extensions().as_ref()),
        excluded_extensions: split_list(globals.get_excluded_extensions().as_ref()),
        dry_run: globals.get_dry_run(),
        move_to_trash: globals.get_move_to_trash(),
    }
}

/// Reference folders only mean something to the scanners that can compare against a
/// read-only set, so the flag is dropped for every other tool.
fn reference_paths_for(store: &AppStore) -> Vec<PathBuf> {
    match crate::tools::spec(store.tool) {
        Some(spec) if spec.tool_type.may_use_reference_paths() => store.reference_paths(),
        _ => Vec::new(),
    }
}

pub fn set_common_settings<T>(tool: &mut T, conditions: &Conditions, stop_flag: &Arc<AtomicBool>)
where
    T: CommonData,
{
    stop_flag.store(false, Ordering::Relaxed);

    tool.set_included_paths(conditions.included.clone());
    tool.set_reference_paths(conditions.reference.clone());
    tool.set_use_reference_folders(!conditions.reference.is_empty());
    tool.set_excluded_paths(conditions.excluded.clone());
    tool.set_recursive_search(conditions.recursive);
    tool.set_minimal_file_size(conditions.minimal_bytes);
    tool.set_maximal_file_size(conditions.maximal_bytes);
    tool.set_allowed_extensions(conditions.allowed_extensions.clone());
    tool.set_excluded_extensions(conditions.excluded_extensions.clone());
    tool.set_excluded_items(conditions.excluded_items.clone());
    tool.set_use_cache(conditions.use_cache);
    tool.set_dry_run(conditions.dry_run);
    tool.set_move_to_trash(conditions.move_to_trash);
}

pub fn messages(tool: &impl CommonData) -> (Option<String>, String) {
    let messages = tool.get_text_messages();
    (messages.critical.clone(), messages.create_messages_text(MessageLimit::NoLimit))
}

/// Reference rows sort with the rest of their group by path and are never selected.
/// In a plain group the largest member is left unchecked so a default deletion keeps
/// one copy; in a group that contains a reference row every ordinary copy is selected,
/// because the original is safe inside the reference directory. This is the same split
/// `results::reclaimable_bytes` measures.
pub fn build_grouped(groups: Vec<(Option<RowData>, Vec<RowData>)>) -> Vec<RowData> {
    let mut entries: Vec<Vec<RowData>> = groups
        .into_iter()
        .map(|(reference, mut members)| {
            if let Some(row) = reference {
                members.push(row);
            }
            members.par_sort_unstable_by(|a, b| split_path_compare(a.path.as_path(), b.path.as_path()));
            members
        })
        .filter(|members| !members.is_empty())
        .collect();

    // Biggest groups first, so the most valuable results stay on top.
    entries.sort_by_key(|members| Reverse(members.iter().map(|row| row.size_bytes).sum::<u64>()));

    let mut rows = Vec::with_capacity(entries.iter().map(Vec::len).sum());
    for (group_index, mut members) in entries.into_iter().enumerate() {
        let group_index = group_index as i32;
        let group_size = members.len() as i32;
        let keeper = group_keeper(&members);
        for (position, row) in members.iter_mut().enumerate() {
            row.group_index = group_index;
            row.group_size = group_size;
            row.is_group_start = position == 0;
            row.checked = !row.is_reference && Some(position) != keeper;
        }
        rows.append(&mut members);
    }
    rows
}

/// The copy a default deletion has to leave behind: no ordinary member is spared when the
/// group owns a reference row, otherwise the largest member (ties go to the first in path order).
fn group_keeper(members: &[RowData]) -> Option<usize> {
    if members.iter().any(|row| row.is_reference) {
        return None;
    }
    members
        .iter()
        .enumerate()
        .reduce(|largest, candidate| if candidate.1.size_bytes > largest.1.size_bytes { candidate } else { largest })
        .map(|(position, _)| position)
}

pub fn build_flat(mut rows: Vec<RowData>) -> Vec<RowData> {
    rows.par_sort_unstable_by(|a, b| split_path_compare(a.path.as_path(), b.path.as_path()));
    rows
}

/// Splits a full path into the name and directory the results table shows.
pub fn make_row(path: PathBuf, cells: Vec<String>, sort_keys: Vec<i64>, size: u64, mtime: u64) -> RowData {
    let (directory, name) = czkawka_core::common::split_path(path.as_path());
    RowData::new(path, name, directory, cells, sort_keys, size, mtime)
}

pub fn outcome(rows: Vec<RowData>, critical: Option<String>, messages: String, stopped: bool, grouped: bool) -> Outcome {
    let phase = match (critical.clone(), stopped) {
        (Some(_), _) => Phase::Error,
        (None, true) => Phase::Stopped,
        (None, false) => Phase::Completed,
    };
    let files = rows.len();
    let groups = if grouped { rows.iter().filter(|row| row.is_group_start).count() } else { files };
    let bytes: u64 = rows.iter().map(|row| row.size_bytes).sum();

    let status = if let Some(critical) = critical {
        critical
    } else if stopped {
        fli!("status_stopped")
    } else if files == 0 {
        fli!("status_nothing_found")
    } else {
        fli!("status_found", files = files, groups = groups, size = format_bytes(bytes))
    };

    Outcome { rows, status, messages, phase }
}

fn run_scan(ctx: ScanCtx) {
    let outcome = if ctx.tool.grouped { scan_grouped::run(&ctx) } else { scan_flat::run(&ctx) };

    let outcome = match outcome {
        Ok(outcome) => outcome,
        Err(error) => Outcome {
            rows: Vec::new(),
            status: error,
            messages: String::new(),
            phase: Phase::Error,
        },
    };

    let store = Arc::clone(&ctx.state);
    let weak = ctx.weak;
    let rows = outcome.rows;
    let _ = weak.upgrade_in_event_loop(move |app| {
        {
            let mut guard = store.lock().expect("App state mutex poisoned");
            guard.set_rows(rows);
            crate::results::refresh(&app, &mut guard);
        }
        let globals = app.global::<AppState>();
        globals.set_phase(outcome.phase);
        globals.set_error_text(outcome.messages.as_str().into());
        globals.set_status_text(outcome.status.as_str().into());
    });
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn row(size: u64, name: &str) -> RowData {
        let mut data = RowData::new(PathBuf::from(format!("/x/{name}")), name.to_string(), "/x".to_string(), vec![], vec![], size, 0);
        data.is_reference = name == "ref";
        data
    }

    #[test]
    fn plain_group_keeps_its_largest_copy() {
        let rows = build_grouped(vec![(None, vec![row(100, "a"), row(300, "b")])]);

        assert_eq!(rows.len(), 2);
        assert!(rows.iter().all(|row| row.group_index == 0));
        assert!(rows.iter().all(|row| row.group_size == 2));
        assert!(rows[0].is_group_start);
        // Path order puts "a" first, so the kept file is the second, larger row.
        assert_eq!(rows[0].name, "a");
        assert_eq!(rows[1].name, "b");
        assert!(rows[0].checked, "the smaller copy is selected for deletion");
        assert!(!rows[1].checked, "the largest member is kept");
    }

    #[test]
    fn reference_group_selects_every_copy() {
        let rows = build_grouped(vec![(Some(row(900, "ref")), vec![row(100, "a"), row(300, "b")])]);

        assert_eq!(rows.len(), 3);
        assert!(rows.iter().all(|row| row.group_index == 0));
        assert!(rows.iter().all(|row| row.group_size == 3));
        assert_eq!(rows[2].name, "ref");
        assert!(!rows[2].checked, "a reference row is never selectable");
        assert!(rows[0].checked);
        assert!(rows[1].checked, "the original lives in the reference dir, so both copies go");
    }

    #[test]
    fn a_small_reference_still_spares_no_ordinary_copy() {
        let rows = build_grouped(vec![(Some(row(10, "ref")), vec![row(500, "a"), row(200, "b")])]);

        assert_eq!(rows[0].name, "a");
        assert!(rows[0].checked, "the largest ordinary member is not the keeper here");
        assert!(rows[1].checked);
        assert!(!rows[2].checked);
    }

    #[test]
    fn plain_group_selection_matches_the_reclaimable_measure() {
        let rows = build_grouped(vec![(None, vec![row(100, "a"), row(300, "b"), row(200, "c")])]);
        let refs: Vec<&RowData> = rows.iter().collect();

        let selected: u64 = rows.iter().filter(|row| row.checked).map(|row| row.size_bytes).sum();
        assert_eq!(selected, crate::results::reclaimable_bytes(&refs, true, false));
        assert_eq!(selected, 300, "a and c go, the 300 byte copy stays");
    }

    #[test]
    fn referenced_group_selection_matches_the_reclaimable_measure() {
        let rows = build_grouped(vec![(Some(row(10, "ref")), vec![row(500, "a"), row(200, "b")])]);
        let refs: Vec<&RowData> = rows.iter().collect();

        let selected: u64 = rows.iter().filter(|row| row.checked).map(|row| row.size_bytes).sum();
        assert_eq!(selected, crate::results::reclaimable_bytes(&refs, true, true));
        assert_eq!(selected, 700, "every ordinary copy is recoverable next to a reference original");
    }

    #[test]
    fn groups_are_ordered_by_their_total_size() {
        let groups = vec![(None, vec![row(10, "small")]), (None, vec![row(1000, "big"), row(1000, "big2")])];
        let rows = build_grouped(groups);
        assert_eq!(rows[0].group_index, 0);
        assert_eq!(rows[0].name, "big");
        assert_eq!(rows[2].group_index, 1);
    }

    #[test]
    fn flat_rows_get_no_group_membership() {
        let rows = build_flat(vec![row(1, "b"), row(2, "a")]);
        assert_eq!(rows[0].name, "a");
        assert!(rows.iter().all(|row| row.group_index == -1));
    }
}
