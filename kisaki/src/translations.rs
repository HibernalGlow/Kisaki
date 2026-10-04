use czkawka_core::localizer_core::{LANGUAGE_LIST, find_language_idx};
use i18n_embed::DesktopLanguageRequester;
use i18n_embed::unic_langid::LanguageIdentifier;
use log::{error, info};
use slint::ComponentHandle;

use crate::localizer_kisaki::{localizer_kisaki, translate_key};
use crate::state::SharedState;
use crate::{AppState, MainWindow, ToolId, Translations, fli};

pub fn find_the_closest_language_idx_to_system() -> i32 {
    let index = match DesktopLanguageRequester::requested_languages().first() {
        Some(language) => {
            let tag = language.to_string();
            info!("System language: {tag}");
            find_language_idx(&tag)
        }
        None => 0,
    };
    i32::try_from(index).unwrap_or(0)
}

/// Selects the language for both the core and the Kisaki catalogues, then rewrites
/// every string the UI reads.
pub fn change_language(app: &MainWindow, index: i32) {
    let Some(language) = LANGUAGE_LIST.get(usize::try_from(index).unwrap_or(0)) else {
        error!("Requested language index {index} is not part of the language list");
        return;
    };

    let Ok(identifier) = LanguageIdentifier::from_bytes(language.short_name.as_bytes()) else {
        error!("Language code \"{}\" is not a valid identifier", language.short_name);
        return;
    };

    for (name, localizer) in [("czkawka_core", czkawka_core::localizer_core::localizer_core()), ("kisaki", localizer_kisaki())] {
        if let Err(problem) = localizer.select(std::slice::from_ref(&identifier)) {
            error!("Failed to select the language for {name}: {problem:?}");
        }
    }

    app.global::<AppState>().set_language_index(index);
    translate_items(app);
}

/// Rewrites the model-backed strings, which are not `Translations` properties.
pub fn refresh_dynamic_text(app: &MainWindow, state: &SharedState) {
    let globals = app.global::<AppState>();
    globals.set_tool_entries(crate::tools::tool_entries());
    let tool = {
        let store = state.lock().expect("App state mutex poisoned");
        store.tool
    };
    globals.set_columns(crate::tools::columns(tool));
    crate::callbacks::sync_fields(app, state);
    set_active_label(app, tool);
}

pub fn set_active_label(app: &MainWindow, tool: ToolId) {
    let globals = app.global::<AppState>();
    match crate::tools::spec(tool) {
        Some(spec) => {
            globals.set_active_tool(tool);
            globals.set_active_label(translate_key(spec.label_key).as_str().into());
            globals.set_active_glyph(spec.glyph.into());
        }
        None => error!("Tool {tool:?} has no registry entry"),
    }
}

// BEGIN GENERATED TRANSLATIONS
fn translate_items(app: &MainWindow) {
    let translation = app.global::<Translations>();
    translation.set_action_add_dirs(fli!("action-add-dirs").into());
    translation.set_action_add_files(fli!("action-add-files").into());
    translation.set_action_add_manual(fli!("action-add-manual").into());
    translation.set_action_clear(fli!("action-clear").into());
    translation.set_action_close(fli!("action-close").into());
    translation.set_action_delete(fli!("action-delete").into());
    translation.set_action_export(fli!("action-export").into());
    translation.set_action_remove_checked(fli!("action-remove-checked").into());
    translation.set_action_reset_layout(fli!("action-reset-layout").into());
    translation.set_action_scan(fli!("action-scan").into());
    translation.set_action_stop(fli!("action-stop").into());
    translation.set_action_strip_exif(fli!("action-strip-exif").into());
    translation.set_action_theme(fli!("action-theme").into());
    translation.set_app_title(fli!("app-title").into());
    translation.set_badge_reference(fli!("badge-reference").into());
    translation.set_col_group(fli!("col-group").into());
    translation.set_col_name(fli!("col-name").into());
    translation.set_confirm_cancel(fli!("confirm-cancel").into());
    translation.set_confirm_ok(fli!("confirm-ok").into());
    translation.set_confirm_title(fli!("confirm-title").into());
    translation.set_empty_done(fli!("empty-done").into());
    translation.set_empty_error(fli!("empty-error").into());
    translation.set_empty_filtered(fli!("empty-filtered").into());
    translation.set_empty_idle(fli!("empty-idle").into());
    translation.set_empty_paths(fli!("empty-paths").into());
    translation.set_empty_running(fli!("empty-running").into());
    translation.set_empty_stopped(fli!("empty-stopped").into());
    translation.set_header_results(fli!("header-results").into());
    translation.set_hint_dry_run(fli!("hint-dry-run").into());
    translation.set_label_allowed_ext(fli!("label-allowed-ext").into());
    translation.set_label_cache(fli!("label-cache").into());
    translation.set_label_dry_run(fli!("label-dry-run").into());
    translation.set_label_errors(fli!("label-errors").into());
    translation.set_label_excluded(fli!("label-excluded").into());
    translation.set_label_excluded_ext(fli!("label-excluded-ext").into());
    translation.set_label_excluded_items(fli!("label-excluded-items").into());
    translation.set_label_included(fli!("label-included").into());
    translation.set_label_max_size(fli!("label-max-size").into());
    translation.set_label_min_size(fli!("label-min-size").into());
    translation.set_label_no_options(fli!("label-no-options").into());
    translation.set_label_recursive(fli!("label-recursive").into());
    translation.set_label_reference(fli!("label-reference").into());
    translation.set_label_trash(fli!("label-trash").into());
    translation.set_lane_analysis(fli!("lane-analysis").into());
    translation.set_lane_results(fli!("lane-results").into());
    translation.set_lane_source(fli!("lane-source").into());
    translation.set_metric_files(fli!("metric-files").into());
    translation.set_metric_groups(fli!("metric-groups").into());
    translation.set_metric_reclaimable(fli!("metric-reclaimable").into());
    translation.set_metric_selected(fli!("metric-selected").into());
    translation.set_metric_selected_size(fli!("metric-selected-size").into());
    translation.set_metric_total(fli!("metric-total").into());
    translation.set_placeholder_filter(fli!("placeholder-filter").into());
    translation.set_placeholder_manual(fli!("placeholder-manual").into());
    translation.set_status_ready(fli!("status-ready").into());
    translation.set_tab_algorithm(fli!("tab-algorithm").into());
    translation.set_tab_paths(fli!("tab-paths").into());
    translation.set_tool_selector(fli!("tool-selector").into());
}
// END GENERATED TRANSLATIONS
