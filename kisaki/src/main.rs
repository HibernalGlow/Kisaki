#![windows_subsystem = "windows"]
#![allow(clippy::allow_attributes)]
#![allow(clippy::indexing_slicing)]

mod actions;
mod build_info;
mod callbacks;
mod common;
mod exif;
mod fields;
mod localizer_kisaki;
mod paths;
mod progress;
mod results;
mod scan;
mod settings;
mod state;
mod tools;
mod translations;

mod ui {
    #![allow(clippy::all, clippy::pedantic, clippy::nursery, clippy::restriction, clippy::cargo, unused_qualifications)]
    slint::include_modules!();
}

use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use crossbeam_channel::{Receiver, Sender, unbounded};
use czkawka_core::common::config_cache_path::set_config_cache_path;
use czkawka_core::common::image::register_image_decoding_hooks;
use czkawka_core::common::logger::{print_version_mode, setup_logger};
use czkawka_core::common::progress_data::ProgressData;
use log::{Record, error, info, warn};
use slint::ComponentHandle;
pub use ui::*;

use crate::settings::KisakiSettings;
use crate::state::{AppStore, SharedState};

fn filtering_messages(_record: &Record) -> bool {
    true
}

fn main() {
    register_image_decoding_hooks();
    let path_report = set_config_cache_path("Czkawka", "Kisaki");
    setup_logger(false, "kisaki", filtering_messages);
    print_version_mode("Kisaki");
    for message in path_report.infos {
        info!("{message}");
    }
    for message in path_report.warnings {
        warn!("{message}");
    }

    let app = match MainWindow::new() {
        Ok(app) => app,
        Err(problem) => {
            error!("Error during creating main window: {problem}");
            show_critical_error(&problem.to_string());
            return;
        }
    };

    let (progress_sender, progress_receiver): (Sender<ProgressData>, Receiver<ProgressData>) = unbounded();
    let stop_flag: Arc<AtomicBool> = Arc::default();

    let (settings, fields) = settings::load();
    let state = AppStore::new_shared(fields, &settings);

    prepare_initial_gui(&app, &state, &settings);
    build_info::install(&app);

    progress::connect_progress(&app, progress_receiver);
    callbacks::connect_all(&app, &state, progress_sender, &stop_flag);

    match app.run() {
        Ok(()) => {
            let fields = store_fields(&state);
            settings::save(&app, &fields);
        }
        Err(problem) => {
            error!("Error during running app: {problem}");
            show_critical_error(&problem.to_string());
        }
    }
}

/// Pushes everything the first paint needs: persisted globals, language, the
/// selected scanner and an empty result set.
fn prepare_initial_gui(app: &MainWindow, state: &SharedState, settings: &KisakiSettings) {
    settings::apply_to_gui(app, settings);
    translations::change_language(app, settings.language_index);
    translations::refresh_dynamic_text(app, state);

    let mut store = lock(state);
    paths::sync_to_gui(app, &store);
    results::refresh(app, &mut store);
}

fn store_fields(state: &SharedState) -> fields::FieldStore {
    lock(state).fields.clone()
}

fn lock(state: &SharedState) -> std::sync::MutexGuard<'_, AppStore> {
    state.lock().expect("App state mutex poisoned")
}

fn show_critical_error(message: &str) {
    rfd::MessageDialog::new().set_title(fli!("rust_init_error_title")).set_description(message).show();
}
