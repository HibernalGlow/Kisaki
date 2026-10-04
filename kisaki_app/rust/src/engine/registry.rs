use czkawka_core::common::model::ToolType;

use crate::api::types::{FieldDef, FieldValue};
use crate::engine::options;

/// Const-friendly column shape; `.into()` is not callable in a `const`, so the FFI-facing
/// `ColumnDef` is built when the registry is read.
/// What the engine knows about one results column: an identity and a translation key. How wide or
/// aligned it is belongs to the toolkit, so `api::presentation` supplies that.
struct ColumnSpec {
    key: &'static str,
    label_key: &'static str,
}

const fn column(key: &'static str, label_key: &'static str) -> ColumnSpec {
    ColumnSpec { key, label_key }
}

/// One results column as the engine sees it: identity and translation key only.
#[derive(Debug, Clone, PartialEq)]
pub struct ColumnKey {
    pub key: String,
    pub label_key: String,
}

/// What a scanner is, free of any toolkit decision, so scanning and exporting can be driven by a
/// different front end without reshaping the registry.
#[derive(Debug, Clone, PartialEq)]
pub struct ToolView {
    pub id: String,
    pub glyph: String,
    pub label_key: String,
    pub grouped: bool,
    pub supports_reference: bool,
    pub columns: Vec<ColumnKey>,
    pub field_ids: Vec<String>,
}

struct Entry {
    id: &'static str,
    tool_type: ToolType,
    glyph: &'static str,
    label_key: &'static str,
    grouped: bool,
    columns: &'static [ColumnSpec],
    field_ids: &'static [&'static str],
}

const COL_SIZE: ColumnSpec = column("size", "col_size");
const COL_MODIFIED: ColumnSpec = column("modified", "col_modified");
const COL_DATES: &[ColumnSpec] = &[COL_MODIFIED];
const COL_SIZE_DATE: &[ColumnSpec] = &[COL_SIZE, COL_MODIFIED];

const COL_DIFFERENCE: ColumnSpec = column("difference", "col_difference");
const COL_RESOLUTION: ColumnSpec = column("resolution", "col_resolution");
const COL_DURATION: ColumnSpec = column("duration", "col_duration");
const COL_CODEC: ColumnSpec = column("codec", "col_codec");
const COL_BITRATE: ColumnSpec = column("bitrate", "col_bitrate");
const COL_TITLE: ColumnSpec = column("title", "col_title");
const COL_ARTIST: ColumnSpec = column("artist", "col_artist");
const COL_YEAR: ColumnSpec = column("year", "col_year");
const COL_LENGTH: ColumnSpec = column("length", "col_length");
const COL_GENRE: ColumnSpec = column("genre", "col_genre");
const COL_DESTINATION: ColumnSpec = column("destination", "col_destination");
const COL_ERRORS: ColumnSpec = column("errors", "col_errors");
const COL_CURRENT_EXT: ColumnSpec = column("current_extension", "col_current_extension");
const COL_PROPER_GROUP: ColumnSpec = column("proper_group", "col_proper_group");
const COL_PROPER_EXT: ColumnSpec = column("proper_extension", "col_proper_extension");
const COL_NEW_NAME: ColumnSpec = column("new_name", "col_new_name");
const COL_TAGS: ColumnSpec = column("tags", "col_tags");
const COL_INFO: ColumnSpec = column("info", "col_info");

const NO_FIELDS: &[&str] = &[];

/// Order is the tool menu order; it mirrors the Slint frontend's registry.
static TOOLS: &[Entry] = &[
    Entry {
        id: "duplicate_files",
        tool_type: ToolType::Duplicate,
        glyph: "D=",
        label_key: "tool_duplicate_files",
        grouped: true,
        columns: COL_SIZE_DATE,
        field_ids: &[
            "dup_check_method",
            "dup_hash_type",
            "dup_case_sensitive_names",
            "dup_ignore_hard_links",
            "dup_use_prehash",
            "dup_hash_cache_size",
            "dup_prehash_cache_size",
        ],
    },
    Entry {
        id: "empty_folders",
        tool_type: ToolType::EmptyFolders,
        glyph: "0F",
        label_key: "tool_empty_folders",
        grouped: false,
        columns: COL_DATES,
        field_ids: NO_FIELDS,
    },
    Entry {
        id: "big_files",
        tool_type: ToolType::BigFile,
        glyph: ">>",
        label_key: "tool_big_files",
        grouped: false,
        columns: COL_SIZE_DATE,
        field_ids: &["big_number_of_files", "big_biggest_first"],
    },
    Entry {
        id: "empty_files",
        tool_type: ToolType::EmptyFiles,
        glyph: "0B",
        label_key: "tool_empty_files",
        grouped: false,
        columns: COL_SIZE_DATE,
        field_ids: &["emp_zero_byte_content", "emp_non_printable_content"],
    },
    Entry {
        id: "temporary_files",
        tool_type: ToolType::TemporaryFiles,
        glyph: "TMP",
        label_key: "tool_temporary_files",
        grouped: false,
        columns: COL_SIZE_DATE,
        field_ids: &["temp_extension_list"],
    },
    Entry {
        id: "similar_images",
        tool_type: ToolType::SimilarImages,
        glyph: "IMG",
        label_key: "tool_similar_images",
        grouped: true,
        columns: &[COL_DIFFERENCE, COL_SIZE, COL_RESOLUTION, COL_MODIFIED],
        field_ids: &[
            "img_similarity",
            "img_hash_size",
            "img_hash_algorithm",
            "img_resize_algorithm",
            "img_ignore_same_size",
            "img_ignore_same_resolution",
            "img_geometric_invariance",
        ],
    },
    Entry {
        id: "similar_videos",
        tool_type: ToolType::SimilarVideos,
        glyph: "VID",
        label_key: "tool_similar_videos",
        grouped: true,
        columns: &[COL_SIZE, COL_DURATION, COL_RESOLUTION, COL_CODEC, COL_BITRATE, COL_MODIFIED],
        field_ids: &[
            "vid_tolerance",
            "vid_ignore_same_size",
            "vid_ignore_same_resolution",
            "vid_skip_forward",
            "vid_hash_duration",
            "vid_letterbox_crop",
            "vid_window_count",
            "vid_duration_tolerance_pct",
            "vid_min_matching_windows",
            "vid_subclip_min_match",
            "vid_generate_thumbnails",
            "vid_thumbnail_percentage",
            "vid_thumbnail_grid",
            "vid_thumbnail_grid_tiles",
            "vid_check_audio_content",
            "vid_audio_similarity_percent",
            "vid_audio_max_difference",
            "vid_audio_length_ratio",
            "vid_audio_min_duration_seconds",
        ],
    },
    Entry {
        id: "duplicate_music",
        tool_type: ToolType::SameMusic,
        glyph: "AUD",
        label_key: "tool_duplicate_music",
        grouped: true,
        columns: &[COL_SIZE, COL_TITLE, COL_ARTIST, COL_YEAR, COL_BITRATE, COL_LENGTH, COL_GENRE, COL_MODIFIED],
        field_ids: &[
            "mus_check_type",
            "mus_approximate",
            "mus_title",
            "mus_artist",
            "mus_bitrate",
            "mus_genre",
            "mus_year",
            "mus_length",
            "mus_max_difference",
            "mus_min_fragment_duration",
        ],
    },
    Entry {
        id: "invalid_symlinks",
        tool_type: ToolType::InvalidSymlinks,
        glyph: "->",
        label_key: "tool_invalid_symlinks",
        grouped: false,
        columns: &[COL_DESTINATION, COL_ERRORS, COL_MODIFIED],
        field_ids: NO_FIELDS,
    },
    Entry {
        id: "broken_files",
        tool_type: ToolType::BrokenFiles,
        glyph: "!!",
        label_key: "tool_broken_files",
        grouped: false,
        columns: &[COL_SIZE, COL_ERRORS, COL_MODIFIED],
        field_ids: &[
            "bro_image",
            "bro_archive",
            "bro_audio",
            "bro_pdf",
            "bro_video_ffprobe",
            "bro_video_ffmpeg",
            "bro_font",
            "bro_markup",
        ],
    },
    Entry {
        id: "bad_extensions",
        tool_type: ToolType::BadExtensions,
        glyph: "EXT",
        label_key: "tool_bad_extensions",
        grouped: false,
        columns: &[COL_CURRENT_EXT, COL_PROPER_GROUP, COL_PROPER_EXT, COL_MODIFIED],
        field_ids: &["bext_include_files_without_extension"],
    },
    Entry {
        id: "bad_names",
        tool_type: ToolType::BadNames,
        glyph: "NAM",
        label_key: "tool_bad_names",
        grouped: false,
        columns: &[COL_NEW_NAME, COL_SIZE, COL_MODIFIED],
        field_ids: &[
            "name_uppercase_extension",
            "name_emoji_used",
            "name_space_at_start_or_end",
            "name_non_ascii_graphical",
            "name_remove_duplicated_non_alphanumeric",
            "name_allowed_charset",
        ],
    },
    Entry {
        id: "exif_remover",
        tool_type: ToolType::ExifRemover,
        glyph: "EXIF",
        label_key: "tool_exif_remover",
        grouped: false,
        columns: &[COL_SIZE, COL_TAGS],
        field_ids: &["exif_ignored_tags"],
    },
    Entry {
        id: "video_optimizer",
        tool_type: ToolType::VideoOptimizer,
        glyph: "OPT",
        label_key: "tool_video_optimizer",
        grouped: false,
        columns: &[COL_SIZE, COL_CODEC, COL_RESOLUTION, COL_INFO, COL_MODIFIED],
        field_ids: &[
            "vid_opt_mode",
            "vid_opt_crop_mechanism",
            "vid_opt_excluded_codecs",
            "vid_opt_black_pixel_threshold",
            "vid_opt_black_bar_min_percentage",
            "vid_opt_max_samples",
            "vid_opt_min_crop_size",
        ],
    },
];

fn find(tool: &str) -> Option<&'static Entry> {
    TOOLS.iter().find(|entry| entry.id == tool)
}

pub fn views() -> Vec<ToolView> {
    TOOLS.iter().map(view_of).collect()
}

pub fn view(tool: &str) -> Option<ToolView> {
    find(tool).map(view_of)
}

fn view_of(entry: &Entry) -> ToolView {
    ToolView {
        id: entry.id.to_string(),
        glyph: entry.glyph.to_string(),
        label_key: entry.label_key.to_string(),
        grouped: entry.grouped,
        supports_reference: entry.tool_type.may_use_reference_paths(),
        columns: entry
            .columns
            .iter()
            .map(|column| ColumnKey {
                key: column.key.to_string(),
                label_key: column.label_key.to_string(),
            })
            .collect(),
        field_ids: entry.field_ids.iter().map(|id| id.to_string()).collect(),
    }
}

pub fn tool_type(tool: &str) -> Option<ToolType> {
    find(tool).map(|entry| entry.tool_type)
}

/// Field metadata for one scanner, filled in by the option registry.
pub fn fields(tool: &str) -> Vec<FieldDef> {
    let Some(entry) = find(tool) else {
        return Vec::new();
    };
    options::defs(entry.field_ids)
}

pub fn defaults(tool: &str) -> Vec<FieldValue> {
    let Some(entry) = find(tool) else {
        return Vec::new();
    };
    options::defaults(entry.field_ids)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_registered_scanner_is_exposed_once() {
        let ids: Vec<String> = views().into_iter().map(|spec| spec.id).collect();
        assert_eq!(ids.len(), czkawka_core::TOOLS_NUMBER, "engine declares a different tool count");
        let unique: std::collections::HashSet<&String> = ids.iter().collect();
        assert_eq!(unique.len(), ids.len(), "duplicate tool id in the registry");
    }

    /// A field id the option registry does not know would render a control in Dart whose value
    /// the scanner silently ignores, so the two tables must stay in step.
    #[test]
    fn every_field_id_resolves_to_a_definition_and_a_default() {
        for spec in views() {
            let defs = fields(&spec.id);
            let defaults = defaults(&spec.id);
            assert_eq!(defs.len(), spec.field_ids.len(), "{}: field definitions missing", spec.id);
            assert_eq!(defaults.len(), spec.field_ids.len(), "{}: field defaults missing", spec.id);
            for (definition, id) in defs.iter().zip(spec.field_ids.iter()) {
                assert_eq!(&definition.id, id, "{}: field order drifted", spec.id);
            }
            for value in &defaults {
                assert!(spec.field_ids.contains(&value.id), "{}: default for unknown field {}", spec.id, value.id);
            }
        }
    }

    #[test]
    fn reference_support_comes_from_the_engine_not_a_local_guess() {
        let supporting: Vec<String> = views().into_iter().filter(|spec| spec.supports_reference).map(|spec| spec.id).collect();
        assert_eq!(
            supporting,
            vec![
                "duplicate_files".to_string(),
                "similar_images".to_string(),
                "similar_videos".to_string(),
                "duplicate_music".to_string(),
            ]
        );
    }

    #[test]
    fn columns_align_with_their_display_labels() {
        let spec = view("similar_images").expect("similar_images must be registered");
        let keys: Vec<&str> = spec.columns.iter().map(|column| column.key.as_str()).collect();
        assert_eq!(keys, vec!["difference", "size", "resolution", "modified"]);
    }
}
