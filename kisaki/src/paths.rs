use std::collections::HashSet;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;

use rfd::FileDialog;
use slint::{ComponentHandle, ModelRc, VecModel};

use crate::state::{AppStore, PathEntry, SharedState};
use crate::{AppState, MainWindow, PathRow};

pub const LIST_INCLUDED: i32 = 0;
pub const LIST_EXCLUDED: i32 = 1;

/// Parses user typed paths: newline, comma or semicolon separate entries, surrounding
/// quotes are dropped and duplicates are removed.
pub fn parse_path_list(text: &str) -> Vec<PathBuf> {
    let mut seen = HashSet::new();
    let mut paths = Vec::new();
    for raw in text.split(['\n', '\r', ',', ';']) {
        let trimmed = raw.trim().trim_matches('"').trim_matches('\'').trim();
        if trimmed.is_empty() || trimmed.contains("://") {
            continue;
        }
        let path = PathBuf::from(trimmed);
        if seen.insert(path.clone()) {
            paths.push(path);
        }
    }
    paths
}

fn list(store: &AppStore, which: i32) -> &[PathEntry] {
    match which {
        LIST_EXCLUDED => &store.excluded,
        _ => &store.included,
    }
}

fn list_mut(store: &mut AppStore, which: i32) -> &mut Vec<PathEntry> {
    match which {
        LIST_EXCLUDED => &mut store.excluded,
        _ => &mut store.included,
    }
}

/// Prepends new entries, keeping existing ones and their reference flags untouched.
pub fn add_paths(store: &mut AppStore, which: i32, paths: &[PathBuf]) {
    let existing: HashSet<PathBuf> = list(store, which).iter().map(|entry| entry.path.clone()).collect();
    let added: Vec<PathEntry> = paths.iter().filter(|path| !existing.contains(*path)).cloned().map(PathEntry::new).collect();
    let target = list_mut(store, which);
    let rest = std::mem::take(target);
    target.extend(added);
    target.extend(rest);
    reconcile(store, which);
}

/// Removing a path must drop its reference flag, so the same path may never appear twice.
pub fn reconcile(store: &mut AppStore, which: i32) {
    let mut seen = HashSet::new();
    let target = list_mut(store, which);
    target.retain(|entry| seen.insert(entry.path.clone()));
}

pub fn remove_checked(store: &mut AppStore, which: i32) {
    list_mut(store, which).retain(|entry| !entry.checked);
    reconcile(store, which);
}

pub fn clear_list(store: &mut AppStore, which: i32) {
    list_mut(store, which).clear();
}

pub fn toggle_checked(store: &mut AppStore, which: i32, index: i32) {
    if let Some(entry) = list_mut(store, which).get_mut(usize::try_from(index).unwrap_or(usize::MAX)) {
        entry.checked = !entry.checked;
    }
}

pub fn toggle_reference(store: &mut AppStore, index: i32) {
    if let Some(entry) = store.included.get_mut(usize::try_from(index).unwrap_or(usize::MAX)) {
        entry.is_reference = !entry.is_reference;
    }
}

fn to_model(entries: &[PathEntry]) -> ModelRc<PathRow> {
    let rows: Vec<PathRow> = entries
        .iter()
        .map(|entry| PathRow {
            path: entry.path.to_string_lossy().to_string().into(),
            is_reference: entry.is_reference,
            checked: entry.checked,
        })
        .collect();
    Rc::new(VecModel::from(rows)).into()
}

pub fn sync_to_gui(app: &MainWindow, store: &AppStore) {
    let state = app.global::<AppState>();
    state.set_included_paths(to_model(&store.included));
    state.set_excluded_paths(to_model(&store.excluded));
}

fn apply_paths(app: &MainWindow, state: &SharedState, which: i32, paths: &[PathBuf]) {
    {
        let mut store = state.lock().expect("App state mutex poisoned");
        add_paths(&mut store, which, paths);
        sync_to_gui(app, &store);
    }
    app.global::<AppState>().set_status_text(crate::fli!("status_paths_updated").into());
}

/// Opens a native folder picker off the event loop so the UI stays responsive.
pub fn pick_folders(app: &MainWindow, state: &SharedState, which: i32) {
    let weak = app.as_weak();
    let state = Arc::clone(state);
    std::thread::spawn(move || {
        let directory = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/"));
        let chosen = FileDialog::new().set_directory(directory).pick_folders();
        let Some(paths) = chosen else {
            return;
        };
        let _ = weak.upgrade_in_event_loop(move |app| apply_paths(&app, &state, which, &paths));
    });
}

pub fn pick_files(app: &MainWindow, state: &SharedState) {
    let weak = app.as_weak();
    let state = Arc::clone(state);
    std::thread::spawn(move || {
        let directory = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/"));
        let chosen = FileDialog::new().set_directory(directory).pick_files();
        let Some(paths) = chosen else {
            return;
        };
        let _ = weak.upgrade_in_event_loop(move |app| apply_paths(&app, &state, LIST_INCLUDED, &paths));
    });
}

pub fn commit_manual(app: &MainWindow, state: &SharedState, which: i32, text: &str) {
    let paths = parse_path_list(text);
    if paths.is_empty() {
        return;
    }
    apply_paths(app, state, which, &paths);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store_with(included: &[(&str, bool)]) -> AppStore {
        let mut store = AppStore::new(crate::fields::default_fields(), crate::settings::KisakiSettings::default());
        for (path, reference) in included {
            store.included.push(PathEntry {
                path: PathBuf::from(path),
                is_reference: *reference,
                checked: false,
            });
        }
        store
    }

    #[test]
    fn parsing_accepts_mixed_separators_and_quotes() {
        let paths = parse_path_list("\"/tmp/a\"\n/tmp/b,/tmp/c;/tmp/c\n\n");
        assert_eq!(paths, vec![PathBuf::from("/tmp/a"), PathBuf::from("/tmp/b"), PathBuf::from("/tmp/c")]);
    }

    #[test]
    fn parsing_ignores_urls_and_blank_entries() {
        let paths = parse_path_list("https://example.com/x\n   \n/tmp/ok");
        assert_eq!(paths, vec![PathBuf::from("/tmp/ok")]);
    }

    #[test]
    fn adding_paths_prepends_and_skips_duplicates() {
        let mut store = store_with(&[("/keep", false)]);
        add_paths(&mut store, LIST_INCLUDED, &[PathBuf::from("/new"), PathBuf::from("/keep")]);
        let paths: Vec<String> = store.included.iter().map(|entry| entry.path.to_string_lossy().to_string()).collect();
        assert_eq!(paths, vec!["/new".to_string(), "/keep".to_string()]);
    }

    #[test]
    fn removing_checked_drops_the_reference_flag_with_the_path() {
        let mut store = store_with(&[("/a", true), ("/b", false)]);
        store.included[0].checked = true;
        remove_checked(&mut store, LIST_INCLUDED);
        assert_eq!(store.included.len(), 1);
        assert_eq!(store.included[0].path, PathBuf::from("/b"));
        assert!(store.reference_paths().is_empty());
    }

    #[test]
    fn toggling_reference_only_flips_the_target_row() {
        let mut store = store_with(&[("/a", false), ("/b", false)]);
        toggle_reference(&mut store, 1);
        assert!(!store.included[0].is_reference);
        assert!(store.included[1].is_reference);
    }

    #[test]
    fn reconcile_removes_duplicated_entries() {
        let mut store = store_with(&[("/a", true), ("/a", false), ("/b", false)]);
        reconcile(&mut store, LIST_INCLUDED);
        assert_eq!(store.included.len(), 2);
        assert!(store.included[0].is_reference);
    }
}
