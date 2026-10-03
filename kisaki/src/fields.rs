use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::{FieldDef, FieldKind, fli};

// Stable numeric ids shared with the Slint `FieldDef` model and persisted settings.
#[repr(i32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum FieldId {
    DupCheckMethod = 100,
    DupHashType = 101,
    DupCaseSensitiveNames = 103,
    DupIgnoreHardLinks = 104,
    DupUsePrehash = 105,
    DupHashCacheSize = 106,
    DupPrehashCacheSize = 107,

    ImgSimilarity = 200,
    ImgHashSize = 201,
    ImgHashAlgorithm = 202,
    ImgResizeAlgorithm = 203,
    ImgIgnoreSameSize = 204,
    ImgIgnoreSameResolution = 205,
    ImgGeometricInvariance = 206,

    VidTolerance = 300,
    VidIgnoreSameSize = 301,
    VidSkipForward = 302,
    VidHashDuration = 303,
    VidLetterboxCrop = 304,

    MusCheckType = 400,
    MusApproximate = 401,
    MusTitle = 402,
    MusArtist = 403,
    MusBitrate = 404,
    MusGenre = 405,
    MusYear = 406,
    MusLength = 407,
    MusMaxDifference = 408,
    MusMinFragmentDuration = 409,

    BigNumberOfFiles = 500,
    BigBiggestFirst = 501,

    EmpZeroByteContent = 600,
    EmpNonPrintableContent = 601,

    TempExtensionList = 700,

    BroAudio = 800,
    BroPdf = 801,
    BroArchive = 802,
    BroImage = 803,
    BroVideoFfprobe = 804,
    BroVideoFfmpeg = 805,
    BroFont = 806,
    BroMarkup = 807,

    ExifIgnoredTags = 900,

    VidOptMode = 1000,
    VidOptExcludedCodecs = 1001,
    VidOptBlackPixelThreshold = 1002,
    VidOptBlackBarMinPercentage = 1003,
    VidOptMaxSamples = 1004,
    VidOptMinCropSize = 1005,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum FieldValue {
    Bool(bool),
    Text(String),
    Choice(i32),
}

impl FieldValue {
    pub fn as_bool(&self) -> bool {
        matches!(self, Self::Bool(true))
    }

    pub fn as_choice(&self) -> i32 {
        match self {
            Self::Choice(index) => *index,
            _ => 0,
        }
    }

    pub fn as_text(&self) -> String {
        match self {
            Self::Text(value) => value.clone(),
            Self::Bool(value) => (if *value { "1" } else { "0" }).to_string(),
            Self::Choice(index) => index.to_string(),
        }
    }

    fn choice_index(&self) -> Option<i32> {
        match self {
            Self::Choice(index) => Some(*index),
            _ => None,
        }
    }

    fn value_text(&self) -> String {
        match self {
            Self::Text(value) => value.clone(),
            Self::Bool(_) | Self::Choice(_) => String::new(),
        }
    }

    fn value_bool(&self) -> bool {
        self.as_bool()
    }
}

pub type FieldStore = HashMap<i32, FieldValue>;

// An extension trait rather than an inherent impl: `FieldStore` aliases a `std` map, and
// inherent impls on foreign types are rejected (E0116).
pub trait FieldRead {
    fn choice(&self, id: FieldId, fallback: i32) -> i32;
    fn flag(&self, id: FieldId, fallback: bool) -> bool;
    fn number(&self, id: FieldId, fallback: i64) -> i64;
    fn float(&self, id: FieldId, fallback: f64) -> f64;
    fn text(&self, id: FieldId) -> String;
}

impl FieldRead for FieldStore {
    fn choice(&self, id: FieldId, fallback: i32) -> i32 {
        self.get(&i32::from(id)).map_or(fallback, FieldValue::as_choice)
    }

    fn flag(&self, id: FieldId, fallback: bool) -> bool {
        self.get(&i32::from(id)).map_or(fallback, FieldValue::as_bool)
    }

    fn number(&self, id: FieldId, fallback: i64) -> i64 {
        self.get(&i32::from(id)).map_or(fallback, |value| parse_number(value, fallback))
    }

    fn float(&self, id: FieldId, fallback: f64) -> f64 {
        self.get(&i32::from(id)).map_or(fallback, |value| parse_float(value, fallback))
    }

    fn text(&self, id: FieldId) -> String {
        self.get(&i32::from(id)).map_or_else(String::new, FieldValue::as_text)
    }
}

pub fn default_fields() -> FieldStore {
    FieldId::ALL.iter().map(|field| (i32::from(*field), field.default_value())).collect()
}

impl From<FieldId> for i32 {
    fn from(field: FieldId) -> Self {
        field as Self
    }
}

impl FieldId {
    pub const ALL: &[Self] = &[
        Self::DupCheckMethod,
        Self::DupHashType,
        Self::DupCaseSensitiveNames,
        Self::DupIgnoreHardLinks,
        Self::DupUsePrehash,
        Self::DupHashCacheSize,
        Self::DupPrehashCacheSize,
        Self::ImgSimilarity,
        Self::ImgHashSize,
        Self::ImgHashAlgorithm,
        Self::ImgResizeAlgorithm,
        Self::ImgIgnoreSameSize,
        Self::ImgIgnoreSameResolution,
        Self::ImgGeometricInvariance,
        Self::VidTolerance,
        Self::VidIgnoreSameSize,
        Self::VidSkipForward,
        Self::VidHashDuration,
        Self::VidLetterboxCrop,
        Self::MusCheckType,
        Self::MusApproximate,
        Self::MusTitle,
        Self::MusArtist,
        Self::MusBitrate,
        Self::MusGenre,
        Self::MusYear,
        Self::MusLength,
        Self::MusMaxDifference,
        Self::MusMinFragmentDuration,
        Self::BigNumberOfFiles,
        Self::BigBiggestFirst,
        Self::EmpZeroByteContent,
        Self::EmpNonPrintableContent,
        Self::TempExtensionList,
        Self::BroAudio,
        Self::BroPdf,
        Self::BroArchive,
        Self::BroImage,
        Self::BroVideoFfprobe,
        Self::BroVideoFfmpeg,
        Self::BroFont,
        Self::BroMarkup,
        Self::ExifIgnoredTags,
        Self::VidOptMode,
        Self::VidOptExcludedCodecs,
        Self::VidOptBlackPixelThreshold,
        Self::VidOptBlackBarMinPercentage,
        Self::VidOptMaxSamples,
        Self::VidOptMinCropSize,
    ];

    pub const fn kind(self) -> FieldKind {
        match self {
            Self::DupCheckMethod
            | Self::DupHashType
            | Self::ImgSimilarity
            | Self::ImgHashSize
            | Self::ImgHashAlgorithm
            | Self::ImgResizeAlgorithm
            | Self::ImgGeometricInvariance
            | Self::MusCheckType
            | Self::VidOptMode => FieldKind::Select,

            Self::DupCaseSensitiveNames
            | Self::DupIgnoreHardLinks
            | Self::DupUsePrehash
            | Self::ImgIgnoreSameSize
            | Self::ImgIgnoreSameResolution
            | Self::VidIgnoreSameSize
            | Self::VidLetterboxCrop
            | Self::MusApproximate
            | Self::MusTitle
            | Self::MusArtist
            | Self::MusBitrate
            | Self::MusGenre
            | Self::MusYear
            | Self::MusLength
            | Self::BigBiggestFirst
            | Self::EmpZeroByteContent
            | Self::EmpNonPrintableContent
            | Self::BroAudio
            | Self::BroPdf
            | Self::BroArchive
            | Self::BroImage
            | Self::BroVideoFfprobe
            | Self::BroVideoFfmpeg
            | Self::BroFont
            | Self::BroMarkup => FieldKind::Bool,

            Self::TempExtensionList | Self::ExifIgnoredTags | Self::VidOptExcludedCodecs => FieldKind::Text,

            Self::DupHashCacheSize
            | Self::DupPrehashCacheSize
            | Self::VidTolerance
            | Self::VidSkipForward
            | Self::VidHashDuration
            | Self::MusMaxDifference
            | Self::MusMinFragmentDuration
            | Self::BigNumberOfFiles
            | Self::VidOptBlackPixelThreshold
            | Self::VidOptBlackBarMinPercentage
            | Self::VidOptMaxSamples
            | Self::VidOptMinCropSize => FieldKind::Number,
        }
    }

    pub const fn label_key(self) -> &'static str {
        match self {
            Self::DupCheckMethod => "field_dup_check_method",
            Self::DupHashType => "field_dup_hash_type",
            Self::DupCaseSensitiveNames => "field_dup_case_sensitive_names",
            Self::DupIgnoreHardLinks => "field_dup_ignore_hard_links",
            Self::DupUsePrehash => "field_dup_use_prehash",
            Self::DupHashCacheSize => "field_dup_hash_cache_size",
            Self::DupPrehashCacheSize => "field_dup_prehash_cache_size",

            Self::ImgSimilarity => "field_img_similarity",
            Self::ImgHashSize => "field_img_hash_size",
            Self::ImgHashAlgorithm => "field_img_hash_algorithm",
            Self::ImgResizeAlgorithm => "field_img_resize_algorithm",
            Self::ImgIgnoreSameSize => "field_img_ignore_same_size",
            Self::ImgIgnoreSameResolution => "field_img_ignore_same_resolution",
            Self::ImgGeometricInvariance => "field_img_geometric_invariance",

            Self::VidTolerance => "field_vid_tolerance",
            Self::VidIgnoreSameSize => "field_vid_ignore_same_size",
            Self::VidSkipForward => "field_vid_skip_forward",
            Self::VidHashDuration => "field_vid_hash_duration",
            Self::VidLetterboxCrop => "field_vid_letterbox_crop",

            Self::MusCheckType => "field_mus_check_type",
            Self::MusApproximate => "field_mus_approximate",
            Self::MusTitle => "field_mus_title",
            Self::MusArtist => "field_mus_artist",
            Self::MusBitrate => "field_mus_bitrate",
            Self::MusGenre => "field_mus_genre",
            Self::MusYear => "field_mus_year",
            Self::MusLength => "field_mus_length",
            Self::MusMaxDifference => "field_mus_max_difference",
            Self::MusMinFragmentDuration => "field_mus_min_fragment_duration",

            Self::BigNumberOfFiles => "field_big_number_of_files",
            Self::BigBiggestFirst => "field_big_biggest_first",

            Self::EmpZeroByteContent => "field_emp_zero_byte_content",
            Self::EmpNonPrintableContent => "field_emp_non_printable_content",

            Self::TempExtensionList => "field_temp_extension_list",

            Self::BroAudio => "field_bro_audio",
            Self::BroPdf => "field_bro_pdf",
            Self::BroArchive => "field_bro_archive",
            Self::BroImage => "field_bro_image",
            Self::BroVideoFfprobe => "field_bro_video_ffprobe",
            Self::BroVideoFfmpeg => "field_bro_video_ffmpeg",
            Self::BroFont => "field_bro_font",
            Self::BroMarkup => "field_bro_markup",

            Self::ExifIgnoredTags => "field_exif_ignored_tags",

            Self::VidOptMode => "field_vidopt_mode",
            Self::VidOptExcludedCodecs => "field_vidopt_excluded_codecs",
            Self::VidOptBlackPixelThreshold => "field_vidopt_black_pixel_threshold",
            Self::VidOptBlackBarMinPercentage => "field_vidopt_black_bar_min_percentage",
            Self::VidOptMaxSamples => "field_vidopt_max_samples",
            Self::VidOptMinCropSize => "field_vidopt_min_crop_size",
        }
    }

    pub const fn suffix(self) -> &'static str {
        match self {
            Self::DupHashCacheSize | Self::DupPrehashCacheSize => "KiB",
            Self::VidTolerance => "0-20",
            Self::VidSkipForward | Self::VidHashDuration | Self::MusMinFragmentDuration => "s",
            Self::MusMaxDifference => "0-10",
            Self::BigNumberOfFiles => "#",
            Self::VidOptBlackPixelThreshold => "0-128",
            Self::VidOptBlackBarMinPercentage => "50-100",
            Self::VidOptMaxSamples => "5-1000",
            Self::VidOptMinCropSize => "1-1000",
            Self::TempExtensionList | Self::ExifIgnoredTags | Self::VidOptExcludedCodecs => ",",
            _ => "",
        }
    }

    // Not `const`: the Text defaults allocate a `String`.
    // Arms are grouped by shared default, so a field lookup follows the order in `FieldId::ALL`.
    pub fn default_value(self) -> FieldValue {
        match self {
            Self::DupCheckMethod | Self::ImgResizeAlgorithm | Self::ImgGeometricInvariance | Self::MusCheckType => FieldValue::Choice(0),
            Self::DupHashType | Self::ImgSimilarity => FieldValue::Choice(2),
            Self::ImgHashSize | Self::ImgHashAlgorithm | Self::VidOptMode => FieldValue::Choice(1),

            Self::DupCaseSensitiveNames
            | Self::DupUsePrehash
            | Self::VidLetterboxCrop
            | Self::MusApproximate
            | Self::MusTitle
            | Self::MusArtist
            | Self::BigBiggestFirst
            | Self::EmpZeroByteContent
            | Self::BroAudio
            | Self::BroPdf
            | Self::BroArchive
            | Self::BroImage => FieldValue::Bool(true),

            Self::DupIgnoreHardLinks
            | Self::ImgIgnoreSameSize
            | Self::ImgIgnoreSameResolution
            | Self::VidIgnoreSameSize
            | Self::MusBitrate
            | Self::MusGenre
            | Self::MusYear
            | Self::MusLength
            | Self::EmpNonPrintableContent
            | Self::BroVideoFfprobe
            | Self::BroVideoFfmpeg
            | Self::BroFont
            | Self::BroMarkup => FieldValue::Bool(false),

            Self::DupHashCacheSize | Self::DupPrehashCacheSize => FieldValue::Text("1000".to_string()),
            Self::VidTolerance | Self::MusMaxDifference => FieldValue::Text("2".to_string()),
            Self::VidHashDuration | Self::MusMinFragmentDuration => FieldValue::Text("10".to_string()),
            Self::TempExtensionList | Self::ExifIgnoredTags => FieldValue::Text(String::new()),

            Self::VidSkipForward => FieldValue::Text("15".to_string()),
            Self::BigNumberOfFiles => FieldValue::Text("50".to_string()),
            Self::VidOptExcludedCodecs => FieldValue::Text("hevc,h265,av1,vp9".to_string()),
            Self::VidOptBlackPixelThreshold => FieldValue::Text("64".to_string()),
            Self::VidOptBlackBarMinPercentage => FieldValue::Text("80".to_string()),
            Self::VidOptMaxSamples => FieldValue::Text("60".to_string()),
            Self::VidOptMinCropSize => FieldValue::Text("20".to_string()),
        }
    }

    pub fn choices(self) -> Vec<String> {
        match self {
            Self::DupCheckMethod => vec![
                fli!("option_check_method_hash"),
                fli!("option_check_method_size"),
                fli!("option_check_method_name"),
                fli!("option_check_method_size_and_name"),
            ],
            Self::DupHashType => vec!["Blake3".to_string(), "CRC32".to_string(), "XXH3".to_string()],
            Self::ImgSimilarity => vec![
                fli!("option_similarity_original"),
                fli!("option_similarity_very_high"),
                fli!("option_similarity_high"),
                fli!("option_similarity_medium"),
                fli!("option_similarity_small"),
                fli!("option_similarity_very_small"),
                fli!("option_similarity_minimal"),
            ],
            Self::ImgHashSize => vec!["8".to_string(), "16".to_string(), "32".to_string(), "64".to_string()],
            Self::ImgHashAlgorithm => vec![
                "Mean".to_string(),
                "Gradient".to_string(),
                "BlockHash".to_string(),
                "VertGradient".to_string(),
                "DoubleGradient".to_string(),
                "Median".to_string(),
            ],
            Self::ImgResizeAlgorithm => vec![
                "Lanczos3".to_string(),
                "Gaussian".to_string(),
                "CatmullRom".to_string(),
                "Triangle".to_string(),
                "Nearest".to_string(),
            ],
            Self::ImgGeometricInvariance => vec![
                fli!("option_geometric_invariance_off"),
                fli!("option_geometric_invariance_mirror_flip"),
                fli!("option_geometric_invariance_mirror_flip_rotate90"),
            ],
            Self::MusCheckType => vec![fli!("option_music_method_tags"), fli!("option_music_method_fingerprint")],
            Self::VidOptMode => vec![fli!("option_video_optimizer_mode_crop"), fli!("option_video_optimizer_mode_transcode")],
            _ => Vec::new(),
        }
    }

    pub fn find(id: i32) -> Option<Self> {
        Self::ALL.iter().copied().find(|field| i32::from(*field) == id)
    }

    pub(crate) fn to_def(self, value: &FieldValue) -> FieldDef {
        let choices: Vec<slint::SharedString> = self.choices().into_iter().map(slint::SharedString::from).collect();
        FieldDef {
            id: i32::from(self),
            kind: self.kind(),
            label: crate::localizer_kisaki::translate_key(self.label_key()).into(),
            value_bool: value.value_bool(),
            value_text: value.value_text().into(),
            choices: slint::ModelRc::from(choices.as_slice()),
            choice_index: value.choice_index().unwrap_or(0),
            suffix: self.suffix().into(),
        }
    }
}

pub fn parse_number(value: &FieldValue, fallback: i64) -> i64 {
    match value {
        FieldValue::Text(text) => text.trim().parse::<i64>().unwrap_or(fallback),
        FieldValue::Choice(index) => *index as i64,
        FieldValue::Bool(flag) => i64::from(*flag),
    }
}

pub fn parse_float(value: &FieldValue, fallback: f64) -> f64 {
    match value {
        FieldValue::Text(text) => text.trim().parse::<f64>().unwrap_or(fallback),
        FieldValue::Choice(index) => *index as f64,
        FieldValue::Bool(flag) => f64::from(*flag),
    }
}
