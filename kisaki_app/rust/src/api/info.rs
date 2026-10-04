use czkawka_core::common::build_runtime_info::BuildRuntimeInfo;
use czkawka_core::common::config_cache_path::set_config_cache_path;
use flutter_rust_bridge::frb;

use crate::api::types::{CodecInfo, EngineInfo};

/// Runs once when Dart calls `RustLib.init()`.
///
/// The engine resolves its config and cache folders lazily and panics if they were never
/// registered, so this must happen before any scan touches the cache.
#[frb(init)]
pub fn init_app() {
    set_config_cache_path("Czkawka", "Kisaki");
}

/// What the bridge knows about the engine it is standing on. `core_version` is read from the core
/// crate itself, not from this crate, because a field named after the engine must not quietly become
/// the frontend's version number the day the two stop being bumped together.
#[frb(sync)]
pub fn engine_info() -> EngineInfo {
    EngineInfo {
        core_version: czkawka_core::CZKAWKA_VERSION.to_string(),
        api_version: 1,
        os: std::env::consts::OS.to_string(),
        thread_limit: std::thread::available_parallelism().map(|count| count.get() as i32).unwrap_or(1),
    }
}

/// Reports which codecs the engine was compiled with. This is the only way a frontend can tell that
/// a scan skipped files: with `heif_build` false, `check_if_can_display_image` rejects `.heic` before
/// the scan collects it, so no message and no failure ever reach the board.
#[frb(sync)]
pub fn codec_info() -> CodecInfo {
    let runtime = BuildRuntimeInfo::get();
    CodecInfo {
        heif_build: runtime.heif_build,
        libraw_build: runtime.libraw_build,
        libavif_build: runtime.libavif_build,
        diagnostic: runtime.format_diagnostic_text("Kisaki"),
    }
}

#[cfg(test)]
mod tests {
    use czkawka_core::common::image::check_if_can_display_image;

    use super::codec_info;

    /// The disclosure must track the behaviour it describes rather than a feature list copied into
    /// this crate: the engine decides `.heic` support in its own extension table.
    #[test]
    fn the_heif_flag_matches_what_the_engine_will_accept() {
        assert_eq!(codec_info().heif_build, check_if_can_display_image("photo.HEIC"));
    }

    #[test]
    fn a_supported_extension_is_reported_as_supported() {
        assert!(check_if_can_display_image("photo.png"), "png must always be scannable");
        assert!(codec_info().diagnostic.contains("Kisaki"), "unexpected: {}", codec_info().diagnostic);
    }
}
