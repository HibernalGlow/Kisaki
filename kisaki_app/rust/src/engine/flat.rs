use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use czkawka_core::common::path_utils::split_path_compare;
use czkawka_core::common::tool_data::CommonData;
use czkawka_core::common::traits::{ResultEntry, Search};
use czkawka_core::helpers::messages::MessageLimit;
use czkawka_core::tools::bad_extensions::{BadExtensions, BadExtensionsParameters, BadFileEntry};
use czkawka_core::tools::bad_names::{BadNameEntry, BadNames, BadNamesParameters, NameIssues};
use czkawka_core::tools::big_file::{BigFile, BigFileParameters, SearchMode};
use czkawka_core::tools::broken_files::{BrokenEntry, BrokenFiles, BrokenFilesParameters, CheckedTypes};
use czkawka_core::tools::empty_files::{EmptyFiles, EmptyFilesParameters};
use czkawka_core::tools::empty_folder::EmptyFolder;
use czkawka_core::tools::exif_remover::{ExifEntry, ExifRemover, ExifRemoverParameters};
use czkawka_core::tools::invalid_symlinks::{ErrorType, InvalidSymlinks, SymlinksFileEntry};
use czkawka_core::tools::temporary::{Temporary, TemporaryParameters};
use czkawka_core::tools::video_optimizer::{
    VideoCropEntry, VideoCropParams, VideoCroppingMechanism, VideoOptimizer, VideoOptimizerMode, VideoOptimizerParameters, VideoTranscodeEntry, VideoTranscodeParams,
};

use crate::api::types::{FieldPayload, ScanRequest, ToolSpec};
use crate::engine::config::apply_common;
use crate::engine::runner::ProgressSender;
use crate::engine::{EngineOutcome, EngineRow, FieldStore};

/// Scanners whose output is a flat list: empty folders, big files, broken files, bad names, etc.
pub fn run(
    spec: &ToolSpec,
    request: &ScanRequest,
    store: &FieldStore,
    sender: ProgressSender,
    stop: Arc<AtomicBool>,
) -> Result<EngineOutcome, String> {
    let scan = Scan { request, store, sender, stop };
    match spec.id.as_str() {
        "empty_folders" => Ok(scan.empty_folders()),
        "big_files" => Ok(scan.big_files()),
        "empty_files" => Ok(scan.empty_files()),
        "temporary_files" => Ok(scan.temporary_files()),
        "invalid_symlinks" => Ok(scan.invalid_symlinks()),
        "broken_files" => Ok(scan.broken_files()),
        "bad_extensions" => Ok(scan.bad_extensions()),
        "bad_names" => Ok(scan.bad_names()),
        "exif_remover" => Ok(scan.exif_remover()),
        // Only the optimizer reads a choice option, so only it can reject the request.
        "video_optimizer" => scan.video_optimizer(),
        other => Err(format!("Tool {other} is not registered as a flat scanner")),
    }
}

/// Everything one flat scan needs: the shared path block, the option values and the engine plumbing.
struct Scan<'a> {
    request: &'a ScanRequest,
    store: &'a FieldStore,
    sender: ProgressSender,
    stop: Arc<AtomicBool>,
}

impl Scan<'_> {
    fn empty_folders(&self) -> EngineOutcome {
        let mut tool = EmptyFolder::new();
        apply_common(&mut tool, self.request);
        tool.search(&self.stop, Some(&self.sender));

        let rows: Vec<EngineRow> = tool.get_empty_folder_list().values().map(modified_only).collect();
        finish(&tool, rows)
    }

    fn big_files(&self) -> EngineOutcome {
        let mode = if flag_or(self.store, "big_biggest_first", true) { SearchMode::BiggestFiles } else { SearchMode::SmallestFiles };
        let count = number_or(self.store, "big_number_of_files", 50).clamp(1, 100_000);

        let mut tool = BigFile::new(BigFileParameters::new(usize::try_from(count).unwrap_or(50), mode));
        apply_common(&mut tool, self.request);
        tool.search(&self.stop, Some(&self.sender));

        let rows: Vec<EngineRow> = tool.get_big_files().iter().map(size_and_date).collect();
        finish(&tool, rows)
    }

    fn empty_files(&self) -> EngineOutcome {
        let params = EmptyFilesParameters {
            search_zero_byte_content_files: flag_or(self.store, "emp_zero_byte_content", true),
            search_non_printable_content_files: flag_or(self.store, "emp_non_printable_content", false),
        };

        let mut tool = EmptyFiles::new(params);
        apply_common(&mut tool, self.request);
        tool.search(&self.stop, Some(&self.sender));

        let rows: Vec<EngineRow> = tool.get_empty_files().iter().map(size_and_date).collect();
        finish(&tool, rows)
    }

    fn temporary_files(&self) -> EngineOutcome {
        let extensions = string_list(self.store, "temp_extension_list", "");
        let params = if extensions.is_empty() { TemporaryParameters::default() } else { TemporaryParameters { extensions } };

        let mut tool = Temporary::new(params);
        apply_common(&mut tool, self.request);
        tool.search(&self.stop, Some(&self.sender));

        let rows: Vec<EngineRow> = tool.get_temporary_files().iter().map(size_and_date).collect();
        finish(&tool, rows)
    }

    fn invalid_symlinks(&self) -> EngineOutcome {
        let mut tool = InvalidSymlinks::new();
        apply_common(&mut tool, self.request);
        tool.search(&self.stop, Some(&self.sender));

        let rows: Vec<EngineRow> = tool.get_invalid_symlinks().iter().map(symlink_row).collect();
        finish(&tool, rows)
    }

    fn broken_files(&self) -> EngineOutcome {
        let mut tool = BrokenFiles::new(BrokenFilesParameters::new(checked_types(self.store)));
        apply_common(&mut tool, self.request);
        tool.search(&self.stop, Some(&self.sender));

        let rows: Vec<EngineRow> = tool.get_broken_files().iter().map(broken_row).collect();
        finish(&tool, rows)
    }

    fn bad_extensions(&self) -> EngineOutcome {
        let mut tool = BadExtensions::new(BadExtensionsParameters::new());
        apply_common(&mut tool, self.request);
        tool.search(&self.stop, Some(&self.sender));

        let rows: Vec<EngineRow> = tool.get_bad_extensions_files().iter().map(bad_extension_row).collect();
        finish(&tool, rows)
    }

    fn bad_names(&self) -> EngineOutcome {
        let mut tool = BadNames::new(BadNamesParameters::new(NameIssues::all()));
        apply_common(&mut tool, self.request);
        tool.search(&self.stop, Some(&self.sender));

        let rows: Vec<EngineRow> = tool.get_bad_names_files().iter().map(bad_name_row).collect();
        finish(&tool, rows)
    }

    fn exif_remover(&self) -> EngineOutcome {
        let mut tool = ExifRemover::new(ExifRemoverParameters::new(string_list(self.store, "exif_ignored_tags", "")));
        apply_common(&mut tool, self.request);
        tool.search(&self.stop, Some(&self.sender));

        let rows: Vec<EngineRow> = tool.get_exif_files().iter().map(exif_row).collect();
        finish(&tool, rows)
    }

    fn video_optimizer(&self) -> Result<EngineOutcome, String> {
        let mode = parse_optimizer_mode(self.store.choice("vid_opt_mode").as_str()).map_err(|error| format!("video_optimizer: {error}"))?;

        // Thumbnail generation is a desktop preview feature, so both modes ask the engine to skip it.
        let params = match mode {
            VideoOptimizerMode::VideoCrop => VideoOptimizerParameters::VideoCrop(VideoCropParams::with_custom_params(
                VideoCroppingMechanism::BlackBars,
                u8::try_from(bounded(self.store, "vid_opt_black_pixel_threshold", 64, 0, 128)).unwrap_or(64),
                u8::try_from(bounded(self.store, "vid_opt_black_bar_min_percentage", 80, 50, 100)).unwrap_or(80),
                usize::try_from(bounded(self.store, "vid_opt_max_samples", 60, 5, 1000)).unwrap_or(60),
                u32::try_from(bounded(self.store, "vid_opt_min_crop_size", 20, 1, 1000)).unwrap_or(20),
                false,
                10,
                false,
                2,
            )),
            VideoOptimizerMode::VideoTranscode => VideoOptimizerParameters::VideoTranscode(VideoTranscodeParams::new(
                string_list(self.store, "vid_opt_excluded_codecs", "hevc,h265,av1,vp9"),
                false,
                10,
                false,
                2,
            )),
        };

        let mut tool = VideoOptimizer::new(params);
        apply_common(&mut tool, self.request);
        tool.search(&self.stop, Some(&self.sender));

        let rows: Vec<EngineRow> = match mode {
            VideoOptimizerMode::VideoCrop => tool.get_video_crop_entries().iter().map(crop_row).collect(),
            VideoOptimizerMode::VideoTranscode => tool.get_video_transcode_entries().iter().map(transcode_row).collect(),
        };
        Ok(finish(&tool, rows))
    }
}

/// Sorts like the reference frontend and reports what the engine wants the user to see.
fn finish<T: CommonData>(tool: &T, mut rows: Vec<EngineRow>) -> EngineOutcome {
    rows.sort_unstable_by(|a, b| split_path_compare(a.path.as_path(), b.path.as_path()));
    let (critical, messages) = messages(tool);
    EngineOutcome { rows, grouped: false, stopped: tool.get_stopped_search(), messages, critical }
}

fn messages(tool: &impl CommonData) -> (Option<String>, String) {
    let messages = tool.get_text_messages();
    (messages.critical.clone(), messages.create_messages_text(MessageLimit::NoLimit))
}

/// Rows for a scanner with a single `modified` column.
fn modified_only(entry: &impl ResultEntry) -> EngineRow {
    let modified = entry.get_modified_date();
    EngineRow::new(entry.get_path().to_path_buf(), vec![format_timestamp(modified)], vec![to_sort_key(modified)], 0, modified)
}

/// Rows for the `size`, `modified` layout most flat scanners share.
fn size_and_date(entry: &impl ResultEntry) -> EngineRow {
    let (size, modified) = (entry.get_size(), entry.get_modified_date());
    EngineRow::new(
        entry.get_path().to_path_buf(),
        vec![format_bytes(size), format_timestamp(modified)],
        vec![to_sort_key(size), to_sort_key(modified)],
        size,
        modified,
    )
}

fn symlink_row(entry: &SymlinksFileEntry) -> EngineRow {
    let (size, modified) = (entry.size, entry.modified_date);
    let error = entry.symlink_info.type_of_error;
    let destination = entry.symlink_info.destination_path.to_string_lossy().into_owned();
    EngineRow::new(
        entry.path.clone(),
        vec![destination, error.to_string(), format_timestamp(modified)],
        vec![0, error_sort_key(error), to_sort_key(modified)],
        size,
        modified,
    )
}

fn error_sort_key(error: ErrorType) -> i64 {
    match error {
        ErrorType::InfiniteRecursion => 0,
        ErrorType::NonExistentFile => 1,
    }
}

/// Which file kinds the engine is allowed to open.
fn checked_types(store: &FieldStore) -> CheckedTypes {
    let mut types = CheckedTypes::NONE;
    if flag_or(store, "bro_image", true) { types |= CheckedTypes::IMAGE; }
    if flag_or(store, "bro_archive", true) { types |= CheckedTypes::ARCHIVE; }
    if flag_or(store, "bro_audio", true) { types |= CheckedTypes::AUDIO; }
    if flag_or(store, "bro_pdf", true) { types |= CheckedTypes::PDF; }
    if flag_or(store, "bro_video_ffprobe", false) { types |= CheckedTypes::VIDEO_FFPROBE; }
    if flag_or(store, "bro_video_ffmpeg", false) { types |= CheckedTypes::VIDEO_FFMPEG; }
    if flag_or(store, "bro_font", false) { types |= CheckedTypes::FONT; }
    if flag_or(store, "bro_markup", false) { types |= CheckedTypes::MARKUP; }
    // The core rejects an empty mask, so fall back to images and archives.
    if types.is_empty() { types = CheckedTypes::IMAGE | CheckedTypes::ARCHIVE; }
    types
}

fn broken_row(entry: &BrokenEntry) -> EngineRow {
    let (size, modified) = (entry.size, entry.modified_date);
    EngineRow::new(
        entry.path.clone(),
        vec![format_bytes(size), entry.get_error_string(), format_timestamp(modified)],
        vec![to_sort_key(size), 0, to_sort_key(modified)],
        size,
        modified,
    )
}

fn bad_extension_row(entry: &BadFileEntry) -> EngineRow {
    let (size, modified) = (entry.size, entry.modified_date);
    EngineRow::new(
        entry.path.clone(),
        vec![
            entry.current_extension.clone(),
            entry.proper_extensions_group.clone(),
            entry.proper_extension.clone(),
            format_timestamp(modified),
        ],
        vec![0, 0, 0, to_sort_key(modified)],
        size,
        modified,
    )
}

fn bad_name_row(entry: &BadNameEntry) -> EngineRow {
    let (size, modified) = (entry.size, entry.modified_date);
    EngineRow::new(
        entry.path.clone(),
        vec![entry.new_name.clone(), format_bytes(size), format_timestamp(modified)],
        vec![0, to_sort_key(size), to_sort_key(modified)],
        size,
        modified,
    )
}

fn exif_row(entry: &ExifEntry) -> EngineRow {
    let (size, modified) = (entry.size, entry.modified_date);
    let tag_count = entry.exif_tags.len();
    let names = entry.exif_tags.iter().map(|tag| tag.name.as_str()).collect::<Vec<_>>().join(", ");
    EngineRow::new(
        entry.path.clone(),
        vec![format_bytes(size), format!("{tag_count} ({names})")],
        vec![to_sort_key(size), i64::try_from(tag_count).unwrap_or(i64::MAX)],
        size,
        modified,
    )
}

fn transcode_row(entry: &VideoTranscodeEntry) -> EngineRow {
    let (size, modified) = (entry.size, entry.modified_date);
    let (width, height) = (entry.width, entry.height);
    let cells =
        vec![format_bytes(size), entry.codec.clone(), format!("{width}x{height}"), entry.error.clone().unwrap_or_default(), format_timestamp(modified)];
    EngineRow::new(entry.path.clone(), cells, vec![to_sort_key(size), 0, resolution_key(width, height), 0, to_sort_key(modified)], size, modified)
}

fn crop_row(entry: &VideoCropEntry) -> EngineRow {
    let (size, modified) = (entry.size, entry.modified_date);
    let (width, height) = (entry.width, entry.height);
    let (left, top, right, bottom) = entry.new_image_dimensions;
    let cells = vec![
        format_bytes(size),
        entry.codec.clone(),
        format!("{width}x{height}"),
        format!("{left},{top},{right},{bottom}"),
        format_timestamp(modified),
    ];
    EngineRow::new(entry.path.clone(), cells, vec![to_sort_key(size), 0, resolution_key(width, height), 0, to_sort_key(modified)], size, modified)
}

/// Pixel count of the resolution column; saturating because both factors are `u32`.
fn resolution_key(width: u32, height: u32) -> i64 {
    i64::from(width).saturating_mul(i64::from(height))
}

/// A missing option keeps the default the Slint frontend used, so a request sent without the
/// option registry still scans exactly like the reference frontend.
fn flag_or(store: &FieldStore, id: &str, default: bool) -> bool {
    store.payload(id).and_then(FieldPayload::as_flag).unwrap_or(default)
}

fn number_or(store: &FieldStore, id: &str, default: i64) -> i64 {
    match store.payload(id) {
        // Numbers may travel as text, which is how every option value was stored in Slint.
        Some(FieldPayload::Text(text)) => text.trim().parse().unwrap_or(default),
        Some(value) => value.as_integer().unwrap_or(default),
        None => default,
    }
}

/// Numeric option clamped into the range the engine itself asserts on.
fn bounded(store: &FieldStore, id: &str, default: i64, min: i64, max: i64) -> i64 {
    number_or(store, id, default).clamp(min, max)
}

/// Tag, extension and codec lists arrive either as tokens or as one separated string.
fn string_list(store: &FieldStore, id: &str, default: &str) -> Vec<String> {
    match store.payload(id) {
        Some(FieldPayload::Tokens(values)) => split_list(&values.join(",")),
        Some(FieldPayload::Text(text)) => split_list(text),
        _ => split_list(default),
    }
}

/// Turns a machine string into the engine's own mode spelling; unknown values are an error.
fn parse_optimizer_mode(raw: &str) -> Result<VideoOptimizerMode, String> {
    let trimmed = raw.trim();
    // The option registry may hand back the fluent key instead of the short machine name.
    let name = trimmed.strip_prefix("option_video_optimizer_mode_").unwrap_or(trimmed);
    name
        .parse::<VideoOptimizerMode>()
        .map_err(|error| format!("'{raw}' is not a valid operation, expected crop or transcode: {error}"))
}

/// Splits a comma, semicolon or newline separated list into trimmed, quote-free, non-empty parts.
fn split_list(text: &str) -> Vec<String> {
    text.split([',', ';', '\n'])
        .map(|item| item.trim().trim_matches('"').trim_matches('\'').to_string())
        .filter(|item| !item.is_empty())
        .collect()
}

/// Sizes and timestamps only need an order, so anything past `i64` collapses to its maximum.
fn to_sort_key(value: u64) -> i64 {
    i64::try_from(value).unwrap_or(i64::MAX)
}

const BYTE_UNITS: [(&str, u32); 9] =
    [("B", 0), ("KiB", 10), ("MiB", 20), ("GiB", 30), ("TiB", 40), ("PiB", 50), ("EiB", 60), ("ZiB", 70), ("YiB", 80)];

/// Binary sizes with two decimals, matching what the Slint frontend renders.
fn format_bytes(size: u64) -> String {
    let (unit, shift) = BYTE_UNITS.iter().rev().copied().find(|&(_, shift)| (size as u128) >= (1u128 << shift)).unwrap_or(("B", 0));
    if shift == 0 {
        return format!("{size} {unit}");
    }
    // Scaling by 100 before the shift keeps the decimals in integer math.
    let hundredths = ((size as u128) * 100 + (1u128 << (shift - 1))) >> shift;
    let (whole, fraction) = (hundredths / 100, hundredths % 100);
    if fraction == 0 { format!("{whole} {unit}") } else { format!("{whole}.{fraction:02} {unit}") }
}

/// The bridge has no date crate, so the calendar is derived from the epoch directly (UTC).
fn format_timestamp(timestamp: u64) -> String {
    let seconds = i64::try_from(timestamp).unwrap_or(i64::MAX);
    let (days, time_of_day) = (seconds.div_euclid(86_400), seconds.rem_euclid(86_400));
    let (year, month, day) = civil_from_days(days);
    let (hour, minute, second) = (time_of_day / 3_600, (time_of_day % 3_600) / 60, time_of_day % 60);
    format!("{year:04}-{month:02}-{day:02} {hour:02}:{minute:02}:{second:02}")
}

/// Howard Hinnant's days-to-civil algorithm.
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let shifted = days + 719_468;
    let era = if shifted >= 0 { shifted } else { shifted - 146_096 } / 146_097;
    let day_of_era = shifted - era * 146_097;
    let year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_position = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_position + 2) / 5 + 1;
    let month = if month_position < 10 { month_position + 3 } else { month_position - 9 };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    (year, month as u32, day as u32)
}

#[cfg(test)]
mod tests {
    use std::path::{Path, PathBuf};

    use czkawka_core::common::model::FileEntry;

    use super::*;
    use crate::api::types::FieldValue;

    fn store(entries: &[(&str, FieldPayload)]) -> FieldStore {
        FieldStore::new(entries.iter().map(|(id, value)| FieldValue { id: (*id).to_string(), value: value.clone() }).collect())
    }

    #[test]
    fn sizes_keep_the_binary_units_of_the_reference_frontend() {
        assert_eq!(format_bytes(0), "0 B");
        assert_eq!(format_bytes(1023), "1023 B");
        assert_eq!(format_bytes(1024), "1 KiB");
        assert_eq!(format_bytes(2048), "2 KiB");
        assert_eq!(format_bytes(1536), "1.50 KiB");
        assert_eq!(format_bytes(12_345), "12.06 KiB");
        assert_eq!(format_bytes(1024 * 1024 * 1024), "1 GiB");
    }

    #[test]
    fn timestamps_render_as_utc_calendar_text() {
        assert_eq!(format_timestamp(0), "1970-01-01 00:00:00");
        assert_eq!(format_timestamp(1_000_000_000), "2001-09-09 01:46:40");
        assert_eq!(format_timestamp(1_700_000_000), "2023-11-14 22:13:20");
        assert_eq!(format_timestamp(1_704_067_200), "2024-01-01 00:00:00");
        // A leap day is the case a hand written calendar gets wrong.
        assert_eq!(format_timestamp(1_709_164_800), "2024-02-29 00:00:00");
    }

    #[test]
    fn oversized_values_still_produce_a_stable_sort_key() {
        assert_eq!(to_sort_key(u64::from(u32::MAX)), 4_294_967_295);
        assert_eq!(to_sort_key(u64::MAX), i64::MAX);
    }

    #[test]
    fn resolution_key_does_not_overflow() {
        assert_eq!(resolution_key(1920, 1080), 2_073_600);
        assert_eq!(resolution_key(u32::MAX, u32::MAX), i64::MAX);
    }

    #[test]
    fn lists_drop_separators_quotes_and_blanks() {
        assert_eq!(split_list(" jpg, png ;\n\"gif\"  , ,txt,"), vec!["jpg".to_string(), "png".to_string(), "gif".to_string(), "txt".to_string()]);
        assert!(split_list(" , ; \n ").is_empty());
    }

    #[test]
    fn video_optimizer_mode_accepts_machine_strings_only() {
        assert_eq!(parse_optimizer_mode("crop").unwrap(), VideoOptimizerMode::VideoCrop);
        assert_eq!(parse_optimizer_mode(" Transcode ").unwrap(), VideoOptimizerMode::VideoTranscode);
        assert_eq!(parse_optimizer_mode("option_video_optimizer_mode_crop").unwrap(), VideoOptimizerMode::VideoCrop);

        // An unset or unknown choice reports itself instead of picking a mode silently.
        assert!(parse_optimizer_mode("").unwrap_err().contains("not a valid operation"));
        assert!(parse_optimizer_mode("shrink").unwrap_err().contains("shrink"));
    }

    #[test]
    fn absent_options_keep_the_reference_defaults() {
        let empty = FieldStore::new(Vec::new());
        assert!(flag_or(&empty, "big_biggest_first", true));
        assert!(!flag_or(&empty, "emp_non_printable_content", false));
        assert_eq!(number_or(&empty, "big_number_of_files", 50), 50);

        let expected = vec!["hevc".to_string(), "h265".to_string(), "av1".to_string(), "vp9".to_string()];
        assert_eq!(string_list(&empty, "vid_opt_excluded_codecs", "hevc,h265,av1,vp9"), expected);
    }

    #[test]
    fn sent_options_override_the_defaults() {
        let store = store(&[
            ("big_biggest_first", FieldPayload::Flag(false)),
            ("big_number_of_files", FieldPayload::Integer(7)),
            ("temp_extension_list", FieldPayload::Text("tmp, bak".to_string())),
        ]);
        assert!(!flag_or(&store, "big_biggest_first", true));
        assert_eq!(number_or(&store, "big_number_of_files", 50), 7);
        assert_eq!(string_list(&store, "temp_extension_list", ""), vec!["tmp".to_string(), "bak".to_string()]);
        assert_eq!(string_list(&store, "temp_extension_list", "log"), vec!["tmp".to_string(), "bak".to_string()]);
    }

    #[test]
    fn numeric_options_accept_text_and_stay_inside_the_engine_range() {
        let store = store(&[("vid_opt_black_bar_min_percentage", FieldPayload::Text(" 140 ".to_string()))]);
        assert_eq!(bounded(&store, "vid_opt_black_bar_min_percentage", 80, 50, 100), 100);
        assert_eq!(bounded(&store, "vid_opt_max_samples", 60, 5, 1000), 60);
    }

    #[test]
    fn token_payloads_are_normalised_like_text_lists() {
        let store = store(&[("exif_ignored_tags", FieldPayload::Tokens(vec![" Make ".to_string(), "".to_string(), "\"Model\"".to_string()]))]);
        assert_eq!(string_list(&store, "exif_ignored_tags", ""), vec!["Make".to_string(), "Model".to_string()]);
    }

    #[test]
    fn broken_types_falls_back_when_every_switch_is_off() {
        // The fallback only fires for an empty mask, so a lone switch is the whole mask.
        let font_only = store(&[
            ("bro_image", FieldPayload::Flag(false)),
            ("bro_archive", FieldPayload::Flag(false)),
            ("bro_audio", FieldPayload::Flag(false)),
            ("bro_pdf", FieldPayload::Flag(false)),
            ("bro_font", FieldPayload::Flag(true)),
        ]);
        assert_eq!(checked_types(&font_only), CheckedTypes::FONT);

        let all_off = store(&[
            ("bro_image", FieldPayload::Flag(false)),
            ("bro_archive", FieldPayload::Flag(false)),
            ("bro_audio", FieldPayload::Flag(false)),
            ("bro_pdf", FieldPayload::Flag(false)),
            ("bro_video_ffprobe", FieldPayload::Flag(false)),
            ("bro_video_ffmpeg", FieldPayload::Flag(false)),
            ("bro_font", FieldPayload::Flag(false)),
            ("bro_markup", FieldPayload::Flag(false)),
        ]);
        assert_eq!(checked_types(&all_off), CheckedTypes::IMAGE | CheckedTypes::ARCHIVE);

        let unset = FieldStore::new(Vec::new());
        assert_eq!(checked_types(&unset), CheckedTypes::IMAGE | CheckedTypes::ARCHIVE | CheckedTypes::AUDIO | CheckedTypes::PDF);
    }

    #[test]
    fn symlink_errors_order_stably() {
        assert_eq!(error_sort_key(ErrorType::InfiniteRecursion), 0);
        assert_eq!(error_sort_key(ErrorType::NonExistentFile), 1);
    }

    #[test]
    fn rows_split_their_path_and_carry_no_group_membership() {
        let row = size_and_date(&FileEntry { path: PathBuf::from("/tmp/example.bin"), size: 2048, modified_date: 1_700_000_000 });
        assert_eq!(row.name, "example.bin");
        assert_eq!(row.directory, "/tmp");
        assert_eq!(row.cells, vec!["2 KiB".to_string(), "2023-11-14 22:13:20".to_string()]);
        assert_eq!(row.sort_keys, vec![2048, 1_700_000_000]);
        assert_eq!((row.group_index, row.group_size, row.is_group_start, row.is_reference), (-1, 0, false, false));
    }

    #[test]
    fn flat_rows_are_ordered_by_directory_then_name() {
        let row = |name: &str| EngineRow::new(Path::new("/x").join(name).to_path_buf(), Vec::new(), Vec::new(), 0, 0);
        let sorted = finish(&EmptyFolder::new(), vec![row("b.txt"), row("a.txt"), row("c.txt")]);
        assert_eq!(sorted.rows.iter().map(|entry| entry.name.clone()).collect::<Vec<_>>(), vec!["a.txt".to_string(), "b.txt".to_string(), "c.txt".to_string()]);
        assert!(!sorted.grouped);
    }
}
