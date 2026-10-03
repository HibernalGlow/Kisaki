/// Seed copy of the tool registry, mirroring the shipped Slint frontend's tables
/// (`kisaki/src/tools.rs`, `kisaki/src/fields.rs`) until the engine serves it over the bridge.
///
/// Data only: every entry is built with the canonical types from `engine/models.dart`, so the
/// seed and the generated bridge hand the very same classes to the board.
library;

import 'package:kisaki_app/engine/models.dart';

// ---------------------------------------------------------------------------
// Result table columns, one constant per column definition in tools.rs.
// ---------------------------------------------------------------------------

const ColumnDef _colSize = ColumnDef(
    key: 'size', labelKey: 'col_size', flex: 0.5, minWidth: 84.0, alignRight: true);
const ColumnDef _colModified = ColumnDef(
    key: 'modified', labelKey: 'col_modified', flex: 1.0, minWidth: 140.0, alignRight: false);
const ColumnDef _colDifference = ColumnDef(
    key: 'difference', labelKey: 'col_difference', flex: 0.7, minWidth: 90.0, alignRight: false);
const ColumnDef _colDuration = ColumnDef(
    key: 'duration', labelKey: 'col_duration', flex: 0.6, minWidth: 70.0, alignRight: false);
const ColumnDef _colCodec = ColumnDef(
    key: 'codec', labelKey: 'col_codec', flex: 0.7, minWidth: 70.0, alignRight: false);
const ColumnDef _colTitle = ColumnDef(
    key: 'title', labelKey: 'col_title', flex: 1.2, minWidth: 120.0, alignRight: false);
const ColumnDef _colArtist = ColumnDef(
    key: 'artist', labelKey: 'col_artist', flex: 1.0, minWidth: 100.0, alignRight: false);
const ColumnDef _colYear = ColumnDef(
    key: 'year', labelKey: 'col_year', flex: 0.4, minWidth: 50.0, alignRight: false);
const ColumnDef _colLength = ColumnDef(
    key: 'length', labelKey: 'col_length', flex: 0.5, minWidth: 60.0, alignRight: true);
const ColumnDef _colGenre = ColumnDef(
    key: 'genre', labelKey: 'col_genre', flex: 0.8, minWidth: 70.0, alignRight: false);
const ColumnDef _colError = ColumnDef(
    key: 'error', labelKey: 'col_error', flex: 1.0, minWidth: 110.0, alignRight: false);
const ColumnDef _colErrors = ColumnDef(
    key: 'errors', labelKey: 'col_errors', flex: 1.6, minWidth: 160.0, alignRight: false);
const ColumnDef _colNewName = ColumnDef(
    key: 'new_name', labelKey: 'col_new_name', flex: 1.4, minWidth: 150.0, alignRight: false);
const ColumnDef _colTags = ColumnDef(
    key: 'tags', labelKey: 'col_tags', flex: 1.8, minWidth: 180.0, alignRight: false);
const ColumnDef _colInfo = ColumnDef(
    key: 'info', labelKey: 'col_info', flex: 1.2, minWidth: 120.0, alignRight: false);

// Column keys long enough that the constructor call has to start on the second line.
const ColumnDef _colResolution =
    ColumnDef(key: 'resolution', labelKey: 'col_resolution', flex: 0.7, minWidth: 90.0,
        alignRight: false);
const ColumnDef _colDestination =
    ColumnDef(key: 'destination', labelKey: 'col_destination', flex: 1.4, minWidth: 140.0,
        alignRight: false);
const ColumnDef _colCurrentExtension =
    ColumnDef(key: 'current_extension', labelKey: 'col_current_extension', flex: 0.7,
        minWidth: 70.0, alignRight: false);
const ColumnDef _colProperGroup =
    ColumnDef(key: 'proper_group', labelKey: 'col_proper_group', flex: 0.8, minWidth: 80.0,
        alignRight: false);
const ColumnDef _colProperExtension =
    ColumnDef(key: 'proper_extension', labelKey: 'col_proper_extension', flex: 0.8,
        minWidth: 80.0, alignRight: false);

// The same label is laid out differently per scanner, so the tables keep separate rows:
// bitrate is 0.7/80 for videos (tools.rs:84) and 0.5/70 for music (tools.rs:112).
const ColumnDef _colVideoBitrate = ColumnDef(
    key: 'bitrate', labelKey: 'col_bitrate', flex: 0.7, minWidth: 80.0, alignRight: true);
const ColumnDef _colMusicBitrate = ColumnDef(
    key: 'bitrate', labelKey: 'col_bitrate', flex: 0.5, minWidth: 70.0, alignRight: true);

// Video optimizer stretches resolution to 0.8 while the similarity scanners use 0.7.
const ColumnDef _colOptResolution =
    ColumnDef(key: 'resolution', labelKey: 'col_resolution', flex: 0.8, minWidth: 90.0,
        alignRight: false);

const List<ColumnDef> _sizeDateColumns = [_colSize, _colModified];
const List<ColumnDef> _dateColumns = [_colModified];
const List<ColumnDef> _imageColumns = [_colDifference, _colSize, _colResolution, _colModified];
const List<ColumnDef> _videoColumns = [
  _colSize,
  _colDuration,
  _colResolution,
  _colCodec,
  _colVideoBitrate,
  _colModified,
];
const List<ColumnDef> _musicColumns = [
  _colSize,
  _colTitle,
  _colArtist,
  _colYear,
  _colMusicBitrate,
  _colLength,
  _colGenre,
  _colModified,
];
const List<ColumnDef> _symlinkColumns = [_colDestination, _colError, _colModified];
const List<ColumnDef> _brokenColumns = [_colSize, _colErrors, _colModified];
const List<ColumnDef> _badExtensionColumns = [
  _colCurrentExtension,
  _colProperGroup,
  _colProperExtension,
  _colModified,
];
const List<ColumnDef> _badNameColumns = [_colNewName, _colSize, _colModified];
const List<ColumnDef> _exifColumns = [_colSize, _colTags];
const List<ColumnDef> _optimizerColumns = [
  _colSize,
  _colCodec,
  _colOptResolution,
  _colInfo,
  _colModified,
];

// ---------------------------------------------------------------------------
// Option fields: one global table, referenced by id from every tool.
// ---------------------------------------------------------------------------

const List<String> _dupCheckMethodOptions = [
  'option_check_method_hash',
  'option_check_method_size',
  'option_check_method_name',
  'option_check_method_size_and_name',
];
const List<String> _dupHashTypeOptions = ['Blake3', 'CRC32', 'XXH3'];
const List<String> _imgSimilarityOptions = [
  'option_similarity_original',
  'option_similarity_very_high',
  'option_similarity_high',
  'option_similarity_medium',
  'option_similarity_small',
  'option_similarity_very_small',
  'option_similarity_minimal',
];
const List<String> _imgHashSizeOptions = ['8', '16', '32', '64'];
const List<String> _imgHashAlgorithmOptions = [
  'Mean',
  'Gradient',
  'BlockHash',
  'VertGradient',
  'DoubleGradient',
  'Median',
];
const List<String> _imgResizeAlgorithmOptions = [
  'Lanczos3',
  'Gaussian',
  'CatmullRom',
  'Triangle',
  'Nearest',
];
const List<String> _imgGeometricInvarianceOptions = [
  'option_geometric_invariance_off',
  'option_geometric_invariance_mirror_flip',
  'option_geometric_invariance_mirror_flip_rotate90',
];
const List<String> _musCheckTypeOptions = [
  'option_music_method_tags',
  'option_music_method_fingerprint',
];
const List<String> _vidOptModeOptions = [
  'option_video_optimizer_mode_crop',
  'option_video_optimizer_mode_transcode',
];

/// Order follows `FieldId::ALL` (kisaki/src/fields.rs:162).
///
/// `min`/`max` only mean something to integer fields; every other kind keeps the 0/0 the
/// ported table used. The two cache sizes carry Rust's `i64::MAX` because the engine only
/// clamps their lower bound, so the UI must not impose an upper limit on them.
const List<FieldDef> _fieldDefs = [
  FieldDef(id: 'dup_check_method', labelKey: 'field_dup_check_method', kind: FieldKind.choice,
      options: _dupCheckMethodOptions, min: 0, max: 0),
  FieldDef(id: 'dup_hash_type', labelKey: 'field_dup_hash_type', kind: FieldKind.choice,
      options: _dupHashTypeOptions, min: 0, max: 0),
  FieldDef(id: 'dup_case_sensitive_names', labelKey: 'field_dup_case_sensitive_names',
      kind: FieldKind.flag, options: [], min: 0, max: 0),
  FieldDef(id: 'dup_ignore_hard_links', labelKey: 'field_dup_ignore_hard_links',
      kind: FieldKind.flag, options: [], min: 0, max: 0),
  FieldDef(id: 'dup_use_prehash', labelKey: 'field_dup_use_prehash', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'dup_hash_cache_size', labelKey: 'field_dup_hash_cache_size',
      kind: FieldKind.integer, options: [], min: 1, max: 0x7FFFFFFFFFFFFFFF),
  FieldDef(id: 'dup_prehash_cache_size', labelKey: 'field_dup_prehash_cache_size',
      kind: FieldKind.integer, options: [], min: 1, max: 0x7FFFFFFFFFFFFFFF),
  FieldDef(id: 'img_similarity', labelKey: 'field_img_similarity', kind: FieldKind.choice,
      options: _imgSimilarityOptions, min: 0, max: 0),
  FieldDef(id: 'img_hash_size', labelKey: 'field_img_hash_size', kind: FieldKind.choice,
      options: _imgHashSizeOptions, min: 0, max: 0),
  FieldDef(id: 'img_hash_algorithm', labelKey: 'field_img_hash_algorithm', kind: FieldKind.choice,
      options: _imgHashAlgorithmOptions, min: 0, max: 0),
  FieldDef(id: 'img_resize_algorithm', labelKey: 'field_img_resize_algorithm',
      kind: FieldKind.choice, options: _imgResizeAlgorithmOptions, min: 0, max: 0),
  FieldDef(id: 'img_ignore_same_size', labelKey: 'field_img_ignore_same_size',
      kind: FieldKind.flag, options: [], min: 0, max: 0),
  FieldDef(id: 'img_ignore_same_resolution', labelKey: 'field_img_ignore_same_resolution',
      kind: FieldKind.flag, options: [], min: 0, max: 0),
  FieldDef(id: 'img_geometric_invariance', labelKey: 'field_img_geometric_invariance',
      kind: FieldKind.choice, options: _imgGeometricInvarianceOptions, min: 0, max: 0),
  FieldDef(id: 'vid_tolerance', labelKey: 'field_vid_tolerance', kind: FieldKind.integer,
      options: [], min: 0, max: 20),
  FieldDef(id: 'vid_ignore_same_size', labelKey: 'field_vid_ignore_same_size',
      kind: FieldKind.flag, options: [], min: 0, max: 0),
  FieldDef(id: 'vid_skip_forward', labelKey: 'field_vid_skip_forward', kind: FieldKind.integer,
      options: [], min: 0, max: 300),
  FieldDef(id: 'vid_hash_duration', labelKey: 'field_vid_hash_duration', kind: FieldKind.integer,
      options: [], min: 2, max: 60),
  FieldDef(id: 'vid_letterbox_crop', labelKey: 'field_vid_letterbox_crop', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'mus_check_type', labelKey: 'field_mus_check_type', kind: FieldKind.choice,
      options: _musCheckTypeOptions, min: 0, max: 0),
  FieldDef(id: 'mus_approximate', labelKey: 'field_mus_approximate', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'mus_title', labelKey: 'field_mus_title', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'mus_artist', labelKey: 'field_mus_artist', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'mus_bitrate', labelKey: 'field_mus_bitrate', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'mus_genre', labelKey: 'field_mus_genre', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'mus_year', labelKey: 'field_mus_year', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'mus_length', labelKey: 'field_mus_length', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  // The engine reads both music numbers as floats but the bridge has no float kind, so they
  // are integers here with the float clamps of scan_grouped.rs:315-316.
  FieldDef(id: 'mus_max_difference', labelKey: 'field_mus_max_difference', kind: FieldKind.integer,
      options: [], min: 0, max: 1000),
  FieldDef(id: 'mus_min_fragment_duration', labelKey: 'field_mus_min_fragment_duration',
      kind: FieldKind.integer, options: [], min: 1, max: 600),
  FieldDef(id: 'big_number_of_files', labelKey: 'field_big_number_of_files',
      kind: FieldKind.integer, options: [], min: 1, max: 100000),
  FieldDef(id: 'big_biggest_first', labelKey: 'field_big_biggest_first', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'emp_zero_byte_content', labelKey: 'field_emp_zero_byte_content',
      kind: FieldKind.flag, options: [], min: 0, max: 0),
  FieldDef(id: 'emp_non_printable_content', labelKey: 'field_emp_non_printable_content',
      kind: FieldKind.flag, options: [], min: 0, max: 0),
  FieldDef(id: 'temp_extension_list', labelKey: 'field_temp_extension_list',
      kind: FieldKind.tokenList, options: [], min: 0, max: 0),
  FieldDef(id: 'bro_audio', labelKey: 'field_bro_audio', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'bro_pdf', labelKey: 'field_bro_pdf', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'bro_archive', labelKey: 'field_bro_archive', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'bro_image', labelKey: 'field_bro_image', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'bro_video_ffprobe', labelKey: 'field_bro_video_ffprobe', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'bro_video_ffmpeg', labelKey: 'field_bro_video_ffmpeg', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'bro_font', labelKey: 'field_bro_font', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'bro_markup', labelKey: 'field_bro_markup', kind: FieldKind.flag,
      options: [], min: 0, max: 0),
  FieldDef(id: 'exif_ignored_tags', labelKey: 'field_exif_ignored_tags',
      kind: FieldKind.tokenList, options: [], min: 0, max: 0),
  FieldDef(id: 'vid_opt_mode', labelKey: 'field_vidopt_mode', kind: FieldKind.choice,
      options: _vidOptModeOptions, min: 0, max: 0),
  FieldDef(id: 'vid_opt_excluded_codecs', labelKey: 'field_vidopt_excluded_codecs',
      kind: FieldKind.tokenList, options: [], min: 0, max: 0),
  FieldDef(id: 'vid_opt_black_pixel_threshold',
      labelKey: 'field_vidopt_black_pixel_threshold', kind: FieldKind.integer,
      options: [], min: 0, max: 128),
  FieldDef(id: 'vid_opt_black_bar_min_percentage',
      labelKey: 'field_vidopt_black_bar_min_percentage', kind: FieldKind.integer,
      options: [], min: 50, max: 100),
  FieldDef(id: 'vid_opt_max_samples', labelKey: 'field_vidopt_max_samples',
      kind: FieldKind.integer, options: [], min: 5, max: 1000),
  FieldDef(id: 'vid_opt_min_crop_size', labelKey: 'field_vidopt_min_crop_size',
      kind: FieldKind.integer, options: [], min: 1, max: 1000),
];

/// Defaults from `FieldId::default_value` (kisaki/src/fields.rs:350); a choice default is the
/// option string the Slint index points at, e.g. `Choice(2)` of `_dupHashTypeOptions`.
const List<FieldValue> _fieldDefaults = [
  FieldValue(id: 'dup_check_method', value: FieldPayloadChoice('option_check_method_hash')),
  FieldValue(id: 'dup_hash_type', value: FieldPayloadChoice('XXH3')),
  FieldValue(id: 'dup_case_sensitive_names', value: FieldPayloadFlag(true)),
  FieldValue(id: 'dup_ignore_hard_links', value: FieldPayloadFlag(false)),
  FieldValue(id: 'dup_use_prehash', value: FieldPayloadFlag(true)),
  FieldValue(id: 'dup_hash_cache_size', value: FieldPayloadInteger(1000)),
  FieldValue(id: 'dup_prehash_cache_size', value: FieldPayloadInteger(1000)),
  FieldValue(id: 'img_similarity', value: FieldPayloadChoice('option_similarity_high')),
  FieldValue(id: 'img_hash_size', value: FieldPayloadChoice('16')),
  FieldValue(id: 'img_hash_algorithm', value: FieldPayloadChoice('Gradient')),
  FieldValue(id: 'img_resize_algorithm', value: FieldPayloadChoice('Lanczos3')),
  FieldValue(id: 'img_ignore_same_size', value: FieldPayloadFlag(false)),
  FieldValue(id: 'img_ignore_same_resolution', value: FieldPayloadFlag(false)),
  FieldValue(id: 'img_geometric_invariance',
      value: FieldPayloadChoice('option_geometric_invariance_off')),
  FieldValue(id: 'vid_tolerance', value: FieldPayloadInteger(2)),
  FieldValue(id: 'vid_ignore_same_size', value: FieldPayloadFlag(false)),
  FieldValue(id: 'vid_skip_forward', value: FieldPayloadInteger(15)),
  FieldValue(id: 'vid_hash_duration', value: FieldPayloadInteger(10)),
  FieldValue(id: 'vid_letterbox_crop', value: FieldPayloadFlag(true)),
  FieldValue(id: 'mus_check_type', value: FieldPayloadChoice('option_music_method_tags')),
  FieldValue(id: 'mus_approximate', value: FieldPayloadFlag(true)),
  FieldValue(id: 'mus_title', value: FieldPayloadFlag(true)),
  FieldValue(id: 'mus_artist', value: FieldPayloadFlag(true)),
  FieldValue(id: 'mus_bitrate', value: FieldPayloadFlag(false)),
  FieldValue(id: 'mus_genre', value: FieldPayloadFlag(false)),
  FieldValue(id: 'mus_year', value: FieldPayloadFlag(false)),
  FieldValue(id: 'mus_length', value: FieldPayloadFlag(false)),
  FieldValue(id: 'mus_max_difference', value: FieldPayloadInteger(2)),
  FieldValue(id: 'mus_min_fragment_duration', value: FieldPayloadInteger(10)),
  FieldValue(id: 'big_number_of_files', value: FieldPayloadInteger(50)),
  FieldValue(id: 'big_biggest_first', value: FieldPayloadFlag(true)),
  FieldValue(id: 'emp_zero_byte_content', value: FieldPayloadFlag(true)),
  FieldValue(id: 'emp_non_printable_content', value: FieldPayloadFlag(false)),
  // An empty list means "use the scanner's own extension set" (scan_flat.rs:117).
  FieldValue(id: 'temp_extension_list', value: FieldPayloadTokens([])),
  FieldValue(id: 'bro_audio', value: FieldPayloadFlag(true)),
  FieldValue(id: 'bro_pdf', value: FieldPayloadFlag(true)),
  FieldValue(id: 'bro_archive', value: FieldPayloadFlag(true)),
  FieldValue(id: 'bro_image', value: FieldPayloadFlag(true)),
  FieldValue(id: 'bro_video_ffprobe', value: FieldPayloadFlag(false)),
  FieldValue(id: 'bro_video_ffmpeg', value: FieldPayloadFlag(false)),
  FieldValue(id: 'bro_font', value: FieldPayloadFlag(false)),
  FieldValue(id: 'bro_markup', value: FieldPayloadFlag(false)),
  FieldValue(id: 'exif_ignored_tags', value: FieldPayloadTokens([])),
  FieldValue(id: 'vid_opt_mode',
      value: FieldPayloadChoice('option_video_optimizer_mode_transcode')),
  FieldValue(id: 'vid_opt_excluded_codecs',
      value: FieldPayloadTokens(['hevc', 'h265', 'av1', 'vp9'])),
  FieldValue(id: 'vid_opt_black_pixel_threshold', value: FieldPayloadInteger(64)),
  FieldValue(id: 'vid_opt_black_bar_min_percentage', value: FieldPayloadInteger(80)),
  FieldValue(id: 'vid_opt_max_samples', value: FieldPayloadInteger(60)),
  FieldValue(id: 'vid_opt_min_crop_size', value: FieldPayloadInteger(20)),
];

// ---------------------------------------------------------------------------
// Field id lists per tool, in the order of the `*_FIELDS` arrays in tools.rs.
// ---------------------------------------------------------------------------

const List<String> _dupFields = [
  'dup_check_method',
  'dup_hash_type',
  'dup_case_sensitive_names',
  'dup_ignore_hard_links',
  'dup_use_prehash',
  'dup_hash_cache_size',
  'dup_prehash_cache_size',
];
const List<String> _imgFields = [
  'img_similarity',
  'img_hash_size',
  'img_hash_algorithm',
  'img_resize_algorithm',
  'img_ignore_same_size',
  'img_ignore_same_resolution',
  'img_geometric_invariance',
];
const List<String> _vidFields = [
  'vid_tolerance',
  'vid_ignore_same_size',
  'vid_skip_forward',
  'vid_hash_duration',
  'vid_letterbox_crop',
];
const List<String> _musFields = [
  'mus_check_type',
  'mus_approximate',
  'mus_title',
  'mus_artist',
  'mus_bitrate',
  'mus_genre',
  'mus_year',
  'mus_length',
  'mus_max_difference',
  'mus_min_fragment_duration',
];
const List<String> _bigFields = ['big_number_of_files', 'big_biggest_first'];
const List<String> _empFields = ['emp_zero_byte_content', 'emp_non_printable_content'];
const List<String> _tempFields = ['temp_extension_list'];
const List<String> _broFields = [
  'bro_image',
  'bro_archive',
  'bro_audio',
  'bro_pdf',
  'bro_video_ffprobe',
  'bro_video_ffmpeg',
  'bro_font',
  'bro_markup',
];
const List<String> _exifFields = ['exif_ignored_tags'];
const List<String> _vidOptFields = [
  'vid_opt_mode',
  'vid_opt_excluded_codecs',
  'vid_opt_black_pixel_threshold',
  'vid_opt_black_bar_min_percentage',
  'vid_opt_max_samples',
  'vid_opt_min_crop_size',
];

/// Menu order: `ToolId` declaration order, which is also the results table's order.
const List<ToolSpec> _tools = [
  ToolSpec(id: 'duplicate_files', glyph: 'D=', labelKey: 'tool_duplicate_files', grouped: true,
      supportsReference: true, columns: _sizeDateColumns, fieldIds: _dupFields),
  ToolSpec(id: 'empty_folders', glyph: '0F', labelKey: 'tool_empty_folders', grouped: false,
      supportsReference: false, columns: _dateColumns, fieldIds: []),
  ToolSpec(id: 'big_files', glyph: '>>', labelKey: 'tool_big_files', grouped: false,
      supportsReference: false, columns: _sizeDateColumns, fieldIds: _bigFields),
  ToolSpec(id: 'empty_files', glyph: '0B', labelKey: 'tool_empty_files', grouped: false,
      supportsReference: false, columns: _sizeDateColumns, fieldIds: _empFields),
  ToolSpec(id: 'temporary_files', glyph: 'TMP', labelKey: 'tool_temporary_files', grouped: false,
      supportsReference: false, columns: _sizeDateColumns, fieldIds: _tempFields),
  ToolSpec(id: 'similar_images', glyph: 'IMG', labelKey: 'tool_similar_images', grouped: true,
      supportsReference: true, columns: _imageColumns, fieldIds: _imgFields),
  ToolSpec(id: 'similar_videos', glyph: 'VID', labelKey: 'tool_similar_videos', grouped: true,
      supportsReference: true, columns: _videoColumns, fieldIds: _vidFields),
  ToolSpec(id: 'duplicate_music', glyph: 'AUD', labelKey: 'tool_duplicate_music', grouped: true,
      supportsReference: true, columns: _musicColumns, fieldIds: _musFields),
  ToolSpec(id: 'invalid_symlinks', glyph: '->', labelKey: 'tool_invalid_symlinks', grouped: false,
      supportsReference: false, columns: _symlinkColumns, fieldIds: []),
  ToolSpec(id: 'broken_files', glyph: '!!', labelKey: 'tool_broken_files', grouped: false,
      supportsReference: false, columns: _brokenColumns, fieldIds: _broFields),
  ToolSpec(id: 'bad_extensions', glyph: 'EXT', labelKey: 'tool_bad_extensions', grouped: false,
      supportsReference: false, columns: _badExtensionColumns, fieldIds: []),
  ToolSpec(id: 'bad_names', glyph: 'NAM', labelKey: 'tool_bad_names', grouped: false,
      supportsReference: false, columns: _badNameColumns, fieldIds: []),
  ToolSpec(id: 'exif_remover', glyph: 'EXIF', labelKey: 'tool_exif_remover', grouped: false,
      supportsReference: false, columns: _exifColumns, fieldIds: _exifFields),
  ToolSpec(id: 'video_optimizer', glyph: 'OPT', labelKey: 'tool_video_optimizer', grouped: false,
      supportsReference: false, columns: _optimizerColumns, fieldIds: _vidOptFields),
];

/// Registry the UI renders from. `engine/registry.rs` and `engine/options.rs` will serve the
/// same data over the bridge; until then every lookup answers from the seed tables above.
abstract final class ToolSeed {
  /// Every scanner, in the order the tool menu and the results table expect.
  static List<ToolSpec> tools() => _tools;

  static ToolSpec? spec(String id) {
    for (final ToolSpec tool in _tools) {
      if (tool.id == id) {
        return tool;
      }
    }
    return null;
  }

  /// Option metadata for one scanner, resolved through the single global field table.
  static List<FieldDef> fields(String toolId) {
    final ToolSpec? tool = spec(toolId);
    if (tool == null) {
      return const [];
    }
    final List<FieldDef> defs = [];
    for (final String id in tool.fieldIds) {
      final FieldDef? def = _fieldDef(id);
      if (def != null) {
        defs.add(def);
      }
    }
    return defs;
  }

  /// Option values a scanner starts with, in the same order as [fields].
  static List<FieldValue> defaults(String toolId) {
    final ToolSpec? tool = spec(toolId);
    if (tool == null) {
      return const [];
    }
    final List<FieldValue> values = [];
    for (final String id in tool.fieldIds) {
      final FieldValue? value = _fieldDefault(id);
      if (value != null) {
        values.add(value);
      }
    }
    return values;
  }

  static bool isGrouped(String toolId) => spec(toolId)?.grouped ?? false;

  static FieldDef? _fieldDef(String id) {
    for (final FieldDef field in _fieldDefs) {
      if (field.id == id) {
        return field;
      }
    }
    return null;
  }

  static FieldValue? _fieldDefault(String id) {
    for (final FieldValue field in _fieldDefaults) {
      if (field.id == id) {
        return field;
      }
    }
    return null;
  }
}
