use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use czkawka_core::common::ffmpeg_utils::check_if_ffprobe_ffmpeg_exists;
use czkawka_core::common::tool_data::CommonData;
use czkawka_core::common::traits::Search;
use czkawka_core::tools::video_optimizer::core::{fix_video_crop, process_video};
use czkawka_core::tools::video_optimizer::{
    HardwareEncoder, NoiseReductionMethod, VideoCodec, VideoCropSingleFixParams, VideoCroppingMechanism, VideoOptimizer, VideoOptimizerParameters, VideoTranscodeFixParams,
};

use crate::api::types::{CropOptions, OptimizeItem, OptimizeOutcome, OptimizeRequest, OptimizeStatus, TranscodeOptions};
use crate::engine::config::apply_common;
use crate::engine::{fix, flat, options};

/// Re-encodes or crops the selected videos with the engine's own ffmpeg plumbing. Which videos are
/// worth the work stays the scanner's decision: this verb re-runs the optimizer scan over the folders
/// holding the selection, so a file the engine no longer flags is skipped instead of rewritten, and a
/// dry run reports the plan without starting ffmpeg.
pub fn optimize(request: &OptimizeRequest) -> Result<OptimizeOutcome, String> {
    if request.paths.is_empty() {
        return Err("No files selected".to_string());
    }
    if !check_if_ffprobe_ffmpeg_exists() {
        return Err("ffmpeg and ffprobe must be installed to optimize videos".to_string());
    }

    let store = options::store(&request.scan);
    let params = flat::video_params(&store)?;
    let stop = Arc::new(AtomicBool::new(false));

    match (&request.transcode, &request.crop) {
        (Some(options), None) => {
            if matches!(params, VideoOptimizerParameters::VideoCrop(_)) {
                return Err("The scan options are set to the crop mode, so a transcode fix has nothing to work from".to_string());
            }
            let fix = transcode_fix(options)?;
            prepare(request, params, stop, |file, entry, warnings| {
                planned(
                    file,
                    transcode_target(file, options.overwrite_original),
                    OptimizeStatus::Transcoded,
                    entry,
                    Work::Transcode(fix.clone()),
                    warnings,
                )
            })
        }
        (None, Some(options)) => {
            if matches!(params, VideoOptimizerParameters::VideoTranscode(_)) {
                return Err("The scan options are set to the transcode mode, so a crop fix has nothing to work from".to_string());
            }
            let mechanism = flat::crop_mechanism_of(&store)?;
            let fix = crop_fix(options, mechanism)?;
            prepare(request, params, stop, move |file, entry, warnings| {
                let rectangle = entry.map(|entry| entry.crop).unwrap_or_default();
                let work = Work::Crop(VideoCropSingleFixParams { crop_rectangle: rectangle, ..fix });
                planned(
                    file,
                    crop_target(file, options.overwrite_original, mechanism),
                    OptimizeStatus::Cropped,
                    entry,
                    work,
                    warnings,
                )
            })
        }
        _ => Err("Exactly one of transcode or crop options must be supplied".to_string()),
    }
}

/// What the scan says about one file: the size it measured, the codec it found, the rectangle it
/// detected, or why it could not say.
struct Scanned {
    size: u64,
    codec: String,
    crop: (u32, u32, u32, u32),
    error: Option<String>,
}

/// One selected file with its target name and the work that would produce it.
struct Prepared {
    file: PathBuf,
    target: PathBuf,
    codec: String,
    size_before: u64,
    success: OptimizeStatus,
    work: Work,
}

/// Either a piece of engine work, or the reason this file is not getting any.
enum Work {
    Transcode(VideoTranscodeFixParams),
    Crop(VideoCropSingleFixParams),
    /// The engine does not want this file optimized, so it stays exactly where it is.
    Nothing(String),
    /// The engine could not analyze the file, so it reports the engine's own reason.
    Broken(String),
}

/// Scans, plans every selected file and performs what a dry run did not forbid.
fn prepare(
    request: &OptimizeRequest,
    params: VideoOptimizerParameters,
    stop: Arc<AtomicBool>,
    plan: impl Fn(&Path, Option<&Scanned>, &[String]) -> Prepared,
) -> Result<OptimizeOutcome, String> {
    let Scan { found, warnings } = scan(request, params)?;
    let items = request
        .paths
        .iter()
        .map(|path| {
            let file = Path::new(path);
            settle(request, plan(file, found.get(&fix::resolved(file)), &warnings), &stop)
        })
        .collect();
    Ok(summarise(items))
}

/// The candidate list plus what the engine said on the way: a file it dropped never reaches the list,
/// so its reason only survives in the warnings.
struct Scan {
    found: HashMap<PathBuf, Scanned>,
    warnings: Vec<String>,
}

/// Turns the engine's answer about one file into work: an unflagged file is skipped, an unanalyzable
/// one reports the engine's error, and anything else is on its way to being rewritten.
fn planned(file: &Path, target: PathBuf, success: OptimizeStatus, entry: Option<&Scanned>, work: Work, warnings: &[String]) -> Prepared {
    match entry {
        Some(entry) => Prepared {
            file: file.to_path_buf(),
            target,
            codec: entry.codec.clone(),
            size_before: entry.size,
            success,
            work: match &entry.error {
                Some(error) => Work::Broken(error.clone()),
                None => work,
            },
        },
        None => {
            // An engine complaint naming this file is a failure it hit while looking at it; silence
            // means the file simply is not on the list any more.
            let reason = warnings.iter().find(|warning| warning.contains(&file.to_string_lossy().to_string()));
            let work = match reason {
                Some(warning) => Work::Broken(warning.clone()),
                None => Work::Nothing(format!("The engine does not ask to optimize {}", file.display())),
            };
            Prepared {
                file: file.to_path_buf(),
                target,
                codec: String::new(),
                size_before: 0,
                success,
                work,
            }
        }
    }
}

/// Runs one planned file, or records what stopped it. The outcome counts are read back out of these
/// items, so a report cannot disagree with the work.
fn settle(request: &OptimizeRequest, job: Prepared, stop: &Arc<AtomicBool>) -> OptimizeItem {
    let Prepared {
        file,
        target,
        codec,
        size_before,
        success,
        work,
    } = job;
    let (status, detail) = match work {
        Work::Nothing(reason) => (OptimizeStatus::Skipped, reason),
        Work::Broken(reason) => (OptimizeStatus::Failed, reason),
        Work::Transcode(fix) => match gate(request, &file, &target, stop) {
            Some(early) => early,
            None => match process_video(stop, &file.to_string_lossy(), size_before, &fix) {
                Ok(()) => (success, String::new()),
                Err(error) => (OptimizeStatus::Failed, error),
            },
        },
        Work::Crop(fix) => match gate(request, &file, &target, stop) {
            Some(early) => early,
            None => match fix_video_crop(&file, &fix, stop, &codec) {
                Ok(()) => (success, String::new()),
                Err(error) => (OptimizeStatus::Failed, error),
            },
        },
    };

    let size_after = match status {
        OptimizeStatus::Transcoded | OptimizeStatus::Cropped => std::fs::metadata(&target).map(|metadata| metadata.len() as i64).unwrap_or_default(),
        _ => 0,
    };
    OptimizeItem {
        path: file.to_string_lossy().into_owned(),
        target: target.to_string_lossy().into_owned(),
        status,
        detail,
        size_before: size_before as i64,
        size_after,
    }
}

/// The checks both modes share: a dry run stops here, and so does a stopped run or a side file whose
/// name is already taken.
fn gate(request: &OptimizeRequest, file: &Path, target: &Path, stop: &Arc<AtomicBool>) -> Option<(OptimizeStatus, String)> {
    if request.dry_run {
        return Some((OptimizeStatus::Planned, String::new()));
    }
    if stop.load(Ordering::Relaxed) {
        return Some((OptimizeStatus::Skipped, "The run was stopped".to_string()));
    }
    if target != file && target.exists() {
        return Some((OptimizeStatus::Failed, format!("{} already exists", target.display())));
    }
    None
}

/// Re-runs the optimizer scan over the folders holding the selection. Every selected file sits
/// directly inside its own parent, so a non-recursive scan of those parents still reaches all of them.
fn scan(request: &OptimizeRequest, params: VideoOptimizerParameters) -> Result<Scan, String> {
    let mut scan = request.scan.clone();
    scan.included = fix::parent_dirs(&request.paths);
    scan.reference = Vec::new();
    scan.recursive = false;
    if scan.included.is_empty() {
        return Err("No folder to scan".to_string());
    }

    let mut tool = VideoOptimizer::new(params);
    apply_common(&mut tool, &scan);
    tool.search(&Arc::new(AtomicBool::new(false)), None);

    let warnings = tool.get_text_messages().warnings.clone();
    let found: HashMap<PathBuf, Scanned> = match request.transcode {
        Some(_) => tool
            .get_video_transcode_entries()
            .iter()
            .map(|entry| {
                (
                    entry.path.clone(),
                    Scanned {
                        size: entry.size,
                        codec: entry.codec.clone(),
                        crop: (0, 0, 0, 0),
                        error: entry.error.clone(),
                    },
                )
            })
            .collect(),
        None => tool
            .get_video_crop_entries()
            .iter()
            .map(|entry| {
                (
                    entry.path.clone(),
                    Scanned {
                        size: entry.size,
                        codec: entry.codec.clone(),
                        crop: entry.new_image_dimensions,
                        error: entry.error.clone(),
                    },
                )
            })
            .collect(),
    };
    Ok(Scan { found, warnings })
}

fn transcode_fix(options: &TranscodeOptions) -> Result<VideoTranscodeFixParams, String> {
    Ok(VideoTranscodeFixParams {
        codec: parse_codec(&options.codec, "Transcode codec")?,
        hardware_encoder: HardwareEncoder::from_str(&options.hardware_encoder).map_err(|error| format!("Hardware encoder: {error}"))?,
        quality: unsigned(options.quality, "Quality")?,
        fail_if_not_smaller: options.fail_if_not_smaller,
        overwrite_original: options.overwrite_original,
        limit_video_size: options.limit_video_size,
        max_width: unsigned(options.max_width, "Max width")?,
        max_height: unsigned(options.max_height, "Max height")?,
        noise_reduction: NoiseReductionMethod::from_str(&options.noise_reduction).map_err(|error| format!("Noise reduction: {error}"))?,
        noise_reduction_strength: unsigned(options.noise_reduction_strength, "Noise reduction strength")?,
        custom_ffmpeg_command: non_empty(&options.custom_ffmpeg_command),
    })
}

/// The engine takes codec and quality as a pair, so an option block naming only one of them is
/// refused here instead of after ffmpeg has been started. The rectangle is filled per file, because
/// every video has its own.
fn crop_fix(options: &CropOptions, mechanism: VideoCroppingMechanism) -> Result<VideoCropSingleFixParams, String> {
    let codec = match non_empty(&options.target_codec) {
        Some(name) => Some(parse_codec(&name, "Crop codec")?),
        None => None,
    };
    let quality = match options.quality {
        value if value < 0 => None,
        value => Some(unsigned(value, "Quality")?),
    };
    if codec.is_some() != quality.is_some() {
        return Err("A crop either keeps the source codec or names both a codec and a quality".to_string());
    }
    Ok(VideoCropSingleFixParams {
        overwrite_original: options.overwrite_original,
        target_codec: codec,
        quality,
        crop_rectangle: (0, 0, 0, 0),
        crop_mechanism: mechanism,
    })
}

/// The engine spells a transcoded side file `name.czkawka_optimized.mp4`.
fn transcode_target(path: &Path, overwrite: bool) -> PathBuf {
    if overwrite {
        return path.to_path_buf();
    }
    path.with_extension("czkawka_optimized.mp4")
}

/// A cropped side file is spelled after the mechanism that detected the rectangle.
fn crop_target(path: &Path, overwrite: bool, mechanism: VideoCroppingMechanism) -> PathBuf {
    if overwrite {
        return path.to_path_buf();
    }
    let extension = path.extension().and_then(|ext| ext.to_str()).unwrap_or("");
    let suffix = match mechanism {
        VideoCroppingMechanism::BlackBars => "blackbars",
        VideoCroppingMechanism::StaticContent => "staticcontent",
    };
    path.with_extension(format!("czkawka_cropped_{suffix}.{extension}"))
}

fn parse_codec(name: &str, label: &str) -> Result<VideoCodec, String> {
    VideoCodec::from_str(name).map_err(|error| format!("{label}: {error}"))
}

fn unsigned(value: i64, label: &str) -> Result<u32, String> {
    u32::try_from(value).map_err(|_| format!("{label} must not be negative"))
}

fn non_empty(value: &str) -> Option<String> {
    let trimmed = value.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

/// Counts come out of the per-file log rather than a running total, so an entry and its counter can
/// never disagree.
fn summarise(items: Vec<OptimizeItem>) -> OptimizeOutcome {
    let count = |wanted: &OptimizeStatus| items.iter().filter(|item| &item.status == wanted).count() as i32;
    let (transcoded, cropped, planned, skipped, failed) = (
        count(&OptimizeStatus::Transcoded),
        count(&OptimizeStatus::Cropped),
        count(&OptimizeStatus::Planned),
        count(&OptimizeStatus::Skipped),
        count(&OptimizeStatus::Failed),
    );
    let messages = if planned > 0 {
        format!("Planned {} video optimization(s); {failed} failed.", transcoded + cropped + planned)
    } else {
        format!("Completed {} video optimization(s); {failed} failed.", transcoded + cropped)
    };
    OptimizeOutcome {
        transcoded,
        cropped,
        planned,
        skipped,
        failed,
        items,
        messages,
    }
}

#[cfg(test)]
mod tests;
