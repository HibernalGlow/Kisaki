use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use crossbeam_channel::Sender;
use czkawka_core::common::progress_data::ProgressData;
use log::error;
use slint::{ComponentHandle, ModelRc};

use crate::fields::FieldValue;
use crate::state::{AppStore, SharedState};
use crate::{AppState, Callabler, MainWindow, Theme, fli};

/// Registers every callback declared in `ui/globals/callabler.slint`, exactly once each.
pub fn connect_all(app: &MainWindow, state: &SharedState, progress_sender: Sender<ProgressData>, stop_flag: &Arc<AtomicBool>) {
    connect_navigation(app, state);
    connect_scan_lifecycle(app, state, progress_sender, stop_flag);
    connect_paths(app, state);
    connect_fields(app, state);
    connect_table(app, state);
    connect_file_actions(app, state, stop_flag);
    connect_status(app);
}

fn connect_navigation(app: &MainWindow, state: &SharedState) {
    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_tool_selected(move |index| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        let Some(spec) = crate::tools::spec_by_index(index) else {
            error!("Tool index {index} has no registry entry");
            return;
        };
        let mut store = shared.lock().expect("App state mutex poisoned");
        store.tool = spec.id;
        store.clear_rows();
        drop(store);

        app.global::<AppState>().set_tool_menu_open(false);
        crate::translations::set_active_label(&app, spec.id);
        app.global::<AppState>().set_columns(crate::tools::columns(spec.id));
        sync_fields(&app, &shared);

        let mut store = shared.lock().expect("App state mutex poisoned");
        crate::results::refresh(&app, &mut store);
    });

    let weak = app.as_weak();
    app.global::<Callabler>().on_toggle_theme(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        let theme = app.global::<Theme>();
        theme.set_dark(!theme.get_dark());
    });

    let weak = app.as_weak();
    app.global::<Callabler>().on_reset_layout(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::settings::reset_layout(&app);
    });
}

fn connect_scan_lifecycle(app: &MainWindow, state: &SharedState, progress_sender: Sender<ProgressData>, stop_flag: &Arc<AtomicBool>) {
    let weak = app.as_weak();
    let shared = Arc::clone(state);
    let sender = progress_sender;
    let scan_flag = Arc::clone(stop_flag);
    app.global::<Callabler>().on_scan_requested(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::scan::start_scan(&app, &shared, sender.clone(), Arc::clone(&scan_flag));
    });

    let stop = Arc::clone(stop_flag);
    let weak = app.as_weak();
    app.global::<Callabler>().on_stop_requested(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        stop.store(true, Ordering::Relaxed);
        app.global::<AppState>().set_status_text(fli!("status_stopping").into());
    });
}

fn connect_paths(app: &MainWindow, state: &SharedState) {
    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_add_directories(move |list| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::paths::pick_folders(&app, &shared, list);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_add_files(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::paths::pick_files(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_commit_manual_paths(move |list, text| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::paths::commit_manual(&app, &shared, list, text.as_ref());
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_remove_checked_paths(move |list| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        {
            let mut store = shared.lock().expect("App state mutex poisoned");
            crate::paths::remove_checked(&mut store, list);
            crate::paths::reconcile(&mut store, list);
        }
        sync_paths(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_clear_paths(move |list| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        {
            let mut store = shared.lock().expect("App state mutex poisoned");
            crate::paths::clear_list(&mut store, list);
            crate::paths::reconcile(&mut store, list);
        }
        sync_paths(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_toggle_reference(move |index| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        {
            let mut store = shared.lock().expect("App state mutex poisoned");
            crate::paths::toggle_reference(&mut store, index);
        }
        sync_paths(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_toggle_path_checked(move |list, index| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        {
            let mut store = shared.lock().expect("App state mutex poisoned");
            crate::paths::toggle_checked(&mut store, list, index);
        }
        sync_paths(&app, &shared);
    });

    let weak = app.as_weak();
    app.global::<Callabler>().on_source_tab_changed(move |index| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        app.global::<AppState>().set_source_tab(index);
    });
}

fn connect_fields(app: &MainWindow, state: &SharedState) {
    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_field_bool_changed(move |id, value| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        set_field(&shared, id, FieldValue::Bool(value));
        sync_fields(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_field_text_changed(move |id, value| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        set_field(&shared, id, FieldValue::Text(value.to_string()));
        sync_fields(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_field_choice_changed(move |id, index| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        set_field(&shared, id, FieldValue::Choice(index));
        sync_fields(&app, &shared);
    });
}

fn connect_table(app: &MainWindow, state: &SharedState) {
    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_row_toggled(move |index| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        with_store_row(&shared, index, |store, row| store.toggle_row(row));
        refresh_table(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_group_toggled(move |index| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        with_store_row(&shared, index, |store, row| store.toggle_group(row));
        refresh_table(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_toggle_all_rows(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        let mut guard = shared.lock().expect("App state mutex poisoned");
        guard.toggle_visible();
        refresh_table(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_column_sorted(move |index| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        {
            let mut store = shared.lock().expect("App state mutex poisoned");
            if store.sort_column == index {
                store.sort_ascending = !store.sort_ascending;
            } else {
                store.sort_column = index;
                store.sort_ascending = true;
            }
            app.global::<AppState>().set_sort_column(store.sort_column);
            app.global::<AppState>().set_sort_ascending(store.sort_ascending);
        }
        refresh_table(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_filter_changed(move |value| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        shared.lock().expect("App state mutex poisoned").filter = value.to_string();
        refresh_table(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_row_opened(move |index| {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::actions::open_row(&app, &shared, index);
    });
}

fn connect_file_actions(app: &MainWindow, state: &SharedState, stop_flag: &Arc<AtomicBool>) {
    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_delete_selected(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::actions::ask_delete(&app, &shared);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_strip_exif(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::exif::ask(&app, &shared);
    });

    let weak = app.as_weak();
    app.global::<Callabler>().on_confirm_rejected(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::actions::confirm_rejected(&app);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    let flag = Arc::clone(stop_flag);
    app.global::<Callabler>().on_confirm_accepted(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::actions::confirm_accepted(&app, &shared, &flag);
    });

    let weak = app.as_weak();
    let shared = Arc::clone(state);
    app.global::<Callabler>().on_export_results(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        crate::actions::export_results(&app, Arc::clone(&shared));
    });
}

fn connect_status(app: &MainWindow) {
    let weak = app.as_weak();
    app.global::<Callabler>().on_show_errors(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        app.global::<AppState>().set_errors_open(true);
    });

    let weak = app.as_weak();
    app.global::<Callabler>().on_hide_errors(move || {
        let app = weak.upgrade().expect("MainWindow dropped while callback is still live");
        app.global::<AppState>().set_errors_open(false);
    });
}

pub(crate) fn sync_fields(app: &MainWindow, state: &SharedState) {
    let store = state.lock().expect("App state mutex poisoned");
    let defs: ModelRc<crate::FieldDef> = crate::tools::field_defs(store.tool, &store.fields);
    drop(store);
    app.global::<AppState>().set_fields(defs);
}

fn sync_paths(app: &MainWindow, state: &SharedState) {
    let store = state.lock().expect("App state mutex poisoned");
    crate::paths::sync_to_gui(app, &store);
}

fn refresh_table(app: &MainWindow, state: &SharedState) {
    let mut store = state.lock().expect("App state mutex poisoned");
    crate::results::refresh(app, &mut store);
}

fn set_field(state: &SharedState, id: i32, value: FieldValue) {
    state.lock().expect("App state mutex poisoned").fields.insert(id, value);
}

/// The table hands back `ResultRow::store_index`, the canonical row index it was built with,
/// so it addresses `store.rows` directly. An index that is no longer present means the model
/// lagged behind a refresh, which is a real race rather than a bad mapping.
fn with_store_row(state: &SharedState, index: i32, action: impl FnOnce(&mut AppStore, usize)) {
    let mut store = state.lock().expect("App state mutex poisoned");
    let Some(position) = usize::try_from(index).ok().and_then(|index| store.rows.get(index).map(|_| index)) else {
        error!("Row index {index} is no longer part of the result set");
        return;
    };
    action(&mut store, position);
}
