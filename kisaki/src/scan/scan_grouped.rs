use std::path::Path;

use czkawka_core::common::model::{CheckingMethod, HashType};
use czkawka_core::common::tool_data::CommonData;
use czkawka_core::common::traits::{ResultEntry, Search};
use czkawka_core::re_exported::{FilterType, HashAlg};
use czkawka_core::tools::duplicate::{DuplicateEntry, DuplicateFinder, DuplicateFinderParameters};
use czkawka_core::tools::same_music::core::format_audio_duration;
use czkawka_core::tools::same_music::{MusicEntry, MusicSimilarity, SameMusic, SameMusicParameters};
use czkawka_core::tools::similar_images::core::{get_string_from_similarity, return_similarity_from_similarity_preset};
use czkawka_core::tools::similar_images::{GeometricInvariance, ImagesEntry, SimilarImages, SimilarImagesParameters, SimilarityPreset};
use czkawka_core::tools::similar_videos::core::{format_bitrate_opt, format_duration_opt};
use czkawka_core::tools::similar_videos::{MAX_TOLERANCE, SimilarVideos, SimilarVideosParameters, VideosEntry};

use crate::ToolId;
use crate::common::{format_bytes, format_timestamp, to_sort_key};
use crate::fields::{FieldId, FieldRead};
use crate::scan::{Outcome, ScanCtx, build_grouped, make_row, messages, outcome, set_common_settings};
use crate::state::RowData;

const HASH_SIZES: [u8; 4] = [8, 16, 32, 64];

pub fn run(ctx: &ScanCtx) -> Result<Outcome, String> {
    let outcome = match ctx.tool.id {
        ToolId::DuplicateFiles => run_duplicates(ctx),
        ToolId::SimilarImages => run_similar_images(ctx),
        ToolId::SimilarVideos => run_similar_videos(ctx),
        ToolId::DuplicateMusic => run_same_music(ctx),
        other => return Err(format!("Tool {other:?} is not registered as a grouped scanner")),
    };
    Ok(outcome)
}

fn row(path: &Path, size: u64, mtime: u64, cells: Vec<String>, sort_keys: Vec<i64>) -> RowData {
    make_row(path.to_path_buf(), cells, sort_keys, size, mtime)
}

fn reference_row(mut row: RowData) -> RowData {
    row.is_reference = true;
    row
}

fn run_duplicates(ctx: &ScanCtx) -> Outcome {
    let fields = &ctx.fields;
    let params = DuplicateFinderParameters::new(
        match fields.choice(FieldId::DupCheckMethod, 0) {
            1 => CheckingMethod::Size,
            2 => CheckingMethod::Name,
            3 => CheckingMethod::SizeName,
            _ => CheckingMethod::Hash,
        },
        match fields.choice(FieldId::DupHashType, 2) {
            0 => HashType::Blake3,
            1 => HashType::Crc32,
            _ => HashType::Xxh3,
        },
        fields.flag(FieldId::DupUsePrehash, true),
        fields.number(FieldId::DupHashCacheSize, 1000).max(1) as u64,
        fields.number(FieldId::DupPrehashCacheSize, 1000).max(1) as u64,
        fields.flag(FieldId::DupCaseSensitiveNames, true),
    );

    let mut tool = DuplicateFinder::new(params);
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.set_hide_hard_links(fields.flag(FieldId::DupIgnoreHardLinks, false));
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let groups = duplicate_groups(&tool)
        .into_iter()
        .map(|(reference, members)| (reference.as_ref().map(duplicate_row).map(reference_row), members.iter().map(duplicate_row).collect()))
        .collect();

    store(ctx, |models| models.duplicate_files = Some(tool));
    outcome(build_grouped(groups), critical, text, stopped, true)
}

fn duplicate_row(entry: &DuplicateEntry) -> RowData {
    row(
        entry.get_path(),
        entry.get_size(),
        entry.get_modified_date(),
        vec![format_bytes(entry.get_size()), format_timestamp(entry.get_modified_date())],
        vec![to_sort_key(entry.get_size()), to_sort_key(entry.get_modified_date())],
    )
}

fn duplicate_groups(tool: &DuplicateFinder) -> Vec<(Option<DuplicateEntry>, Vec<DuplicateEntry>)> {
    if tool.get_use_reference() {
        let referenced: Vec<(DuplicateEntry, Vec<DuplicateEntry>)> = match tool.get_params().check_method {
            CheckingMethod::Hash => tool.get_files_with_identical_hashes_referenced().values().flatten().cloned().collect(),
            CheckingMethod::Name => tool.get_files_with_identical_name_referenced().values().cloned().collect(),
            CheckingMethod::Size => tool.get_files_with_identical_size_referenced().values().cloned().collect(),
            CheckingMethod::SizeName => tool.get_files_with_identical_size_names_referenced().values().cloned().collect(),
            _ => Vec::new(),
        };
        return referenced.into_iter().map(|(original, others)| (Some(original), others)).collect();
    }
    let groups: Vec<Vec<DuplicateEntry>> = match tool.get_params().check_method {
        CheckingMethod::Hash => tool.get_files_sorted_by_hash().values().flatten().cloned().collect(),
        CheckingMethod::Name => tool.get_files_sorted_by_names().values().cloned().collect(),
        CheckingMethod::Size => tool.get_files_sorted_by_size().values().cloned().collect(),
        CheckingMethod::SizeName => tool.get_files_sorted_by_size_name().values().cloned().collect(),
        _ => Vec::new(),
    };
    groups.into_iter().map(|members| (None, members)).collect()
}

fn run_similar_images(ctx: &ScanCtx) -> Outcome {
    let fields = &ctx.fields;
    let hash_size = HASH_SIZES.get(usize::try_from(fields.choice(FieldId::ImgHashSize, 1)).unwrap_or(1)).copied().unwrap_or(16);
    let preset = match fields.choice(FieldId::ImgSimilarity, 2) {
        0 => SimilarityPreset::Original,
        1 => SimilarityPreset::VeryHigh,
        2 => SimilarityPreset::High,
        3 => SimilarityPreset::Medium,
        4 => SimilarityPreset::Small,
        5 => SimilarityPreset::VerySmall,
        _ => SimilarityPreset::Minimal,
    };
    let params = SimilarImagesParameters::new(
        return_similarity_from_similarity_preset(preset, hash_size),
        hash_size,
        match fields.choice(FieldId::ImgHashAlgorithm, 1) {
            0 => HashAlg::Mean,
            1 => HashAlg::Gradient,
            2 => HashAlg::Blockhash,
            3 => HashAlg::VertGradient,
            4 => HashAlg::DoubleGradient,
            _ => HashAlg::Median,
        },
        match fields.choice(FieldId::ImgResizeAlgorithm, 0) {
            0 => FilterType::Lanczos3,
            1 => FilterType::Gaussian,
            2 => FilterType::CatmullRom,
            3 => FilterType::Triangle,
            _ => FilterType::Nearest,
        },
        fields.flag(FieldId::ImgIgnoreSameSize, false),
        fields.flag(FieldId::ImgIgnoreSameResolution, false),
        match fields.choice(FieldId::ImgGeometricInvariance, 0) {
            1 => GeometricInvariance::MirrorFlip,
            2 => GeometricInvariance::MirrorFlipRotate90,
            _ => GeometricInvariance::Off,
        },
    );

    let mut tool = SimilarImages::new(params);
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let groups = image_groups(&tool)
        .into_iter()
        .map(|(reference, members)| {
            (
                reference.map(|entry| reference_row(image_row(&entry, hash_size))),
                members.into_iter().map(|entry| image_row(&entry, hash_size)).collect(),
            )
        })
        .collect();

    store(ctx, |models| models.similar_images = Some(tool));
    outcome(build_grouped(groups), critical, text, stopped, true)
}

fn image_row(entry: &ImagesEntry, hash_size: u8) -> RowData {
    let resolution = format!("{}x{}", entry.width, entry.height);
    row(
        entry.get_path(),
        entry.size,
        entry.get_modified_date(),
        vec![
            get_string_from_similarity(entry.difference, hash_size),
            format_bytes(entry.size),
            resolution,
            format_timestamp(entry.get_modified_date()),
        ],
        vec![
            entry.difference as i64,
            to_sort_key(entry.size),
            i64::from(entry.width) * i64::from(entry.height),
            to_sort_key(entry.get_modified_date()),
        ],
    )
}

fn image_groups(tool: &SimilarImages) -> Vec<(Option<ImagesEntry>, Vec<ImagesEntry>)> {
    if tool.get_use_reference() {
        return tool
            .get_similar_images_referenced()
            .iter()
            .cloned()
            .map(|(original, others)| (Some(original), others))
            .collect();
    }
    tool.get_similar_images().iter().cloned().map(|members| (None, members)).collect()
}

fn run_similar_videos(ctx: &ScanCtx) -> Outcome {
    let fields = &ctx.fields;
    let params = SimilarVideosParameters::new(
        fields.number(FieldId::VidTolerance, 2).clamp(0, i64::from(MAX_TOLERANCE)) as i32,
        fields.flag(FieldId::VidIgnoreSameSize, false),
        false,
        fields.number(FieldId::VidSkipForward, 15).clamp(0, 300) as u32,
        fields.number(FieldId::VidHashDuration, 10).clamp(2, 60) as u32,
        fields.flag(FieldId::VidLetterboxCrop, true),
        5,
        20.0,
        0.6,
        0.5,
        false,
        10,
        false,
        2,
        false,
        80.0,
        3.0,
        0.1,
        10,
    );

    let mut tool = SimilarVideos::new(params);
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let groups = video_groups(&tool)
        .into_iter()
        .map(|(reference, members)| (reference.as_ref().map(video_row).map(reference_row), members.iter().map(video_row).collect()))
        .collect();

    store(ctx, |models| models.similar_videos = Some(tool));
    outcome(build_grouped(groups), critical, text, stopped, true)
}

fn video_row(entry: &VideosEntry) -> RowData {
    let resolution = match (entry.width, entry.height) {
        (Some(width), Some(height)) => format!("{width}x{height}"),
        _ => String::new(),
    };
    row(
        entry.get_path(),
        entry.size,
        entry.get_modified_date(),
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
            0,
            entry.bitrate.map_or(0, to_sort_key),
            to_sort_key(entry.get_modified_date()),
        ],
    )
}

fn video_groups(tool: &SimilarVideos) -> Vec<(Option<VideosEntry>, Vec<VideosEntry>)> {
    if tool.get_use_reference() {
        return tool
            .get_similar_videos_referenced()
            .iter()
            .cloned()
            .map(|(original, others)| (Some(original), others))
            .collect();
    }
    tool.get_similar_videos().iter().cloned().map(|members| (None, members)).collect()
}

fn run_same_music(ctx: &ScanCtx) -> Outcome {
    let fields = &ctx.fields;
    let mut similarity = MusicSimilarity::NONE;
    if fields.flag(FieldId::MusTitle, true) {
        similarity |= MusicSimilarity::TRACK_TITLE;
    }
    if fields.flag(FieldId::MusArtist, true) {
        similarity |= MusicSimilarity::TRACK_ARTIST;
    }
    if fields.flag(FieldId::MusYear, false) {
        similarity |= MusicSimilarity::YEAR;
    }
    if fields.flag(FieldId::MusLength, false) {
        similarity |= MusicSimilarity::LENGTH;
    }
    if fields.flag(FieldId::MusGenre, false) {
        similarity |= MusicSimilarity::GENRE;
    }
    if fields.flag(FieldId::MusBitrate, false) {
        similarity |= MusicSimilarity::BITRATE;
    }
    // The core asserts a non-empty mask, so fall back to comparing titles.
    if similarity.is_empty() {
        similarity = MusicSimilarity::TRACK_TITLE;
    }

    let params = SameMusicParameters::new(
        similarity,
        fields.flag(FieldId::MusApproximate, true),
        if fields.choice(FieldId::MusCheckType, 0) == 1 {
            CheckingMethod::AudioContent
        } else {
            CheckingMethod::AudioTags
        },
        fields.float(FieldId::MusMinFragmentDuration, 10.0).clamp(1.0, 600.0) as f32,
        fields.float(FieldId::MusMaxDifference, 2.0).clamp(0.0, 1000.0),
        true,
    );

    let mut tool = SameMusic::new(params);
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let groups = music_groups(&tool)
        .into_iter()
        .map(|(reference, members)| (reference.as_ref().map(music_row).map(reference_row), members.iter().map(music_row).collect()))
        .collect();

    store(ctx, |models| models.same_music = Some(tool));
    outcome(build_grouped(groups), critical, text, stopped, true)
}

fn music_row(entry: &MusicEntry) -> RowData {
    row(
        entry.get_path(),
        entry.size,
        entry.get_modified_date(),
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
            0,
            0,
            entry.year.parse::<i64>().unwrap_or(0),
            entry.bitrate as i64,
            entry.length as i64,
            0,
            to_sort_key(entry.get_modified_date()),
        ],
    )
}

fn music_groups(tool: &SameMusic) -> Vec<(Option<MusicEntry>, Vec<MusicEntry>)> {
    if tool.get_use_reference() {
        return tool
            .get_similar_music_referenced()
            .iter()
            .cloned()
            .map(|(original, others)| (Some(original), others))
            .collect();
    }
    tool.get_duplicated_music_entries().iter().cloned().map(|members| (None, members)).collect()
}

fn store<F>(ctx: &ScanCtx, insert: F)
where
    F: FnOnce(&mut crate::state::SharedModels),
{
    let mut guard = ctx.state.lock().expect("App state mutex poisoned");
    insert(&mut guard.models);
}
