use std::cmp::Reverse;
use std::ops::RangeInclusive;
use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use czkawka_core::common::model::{CheckingMethod, HashType};
use czkawka_core::common::path_utils::split_path_compare;
use czkawka_core::common::tool_data::CommonData;
use czkawka_core::common::traits::{ResultEntry, Search};
use czkawka_core::helpers::messages::MessageLimit;
use czkawka_core::re_exported::{FilterType, HashAlg};
use czkawka_core::tools::duplicate::{DuplicateEntry, DuplicateFinder, DuplicateFinderParameters};
use czkawka_core::tools::same_music::core::format_audio_duration;
use czkawka_core::tools::same_music::{MusicEntry, MusicSimilarity, SameMusic, SameMusicParameters};
use czkawka_core::tools::similar_images::core::{get_string_from_similarity, return_similarity_from_similarity_preset};
use czkawka_core::tools::similar_images::{GeometricInvariance, ImagesEntry, SimilarImages, SimilarImagesParameters, SimilarityPreset};
use czkawka_core::tools::similar_videos::core::{format_bitrate_opt, format_duration_opt};
use czkawka_core::tools::similar_videos::{
    ALLOWED_AUDIO_LENGTH_RATIO, ALLOWED_AUDIO_SIMILARITY_PERCENT, ALLOWED_DURATION_TOLERANCE_PCT, ALLOWED_MATCH_FRACTION, ALLOWED_SKIP_FORWARD_AMOUNT, ALLOWED_VID_HASH_DURATION,
    ALLOWED_WINDOW_COUNT, DEFAULT_AUDIO_LENGTH_RATIO, DEFAULT_AUDIO_MAXIMUM_DIFFERENCE, DEFAULT_AUDIO_MIN_DURATION_SECONDS, DEFAULT_AUDIO_SIMILARITY_PERCENT, DEFAULT_CROP_DETECT,
    DEFAULT_DURATION_TOLERANCE_PCT, DEFAULT_MIN_MATCHING_WINDOWS, DEFAULT_SKIP_FORWARD_AMOUNT, DEFAULT_SUBCLIP_MIN_MATCH, DEFAULT_THUMBNAIL_GRID_TILES_PER_SIDE,
    DEFAULT_VID_HASH_DURATION, DEFAULT_VIDEO_PERCENTAGE_FOR_THUMBNAIL, DEFAULT_WINDOW_COUNT, MAX_TOLERANCE, SimilarVideos, SimilarVideosParameters, VideosEntry,
};

use crate::api::types::{FieldPayload, ScanRequest, ToolSpec};
use crate::engine::runner::ProgressSender;
use crate::engine::{EngineOutcome, EngineRow, FieldStore, config};

/// Scanners whose output is a set of groups: duplicates, similar images, similar videos, music.
pub fn run(spec: &ToolSpec, request: &ScanRequest, store: &FieldStore, sender: ProgressSender, stop: Arc<AtomicBool>) -> Result<EngineOutcome, String> {
    let options = Options::new(request, store);
    match spec.id.as_str() {
        "duplicate_files" => run_duplicates(spec, request, &options, sender, stop),
        "similar_images" => run_similar_images(spec, request, &options, sender, stop),
        "similar_videos" => run_similar_videos(spec, request, &options, sender, stop),
        "duplicate_music" => run_same_music(spec, request, &options, sender, stop),
        other => Err(format!("Tool '{other}' is not registered as a grouped scanner")),
    }
}

fn run_duplicates(spec: &ToolSpec, request: &ScanRequest, options: &Options<'_>, sender: ProgressSender, stop: Arc<AtomicBool>) -> Result<EngineOutcome, String> {
    let params = DuplicateFinderParameters::new(
        check_method(options)?,
        hash_type(options)?,
        options.flag("dup_use_prehash", true),
        options.integer("dup_hash_cache_size", 1000).max(1) as u64,
        options.integer("dup_prehash_cache_size", 1000).max(1) as u64,
        options.flag("dup_case_sensitive_names", true),
    );

    let mut tool = DuplicateFinder::new(params);
    config::apply_common(&mut tool, request);
    tool.set_hide_hard_links(options.flag("dup_ignore_hard_links", false));
    tool.search(&stop, Some(&sender));

    let (critical, messages) = engine_messages(&tool);
    let stopped = tool.get_stopped_search();
    grouped_outcome(spec, build_grouped(duplicate_groups(&tool)), stopped, messages, critical)
}

fn duplicate_groups(tool: &DuplicateFinder) -> Vec<Group> {
    if tool.get_use_reference() {
        let referenced: Vec<(DuplicateEntry, Vec<DuplicateEntry>)> = match tool.get_params().check_method {
            CheckingMethod::Hash => tool.get_files_with_identical_hashes_referenced().values().flatten().cloned().collect(),
            CheckingMethod::Name => tool.get_files_with_identical_name_referenced().values().cloned().collect(),
            CheckingMethod::Size => tool.get_files_with_identical_size_referenced().values().cloned().collect(),
            CheckingMethod::SizeName => tool.get_files_with_identical_size_names_referenced().values().cloned().collect(),
            _ => Vec::new(),
        };
        return referenced
            .into_iter()
            .map(|(original, others)| Group {
                reference: Some(reference_row(duplicate_row(&original))),
                members: others.iter().map(duplicate_row).collect(),
            })
            .collect();
    }

    let groups: Vec<Vec<DuplicateEntry>> = match tool.get_params().check_method {
        CheckingMethod::Hash => tool.get_files_sorted_by_hash().values().flatten().cloned().collect(),
        CheckingMethod::Name => tool.get_files_sorted_by_names().values().cloned().collect(),
        CheckingMethod::Size => tool.get_files_sorted_by_size().values().cloned().collect(),
        CheckingMethod::SizeName => tool.get_files_sorted_by_size_name().values().cloned().collect(),
        _ => Vec::new(),
    };
    groups
        .into_iter()
        .map(|members| Group {
            reference: None,
            members: members.iter().map(duplicate_row).collect(),
        })
        .collect()
}

fn duplicate_row(entry: &DuplicateEntry) -> EngineRow {
    EngineRow::new(
        entry.get_path().to_path_buf(),
        vec![format_bytes(entry.get_size()), format_timestamp(entry.get_modified_date())],
        vec![to_sort_key(entry.get_size()), to_sort_key(entry.get_modified_date())],
        entry.get_size(),
        entry.get_modified_date(),
    )
}

fn run_similar_images(spec: &ToolSpec, request: &ScanRequest, options: &Options<'_>, sender: ProgressSender, stop: Arc<AtomicBool>) -> Result<EngineOutcome, String> {
    let hash_size = image_hash_size(options)?;
    let params = SimilarImagesParameters::new(
        return_similarity_from_similarity_preset(similarity_preset(options)?, hash_size),
        hash_size,
        hash_algorithm(options)?,
        resize_algorithm(options)?,
        options.flag("img_ignore_same_size", false),
        options.flag("img_ignore_same_resolution", false),
        geometric_invariance(options)?,
    );

    let mut tool = SimilarImages::new(params);
    config::apply_common(&mut tool, request);
    tool.search(&stop, Some(&sender));

    let (critical, messages) = engine_messages(&tool);
    let stopped = tool.get_stopped_search();
    grouped_outcome(spec, build_grouped(image_groups(&tool, hash_size)), stopped, messages, critical)
}

fn image_groups(tool: &SimilarImages, hash_size: u8) -> Vec<Group> {
    if tool.get_use_reference() {
        return tool
            .get_similar_images_referenced()
            .iter()
            .map(|(original, others)| Group {
                reference: Some(reference_row(image_row(original, hash_size))),
                members: others.iter().map(|entry| image_row(entry, hash_size)).collect(),
            })
            .collect();
    }
    tool.get_similar_images()
        .iter()
        .map(|members| Group {
            reference: None,
            members: members.iter().map(|entry| image_row(entry, hash_size)).collect(),
        })
        .collect()
}

fn image_row(entry: &ImagesEntry, hash_size: u8) -> EngineRow {
    let resolution = format!("{}x{}", entry.width, entry.height);
    EngineRow::new(
        entry.get_path().to_path_buf(),
        vec![
            get_string_from_similarity(entry.difference, hash_size),
            format_bytes(entry.size),
            resolution,
            format_timestamp(entry.get_modified_date()),
        ],
        vec![
            i64::from(entry.difference),
            to_sort_key(entry.size),
            i64::from(entry.width) * i64::from(entry.height),
            to_sort_key(entry.get_modified_date()),
        ],
        entry.size,
        entry.get_modified_date(),
    )
}

fn run_similar_videos(spec: &ToolSpec, request: &ScanRequest, options: &Options<'_>, sender: ProgressSender, stop: Arc<AtomicBool>) -> Result<EngineOutcome, String> {
    // Every parameter the engine takes is exposed; each value is clamped into the range
    // SimilarVideosParameters::new asserts on, because an assert there panics the scan thread.
    let params = SimilarVideosParameters::new(
        options.integer("vid_tolerance", 2).clamp(0, i64::from(MAX_TOLERANCE)) as i32,
        options.flag("vid_ignore_same_size", false),
        options.flag("vid_ignore_same_resolution", false),
        whole(&ALLOWED_SKIP_FORWARD_AMOUNT, options.integer("vid_skip_forward", i64::from(DEFAULT_SKIP_FORWARD_AMOUNT))),
        whole(&ALLOWED_VID_HASH_DURATION, options.integer("vid_hash_duration", i64::from(DEFAULT_VID_HASH_DURATION))),
        options.flag("vid_letterbox_crop", DEFAULT_CROP_DETECT),
        whole(&ALLOWED_WINDOW_COUNT, options.integer("vid_window_count", i64::from(DEFAULT_WINDOW_COUNT))),
        fraction(
            &ALLOWED_DURATION_TOLERANCE_PCT,
            options.number("vid_duration_tolerance_pct", DEFAULT_DURATION_TOLERANCE_PCT),
        ),
        fraction(&ALLOWED_MATCH_FRACTION, options.number("vid_min_matching_windows", DEFAULT_MIN_MATCHING_WINDOWS)),
        fraction(&ALLOWED_MATCH_FRACTION, options.number("vid_subclip_min_match", DEFAULT_SUBCLIP_MIN_MATCH)),
        options.flag("vid_generate_thumbnails", false),
        u8::try_from(options.integer("vid_thumbnail_percentage", i64::from(DEFAULT_VIDEO_PERCENTAGE_FOR_THUMBNAIL)).clamp(0, 100))
            .unwrap_or(DEFAULT_VIDEO_PERCENTAGE_FOR_THUMBNAIL),
        options.flag("vid_thumbnail_grid", false),
        u8::try_from(options.integer("vid_thumbnail_grid_tiles", i64::from(DEFAULT_THUMBNAIL_GRID_TILES_PER_SIDE)).clamp(2, 6)).unwrap_or(DEFAULT_THUMBNAIL_GRID_TILES_PER_SIDE),
        options.flag("vid_check_audio_content", false),
        fraction(
            &ALLOWED_AUDIO_SIMILARITY_PERCENT,
            options.number("vid_audio_similarity_percent", DEFAULT_AUDIO_SIMILARITY_PERCENT),
        ),
        // Only the two percentages and the ratio are asserted by the engine; the maximum
        // difference is a plain f64, so it just needs to stay non-negative.
        options.number("vid_audio_max_difference", DEFAULT_AUDIO_MAXIMUM_DIFFERENCE).max(0.0),
        fraction(&ALLOWED_AUDIO_LENGTH_RATIO, options.number("vid_audio_length_ratio", DEFAULT_AUDIO_LENGTH_RATIO)),
        options
            .integer("vid_audio_min_duration_seconds", i64::from(DEFAULT_AUDIO_MIN_DURATION_SECONDS))
            .clamp(0, 600) as u32,
    );

    let mut tool = SimilarVideos::new(params);
    config::apply_common(&mut tool, request);
    tool.search(&stop, Some(&sender));

    let (critical, messages) = engine_messages(&tool);
    let stopped = tool.get_stopped_search();
    grouped_outcome(spec, build_grouped(video_groups(&tool)), stopped, messages, critical)
}

fn video_groups(tool: &SimilarVideos) -> Vec<Group> {
    if tool.get_use_reference() {
        return tool
            .get_similar_videos_referenced()
            .iter()
            .map(|(original, others)| Group {
                reference: Some(reference_row(video_row(original))),
                members: others.iter().map(video_row).collect(),
            })
            .collect();
    }
    tool.get_similar_videos()
        .iter()
        .map(|members| Group {
            reference: None,
            members: members.iter().map(video_row).collect(),
        })
        .collect()
}

fn video_row(entry: &VideosEntry) -> EngineRow {
    let resolution = match (entry.width, entry.height) {
        (Some(width), Some(height)) => format!("{width}x{height}"),
        _ => String::new(),
    };
    EngineRow::new(
        entry.get_path().to_path_buf(),
        vec![
            format_bytes(entry.size),
            format_duration_opt(entry.duration),
            resolution,
            entry.codec.clone().unwrap_or_default(),
            format_bitrate_opt(entry.bitrate),
            format_timestamp(entry.get_modified_date()),
        ],
        vec![
            to_sort_key(entry.size),
            (entry.duration.unwrap_or(0.0) * 1000.0) as i64,
            entry.width.map_or(0, i64::from) * entry.height.map_or(0, i64::from),
            0, // codec is text only, there is nothing numeric to sort it by
            entry.bitrate.map_or(0, to_sort_key),
            to_sort_key(entry.get_modified_date()),
        ],
        entry.size,
        entry.get_modified_date(),
    )
}

fn run_same_music(spec: &ToolSpec, request: &ScanRequest, options: &Options<'_>, sender: ProgressSender, stop: Arc<AtomicBool>) -> Result<EngineOutcome, String> {
    let params = SameMusicParameters::new(
        music_similarity(options),
        options.flag("mus_approximate", true),
        music_check_method(options)?,
        options.number("mus_min_fragment_duration", 10.0).clamp(1.0, 600.0) as f32,
        options.number("mus_max_difference", 2.0).clamp(0.0, 1000.0),
        true,
    );

    let mut tool = SameMusic::new(params);
    config::apply_common(&mut tool, request);
    tool.search(&stop, Some(&sender));

    let (critical, messages) = engine_messages(&tool);
    let stopped = tool.get_stopped_search();
    grouped_outcome(spec, build_grouped(music_groups(&tool)), stopped, messages, critical)
}

fn music_groups(tool: &SameMusic) -> Vec<Group> {
    if tool.get_use_reference() {
        return tool
            .get_similar_music_referenced()
            .iter()
            .map(|(original, others)| Group {
                reference: Some(reference_row(music_row(original))),
                members: others.iter().map(music_row).collect(),
            })
            .collect();
    }
    tool.get_duplicated_music_entries()
        .iter()
        .map(|members| Group {
            reference: None,
            members: members.iter().map(music_row).collect(),
        })
        .collect()
}

fn music_row(entry: &MusicEntry) -> EngineRow {
    EngineRow::new(
        entry.get_path().to_path_buf(),
        vec![
            format_bytes(entry.size),
            entry.track_title.clone(),
            entry.track_artist.clone(),
            entry.year.clone(),
            entry.bitrate.to_string(),
            format_audio_duration(entry.length),
            entry.genre.clone(),
            format_timestamp(entry.get_modified_date()),
        ],
        vec![
            to_sort_key(entry.size),
            0, // title and genre are text only, so they keep a neutral sort key
            0,
            entry.year.parse::<i64>().unwrap_or(0),
            i64::from(entry.bitrate),
            i64::from(entry.length),
            0,
            to_sort_key(entry.get_modified_date()),
        ],
        entry.size,
        entry.get_modified_date(),
    )
}

/// One scanner group before assembly: a read-only original from a reference folder and its copies.
struct Group {
    reference: Option<EngineRow>,
    members: Vec<EngineRow>,
}

fn reference_row(mut row: EngineRow) -> EngineRow {
    row.is_reference = true;
    row
}

/// Mirrors the Slint frontend's `build_grouped`: members are ordered by path, the largest total
/// group comes first, and every row records its group membership. Selection stays in Dart.
fn build_grouped(groups: Vec<Group>) -> Vec<EngineRow> {
    let mut entries: Vec<Vec<EngineRow>> = groups
        .into_iter()
        .map(|group| {
            let mut members = group.members;
            if let Some(reference) = group.reference {
                members.push(reference);
            }
            members.sort_unstable_by(|a, b| split_path_compare(a.path.as_path(), b.path.as_path()));
            members
        })
        .filter(|members| !members.is_empty())
        .collect();

    // Biggest groups first, so the most valuable results stay on top.
    entries.sort_by_key(|members| Reverse(members.iter().map(|row| row.size_bytes).sum::<u64>()));

    let mut rows = Vec::with_capacity(entries.iter().map(Vec::len).sum());
    for (group_index, members) in entries.into_iter().enumerate() {
        let group_size = members.len() as i32;
        for (position, mut row) in members.into_iter().enumerate() {
            row.group_index = group_index as i32;
            row.group_size = group_size;
            row.is_group_start = position == 0;
            rows.push(row);
        }
    }
    rows
}

/// Packs the rows into the engine outcome, refusing to hand Dart a row that does not fill the
/// declared columns.
fn grouped_outcome(spec: &ToolSpec, rows: Vec<EngineRow>, stopped: bool, messages: String, critical: Option<String>) -> Result<EngineOutcome, String> {
    if let Some(row) = rows.iter().find(|row| row.cells.len() != spec.columns.len() || row.sort_keys.len() != spec.columns.len()) {
        return Err(format!(
            "Scanner '{}' built a row with {} cells for '{}' but declares {} columns",
            spec.id,
            row.cells.len(),
            row.path.display(),
            spec.columns.len()
        ));
    }
    Ok(EngineOutcome {
        rows,
        grouped: true,
        stopped,
        messages,
        critical,
    })
}

/// Engine log text plus the critical error, harvested exactly as the Slint frontend does.
fn engine_messages(tool: &impl CommonData) -> (Option<String>, String) {
    let messages = tool.get_text_messages();
    (messages.critical.clone(), messages.create_messages_text(MessageLimit::NoLimit))
}

/// Reads per-tool options by field id.
///
/// `FieldStore` collapses an absent option into its zero value, so the fallbacks the Slint
/// frontend used are restored here from the raw request payload list.
struct Options<'a> {
    request: &'a ScanRequest,
    store: &'a FieldStore,
}

impl<'a> Options<'a> {
    fn new(request: &'a ScanRequest, store: &'a FieldStore) -> Self {
        Options { request, store }
    }

    fn flag(&self, id: &str, default: bool) -> bool {
        if self.present(id) { self.store.flag(id) } else { default }
    }

    /// Numbers may arrive as an integer payload or as the text the settings fields store.
    fn integer(&self, id: &str, default: i64) -> i64 {
        if !self.present(id) {
            return default;
        }
        match self.payload(id) {
            Some(FieldPayload::Text(text)) => text.trim().parse().unwrap_or(default),
            _ => self.store.integer(id),
        }
    }

    /// Duration and tolerance values the engine takes as floats; Dart sends whole numbers or text.
    fn number(&self, id: &str, default: f64) -> f64 {
        if !self.present(id) {
            return default;
        }
        let value = match self.payload(id) {
            Some(FieldPayload::Text(text)) => text.trim().parse().unwrap_or(default),
            _ => self.store.integer(id) as f64,
        };
        // The engine clamps these values, and `f64::clamp` panics on NaN.
        if value.is_nan() { default } else { value }
    }

    /// Choice as a machine key. An unset option yields `default`; anything else is normalized so
    /// the callers can compare against separator-free lowercase keys.
    fn choice(&self, id: &str, default: &str) -> String {
        let raw = match self.payload(id) {
            Some(FieldPayload::Text(text)) => text.clone(),
            _ => self.store.choice(id),
        };
        if raw.trim().is_empty() { default.to_string() } else { normalize_key(&raw) }
    }

    fn present(&self, id: &str) -> bool {
        self.payload(id).is_some()
    }

    fn payload(&self, id: &str) -> Option<&FieldPayload> {
        self.request.fields.iter().find(|field| field.id == id).map(|field| &field.value)
    }
}

fn normalize_key(raw: &str) -> String {
    raw.chars().filter(|c| c.is_alphanumeric()).flat_map(char::to_lowercase).collect()
}

/// Snaps a whole-number option into the range the engine asserts on, so an out-of-range request
/// clamps instead of panicking the scan thread.
fn whole(range: &RangeInclusive<u32>, value: i64) -> u32 {
    value.clamp(i64::from(*range.start()), i64::from(*range.end())) as u32
}

/// Same guard for the fractional options (`0.0..=1.0` and percentage ranges).
fn fraction(range: &RangeInclusive<f64>, value: f64) -> f64 {
    value.clamp(*range.start(), *range.end())
}

fn invalid_choice(id: &str, value: &str, accepted: &str) -> String {
    format!("Invalid choice '{value}' for option '{id}' - expected one of {accepted}")
}

fn check_method(options: &Options<'_>) -> Result<CheckingMethod, String> {
    match options.choice("dup_check_method", "hash").as_str() {
        "hash" => Ok(CheckingMethod::Hash),
        "size" => Ok(CheckingMethod::Size),
        "name" => Ok(CheckingMethod::Name),
        "sizename" => Ok(CheckingMethod::SizeName),
        value => Err(invalid_choice("dup_check_method", value, "hash, size, name, size_name")),
    }
}

fn hash_type(options: &Options<'_>) -> Result<HashType, String> {
    match options.choice("dup_hash_type", "xxh3").as_str() {
        "blake3" => Ok(HashType::Blake3),
        "crc32" => Ok(HashType::Crc32),
        "xxh3" => Ok(HashType::Xxh3),
        value => Err(invalid_choice("dup_hash_type", value, "blake3, crc32, xxh3")),
    }
}

/// The core asserts on the hash size, so only the four supported values may reach it.
fn image_hash_size(options: &Options<'_>) -> Result<u8, String> {
    match options.choice("img_hash_size", "16").as_str() {
        "8" => Ok(8),
        "16" => Ok(16),
        "32" => Ok(32),
        "64" => Ok(64),
        value => Err(invalid_choice("img_hash_size", value, "8, 16, 32, 64")),
    }
}

fn similarity_preset(options: &Options<'_>) -> Result<SimilarityPreset, String> {
    match options.choice("img_similarity", "high").as_str() {
        "original" => Ok(SimilarityPreset::Original),
        "veryhigh" => Ok(SimilarityPreset::VeryHigh),
        "high" => Ok(SimilarityPreset::High),
        "medium" => Ok(SimilarityPreset::Medium),
        "small" => Ok(SimilarityPreset::Small),
        "verysmall" => Ok(SimilarityPreset::VerySmall),
        "minimal" => Ok(SimilarityPreset::Minimal),
        value => Err(invalid_choice("img_similarity", value, "original, very_high, high, medium, small, very_small, minimal")),
    }
}

fn hash_algorithm(options: &Options<'_>) -> Result<HashAlg, String> {
    match options.choice("img_hash_algorithm", "gradient").as_str() {
        "mean" => Ok(HashAlg::Mean),
        "gradient" => Ok(HashAlg::Gradient),
        "blockhash" => Ok(HashAlg::Blockhash),
        "vertgradient" => Ok(HashAlg::VertGradient),
        "doublegradient" => Ok(HashAlg::DoubleGradient),
        "median" => Ok(HashAlg::Median),
        value => Err(invalid_choice(
            "img_hash_algorithm",
            value,
            "mean, gradient, blockhash, vert_gradient, double_gradient, median",
        )),
    }
}

fn resize_algorithm(options: &Options<'_>) -> Result<FilterType, String> {
    match options.choice("img_resize_algorithm", "lanczos3").as_str() {
        "lanczos3" => Ok(FilterType::Lanczos3),
        "gaussian" => Ok(FilterType::Gaussian),
        "catmullrom" => Ok(FilterType::CatmullRom),
        "triangle" => Ok(FilterType::Triangle),
        "nearest" => Ok(FilterType::Nearest),
        value => Err(invalid_choice("img_resize_algorithm", value, "lanczos3, gaussian, catmullrom, triangle, nearest")),
    }
}

fn geometric_invariance(options: &Options<'_>) -> Result<GeometricInvariance, String> {
    match options.choice("img_geometric_invariance", "off").as_str() {
        "off" => Ok(GeometricInvariance::Off),
        "mirrorflip" => Ok(GeometricInvariance::MirrorFlip),
        "mirrorfliprotate90" => Ok(GeometricInvariance::MirrorFlipRotate90),
        value => Err(invalid_choice("img_geometric_invariance", value, "off, mirror_flip, mirror_flip_rotate90")),
    }
}

fn music_similarity(options: &Options<'_>) -> MusicSimilarity {
    let mut similarity = MusicSimilarity::NONE;
    if options.flag("mus_title", true) {
        similarity |= MusicSimilarity::TRACK_TITLE;
    }
    if options.flag("mus_artist", true) {
        similarity |= MusicSimilarity::TRACK_ARTIST;
    }
    if options.flag("mus_year", false) {
        similarity |= MusicSimilarity::YEAR;
    }
    if options.flag("mus_length", false) {
        similarity |= MusicSimilarity::LENGTH;
    }
    if options.flag("mus_genre", false) {
        similarity |= MusicSimilarity::GENRE;
    }
    if options.flag("mus_bitrate", false) {
        similarity |= MusicSimilarity::BITRATE;
    }
    // The core asserts a non-empty mask, so fall back to comparing titles.
    if similarity.is_empty() {
        similarity = MusicSimilarity::TRACK_TITLE;
    }
    similarity
}

fn music_check_method(options: &Options<'_>) -> Result<CheckingMethod, String> {
    match options.choice("mus_check_type", "tags").as_str() {
        "tags" => Ok(CheckingMethod::AudioTags),
        "fingerprint" => Ok(CheckingMethod::AudioContent),
        value => Err(invalid_choice("mus_check_type", value, "tags, fingerprint")),
    }
}

/// Splits a length so it fits an i64 sort key without losing order.
fn to_sort_key(value: u64) -> i64 {
    i64::try_from(value).unwrap_or(i64::MAX)
}

const BYTE_UNITS: [&str; 8] = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB"];

/// Binary size, formatted locally because the bridge crate pulls in no formatting dependency.
fn format_bytes(size: u64) -> String {
    let mut value = size as f64;
    let mut units = BYTE_UNITS.iter().copied();
    let mut unit = units.next().unwrap_or("B");
    while value >= 1024.0 {
        let Some(next_unit) = units.next() else { break };
        value /= 1024.0;
        unit = next_unit;
    }
    if unit == "B" { format!("{size} B") } else { format!("{value:.2} {unit}") }
}

/// The bridge crate has no date dependency, so civil time is derived here; std exposes no local
/// offset, so modification dates are shown in UTC.
fn format_timestamp(epoch_seconds: u64) -> String {
    let seconds = i64::try_from(epoch_seconds).unwrap_or_default();
    let (year, month, day) = civil_from_days(seconds.div_euclid(86_400));
    let time = seconds.rem_euclid(86_400);
    format!("{year:04}-{month:02}-{day:02} {:02}:{:02}:{:02}", time / 3600, (time % 3600) / 60, time % 60)
}

/// Days since 1970-01-01 to a proleptic Gregorian date (Howard Hinnant's algorithm).
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let shifted = days + 719_468;
    // Subtracting divisor-1 before truncating division turns it into floor division.
    let era = if shifted < 0 { shifted - 146_096 } else { shifted } / 146_097;
    let day_of_era = (shifted - era * 146_097) as u32;
    let year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = i64::from(year_of_era) + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_shift = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_shift + 2) / 5 + 1;
    let month = if month_shift < 10 { month_shift + 3 } else { month_shift - 9 };
    (if month <= 2 { year + 1 } else { year }, month, day)
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;
    use crate::api::types::FieldValue;

    fn request_with(fields: &[(&str, FieldPayload)]) -> ScanRequest {
        ScanRequest {
            tool: "duplicate_files".to_string(),
            included: vec!["/tmp".to_string()],
            reference: Vec::new(),
            excluded_paths: Vec::new(),
            excluded_items: Vec::new(),
            allowed_extensions: Vec::new(),
            excluded_extensions: Vec::new(),
            recursive: true,
            use_cache: true,
            min_size_kib: String::new(),
            max_size_kib: String::new(),
            fields: fields
                .iter()
                .map(|(id, value)| FieldValue {
                    id: (*id).to_string(),
                    value: (*value).clone(),
                })
                .collect(),
        }
    }

    fn options_with(fields: &[(&str, FieldPayload)]) -> (ScanRequest, FieldStore) {
        let request = request_with(fields);
        let store = FieldStore::new(request.fields.clone());
        (request, store)
    }

    fn row(size: u64, name: &str) -> EngineRow {
        EngineRow::new(PathBuf::from(format!("/x/{name}")), vec![], vec![], size, 0)
    }

    #[test]
    fn out_of_range_numbers_clamp_instead_of_reaching_the_engine_asserts() {
        assert_eq!(whole(&ALLOWED_WINDOW_COUNT, 0), 1);
        assert_eq!(whole(&ALLOWED_WINDOW_COUNT, 999), 20);
        assert_eq!(whole(&ALLOWED_SKIP_FORWARD_AMOUNT, -5), 0);
        assert_eq!(whole(&ALLOWED_VID_HASH_DURATION, 10), 10);

        assert_eq!(fraction(&ALLOWED_MATCH_FRACTION, 1.4), 1.0);
        assert_eq!(fraction(&ALLOWED_DURATION_TOLERANCE_PCT, -3.0), 0.0);
        assert_eq!(fraction(&ALLOWED_AUDIO_LENGTH_RATIO, 0.25), 0.25);
    }

    #[test]
    fn video_defaults_satisfy_the_ranges_the_engine_asserts_on() {
        // A default outside an asserted range would panic the scan thread on every video scan.
        let ids = [
            "vid_skip_forward",
            "vid_hash_duration",
            "vid_window_count",
            "vid_duration_tolerance_pct",
            "vid_min_matching_windows",
            "vid_subclip_min_match",
            "vid_audio_similarity_percent",
            "vid_audio_length_ratio",
        ];
        let values = crate::engine::options::defaults(&ids);
        let number = |id: &str| -> f64 {
            let payload = values.iter().find(|value| value.id == id).unwrap_or_else(|| panic!("missing default: {id}"));
            match &payload.value {
                FieldPayload::Text(text) => text.parse().unwrap_or_else(|_| panic!("{id} default is not a number: {text}")),
                FieldPayload::Integer(value) => *value as f64,
                other => panic!("{id} default should be numeric, got {other:?}"),
            }
        };
        let whole_number = |id: &str| number(id) as u32;

        assert!(ALLOWED_SKIP_FORWARD_AMOUNT.contains(&whole_number("vid_skip_forward")));
        assert!(ALLOWED_VID_HASH_DURATION.contains(&whole_number("vid_hash_duration")));
        assert!(ALLOWED_WINDOW_COUNT.contains(&whole_number("vid_window_count")));
        assert!(ALLOWED_DURATION_TOLERANCE_PCT.contains(&number("vid_duration_tolerance_pct")));
        assert!(ALLOWED_MATCH_FRACTION.contains(&number("vid_min_matching_windows")));
        assert!(ALLOWED_MATCH_FRACTION.contains(&number("vid_subclip_min_match")));
        assert!(ALLOWED_AUDIO_SIMILARITY_PERCENT.contains(&number("vid_audio_similarity_percent")));
        assert!(ALLOWED_AUDIO_LENGTH_RATIO.contains(&number("vid_audio_length_ratio")));
    }

    #[test]
    fn choice_parsing_accepts_machine_keys_in_any_spelling() {
        let (request, store) = options_with(&[
            ("dup_check_method", FieldPayload::Choice("Size_Name".to_string())),
            ("dup_hash_type", FieldPayload::Choice("blake3".to_string())),
            ("img_similarity", FieldPayload::Choice("very-high".to_string())),
            ("img_hash_size", FieldPayload::Choice("64".to_string())),
            ("mus_check_type", FieldPayload::Choice("fingerprint".to_string())),
        ]);
        let options = Options::new(&request, &store);

        assert_eq!(check_method(&options).unwrap(), CheckingMethod::SizeName);
        assert_eq!(hash_type(&options).unwrap(), HashType::Blake3);
        // SimilarityPreset has no PartialEq, so the variant is matched directly.
        assert!(matches!(similarity_preset(&options).unwrap(), SimilarityPreset::VeryHigh));
        assert_eq!(image_hash_size(&options).unwrap(), 64);
        assert_eq!(music_check_method(&options).unwrap(), CheckingMethod::AudioContent);
    }

    #[test]
    fn unknown_choice_is_reported_not_defaulted() {
        let (request, store) = options_with(&[("dup_hash_type", FieldPayload::Choice("md5".to_string()))]);
        let options = Options::new(&request, &store);

        let error = hash_type(&options).expect_err("md5 is not a supported hash type");
        assert!(error.contains("dup_hash_type"), "{error}");
        assert!(error.contains("md5"), "{error}");
        assert!(error.contains("blake3, crc32, xxh3"), "{error}");
    }

    #[test]
    fn absent_options_keep_the_frontend_defaults() {
        let (request, store) = options_with(&[]);
        let options = Options::new(&request, &store);

        assert_eq!(check_method(&options).unwrap(), CheckingMethod::Hash);
        assert_eq!(hash_type(&options).unwrap(), HashType::Xxh3);
        assert_eq!(image_hash_size(&options).unwrap(), 16);
        assert!(options.flag("dup_use_prehash", true));
        assert!(!options.flag("dup_ignore_hard_links", false));
        assert_eq!(options.integer("dup_hash_cache_size", 1000), 1000);
        assert_eq!(options.number("mus_max_difference", 2.0), 2.0);
    }

    #[test]
    fn present_zero_is_not_treated_as_absent() {
        let (request, store) = options_with(&[("dup_hash_cache_size", FieldPayload::Integer(0))]);
        let options = Options::new(&request, &store);

        assert_eq!(options.integer("dup_hash_cache_size", 1000), 0);
    }

    #[test]
    fn numeric_options_accept_integer_and_text_payloads() {
        let (request, store) = options_with(&[
            ("mus_min_fragment_duration", FieldPayload::Integer(30)),
            ("mus_max_difference", FieldPayload::Text("1.5".to_string())),
            ("dup_hash_cache_size", FieldPayload::Text("500".to_string())),
        ]);
        let options = Options::new(&request, &store);

        assert_eq!(options.number("mus_min_fragment_duration", 10.0), 30.0);
        assert_eq!(options.number("mus_max_difference", 2.0), 1.5);
        assert_eq!(options.integer("dup_hash_cache_size", 1000), 500);
    }

    #[test]
    fn choice_options_accept_text_payloads() {
        let (request, store) = options_with(&[("dup_hash_type", FieldPayload::Text("crc32".to_string()))]);
        let options = Options::new(&request, &store);

        assert_eq!(hash_type(&options).unwrap(), HashType::Crc32);
    }

    #[test]
    fn empty_tag_selection_still_compares_titles() {
        let (request, store) = options_with(&[
            ("mus_title", FieldPayload::Flag(false)),
            ("mus_artist", FieldPayload::Flag(false)),
            ("mus_year", FieldPayload::Flag(false)),
            ("mus_length", FieldPayload::Flag(false)),
            ("mus_genre", FieldPayload::Flag(false)),
            ("mus_bitrate", FieldPayload::Flag(false)),
        ]);
        let options = Options::new(&request, &store);

        assert_eq!(music_similarity(&options), MusicSimilarity::TRACK_TITLE);
    }

    #[test]
    fn bytes_render_in_binary_units() {
        assert_eq!(format_bytes(0), "0 B");
        assert_eq!(format_bytes(999), "999 B");
        assert_eq!(format_bytes(1024), "1.00 KiB");
        assert_eq!(format_bytes(1_048_576), "1.00 MiB");
        assert_eq!(format_bytes(1_572_864), "1.50 MiB");
    }

    #[test]
    fn timestamps_render_in_utc() {
        assert_eq!(format_timestamp(0), "1970-01-01 00:00:00");
        assert_eq!(format_timestamp(1_700_000_000), "2023-11-14 22:13:20");
        assert_eq!(format_timestamp(86_399), "1970-01-01 23:59:59");
    }

    #[test]
    fn groups_order_by_total_size_then_path() {
        let rows = build_grouped(vec![
            Group {
                reference: None,
                members: vec![row(10, "small")],
            },
            Group {
                reference: None,
                members: vec![row(300, "b"), row(100, "a")],
            },
        ]);

        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].name, "a");
        assert_eq!(rows[0].group_index, 0);
        assert_eq!(rows[0].group_size, 2);
        assert!(rows[0].is_group_start);
        assert!(!rows[1].is_group_start);
        assert_eq!(rows[2].group_index, 1);
        assert_eq!(rows[2].group_size, 1);
    }

    #[test]
    fn reference_row_stays_sorted_inside_its_group() {
        let rows = build_grouped(vec![Group {
            reference: Some(reference_row(row(500, "c"))),
            members: vec![row(100, "a"), row(300, "b")],
        }]);

        assert_eq!(rows.len(), 3);
        assert_eq!(rows[2].name, "c");
        assert!(rows[2].is_reference);
        assert!(rows[..2].iter().all(|row| !row.is_reference));
        assert_eq!(rows.iter().map(|row| row.group_size).collect::<Vec<_>>(), vec![3; 3]);
    }

    #[test]
    fn empty_groups_are_dropped() {
        let rows = build_grouped(vec![Group {
            reference: None,
            members: Vec::new(),
        }]);
        assert!(rows.is_empty());
    }
}
