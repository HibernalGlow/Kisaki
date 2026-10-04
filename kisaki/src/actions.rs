use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use czkawka_core::common::fs_ops::{remove_folder_if_contains_only_empty_folders, remove_single_file, remove_single_folder};
use rayon::prelude::*;
use rfd::FileDialog;
use slint::ComponentHandle;

use crate::common::format_bytes;
use crate::state::{RowData, SharedState};
use crate::{AppState, MainWindow, PendingAction, Phase, ToolId, fli};

const PLAN_PREVIEW_ROWS: usize = 12;

fn selected_rows(store: &crate::state::AppStore) -> Vec<&RowData> {
    store.rows.iter().filter(|row| store.selection.contains(&row.path)).collect()
}

/// Builds a human readable plan; never touches the filesystem.
pub fn build_plan(rows: &[&RowData], folder_targets: bool, remove_to_trash: bool) -> String {
    if rows.is_empty() {
        return fli!("status_nothing_selected");
    }
    let verb = if folder_targets {
        if remove_to_trash {
            fli!("plan_folders_to_trash")
        } else {
            fli!("plan_folders_to_delete")
        }
    } else if remove_to_trash {
        fli!("plan_files_to_trash")
    } else {
        fli!("plan_files_to_delete")
    };
    let bytes: u64 = rows.iter().map(|row| row.size_bytes).sum();
    let mut lines = vec![fli!("plan_header", count = rows.len(), size = format_bytes(bytes), verb = verb)];
    for row in rows.iter().take(PLAN_PREVIEW_ROWS) {
        lines.push(format!("  {}  {}", format_bytes(row.size_bytes), row.path.to_string_lossy()));
    }
    if rows.len() > PLAN_PREVIEW_ROWS {
        let hidden: usize = rows.len() - PLAN_PREVIEW_ROWS;
        lines.push(fli!("plan_more", count = hidden));
    }
    lines.join("\n")
}

struct DeleteRequest {
    plan: String,
    count: usize,
    bytes: u64,
    dry_run: bool,
}

/// Opens the confirmation overlay; the destructive step only runs from `confirm_accepted`.
pub fn ask_delete(app: &MainWindow, state: &SharedState) {
    let globals = app.global::<AppState>();
    let request = {
        let store = state.lock().expect("App state mutex poisoned");
        let rows = selected_rows(&store);
        if rows.is_empty() {
            globals.set_status_text(fli!("status_nothing_selected").into());
            return;
        }
        DeleteRequest {
            plan: build_plan(&rows, store.tool == ToolId::EmptyFolders, globals.get_move_to_trash()),
            count: rows.len(),
            bytes: rows.iter().map(|row| row.size_bytes).sum::<u64>(),
            dry_run: globals.get_dry_run(),
        }
    };

    globals.set_pending_action(PendingAction::Delete);
    globals.set_confirm_title(fli!("confirm_delete_title").into());
    let body = if request.dry_run {
        fli!("confirm_dry_run_body", count = request.count, size = format_bytes(request.bytes))
    } else {
        fli!("confirm_delete_body", count = request.count, size = format_bytes(request.bytes))
    };
    globals.set_confirm_body(body.as_str().into());
    globals.set_action_summary(request.plan.as_str().into());
    globals.set_confirm_open(true);
}

pub fn confirm_rejected(app: &MainWindow) {
    let globals = app.global::<AppState>();
    globals.set_confirm_open(false);
    globals.set_status_text(fli!("status_cancelled").into());
}

pub fn confirm_accepted(app: &MainWindow, state: &SharedState, stop_flag: &AtomicBool) {
    let globals = app.global::<AppState>();
    globals.set_confirm_open(false);

    // The overlay carries which verb it was opened for, so it always falls back to delete.
    let pending = globals.get_pending_action();
    globals.set_pending_action(PendingAction::Delete);
    if pending == PendingAction::StripExif {
        crate::exif::run(app, state);
        return;
    }

    let (targets, dry_run, to_trash, folders) = {
        let store = state.lock().expect("App state mutex poisoned");
        (
            store.checked_paths(),
            globals.get_dry_run(),
            globals.get_move_to_trash(),
            store.tool == ToolId::EmptyFolders,
        )
    };

    if dry_run {
        globals.set_status_text(fli!("status_dry_run_only").into());
        return;
    }
    if targets.is_empty() {
        globals.set_status_text(fli!("status_nothing_selected").into());
        return;
    }

    stop_flag.store(false, Ordering::Relaxed);
    globals.set_phase(Phase::Running);
    globals.set_progress_all(0);
    globals.set_status_text(fli!("status_deleting").into());

    let weak = app.as_weak();
    let store = Arc::clone(state);
    std::thread::spawn(move || {
        let total = targets.len();
        let completed = AtomicUsize::new(0);
        // Deletion runs in parallel, so progress counts finished items and is posted only on
        // percentage steps to keep the event queue small.
        let step = (total / 100).max(1);
        let results: Vec<Option<PathBuf>> = targets
            .into_par_iter()
            .map(|path| {
                let failure = remove_one(&path, folders, to_trash);
                let done = completed.fetch_add(1, Ordering::Relaxed) + 1;
                if done == total || done.is_multiple_of(step) {
                    let percent = ((done * 100) / total.max(1)) as i32;
                    let _ = weak.clone().upgrade_in_event_loop(move |app| {
                        app.global::<AppState>().set_progress_all(percent);
                    });
                }
                match failure {
                    Ok(()) => Some(path),
                    Err(error) => {
                        log::error!("Failed to remove {}: {error}", path.display());
                        None
                    }
                }
            })
            .collect();

        let removed: HashSet<PathBuf> = results.into_iter().flatten().collect();
        let failed = total - removed.len();
        let _ = weak.upgrade_in_event_loop(move |app| {
            {
                let mut guard = store.lock().expect("App state mutex poisoned");
                guard.drop_paths(&removed);
                crate::results::refresh(&app, &mut guard);
            }
            let globals = app.global::<AppState>();
            globals.set_phase(Phase::Completed);
            globals.set_progress_all(100);
            globals.set_progress_current(-1);
            let message = if failed == 0 {
                fli!("status_removed_all", count = removed.len())
            } else {
                fli!("status_removed_partial", removed = removed.len(), failed = failed)
            };
            globals.set_status_text(message.as_str().into());
            globals.set_action_summary("".into());
        });
    });
}

fn remove_one(path: &Path, folders: bool, to_trash: bool) -> Result<(), String> {
    let text = path.to_string_lossy().to_string();
    if folders {
        return remove_folder_if_contains_only_empty_folders(&text, to_trash);
    }
    if path.is_dir() {
        remove_single_folder(&text, to_trash)
    } else {
        remove_single_file(&text, to_trash)
    }
}

pub fn open_row(app: &MainWindow, state: &SharedState, index: i32) {
    let path = {
        let store = state.lock().expect("App state mutex poisoned");
        let Some(index) = usize::try_from(index).ok() else {
            return;
        };
        store.rows.get(index).map(|row| row.path.clone())
    };
    let Some(path) = path else {
        return;
    };
    if let Err(error) = open::that(&path) {
        let globals = app.global::<AppState>();
        globals.set_status_text(fli!("status_open_failed", path = path.to_string_lossy(), error = error.to_string()).as_str().into());
    }
}

/// Exports the stored scan result through the core's `PrintResults` implementation.
pub fn export_results(app: &MainWindow, state: SharedState) {
    let globals = app.global::<AppState>();
    if !globals.get_has_results() {
        globals.set_status_text(fli!("status_nothing_to_export").into());
        return;
    }
    let tool = state.lock().expect("App state mutex poisoned").tool;

    let weak = app.as_weak();
    std::thread::spawn(move || {
        let Some(folder) = FileDialog::new().pick_folder() else {
            return;
        };
        let folder_text = folder.to_string_lossy().to_string();
        let _ = weak.upgrade_in_event_loop(move |app| {
            let message = {
                let guard = state.lock().expect("App state mutex poisoned");
                match crate::state::save_results(&guard.models, tool, &folder_text) {
                    Ok(()) => fli!("status_exported", folder = folder_text),
                    Err(error) => fli!("status_export_failed", error = error),
                }
            };
            app.global::<AppState>().set_status_text(message.as_str().into());
        });
    });
}
