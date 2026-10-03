use std::fs;
use std::process::{Command, Stdio};

use czkawka_core::common::config_cache_path::set_config_cache_path;

use super::*;
use crate::api::types::{FieldPayload, FieldValue, ScanRequest};

#[test]
fn an_empty_selection_is_refused() {
    let error = optimize(&empty_request()).expect_err("nothing to do");
    assert!(error.contains("No files selected"), "unexpected: {error}");
}

#[test]
fn both_modes_at_once_are_refused() {
    let dir = scratch("both_modes");
    let video = fixture_video(&dir, "clip.mp4");

    let mut request = request(vec![video], transcode_options(true), false);
    request.crop = Some(crop_options());
    let error = optimize(&request).expect_err("one mode at a time");
    assert!(error.contains("Exactly one of"), "unexpected: {error}");

    fs::remove_dir_all(dir).expect("remove scratch directory");
}

#[test]
fn an_unknown_codec_is_refused_before_ffmpeg_starts() {
    let dir = scratch("bad_codec");
    let video = fixture_video(&dir, "clip.mp4");

    let mut options = transcode_options(true);
    options.codec = "divx".to_string();
    let error = optimize(&request(vec![video], options, false)).expect_err("not a codec the engine knows");
    assert!(error.contains("Transcode codec"), "unexpected: {error}");

    fs::remove_dir_all(dir).expect("remove scratch directory");
}

#[test]
fn a_crop_needs_both_a_codec_and_a_quality() {
    let error = crop_fix(
        &CropOptions {
            overwrite_original: false,
            target_codec: "h264".to_string(),
            quality: -1,
        },
        VideoCroppingMechanism::BlackBars,
    )
    .expect_err("half a codec pair");
    assert!(error.contains("both a codec and a quality"), "unexpected: {error}");
}

#[test]
fn a_transcode_overwriting_the_original_replaces_it() {
    let dir = scratch("transcode");
    let video = fixture_video(&dir, "clip.mp4");
    let before = fs::read(&video).expect("read the fixture");

    let outcome = optimize(&request(vec![video.clone()], transcode_options(true), false)).expect("transcode runs");
    assert_eq!((outcome.transcoded, outcome.failed, outcome.skipped), (1, 0, 0), "unexpected: {:?}", outcome.items);
    assert_eq!(outcome.items[0].target, video.to_string_lossy(), "an overwrite keeps the path");
    assert!(outcome.items[0].size_after > 0, "the new size is reported");
    assert_eq!(codec_of(&video), "h264", "the engine wrote the requested codec");
    assert_ne!(fs::read(&video).expect("read the result"), before, "the bytes changed");

    fs::remove_dir_all(dir).expect("remove scratch directory");
}

#[test]
fn a_dry_run_starts_no_ffmpeg() {
    let dir = scratch("dry_run");
    let video = fixture_video(&dir, "clip.mp4");
    let before = fs::read(&video).expect("read the fixture");
    let side = video.with_extension("czkawka_optimized.mp4");

    let outcome = optimize(&request(vec![video.clone()], transcode_options(false), true)).expect("dry run");
    assert_eq!((outcome.planned, outcome.transcoded, outcome.failed), (1, 0, 0), "unexpected: {:?}", outcome.items);
    assert_eq!(outcome.items[0].target, side.to_string_lossy());
    assert_eq!(fs::read(&video).expect("the file is untouched"), before);
    assert!(!side.exists(), "a planned run writes nothing");
    assert!(outcome.messages.contains("Planned 1 video"), "unexpected: {}", outcome.messages);

    fs::remove_dir_all(dir).expect("remove scratch directory");
}

#[test]
fn a_side_file_already_on_disk_is_not_overwritten() {
    let dir = scratch("occupied");
    let video = fixture_video(&dir, "clip.mp4");
    let side = video.with_extension("czkawka_optimized.mp4");
    fs::write(&side, "someone else").expect("occupy the side name");

    let outcome = optimize(&request(vec![video], transcode_options(false), false)).expect("the failure is reported");
    assert_eq!((outcome.transcoded, outcome.failed), (0, 1), "unexpected: {:?}", outcome.items);
    assert!(outcome.items[0].detail.contains("already exists"), "unexpected: {:?}", outcome.items[0]);
    assert_eq!(fs::read(&side).expect("the occupant survives"), b"someone else");

    fs::remove_dir_all(dir).expect("remove scratch directory");
}

#[test]
fn a_file_the_engine_does_not_flag_is_skipped() {
    let dir = scratch("unflagged");
    let video = fixture_video(&dir, "clip.mp4");
    let text = dir.join("notes.txt");
    fs::write(&text, "not a video").expect("write a text file");

    let outcome = optimize(&request(vec![text], transcode_options(false), false)).expect("the scan still runs");
    assert_eq!((outcome.skipped, outcome.transcoded, outcome.failed), (1, 0, 0), "unexpected: {:?}", outcome.items);
    assert_eq!(outcome.items[0].status, OptimizeStatus::Skipped);
    assert_eq!(codec_of(&video), "mpeg4", "an unselected video keeps its codec");

    fs::remove_dir_all(dir).expect("remove scratch directory");
}

#[test]
fn the_scan_options_have_to_name_the_mode_being_fixed() {
    let dir = scratch("wrong_mode");
    let video = fixture_video(&dir, "clip.mp4");

    let mut request = request(vec![video], transcode_options(false), true);
    request.scan.fields = vec![FieldValue {
        id: "vid_opt_mode".to_string(),
        value: FieldPayload::Choice("Crop".to_string()),
    }];
    let error = optimize(&request).expect_err("a crop scan cannot serve a transcode fix");
    assert!(error.contains("transcode fix"), "unexpected: {error}");

    fs::remove_dir_all(dir).expect("remove scratch directory");
}

/// An mpeg4 clip, so the default excluded-codec list leaves it eligible for a transcode.
fn fixture_video(dir: &Path, name: &str) -> PathBuf {
    let path = dir.join(name);
    let status = Command::new("ffmpeg")
        .args([
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-f",
            "lavfi",
            "-i",
            "testsrc=duration=1:size=160x120:rate=5",
            "-c:v",
            "mpeg4",
            "-q:v",
            "8",
        ])
        .arg(&path)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .expect("ffmpeg is needed for these tests");
    assert!(status.success(), "ffmpeg could not build the fixture video");
    assert!(fs::metadata(&path).expect("stat the fixture").len() > 0, "the fixture video is empty");
    path
}

fn codec_of(path: &Path) -> String {
    let output = Command::new("ffprobe")
        .args([
            "-hide_banner",
            "-loglevel",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=codec_name",
            "-of",
            "csv=p=0",
        ])
        .arg(path)
        .output()
        .expect("ffprobe is needed for these tests");
    assert!(output.status.success(), "ffprobe failed on {}", path.display());
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

fn transcode_options(overwrite: bool) -> TranscodeOptions {
    TranscodeOptions {
        codec: "h264".to_string(),
        hardware_encoder: "none".to_string(),
        quality: 28,
        fail_if_not_smaller: false,
        overwrite_original: overwrite,
        limit_video_size: false,
        max_width: 0,
        max_height: 0,
        noise_reduction: "none".to_string(),
        noise_reduction_strength: 0,
        custom_ffmpeg_command: String::new(),
    }
}

fn crop_options() -> CropOptions {
    CropOptions {
        overwrite_original: false,
        target_codec: String::new(),
        quality: -1,
    }
}

fn request(paths: Vec<PathBuf>, options: TranscodeOptions, dry_run: bool) -> OptimizeRequest {
    OptimizeRequest {
        scan: scan_request(&paths[0]),
        paths: paths.iter().map(|path| path.to_string_lossy().into_owned()).collect(),
        transcode: Some(options),
        crop: None,
        dry_run,
    }
}

/// A scan block carrying only the mode; every other option keeps its engine default.
fn scan_request(inside: &Path) -> ScanRequest {
    let directory = inside.parent().expect("the fixture lives in a folder").to_path_buf();
    ScanRequest {
        tool: "video_optimizer".to_string(),
        included: vec![directory.to_string_lossy().into_owned()],
        reference: Vec::new(),
        excluded_paths: Vec::new(),
        excluded_items: Vec::new(),
        allowed_extensions: Vec::new(),
        excluded_extensions: Vec::new(),
        recursive: false,
        use_cache: false,
        min_size_kib: String::new(),
        max_size_kib: String::new(),
        fields: vec![FieldValue {
            id: "vid_opt_mode".to_string(),
            value: FieldPayload::Choice("Transcode".to_string()),
        }],
    }
}

fn scratch(name: &str) -> PathBuf {
    register_cache_root();
    let dir = std::env::temp_dir().join(format!("kisaki_bridge_optimize_{name}"));
    if dir.exists() {
        fs::remove_dir_all(&dir).expect("clear a stale scratch directory");
    }
    fs::create_dir_all(&dir).expect("create scratch directory");
    dir
}

/// The app registers the engine's config and cache folders in its FRB init; a unit test has to do
/// it itself or the optimizer panics while resolving its cache file. The setter keeps the first
/// registration, so one call for the whole test binary is enough.
fn register_cache_root() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        set_config_cache_path("Czkawka", "Kisaki");
    });
}

/// The shape of a request with nothing selected, which is refused before any folder is read.
fn empty_request() -> OptimizeRequest {
    OptimizeRequest {
        scan: scan_request(Path::new("/tmp")),
        paths: Vec::new(),
        transcode: Some(transcode_options(false)),
        crop: None,
        dry_run: false,
    }
}
