use czkawka_core::common::build_runtime_info::BuildRuntimeInfo;
use slint::ComponentHandle;

use crate::MainWindow;

/// Puts the compiled-in codecs where a reader can see them.
///
/// A missing codec is not an error: the core drops those extensions from the scan before anything can
/// complain, so an apparently clean folder is the only symptom. The caption is the one place that can
/// say "this build cannot read HEIC" without a dialog.
pub fn install(app: &MainWindow) {
    app.set_build_flags(summary(&BuildRuntimeInfo::get()).into());

    let weak = app.as_weak();
    BuildRuntimeInfo::start_background_probes(move || {
        let info = BuildRuntimeInfo::get();
        info.log_runtime_summary();
        if let Some(app) = weak.upgrade() {
            app.set_build_flags(summary(&info).into());
        }
    });
}

/// Lists the three optional decoders even when absent, so the line never reads as "no information".
fn summary(info: &BuildRuntimeInfo) -> String {
    let flag = |built| if built { '+' } else { '-' };
    format!(" (heif{} raw{} avif{})", flag(info.heif_build), flag(info.libraw_build), flag(info.libavif_build),)
}

#[cfg(test)]
mod tests {
    use czkawka_core::common::build_runtime_info::BuildRuntimeInfo;

    use super::summary;

    fn info(heif: bool, libraw: bool, libavif: bool) -> BuildRuntimeInfo {
        BuildRuntimeInfo {
            heif_build: heif,
            libraw_build: libraw,
            libavif_build: libavif,
            heif_runtime_hevc: false,
            heif_runtime_av1: false,
            libraw_runtime: false,
            libavif_runtime: false,
            ffmpeg_runtime: false,
            ffprobe_runtime: false,
            probes_complete: false,
        }
    }

    #[test]
    fn a_default_build_shows_all_three_decoders_missing() {
        assert_eq!(summary(&info(false, false, false)), " (heif- raw- avif-)");
    }

    #[test]
    fn each_decoder_is_reported_on_its_own() {
        assert_eq!(summary(&info(true, false, false)), " (heif+ raw- avif-)");
        assert_eq!(summary(&info(false, true, false)), " (heif- raw+ avif-)");
        assert_eq!(summary(&info(false, false, true)), " (heif- raw- avif+)");
    }
}
