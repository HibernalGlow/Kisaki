import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/l10n/labels.dart';

/// The engine hands back translation keys, and an unknown key renders as a humanised id
/// ('field_never_authored' -> 'Field never authored'), which a plain `of() != key` check can
/// never catch. So this test asserts membership in the table itself, with the exact spelling
/// the catalog uses: hyphens for board keys, underscores for engine keys.
void main() {
  const List<String> boardKeys = <String>[
    'action-add-dirs',
    'action-add-files',
    'action-add-manual',
    'action-clear',
    'action-close',
    'action-delete',
    'action-export',
    'action-remove-checked',
    'action-reset-layout',
    'action-scan',
    'action-select-all',
    'action-select-group',
    'action-stop',
    'action-theme',
    'app-title',
    'badge-reference',
    'col-group',
    'col-name',
    'confirm-cancel',
    'confirm-ok',
    'confirm-title',
    'empty-done',
    'empty-error',
    'empty-filtered',
    'empty-idle',
    'empty-paths',
    'empty-running',
    'empty-stopped',
    'header-results',
    'hint-dry-run',
    'label-allowed-ext',
    'label-cache',
    'label-dry-run',
    'label-errors',
    'label-excluded',
    'label-excluded-ext',
    'label-excluded-items',
    'label-included',
    'label-max-size',
    'label-min-size',
    'label-no-options',
    'label-recursive',
    'label-reference',
    'label-trash',
    'lane-analysis',
    'lane-results',
    'lane-source',
    'metric-files',
    'metric-groups',
    'metric-reclaimable',
    'metric-selected',
    'metric-selected-size',
    'metric-total',
    'placeholder-filter',
    'placeholder-manual',
    'status-ready',
    'tab-algorithm',
    'tab-paths',
    'tool-selector',
  ];

  const List<String> engineKeys = <String>[
    'confirm_delete_body',
    'confirm_delete_title',
    'confirm_dry_run_body',
    'plan_files_to_delete',
    'plan_files_to_trash',
    'plan_folders_to_delete',
    'plan_folders_to_trash',
    'plan_header',
    'plan_more',
    'rust_no_included_paths',
    'status_cancelled',
    'status_deleting',
    'status_dry_run_only',
    'status_export_failed',
    'status_exported',
    'status_found',
    'status_nothing_found',
    'status_nothing_selected',
    'status_nothing_to_export',
    'status_removed_all',
    'status_removed_partial',
    'status_scanning',
    'status_stopped',
    'status_stopping',
    'col_artist',
    'col_bitrate',
    'col_codec',
    'col_current_extension',
    'col_destination',
    'col_difference',
    'col_duration',
    'col_error',
    'col_errors',
    'col_genre',
    'col_info',
    'col_length',
    'col_modified',
    'col_new_name',
    'col_proper_extension',
    'col_proper_group',
    'col_resolution',
    'col_size',
    'col_tags',
    'col_title',
    'col_year',
    'tool_bad_extensions',
    'tool_bad_names',
    'tool_big_files',
    'tool_broken_files',
    'tool_duplicate_files',
    'tool_duplicate_music',
    'tool_empty_files',
    'tool_empty_folders',
    'tool_exif_remover',
    'tool_invalid_symlinks',
    'tool_similar_images',
    'tool_similar_videos',
    'tool_temporary_files',
    'tool_video_optimizer',
    'option_check_method_hash',
    'option_check_method_name',
    'option_check_method_size',
    'option_check_method_size_and_name',
    'option_geometric_invariance_mirror_flip',
    'option_geometric_invariance_mirror_flip_rotate90',
    'option_geometric_invariance_off',
    'option_music_method_fingerprint',
    'option_music_method_tags',
    'option_similarity_high',
    'option_similarity_medium',
    'option_similarity_minimal',
    'option_similarity_original',
    'option_similarity_small',
    'option_similarity_very_high',
    'option_similarity_very_small',
    'option_video_optimizer_mode_crop',
    'option_video_optimizer_mode_transcode',
  ];

  test('every board key the widgets ask for is in the catalog', () {
    for (final String key in boardKeys) {
      expect(Labels.knows(key), isTrue, reason: '$key missing from Labels');
    }
  });

  test('every engine-supplied key is in the catalog', () {
    for (final String key in engineKeys) {
      expect(Labels.knows(key), isTrue, reason: '$key missing from Labels');
    }
  });

  test('the gate sees a violation: a renamed key is reported as missing', () {
    expect(Labels.knows('action-scanned'), isFalse);
    expect(Labels.knows('col_sizes'), isFalse);
    expect(Labels.knows('status-scaning'), isFalse);
  });

  test('status placeholders are substituted, never shown raw', () {
    expect(
      Labels.of(
        'status_found',
        args: <String, Object>{'files': 3, 'groups': 2, 'size': '1.5 MiB'},
      ),
      'Found 3 files in 2 groups (1.5 MiB)',
    );
    expect(
      Labels.of(
        'plan_header',
        args: <String, Object>{
          'count': 4,
          'size': '9 B',
          'verb': 'move to trash',
        },
      ),
      'Plan for 4 paths (9 B): move to trash',
    );
    expect(
      Labels.of(
        'confirm_delete_body',
        args: <String, Object>{'count': 1, 'size': '1 B'},
      ),
      'This will remove 1 paths (1 B) for real.',
    );
    expect(Labels.of('status_scanning'), 'Scanning...');
    expect(
      Labels.of('status_scanning', args: <String, Object>{'ignored': 1}),
      'Scanning...',
    );
  });

  test('an unknown key still reads as a label, not as the raw id', () {
    expect(Labels.of('field_never_authored'), 'Field Never Authored');
    expect(Labels.knows('field_never_authored'), isFalse);
  });
}
