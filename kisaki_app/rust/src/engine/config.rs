use std::path::PathBuf;

use czkawka_core::common::tool_data::CommonData;

use crate::api::types::ScanRequest;

/// Configures any engine tool through the shared `CommonData` surface - the same call sequence
/// the Slint frontend uses, so both frontends ask the engine for identical behaviour.
pub fn apply_common<T: CommonData>(tool: &mut T, request: &ScanRequest) {
    tool.set_included_paths(to_paths(&request.included));
    tool.set_reference_paths(to_paths(&request.reference));
    tool.set_use_reference_folders(!request.reference.is_empty());
    tool.set_excluded_paths(to_paths(&request.excluded_paths));
    tool.set_recursive_search(request.recursive);
    tool.set_minimal_file_size(parse_kib(&request.min_size_kib, 0));
    tool.set_maximal_file_size(parse_kib(&request.max_size_kib, u64::MAX));
    tool.set_allowed_extensions(request.allowed_extensions.clone());
    tool.set_excluded_extensions(request.excluded_extensions.clone());
    tool.set_excluded_items(request.excluded_items.clone());
    tool.set_use_cache(request.use_cache);
}

fn to_paths(paths: &[String]) -> Vec<PathBuf> {
    paths.iter().map(PathBuf::from).collect()
}

/// KiB input from the settings fields; an empty field means "no limit" rather than zero.
fn parse_kib(text: &str, default: u64) -> u64 {
    match text.trim().parse::<u64>() {
        Ok(value) => value.saturating_mul(1024),
        Err(_) => default,
    }
}
