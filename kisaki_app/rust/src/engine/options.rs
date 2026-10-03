use crate::api::types::{FieldDef, FieldKind, FieldPayload, FieldValue, ScanRequest};
use crate::engine::FieldStore;

/// Reads the request's option list into a lookup the scanners can query by field id.
pub fn store(request: &ScanRequest) -> FieldStore {
    FieldStore::new(request.fields.clone())
}

/// Starting value of one field. Mirrors [`FieldKind`], so a choice default is always one of the
/// machine values declared by the same field.
#[derive(Clone, Copy)]
enum Initial {
    Flag(bool),
    Choice(&'static str),
    Integer(i64),
    /// A float the engine takes directly (`duration_tolerance_pct`), carried as text because the
    /// FFI has no float payload. Defaults are written the way they should be displayed ("0.6").
    Decimal(&'static str),
    Tokens(&'static [&'static str]),
}

/// One scanner option.
///
/// `options` holds machine values, never display labels: Dart echoes the selected string back and
/// the scanners match on it. Each entry names the `czkawka_core` value it selects
/// (`HashType::Xxh3` -> "XXH3", `CheckingMethod::SizeName` -> "SizeName",
/// `SimilarityPreset::VeryHigh` -> "VeryHigh"); the scanners compare after dropping separators and
/// case, so spellings like "SizeName" and "size_name" reach the same arm.
/// `min`/`max` mirror the clamps the scanners apply and are advisory for the UI.
struct Spec {
    id: &'static str,
    kind: FieldKind,
    options: &'static [&'static str],
    min: i64,
    max: i64,
    initial: Initial,
}

/// The engine only floors the KiB cache sizes, so the ceiling is the FFI's own integer limit.
const NO_CEILING: i64 = i64::MAX;

const fn flag(id: &'static str, default: bool) -> Spec {
    Spec {
        id,
        kind: FieldKind::Flag,
        options: &[],
        min: 0,
        max: 0,
        initial: Initial::Flag(default),
    }
}

const fn choice(id: &'static str, options: &'static [&'static str], default: &'static str) -> Spec {
    Spec {
        id,
        kind: FieldKind::Choice,
        options,
        min: 0,
        max: 0,
        initial: Initial::Choice(default),
    }
}

const fn integer(id: &'static str, min: i64, max: i64, default: i64) -> Spec {
    Spec {
        id,
        kind: FieldKind::Integer,
        options: &[],
        min,
        max,
        initial: Initial::Integer(default),
    }
}

/// A fractional option. It travels as text, so `min`/`max` describe the whole-number span the
/// engine asserts on (`0..=1` for fractions, `0..=100` for percentages) rather than a slider range.
const fn decimal(id: &'static str, min: i64, max: i64, default: &'static str) -> Spec {
    Spec {
        id,
        kind: FieldKind::Text,
        options: &[],
        min,
        max,
        initial: Initial::Decimal(default),
    }
}

const fn tokens(id: &'static str, default: &'static [&'static str]) -> Spec {
    Spec {
        id,
        kind: FieldKind::TokenList,
        options: &[],
        min: 0,
        max: 0,
        initial: Initial::Tokens(default),
    }
}

const SPECS: &[Spec] = &[
    // Duplicate files
    choice("dup_check_method", &["Hash", "Size", "Name", "SizeName"], "Hash"),
    choice("dup_hash_type", &["Blake3", "CRC32", "XXH3"], "XXH3"),
    flag("dup_case_sensitive_names", true),
    flag("dup_ignore_hard_links", false),
    flag("dup_use_prehash", true),
    integer("dup_hash_cache_size", 1, NO_CEILING, 1000),
    integer("dup_prehash_cache_size", 1, NO_CEILING, 1000),
    // Similar images
    choice("img_similarity", &["Original", "VeryHigh", "High", "Medium", "Small", "VerySmall", "Minimal"], "High"),
    choice("img_hash_size", &["8", "16", "32", "64"], "16"),
    choice(
        "img_hash_algorithm",
        &["Mean", "Gradient", "BlockHash", "VertGradient", "DoubleGradient", "Median"],
        "Gradient",
    ),
    choice("img_resize_algorithm", &["Lanczos3", "Gaussian", "CatmullRom", "Triangle", "Nearest"], "Lanczos3"),
    flag("img_ignore_same_size", false),
    flag("img_ignore_same_resolution", false),
    choice("img_geometric_invariance", &["Off", "MirrorFlip", "MirrorFlipRotate90"], "Off"),
    // Similar videos - in the order SimilarVideosParameters::new takes them
    integer("vid_tolerance", 0, 20, 2),
    flag("vid_ignore_same_size", false),
    flag("vid_ignore_same_resolution", false),
    integer("vid_skip_forward", 0, 300, 15),
    integer("vid_hash_duration", 2, 60, 10),
    flag("vid_letterbox_crop", true),
    integer("vid_window_count", 1, 20, 5),
    decimal("vid_duration_tolerance_pct", 0, 100, "20"),
    decimal("vid_min_matching_windows", 0, 1, "0.6"),
    decimal("vid_subclip_min_match", 0, 1, "0.5"),
    flag("vid_generate_thumbnails", false),
    integer("vid_thumbnail_percentage", 0, 100, 10),
    flag("vid_thumbnail_grid", false),
    integer("vid_thumbnail_grid_tiles", 2, 6, 2),
    flag("vid_check_audio_content", false),
    decimal("vid_audio_similarity_percent", 0, 100, "80"),
    decimal("vid_audio_max_difference", 0, 10, "3"),
    decimal("vid_audio_length_ratio", 0, 1, "0.1"),
    integer("vid_audio_min_duration_seconds", 0, 600, 10),
    // Duplicate music
    choice("mus_check_type", &["Tags", "Fingerprint"], "Tags"),
    flag("mus_approximate", true),
    flag("mus_title", true),
    flag("mus_artist", true),
    flag("mus_bitrate", false),
    flag("mus_genre", false),
    flag("mus_year", false),
    flag("mus_length", false),
    // Both music tolerances are floats in the engine; the flat integer kind truncates them.
    integer("mus_max_difference", 0, 1000, 2),
    integer("mus_min_fragment_duration", 1, 600, 10),
    // Big files
    integer("big_number_of_files", 1, 100_000, 50),
    flag("big_biggest_first", true),
    // Empty files
    flag("emp_zero_byte_content", true),
    flag("emp_non_printable_content", false),
    // Temporary files
    tokens("temp_extension_list", &[]),
    // Broken files
    flag("bro_image", true),
    flag("bro_archive", true),
    flag("bro_audio", true),
    flag("bro_pdf", true),
    flag("bro_video_ffprobe", false),
    flag("bro_video_ffmpeg", false),
    flag("bro_font", false),
    flag("bro_markup", false),
    // Exif remover
    tokens("exif_ignored_tags", &[]),
    // Video optimizer
    choice("vid_opt_mode", &["Crop", "Transcode"], "Transcode"),
    choice("vid_opt_crop_mechanism", &["BlackBars", "StaticContent"], "BlackBars"),
    tokens("vid_opt_excluded_codecs", &["hevc", "h265", "av1", "vp9"]),
    integer("vid_opt_black_pixel_threshold", 0, 128, 64),
    integer("vid_opt_black_bar_min_percentage", 50, 100, 80),
    integer("vid_opt_max_samples", 5, 1000, 60),
    integer("vid_opt_min_crop_size", 1, 1000, 20),
];

impl From<Initial> for FieldPayload {
    fn from(initial: Initial) -> FieldPayload {
        match initial {
            Initial::Flag(value) => FieldPayload::Flag(value),
            Initial::Choice(value) => FieldPayload::Choice(value.to_string()),
            Initial::Integer(value) => FieldPayload::Integer(value),
            Initial::Decimal(value) => FieldPayload::Text(value.to_string()),
            Initial::Tokens(values) => FieldPayload::Tokens(values.iter().map(|value| value.to_string()).collect()),
        }
    }
}

/// Metadata for the requested field ids, in the given order.
///
/// Ported from the Slint frontend's field registry, which owns the label keys, kinds, choice
/// lists and numeric bounds for every scanner option. Ids with no registry entry are skipped.
pub fn defs(ids: &[&str]) -> Vec<FieldDef> {
    ids.iter().copied().filter_map(find).map(to_def).collect()
}

pub fn defaults(ids: &[&str]) -> Vec<FieldValue> {
    ids.iter().copied().filter_map(find).map(to_value).collect()
}

fn find(id: &str) -> Option<&'static Spec> {
    SPECS.iter().find(|spec| spec.id == id)
}

fn to_def(spec: &Spec) -> FieldDef {
    let id = spec.id;
    FieldDef {
        id: id.to_string(),
        label_key: label_key(id),
        kind: spec.kind.clone(),
        options: spec.options.iter().map(|option| option.to_string()).collect(),
        min: spec.min,
        max: spec.max,
    }
}

/// The Slint frontend's Fluent key for a field. Its video optimizer keys were written before the
/// `vid_opt_` ids existed and stay `field_vidopt_*`, so the key is not derivable from the id alone.
fn label_key(id: &str) -> String {
    match id.strip_prefix("vid_opt_") {
        Some(suffix) => format!("field_vidopt_{suffix}"),
        None => format!("field_{id}"),
    }
}

fn to_value(spec: &Spec) -> FieldValue {
    FieldValue {
        id: spec.id.to_string(),
        value: spec.initial.into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_registry_field_id_resolves() {
        let tools = crate::engine::registry::tools();
        let ids: Vec<&str> = tools.iter().flat_map(|tool| tool.field_ids.iter().map(String::as_str)).collect();

        let defs = defs(&ids);
        let defaults = defaults(&ids);
        assert_eq!(defs.len(), ids.len(), "a tool table id has no option registry entry");
        assert_eq!(defaults.len(), ids.len());

        for (def, default) in defs.iter().zip(defaults.iter()) {
            assert_eq!(def.id, default.id);
            assert_eq!(def.label_key, label_key(&def.id));
            if let (FieldKind::Choice, FieldPayload::Choice(selected)) = (&def.kind, &default.value) {
                assert!(def.options.contains(selected), "choice default of {}: {selected}", def.id);
            }
        }
    }

    #[test]
    fn label_keys_are_the_fluent_ones() {
        assert_eq!(label_key("dup_hash_type"), "field_dup_hash_type");
        assert_eq!(label_key("vid_opt_mode"), "field_vidopt_mode");
        assert_eq!(label_key("vid_opt_black_pixel_threshold"), "field_vidopt_black_pixel_threshold");
    }

    #[test]
    fn order_follows_the_requested_ids() {
        let defs = defs(&["big_biggest_first", "dup_hash_type"]);
        assert_eq!(defs.len(), 2);
        assert_eq!(defs[0].id, "big_biggest_first");
        assert_eq!(defs[1].id, "dup_hash_type");

        let defaults = defaults(&["big_biggest_first", "dup_hash_type"]);
        assert_eq!(defaults[0].value, FieldPayload::Flag(true));
        assert_eq!(defaults[1].value, FieldPayload::Choice("XXH3".to_string()));
    }

    #[test]
    fn unknown_ids_are_skipped() {
        assert_eq!(defs(&["no_such_field"]), Vec::new());
        assert_eq!(defaults(&["no_such_field"]), Vec::new());
    }

    #[test]
    fn bounds_match_the_engine_clamps() {
        let defs = defs(&["vid_tolerance", "vid_hash_duration", "big_number_of_files", "vid_opt_max_samples"]);
        let bounds: Vec<(i64, i64)> = defs.iter().map(|def| (def.min, def.max)).collect();
        assert_eq!(bounds, vec![(0, 20), (2, 60), (1, 100_000), (5, 1000)]);
    }

    #[test]
    fn token_lists_default_to_the_engine_fallbacks() {
        let defaults = defaults(&["temp_extension_list", "vid_opt_excluded_codecs"]);
        assert_eq!(defaults[0].value, FieldPayload::Tokens(Vec::new()));
        assert_eq!(
            defaults[1].value,
            FieldPayload::Tokens(vec!["hevc".to_string(), "h265".to_string(), "av1".to_string(), "vp9".to_string()])
        );
    }
}
