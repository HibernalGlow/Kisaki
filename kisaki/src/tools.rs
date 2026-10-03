use std::rc::Rc;

use czkawka_core::common::model::ToolType;
use slint::{ModelRc, VecModel};

use crate::fields::{FieldId, FieldStore};
use crate::{ColumnDef, FieldDef, ToolEntry, ToolId};

pub struct ColumnSpec {
    pub title_key: &'static str,
    // Slint stores both as `float`/`length`, which are f32 on the Rust side.
    pub stretch: f32,
    pub min_width: f32,
    pub align_right: bool,
}

pub struct ToolSpec {
    pub id: ToolId,
    pub tool_type: ToolType,
    pub glyph: &'static str,
    pub label_key: &'static str,
    pub grouped: bool,
    pub columns: &'static [ColumnSpec],
    pub fields: &'static [FieldId],
}

const COL_SIZE: ColumnSpec = ColumnSpec {
    title_key: "col_size",
    stretch: 0.5,
    min_width: 84.0,
    align_right: true,
};
const COL_MODIFIED: ColumnSpec = ColumnSpec {
    title_key: "col_modified",
    stretch: 1.0,
    min_width: 140.0,
    align_right: false,
};
const COL_DATES: &[ColumnSpec] = &[COL_MODIFIED];
const COL_SIZE_DATE: &[ColumnSpec] = &[COL_SIZE, COL_MODIFIED];

pub static DUPLICATE_COLUMNS: &[ColumnSpec] = COL_SIZE_DATE;
pub static EMPTY_FOLDER_COLUMNS: &[ColumnSpec] = COL_DATES;
pub static BIG_FILE_COLUMNS: &[ColumnSpec] = COL_SIZE_DATE;
pub static EMPTY_FILE_COLUMNS: &[ColumnSpec] = COL_SIZE_DATE;
pub static TEMPORARY_COLUMNS: &[ColumnSpec] = COL_SIZE_DATE;
pub static SIMILAR_IMAGE_COLUMNS: &[ColumnSpec] = &[
    ColumnSpec {
        title_key: "col_difference",
        stretch: 0.7,
        min_width: 90.0,
        align_right: false,
    },
    COL_SIZE,
    ColumnSpec {
        title_key: "col_resolution",
        stretch: 0.7,
        min_width: 90.0,
        align_right: false,
    },
    COL_MODIFIED,
];
pub static SIMILAR_VIDEO_COLUMNS: &[ColumnSpec] = &[
    COL_SIZE,
    ColumnSpec {
        title_key: "col_duration",
        stretch: 0.6,
        min_width: 70.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_resolution",
        stretch: 0.7,
        min_width: 90.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_codec",
        stretch: 0.7,
        min_width: 70.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_bitrate",
        stretch: 0.7,
        min_width: 80.0,
        align_right: true,
    },
    COL_MODIFIED,
];
pub static SAME_MUSIC_COLUMNS: &[ColumnSpec] = &[
    COL_SIZE,
    ColumnSpec {
        title_key: "col_title",
        stretch: 1.2,
        min_width: 120.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_artist",
        stretch: 1.0,
        min_width: 100.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_year",
        stretch: 0.4,
        min_width: 50.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_bitrate",
        stretch: 0.5,
        min_width: 70.0,
        align_right: true,
    },
    ColumnSpec {
        title_key: "col_length",
        stretch: 0.5,
        min_width: 60.0,
        align_right: true,
    },
    ColumnSpec {
        title_key: "col_genre",
        stretch: 0.8,
        min_width: 70.0,
        align_right: false,
    },
    COL_MODIFIED,
];
pub static INVALID_SYMLINK_COLUMNS: &[ColumnSpec] = &[
    ColumnSpec {
        title_key: "col_destination",
        stretch: 1.4,
        min_width: 140.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_error",
        stretch: 1.0,
        min_width: 110.0,
        align_right: false,
    },
    COL_MODIFIED,
];
pub static BROKEN_FILE_COLUMNS: &[ColumnSpec] = &[
    COL_SIZE,
    ColumnSpec {
        title_key: "col_errors",
        stretch: 1.6,
        min_width: 160.0,
        align_right: false,
    },
    COL_MODIFIED,
];
pub static BAD_EXTENSION_COLUMNS: &[ColumnSpec] = &[
    ColumnSpec {
        title_key: "col_current_extension",
        stretch: 0.7,
        min_width: 70.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_proper_group",
        stretch: 0.8,
        min_width: 80.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_proper_extension",
        stretch: 0.8,
        min_width: 80.0,
        align_right: false,
    },
    COL_MODIFIED,
];
pub static BAD_NAME_COLUMNS: &[ColumnSpec] = &[
    ColumnSpec {
        title_key: "col_new_name",
        stretch: 1.4,
        min_width: 150.0,
        align_right: false,
    },
    COL_SIZE,
    COL_MODIFIED,
];
pub static EXIF_REMOVER_COLUMNS: &[ColumnSpec] = &[
    COL_SIZE,
    ColumnSpec {
        title_key: "col_tags",
        stretch: 1.8,
        min_width: 180.0,
        align_right: false,
    },
];
pub static VIDEO_OPTIMIZER_COLUMNS: &[ColumnSpec] = &[
    COL_SIZE,
    ColumnSpec {
        title_key: "col_codec",
        stretch: 0.7,
        min_width: 70.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_resolution",
        stretch: 0.8,
        min_width: 90.0,
        align_right: false,
    },
    ColumnSpec {
        title_key: "col_info",
        stretch: 1.2,
        min_width: 120.0,
        align_right: false,
    },
    COL_MODIFIED,
];

static DUPLICATE_FIELDS: &[FieldId] = &[
    FieldId::DupCheckMethod,
    FieldId::DupHashType,
    FieldId::DupCaseSensitiveNames,
    FieldId::DupIgnoreHardLinks,
    FieldId::DupUsePrehash,
    FieldId::DupHashCacheSize,
    FieldId::DupPrehashCacheSize,
];
static SIMILAR_IMAGE_FIELDS: &[FieldId] = &[
    FieldId::ImgSimilarity,
    FieldId::ImgHashSize,
    FieldId::ImgHashAlgorithm,
    FieldId::ImgResizeAlgorithm,
    FieldId::ImgIgnoreSameSize,
    FieldId::ImgIgnoreSameResolution,
    FieldId::ImgGeometricInvariance,
];
static SIMILAR_VIDEO_FIELDS: &[FieldId] = &[
    FieldId::VidTolerance,
    FieldId::VidIgnoreSameSize,
    FieldId::VidSkipForward,
    FieldId::VidHashDuration,
    FieldId::VidLetterboxCrop,
];
static SAME_MUSIC_FIELDS: &[FieldId] = &[
    FieldId::MusCheckType,
    FieldId::MusApproximate,
    FieldId::MusTitle,
    FieldId::MusArtist,
    FieldId::MusBitrate,
    FieldId::MusGenre,
    FieldId::MusYear,
    FieldId::MusLength,
    FieldId::MusMaxDifference,
    FieldId::MusMinFragmentDuration,
];
static BIG_FILE_FIELDS: &[FieldId] = &[FieldId::BigNumberOfFiles, FieldId::BigBiggestFirst];
static EMPTY_FILE_FIELDS: &[FieldId] = &[FieldId::EmpZeroByteContent, FieldId::EmpNonPrintableContent];
static TEMPORARY_FIELDS: &[FieldId] = &[FieldId::TempExtensionList];
static BROKEN_FILE_FIELDS: &[FieldId] = &[
    FieldId::BroImage,
    FieldId::BroArchive,
    FieldId::BroAudio,
    FieldId::BroPdf,
    FieldId::BroVideoFfprobe,
    FieldId::BroVideoFfmpeg,
    FieldId::BroFont,
    FieldId::BroMarkup,
];
static EXIF_REMOVER_FIELDS: &[FieldId] = &[FieldId::ExifIgnoredTags];
static VIDEO_OPTIMIZER_FIELDS: &[FieldId] = &[
    FieldId::VidOptMode,
    FieldId::VidOptExcludedCodecs,
    FieldId::VidOptBlackPixelThreshold,
    FieldId::VidOptBlackBarMinPercentage,
    FieldId::VidOptMaxSamples,
    FieldId::VidOptMinCropSize,
];
static NO_FIELDS: &[FieldId] = &[];

/// Order matches the `ToolId` enum and the requirements of the results table.
pub static TOOLS: &[ToolSpec] = &[
    ToolSpec {
        id: ToolId::DuplicateFiles,
        tool_type: ToolType::Duplicate,
        glyph: "D=",
        label_key: "tool_duplicate_files",
        grouped: true,
        columns: DUPLICATE_COLUMNS,
        fields: DUPLICATE_FIELDS,
    },
    ToolSpec {
        id: ToolId::EmptyFolders,
        tool_type: ToolType::EmptyFolders,
        glyph: "0F",
        label_key: "tool_empty_folders",
        grouped: false,
        columns: EMPTY_FOLDER_COLUMNS,
        fields: NO_FIELDS,
    },
    ToolSpec {
        id: ToolId::BigFiles,
        tool_type: ToolType::BigFile,
        glyph: ">>",
        label_key: "tool_big_files",
        grouped: false,
        columns: BIG_FILE_COLUMNS,
        fields: BIG_FILE_FIELDS,
    },
    ToolSpec {
        id: ToolId::EmptyFiles,
        tool_type: ToolType::EmptyFiles,
        glyph: "0B",
        label_key: "tool_empty_files",
        grouped: false,
        columns: EMPTY_FILE_COLUMNS,
        fields: EMPTY_FILE_FIELDS,
    },
    ToolSpec {
        id: ToolId::TemporaryFiles,
        tool_type: ToolType::TemporaryFiles,
        glyph: "TMP",
        label_key: "tool_temporary_files",
        grouped: false,
        columns: TEMPORARY_COLUMNS,
        fields: TEMPORARY_FIELDS,
    },
    ToolSpec {
        id: ToolId::SimilarImages,
        tool_type: ToolType::SimilarImages,
        glyph: "IMG",
        label_key: "tool_similar_images",
        grouped: true,
        columns: SIMILAR_IMAGE_COLUMNS,
        fields: SIMILAR_IMAGE_FIELDS,
    },
    ToolSpec {
        id: ToolId::SimilarVideos,
        tool_type: ToolType::SimilarVideos,
        glyph: "VID",
        label_key: "tool_similar_videos",
        grouped: true,
        columns: SIMILAR_VIDEO_COLUMNS,
        fields: SIMILAR_VIDEO_FIELDS,
    },
    ToolSpec {
        id: ToolId::DuplicateMusic,
        tool_type: ToolType::SameMusic,
        glyph: "AUD",
        label_key: "tool_duplicate_music",
        grouped: true,
        columns: SAME_MUSIC_COLUMNS,
        fields: SAME_MUSIC_FIELDS,
    },
    ToolSpec {
        id: ToolId::InvalidSymlinks,
        tool_type: ToolType::InvalidSymlinks,
        glyph: "->",
        label_key: "tool_invalid_symlinks",
        grouped: false,
        columns: INVALID_SYMLINK_COLUMNS,
        fields: NO_FIELDS,
    },
    ToolSpec {
        id: ToolId::BrokenFiles,
        tool_type: ToolType::BrokenFiles,
        glyph: "!!",
        label_key: "tool_broken_files",
        grouped: false,
        columns: BROKEN_FILE_COLUMNS,
        fields: BROKEN_FILE_FIELDS,
    },
    ToolSpec {
        id: ToolId::BadExtensions,
        tool_type: ToolType::BadExtensions,
        glyph: "EXT",
        label_key: "tool_bad_extensions",
        grouped: false,
        columns: BAD_EXTENSION_COLUMNS,
        fields: NO_FIELDS,
    },
    ToolSpec {
        id: ToolId::BadNames,
        tool_type: ToolType::BadNames,
        glyph: "NAM",
        label_key: "tool_bad_names",
        grouped: false,
        columns: BAD_NAME_COLUMNS,
        fields: NO_FIELDS,
    },
    ToolSpec {
        id: ToolId::ExifRemover,
        tool_type: ToolType::ExifRemover,
        glyph: "EXIF",
        label_key: "tool_exif_remover",
        grouped: false,
        columns: EXIF_REMOVER_COLUMNS,
        fields: EXIF_REMOVER_FIELDS,
    },
    ToolSpec {
        id: ToolId::VideoOptimizer,
        tool_type: ToolType::VideoOptimizer,
        glyph: "OPT",
        label_key: "tool_video_optimizer",
        grouped: false,
        columns: VIDEO_OPTIMIZER_COLUMNS,
        fields: VIDEO_OPTIMIZER_FIELDS,
    },
];

pub fn spec(id: ToolId) -> Option<&'static ToolSpec> {
    TOOLS.iter().find(|tool| tool.id == id)
}

pub fn spec_by_index(index: i32) -> Option<&'static ToolSpec> {
    let index = usize::try_from(index).ok()?;
    TOOLS.get(index)
}

pub fn tool_entries() -> ModelRc<ToolEntry> {
    let entries: Vec<ToolEntry> = TOOLS
        .iter()
        .map(|tool| ToolEntry {
            id: tool.id,
            label: crate::localizer_kisaki::translate_key(tool.label_key).into(),
            glyph: tool.glyph.into(),
        })
        .collect();
    Rc::new(VecModel::from(entries)).into()
}

pub fn columns(id: ToolId) -> ModelRc<ColumnDef> {
    let columns: Vec<ColumnDef> = spec(id)
        .map(|tool| tool.columns)
        .unwrap_or_default()
        .iter()
        .map(|column| ColumnDef {
            title: crate::localizer_kisaki::translate_key(column.title_key).into(),
            stretch: column.stretch,
            min_width: column.min_width,
            align_right: column.align_right,
        })
        .collect();
    Rc::new(VecModel::from(columns)).into()
}

pub fn field_defs(id: ToolId, store: &FieldStore) -> ModelRc<FieldDef> {
    let fields: Vec<FieldDef> = spec(id)
        .map(|tool| tool.fields)
        .unwrap_or_default()
        .iter()
        .filter_map(|field| store.get(&i32::from(*field)).map(|value| field.to_def(value)))
        .collect();
    Rc::new(VecModel::from(fields)).into()
}
