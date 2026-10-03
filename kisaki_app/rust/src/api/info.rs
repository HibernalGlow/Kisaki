use czkawka_core::common::config_cache_path::set_config_cache_path;
use flutter_rust_bridge::frb;

use crate::api::types::EngineInfo;

/// Runs once when Dart calls `RustLib.init()`.
///
/// The engine resolves its config and cache folders lazily and panics if they were never
/// registered, so this must happen before any scan touches the cache.
#[frb(init)]
pub fn init_app() {
    set_config_cache_path("Czkawka", "Kisaki");
}

#[frb(sync)]
pub fn engine_info() -> EngineInfo {
    EngineInfo {
        core_version: env!("CARGO_PKG_VERSION").to_string(),
        api_version: 1,
        os: std::env::consts::OS.to_string(),
        thread_limit: std::thread::available_parallelism().map(|count| count.get() as i32).unwrap_or(1),
    }
}
