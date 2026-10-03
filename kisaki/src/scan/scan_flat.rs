use czkawka_core::common::model::FileEntry;
use czkawka_core::common::tool_data::CommonData;
use czkawka_core::common::traits::Search;
use czkawka_core::tools::bad_extensions::{BadExtensions, BadExtensionsParameters, BadFileEntry};
use czkawka_core::tools::bad_names::{BadNameEntry, BadNames, BadNamesParameters, NameIssues};
use czkawka_core::tools::big_file::{BigFile, BigFileParameters, SearchMode};
use czkawka_core::tools::broken_files::{BrokenEntry, BrokenFiles, BrokenFilesParameters, CheckedTypes};
use czkawka_core::tools::empty_files::{EmptyFiles, EmptyFilesParameters};
use czkawka_core::tools::empty_folder::{EmptyFolder, FolderEntry};
use czkawka_core::tools::exif_remover::{ExifEntry, ExifRemover, ExifRemoverParameters};
use czkawka_core::tools::invalid_symlinks::{ErrorType, InvalidSymlinks, SymlinksFileEntry};
use czkawka_core::tools::temporary::{Temporary, TemporaryFileEntry, TemporaryParameters};
use czkawka_core::tools::video_optimizer::{VideoCropEntry, VideoCropParams, VideoOptimizer, VideoOptimizerParameters, VideoTranscodeEntry, VideoTranscodeParams};

use crate::ToolId;
use crate::common::{format_bytes, format_timestamp, split_list, to_sort_key};
use crate::fields::{FieldId, FieldRead, FieldStore};
use crate::scan::{Outcome, ScanCtx, build_flat, make_row, messages, outcome, set_common_settings};
use crate::state::RowData;

pub fn run(ctx: &ScanCtx) -> Result<Outcome, String> {
    let outcome = match ctx.tool.id {
        ToolId::EmptyFolders => run_empty_folders(ctx),
        ToolId::BigFiles => run_big_files(ctx),
        ToolId::EmptyFiles => run_empty_files(ctx),
        ToolId::TemporaryFiles => run_temporary(ctx),
        ToolId::InvalidSymlinks => run_invalid_symlinks(ctx),
        ToolId::BrokenFiles => run_broken_files(ctx),
        ToolId::BadExtensions => run_bad_extensions(ctx),
        ToolId::BadNames => run_bad_names(ctx),
        ToolId::ExifRemover => run_exif_remover(ctx),
        ToolId::VideoOptimizer => run_video_optimizer(ctx),
        other => return Err(format!("Tool {other:?} is not registered as a flat scanner")),
    };
    Ok(outcome)
}

fn store_tool<T>(ctx: &ScanCtx, tool: T, insert: impl FnOnce(&mut crate::state::SharedModels, T)) {
    let mut guard = ctx.state.lock().expect("App state mutex poisoned");
    insert(&mut guard.models, tool);
}

fn date_only(path: &std::path::Path, mtime: u64) -> RowData {
    make_row(path.to_path_buf(), vec![format_timestamp(mtime)], vec![to_sort_key(mtime)], 0, mtime)
}

fn size_and_date(entry: &FileEntry) -> RowData {
    make_row(
        entry.path.clone(),
        vec![format_bytes(entry.size), format_timestamp(entry.modified_date)],
        vec![to_sort_key(entry.size), to_sort_key(entry.modified_date)],
        entry.size,
        entry.modified_date,
    )
}

fn run_empty_folders(ctx: &ScanCtx) -> Outcome {
    let mut tool = EmptyFolder::new();
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let rows: Vec<RowData> = tool.get_empty_folder_list().values().map(empty_folder_row).collect();
    store_tool(ctx, tool, |models, tool| models.empty_folders = Some(tool));
    outcome(build_flat(rows), critical, text, stopped, false)
}

fn empty_folder_row(entry: &FolderEntry) -> RowData {
    date_only(&entry.path, entry.modified_date)
}

fn run_big_files(ctx: &ScanCtx) -> Outcome {
    let biggest_first = ctx.fields.flag(FieldId::BigBiggestFirst, true);
    let mode = if biggest_first { SearchMode::BiggestFiles } else { SearchMode::SmallestFiles };
    let count = ctx.fields.number(FieldId::BigNumberOfFiles, 50).clamp(1, 100_000) as usize;

    let mut tool = BigFile::new(BigFileParameters::new(count, mode));
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let rows: Vec<RowData> = tool.get_big_files().iter().map(size_and_date).collect();
    store_tool(ctx, tool, |models, tool| models.big_files = Some(tool));
    outcome(build_flat(rows), critical, text, stopped, false)
}

fn run_empty_files(ctx: &ScanCtx) -> Outcome {
    let params = EmptyFilesParameters {
        search_zero_byte_content_files: ctx.fields.flag(FieldId::EmpZeroByteContent, true),
        search_non_printable_content_files: ctx.fields.flag(FieldId::EmpNonPrintableContent, false),
    };
    let mut tool = EmptyFiles::new(params);
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let rows: Vec<RowData> = tool.get_empty_files().iter().map(size_and_date).collect();
    store_tool(ctx, tool, |models, tool| models.empty_files = Some(tool));
    outcome(build_flat(rows), critical, text, stopped, false)
}

fn temporary_row(entry: &TemporaryFileEntry) -> RowData {
    make_row(
        entry.path.clone(),
        vec![format_bytes(entry.size), format_timestamp(entry.modified_date)],
        vec![to_sort_key(entry.size), to_sort_key(entry.modified_date)],
        entry.size,
        entry.modified_date,
    )
}

fn run_temporary(ctx: &ScanCtx) -> Outcome {
    let extensions = split_list(&ctx.fields.text(FieldId::TempExtensionList));
    let params = if extensions.is_empty() {
        TemporaryParameters::default()
    } else {
        TemporaryParameters { extensions }
    };

    let mut tool = Temporary::new(params);
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let rows: Vec<RowData> = tool.get_temporary_files().iter().map(temporary_row).collect();
    store_tool(ctx, tool, |models, tool| models.temporary_files = Some(tool));
    outcome(build_flat(rows), critical, text, stopped, false)
}

fn symlink_row(entry: &SymlinksFileEntry) -> RowData {
    let error = entry.symlink_info.type_of_error;
    make_row(
        entry.path.clone(),
        vec![
            entry.symlink_info.destination_path.to_string_lossy().to_string(),
            describe_error(error).to_string(),
            format_timestamp(entry.modified_date),
        ],
        vec![0, error_sort_key(error), to_sort_key(entry.modified_date)],
        entry.size,
        entry.modified_date,
    )
}

fn describe_error(error: ErrorType) -> &'static str {
    match error {
        ErrorType::InfiniteRecursion => "Infinite recursion",
        ErrorType::NonExistentFile => "Non existent file",
    }
}

fn error_sort_key(error: ErrorType) -> i64 {
    match error {
        ErrorType::InfiniteRecursion => 0,
        ErrorType::NonExistentFile => 1,
    }
}

fn run_invalid_symlinks(ctx: &ScanCtx) -> Outcome {
    let mut tool = InvalidSymlinks::new();
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let rows: Vec<RowData> = tool.get_invalid_symlinks().iter().map(symlink_row).collect();
    store_tool(ctx, tool, |models, tool| models.invalid_symlinks = Some(tool));
    outcome(build_flat(rows), critical, text, stopped, false)
}

fn broken_types(fields: &FieldStore) -> CheckedTypes {
    let mut types = CheckedTypes::NONE;
    if fields.flag(FieldId::BroImage, true) {
        types |= CheckedTypes::IMAGE;
    }
    if fields.flag(FieldId::BroArchive, true) {
        types |= CheckedTypes::ARCHIVE;
    }
    if fields.flag(FieldId::BroAudio, true) {
        types |= CheckedTypes::AUDIO;
    }
    if fields.flag(FieldId::BroPdf, true) {
        types |= CheckedTypes::PDF;
    }
    if fields.flag(FieldId::BroVideoFfprobe, false) {
        types |= CheckedTypes::VIDEO_FFPROBE;
    }
    if fields.flag(FieldId::BroVideoFfmpeg, false) {
        types |= CheckedTypes::VIDEO_FFMPEG;
    }
    if fields.flag(FieldId::BroFont, false) {
        types |= CheckedTypes::FONT;
    }
    if fields.flag(FieldId::BroMarkup, false) {
        types |= CheckedTypes::MARKUP;
    }
    // The core rejects an empty mask, so fall back to images and archives.
    if types.is_empty() {
        types = CheckedTypes::IMAGE | CheckedTypes::ARCHIVE;
    }
    types
}

fn broken_row(entry: &BrokenEntry) -> RowData {
    make_row(
        entry.path.clone(),
        vec![format_bytes(entry.size), entry.get_error_string(), format_timestamp(entry.modified_date)],
        vec![to_sort_key(entry.size), 0, to_sort_key(entry.modified_date)],
        entry.size,
        entry.modified_date,
    )
}

fn run_broken_files(ctx: &ScanCtx) -> Outcome {
    let mut tool = BrokenFiles::new(BrokenFilesParameters::new(broken_types(&ctx.fields)));
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let rows: Vec<RowData> = tool.get_broken_files().iter().map(broken_row).collect();
    store_tool(ctx, tool, |models, tool| models.broken_files = Some(tool));
    outcome(build_flat(rows), critical, text, stopped, false)
}

fn bad_extension_row(entry: &BadFileEntry) -> RowData {
    make_row(
        entry.path.clone(),
        vec![
            entry.current_extension.clone(),
            entry.proper_extensions_group.clone(),
            entry.proper_extension.clone(),
            format_timestamp(entry.modified_date),
        ],
        vec![0, 0, 0, to_sort_key(entry.modified_date)],
        entry.size,
        entry.modified_date,
    )
}

fn run_bad_extensions(ctx: &ScanCtx) -> Outcome {
    let mut tool = BadExtensions::new(BadExtensionsParameters::new());
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let rows: Vec<RowData> = tool.get_bad_extensions_files().iter().map(bad_extension_row).collect();
    store_tool(ctx, tool, |models, tool| models.bad_extensions = Some(tool));
    outcome(build_flat(rows), critical, text, stopped, false)
}

fn bad_name_row(entry: &BadNameEntry) -> RowData {
    make_row(
        entry.path.clone(),
        vec![entry.new_name.clone(), format_bytes(entry.size), format_timestamp(entry.modified_date)],
        vec![0, to_sort_key(entry.size), to_sort_key(entry.modified_date)],
        entry.size,
        entry.modified_date,
    )
}

fn run_bad_names(ctx: &ScanCtx) -> Outcome {
    let mut tool = BadNames::new(BadNamesParameters::new(NameIssues::all()));
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let rows: Vec<RowData> = tool.get_bad_names_files().iter().map(bad_name_row).collect();
    store_tool(ctx, tool, |models, tool| models.bad_names = Some(tool));
    outcome(build_flat(rows), critical, text, stopped, false)
}

fn exif_row(entry: &ExifEntry) -> RowData {
    let tags = format!(
        "{} ({})",
        entry.exif_tags.len(),
        entry.exif_tags.iter().map(|tag| tag.name.as_str()).collect::<Vec<_>>().join(", ")
    );
    make_row(
        entry.path.clone(),
        vec![format_bytes(entry.size), tags],
        vec![to_sort_key(entry.size), entry.exif_tags.len() as i64],
        entry.size,
        entry.modified_date,
    )
}

fn run_exif_remover(ctx: &ScanCtx) -> Outcome {
    let mut tool = ExifRemover::new(ExifRemoverParameters::new(split_list(&ctx.fields.text(FieldId::ExifIgnoredTags))));
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let rows: Vec<RowData> = tool.get_exif_files().iter().map(exif_row).collect();
    store_tool(ctx, tool, |models, tool| models.exif_remover = Some(tool));
    outcome(build_flat(rows), critical, text, stopped, false)
}

fn transcode_row(entry: &VideoTranscodeEntry) -> RowData {
    make_row(
        entry.path.clone(),
        vec![
            format_bytes(entry.size),
            entry.codec.clone(),
            format!("{}x{}", entry.width, entry.height),
            entry.error.clone().unwrap_or_default(),
            format_timestamp(entry.modified_date),
        ],
        vec![
            to_sort_key(entry.size),
            0,
            i64::from(entry.width) * i64::from(entry.height),
            0,
            to_sort_key(entry.modified_date),
        ],
        entry.size,
        entry.modified_date,
    )
}

fn crop_row(entry: &VideoCropEntry) -> RowData {
    let (left, top, right, bottom) = entry.new_image_dimensions;
    make_row(
        entry.path.clone(),
        vec![
            format_bytes(entry.size),
            entry.codec.clone(),
            format!("{}x{}", entry.width, entry.height),
            format!("{left},{top},{right},{bottom}"),
            format_timestamp(entry.modified_date),
        ],
        vec![
            to_sort_key(entry.size),
            0,
            i64::from(entry.width) * i64::from(entry.height),
            0,
            to_sort_key(entry.modified_date),
        ],
        entry.size,
        entry.modified_date,
    )
}

fn run_video_optimizer(ctx: &ScanCtx) -> Outcome {
    let fields = &ctx.fields;
    let cropping = fields.choice(FieldId::VidOptMode, 1) == 0;

    let params = if cropping {
        VideoOptimizerParameters::VideoCrop(VideoCropParams::with_custom_params(
            czkawka_core::tools::video_optimizer::VideoCroppingMechanism::BlackBars,
            fields.number(FieldId::VidOptBlackPixelThreshold, 64).clamp(0, 128) as u8,
            fields.number(FieldId::VidOptBlackBarMinPercentage, 80).clamp(50, 100) as u8,
            fields.number(FieldId::VidOptMaxSamples, 60).clamp(5, 1000) as usize,
            fields.number(FieldId::VidOptMinCropSize, 20).clamp(1, 1000) as u32,
            false,
            10,
            false,
            2,
        ))
    } else {
        VideoOptimizerParameters::VideoTranscode(VideoTranscodeParams::new(split_list(&fields.text(FieldId::VidOptExcludedCodecs)), false, 10, false, 2))
    };

    let mut tool = VideoOptimizer::new(params);
    set_common_settings(&mut tool, &ctx.conditions, &ctx.stop_flag);
    tool.search(&ctx.stop_flag, Some(&ctx.progress_sender));

    let (critical, text) = messages(&tool);
    let stopped = tool.get_stopped_search();
    let rows: Vec<RowData> = if cropping {
        tool.get_video_crop_entries().iter().map(crop_row).collect()
    } else {
        tool.get_video_transcode_entries().iter().map(transcode_row).collect()
    };
    store_tool(ctx, tool, |models, tool| models.video_optimizer = Some(tool));
    outcome(build_flat(rows), critical, text, stopped, false)
}
