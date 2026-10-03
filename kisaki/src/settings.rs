use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use czkawka_core::common::config_cache_path::get_config_cache_path;
use log::{error, info};
use serde::{Deserialize, Serialize};
use slint::{ComponentHandle, Model};

use crate::fields::{FieldStore, default_fields};
use crate::tools::spec_by_index;
use crate::{AppState, MainWindow, Theme};

const SETTINGS_FILE: &str = "kisaki_settings.json";

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct PathEntrySettings {
    pub path: String,
    pub is_reference: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct KisakiSettings {
    pub dark: bool,
    pub language_index: i32,
    pub window_width: u32,
    pub window_height: u32,
    // Slint length properties are f32 on the Rust side.
    pub source_width: f32,
    pub analysis_width: f32,
    pub source_collapsed: bool,
    pub analysis_collapsed: bool,
    pub included_paths: Vec<PathEntrySettings>,
    pub excluded_paths: Vec<String>,
    pub excluded_items: String,
    pub allowed_extensions: String,
    pub excluded_extensions: String,
    pub min_size_kib: String,
    pub max_size_kib: String,
    pub recursive_search: bool,
    pub use_cache: bool,
    pub dry_run: bool,
    pub move_to_trash: bool,
    pub active_tool: i32,
    pub field_values: HashMap<i32, super::fields::FieldValue>,
}

impl Default for KisakiSettings {
    fn default() -> Self {
        Self {
            dark: true,
            language_index: crate::translations::find_the_closest_language_idx_to_system(),
            window_width: 1280,
            window_height: 800,
            source_width: 300.0,
            analysis_width: 300.0,
            source_collapsed: false,
            analysis_collapsed: false,
            included_paths: Vec::new(),
            excluded_paths: Vec::new(),
            excluded_items: "*/.git/*,*/cache/*".to_string(),
            allowed_extensions: String::new(),
            excluded_extensions: String::new(),
            min_size_kib: "1".to_string(),
            max_size_kib: "4000000".to_string(),
            recursive_search: true,
            use_cache: true,
            dry_run: true,
            move_to_trash: true,
            active_tool: 0,
            field_values: HashMap::new(),
        }
    }
}

fn settings_path() -> Option<PathBuf> {
    get_config_cache_path().map(|paths| paths.config_folder.join(SETTINGS_FILE))
}

pub fn load() -> (KisakiSettings, FieldStore) {
    let Some(path) = settings_path() else {
        error!("Config folder is unavailable, starting with defaults");
        return (KisakiSettings::default(), default_fields());
    };
    match read_settings(&path) {
        Some(settings) => {
            info!("Loaded settings from {}", path.display());
            let fields = merge_fields(settings.field_values.clone());
            (settings, fields)
        }
        None => (KisakiSettings::default(), default_fields()),
    }
}

fn read_settings(path: &Path) -> Option<KisakiSettings> {
    let raw = match fs::read_to_string(path) {
        Ok(raw) => raw,
        Err(error) => {
            if error.kind() != std::io::ErrorKind::NotFound {
                error!("Failed to read settings from {}: {error}", path.display());
            }
            return None;
        }
    };
    match serde_json::from_str::<KisakiSettings>(&raw) {
        Ok(settings) => Some(settings),
        Err(error) => {
            error!("Failed to parse settings from {}: {error}", path.display());
            None
        }
    }
}

/// Stored field values may be newer, older or incomplete compared to the current registry.
pub fn merge_fields(stored: HashMap<i32, super::fields::FieldValue>) -> FieldStore {
    let mut fields = default_fields();
    for (id, value) in stored {
        if fields.contains_key(&id) {
            fields.insert(id, value);
        }
    }
    fields
}

pub fn save(app: &MainWindow, fields: &FieldStore) {
    let Some(path) = settings_path() else {
        error!("Config folder is unavailable, settings were not saved");
        return;
    };
    let settings = collect(app, fields);
    match serde_json::to_string_pretty(&settings) {
        Ok(raw) => {
            if let Some(parent) = path.parent()
                && let Err(error) = fs::create_dir_all(parent)
            {
                error!("Cannot create config folder {}: {error}", parent.display());
                return;
            }
            match fs::write(&path, raw) {
                Ok(()) => info!("Saved settings to {}", path.display()),
                Err(error) => error!("Failed to write settings to {}: {error}", path.display()),
            }
        }
        Err(error) => error!("Failed to serialize settings: {error}"),
    }
}

fn collect(app: &MainWindow, fields: &FieldStore) -> KisakiSettings {
    let state = app.global::<AppState>();
    let theme = app.global::<Theme>();
    let size = app.window().size();
    KisakiSettings {
        dark: theme.get_dark(),
        language_index: state.get_language_index(),
        window_width: size.width,
        window_height: size.height,
        source_width: state.get_source_width(),
        analysis_width: state.get_analysis_width(),
        source_collapsed: state.get_source_collapsed(),
        analysis_collapsed: state.get_analysis_collapsed(),
        included_paths: state
            .get_included_paths()
            .iter()
            .map(|entry| PathEntrySettings {
                path: entry.path.to_string(),
                is_reference: entry.is_reference,
            })
            .collect(),
        excluded_paths: state.get_excluded_paths().iter().map(|entry| entry.path.to_string()).collect(),
        excluded_items: state.get_excluded_items().to_string(),
        allowed_extensions: state.get_allowed_extensions().to_string(),
        excluded_extensions: state.get_excluded_extensions().to_string(),
        min_size_kib: state.get_min_size_kib().to_string(),
        max_size_kib: state.get_max_size_kib().to_string(),
        recursive_search: state.get_recursive_search(),
        use_cache: state.get_use_cache(),
        dry_run: state.get_dry_run(),
        move_to_trash: state.get_move_to_trash(),
        active_tool: crate::tools::TOOLS.iter().position(|tool| tool.id == state.get_active_tool()).map_or(0, |pos| pos as i32),
        field_values: fields.clone(),
    }
}

pub fn apply_to_gui(app: &MainWindow, settings: &KisakiSettings) {
    let state = app.global::<AppState>();
    let theme = app.global::<Theme>();

    theme.set_dark(settings.dark);
    state.set_language_index(settings.language_index);
    app.window().set_size(slint::PhysicalSize::new(settings.window_width, settings.window_height));
    state.set_source_width(settings.source_width);
    state.set_analysis_width(settings.analysis_width);
    state.set_source_collapsed(settings.source_collapsed);
    state.set_analysis_collapsed(settings.analysis_collapsed);
    state.set_excluded_items(settings.excluded_items.as_str().into());
    state.set_allowed_extensions(settings.allowed_extensions.as_str().into());
    state.set_excluded_extensions(settings.excluded_extensions.as_str().into());
    state.set_min_size_kib(settings.min_size_kib.as_str().into());
    state.set_max_size_kib(settings.max_size_kib.as_str().into());
    state.set_recursive_search(settings.recursive_search);
    state.set_use_cache(settings.use_cache);
    state.set_dry_run(settings.dry_run);
    state.set_move_to_trash(settings.move_to_trash);
    if let Some(spec) = spec_by_index(settings.active_tool) {
        state.set_active_tool(spec.id);
    }
}

/// Restores the two lane widths and the collapse flags after a layout reset.
pub fn reset_layout(app: &MainWindow) {
    let state = app.global::<AppState>();
    state.set_source_width(300.0);
    state.set_analysis_width(300.0);
    state.set_source_collapsed(false);
    state.set_analysis_collapsed(false);
}
