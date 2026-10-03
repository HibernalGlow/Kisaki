/// Resolves the translation keys the engine hands back (`label_key`, `stage_label_key`).
///
/// The table mirrors `kisaki/i18n/en/kisaki.ftl`. Real locale switching will replace
/// [Labels.of] with a Fluent-backed lookup; callers only ever see a key.
library;

typedef LabelArgs = Map<String, Object>;

class Labels {
  const Labels._();

  static String of(String key, {LabelArgs? args}) {
    final String raw = _table[key] ?? _fallback(key);
    if (args == null || args.isEmpty) {
      return raw;
    }
    var out = raw;
    args.forEach((name, value) {
      out = out.replaceAll('{ \$$name }', '$value');
    });
    return out;
  }

  /// Unknown keys keep the scan usable: `field_dup_hash_type` reads as `Dup hash type`.
  static String _fallback(String key) {
    final List<String> parts = key.split(RegExp(r'[_-]')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return key;
    }
    final StringBuffer text = StringBuffer(parts.first.toUpperCase());
    for (final String part in parts.skip(1)) {
      text.write(' ${part[0].toUpperCase()}${part.substring(1)}');
    }
    return text.toString();
  }

  static bool knows(String key) => _table.containsKey(key);

  static const Map<String, String> _table = {
    'action-add-dirs': 'Add directories',
    'action-add-files': 'Add files',
    'action-add-manual': 'Type paths',
    'action-clear': 'Clear list',
    'action-close': 'Close',
    'action-delete': 'Delete selected',
    'action-export': 'Export results',
    'action-remove-checked': 'Remove checked',
    'action-reset-layout': 'Reset lane layout',
    'action-scan': 'Scan',
    'action-stop': 'Stop',
    'action-theme': 'Toggle theme',
    'app-title': 'Kisaki',
    'badge-reference': 'ref',
    'col-group': 'Group',
    'col-name': 'Name',
    'confirm-cancel': 'Cancel',
    'confirm-ok': 'Confirm',
    'confirm-title': 'Confirm this operation',
    'empty-done': 'Scan finished, nothing found.',
    'empty-error': 'The scan failed, please retry.',
    'empty-filtered': 'Nothing matches the current filter.',
    'empty-idle': 'Add a directory and start a scan.',
    'empty-paths': 'No directories added yet.',
    'empty-running': 'Analyzing files...',
    'empty-stopped': 'Scan stopped, no results returned.',
    'header-results': 'Result groups',
    'hint-dry-run': 'Delete and export only produce a plan while dry run is on.',
    'label-allowed-ext': 'Allowed extensions',
    'label-cache': 'Use cache',
    'label-dry-run': 'Dry run',
    'label-errors': 'Scan messages',
    'label-excluded': 'Excluded',
    'label-excluded-ext': 'Excluded extensions',
    'label-excluded-items': 'Excluded rules',
    'label-included': 'Included',
    'label-max-size': 'Maximum size (KiB)',
    'label-min-size': 'Minimum size (KiB)',
    'label-no-options': 'This scanner has no additional options.',
    'label-recursive': 'Recursive search',
    'label-reference': 'Reference folder',
    'label-trash': 'Move to trash',
    'lane-analysis': 'Analysis and actions',
    'lane-results': 'Results',
    'lane-source': 'Scan conditions',
    'metric-files': 'Files',
    'metric-groups': 'Groups',
    'metric-reclaimable': 'Reclaimable',
    'metric-selected': 'Selected',
    'metric-selected-size': 'Selected size',
    'metric-total': 'Total size',
    'placeholder-filter': 'Filter results',
    'placeholder-manual': 'Paste paths, one per line',
    'status-ready': 'Kisaki is ready.',
    'tab-algorithm': 'Algorithm',
    'tab-paths': 'Paths',
    'tool-selector': 'Scanner',
    'col_artist': 'Artist',
    'col_bitrate': 'Bitrate',
    'col_codec': 'Codec',
    'col_current_extension': 'Current extension',
    'col_destination': 'Destination',
    'col_difference': 'Difference',
    'col_duration': 'Duration',
    'col_error': 'Error',
    'col_errors': 'Errors',
    'col_genre': 'Genre',
    'col_info': 'Info',
    'col_length': 'Length',
    'col_modified': 'Modified',
    'col_new_name': 'New name',
    'col_proper_extension': 'Proper extension',
    'col_proper_group': 'Proper group',
    'col_resolution': 'Resolution',
    'col_size': 'Size',
    'col_tags': 'Tags',
    'col_title': 'Title',
    'col_year': 'Year',
    'confirm_delete_body': 'This will remove { \$count } paths ({ \$size }) for real.',
    'confirm_dry_run_body': 'Dry run: plans { \$count } paths ({ \$size }) and changes nothing.',
    'plan_files_to_delete': 'delete permanently',
    'plan_files_to_trash': 'move to trash',
    'plan_folders_to_delete': 'delete folders permanently',
    'plan_folders_to_trash': 'move folders to trash',
    'plan_header': 'Plan for { \$count } paths ({ \$size }): { \$verb }',
    'plan_more': '... and { \$count } more',
    'rust_init_error_title': 'Kisaki failed to start',
    'rust_no_included_paths': 'Add at least one included directory before scanning',
    'status_cancelled': 'Scan stopped',
    'status_deleting': 'Applying file operations...',
    'status_dry_run_only': 'Dry run only - no files were changed',
    'status_export_failed': 'Export failed: { \$error }',
    'status_exported': 'Results written to { \$folder }',
    'status_found': 'Found { \$files } files in { \$groups } groups ({ \$size })',
    'status_nothing_found': 'Scan finished, nothing found',
    'status_nothing_selected': 'Select at least one result first',
    'status_nothing_to_export': 'There are no results to export',
    'status_open_failed': 'Cannot open { \$path }: { \$error }',
    'status_paths_updated': 'Path list updated',
    'status_removed_all': 'Removed { \$count } paths',
    'status_removed_partial': 'Removed { \$removed } paths, { \$failed } failed',
    'status_scanning': 'Scanning...',
    'status_stopped': 'Scan stopped - results found so far are kept',
    'status_stopping': 'Requesting stop...',

    // Engine-supplied keys: the bridge hands back these ids, never the English text.
    'tool_bad_extensions': 'Bad extensions',
    'tool_bad_names': 'Bad names',
    'tool_big_files': 'Big files',
    'tool_broken_files': 'Broken files',
    'tool_duplicate_files': 'Duplicate files',
    'tool_duplicate_music': 'Same music',
    'tool_empty_files': 'Empty files',
    'tool_empty_folders': 'Empty folders',
    'tool_exif_remover': 'EXIF remover',
    'tool_invalid_symlinks': 'Invalid symlinks',
    'tool_similar_images': 'Similar images',
    'tool_similar_videos': 'Similar videos',
    'tool_temporary_files': 'Temporary files',
    'tool_video_optimizer': 'Video optimizer',
    'field_big_biggest_first': 'Show biggest files first',
    'field_big_number_of_files': 'Number of files',
    'field_bro_archive': 'Check archives',
    'field_bro_audio': 'Check audio',
    'field_bro_font': 'Check fonts',
    'field_bro_image': 'Check images',
    'field_bro_markup': 'Check markup',
    'field_bro_pdf': 'Check PDF',
    'field_bro_video_ffmpeg': 'Check videos with ffmpeg',
    'field_bro_video_ffprobe': 'Check videos with ffprobe',
    'field_dup_case_sensitive_names': 'Case sensitive names',
    'field_dup_check_method': 'Checking method',
    'field_dup_hash_cache_size': 'Minimal cache file size - hash (KiB)',
    'field_dup_hash_type': 'Hash algorithm',
    'field_dup_ignore_hard_links': 'Ignore hard links',
    'field_dup_prehash_cache_size': 'Minimal cache file size - prehash (KiB)',
    'field_dup_use_prehash': 'Use prehash',
    'field_emp_non_printable_content': 'Non printable content',
    'field_emp_zero_byte_content': 'Zero byte content',
    'field_exif_ignored_tags': 'Ignored EXIF tags',
    'field_img_geometric_invariance': 'Geometric invariance',
    'field_img_hash_algorithm': 'Hash algorithm',
    'field_img_hash_size': 'Hash size',
    'field_img_ignore_same_resolution': 'Ignore same resolution',
    'field_img_ignore_same_size': 'Ignore same size',
    'field_img_resize_algorithm': 'Resize algorithm',
    'field_img_similarity': 'Maximum similarity',
    'field_mus_approximate': 'Approximate comparison',
    'field_mus_artist': 'Compare artist',
    'field_mus_bitrate': 'Compare bitrate',
    'field_mus_check_type': 'Comparing method',
    'field_mus_genre': 'Compare genre',
    'field_mus_length': 'Compare length',
    'field_mus_max_difference': 'Maximum difference',
    'field_mus_min_fragment_duration': 'Minimum fragment duration (s)',
    'field_mus_title': 'Compare title',
    'field_mus_year': 'Compare year',
    'field_temp_extension_list': 'Temporary extensions',
    'field_vid_hash_duration': 'Hash duration (s)',
    'field_vid_ignore_same_size': 'Ignore same size',
    'field_vid_letterbox_crop': 'Detect letterboxing',
    'field_vid_skip_forward': 'Skip forward (s)',
    'field_vid_tolerance': 'Similarity tolerance',
    'field_vidopt_black_bar_min_percentage': 'Minimum black bar percentage',
    'field_vidopt_black_pixel_threshold': 'Black pixel threshold',
    'field_vidopt_excluded_codecs': 'Excluded codecs',
    'field_vidopt_max_samples': 'Maximum samples',
    'field_vidopt_min_crop_size': 'Minimum crop size',
    'field_vidopt_mode': 'Operation',
    'option_check_method_hash': 'Hash',
    'option_check_method_name': 'Name',
    'option_check_method_size': 'Size',
    'option_check_method_size_and_name': 'Size and name',
    'option_geometric_invariance_mirror_flip': 'Mirror and flip',
    'option_geometric_invariance_mirror_flip_rotate90': 'Mirror, flip and rotate 90',
    'option_geometric_invariance_off': 'Off',
    'option_music_method_fingerprint': 'Fingerprint',
    'option_music_method_tags': 'Tags',
    'option_similarity_high': 'High',
    'option_similarity_medium': 'Medium',
    'option_similarity_minimal': 'Minimal',
    'option_similarity_original': 'Original',
    'option_similarity_small': 'Small',
    'option_similarity_very_high': 'Very high',
    'option_similarity_very_small': 'Very small',
    'option_video_optimizer_mode_crop': 'Crop',
    'option_video_optimizer_mode_transcode': 'Transcode',

    // Keys the Flutter board needs that `kisaki/i18n/en/kisaki.ftl` does not carry yet.
    // The Flutter i18n file will own these once the app gets its own Fluent catalog.
    'action-select-all': 'Select all',
    'action-select-group': 'Select group',
  };
}
