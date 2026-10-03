/// Placeholder data source: answers the board from the [ToolSeed] tables and deterministic
/// synthetic rows so the app runs and demos before the Rust bridge lands. Never touches files.
library;

import 'dart:io';

import '../registry/tool_seed.dart';
import '../util/format.dart';
import 'kisaki_engine.dart';
import 'models.dart';

class SeedEngine implements KisakiEngine {
  SeedEngine();

  /// Percentages emitted before the result, so the progress rail visibly moves.
  static const List<int> _ticks = <int>[15, 40, 65, 90, 100];

  /// Synthetic shape: flat tools report [_flatRowsPerRoot] hits per root, grouped tools
  /// [_groupsPerRoot] sets of [_membersPerGroup].
  static const int _flatRowsPerRoot = 5;
  static const int _groupsPerRoot = 2;
  static const int _membersPerGroup = 3;

  /// Fixed epoch (2026-01-01T00:00:00Z) so repeated scans render identical dates.
  static const int _baseTs = 1767225600;

  static const Map<String, String> _extensions = <String, String>{
    'duplicate_files': 'bin',
    'empty_folders': '',
    'big_files': 'iso',
    'empty_files': '',
    'temporary_files': 'tmp',
    'similar_images': 'png',
    'similar_videos': 'mp4',
    'duplicate_music': 'flac',
    'invalid_symlinks': '',
    'broken_files': 'jpg',
    'bad_extensions': 'jpg',
    'bad_names': 'pdf',
    'exif_remover': 'jpg',
    'video_optimizer': 'mkv',
  };

  /// Scanners whose hits really carry no payload, mirrored so the metrics read sensibly.
  static const Set<String> _zeroSized = <String>{
    'empty_folders',
    'empty_files',
  };

  /// Display text per column key; only `size` and `modified` are computed from the row itself.
  static const Map<String, List<String>> _vocabulary = <String, List<String>>{
    'difference': <String>['0', '2', '5', '9', '14'],
    'resolution': <String>['1920x1080', '1280x720', '3840x2160', '854x480'],
    'duration': <String>['00:12', '01:05', '03:41', '12:07'],
    'codec': <String>['h264', 'hevc', 'av1', 'vp9', 'mpeg2'],
    'bitrate': <String>['128 kbps', '192 kbps', '256 kbps', '320 kbps'],
    'title': <String>['Track one', 'Track two', 'Track three', 'Untitled'],
    'artist': <String>['Artist a', 'Artist b', 'Unknown artist'],
    'year': <String>['1998', '2004', '2011', '2019'],
    'length': <String>['2:14', '3:02', '4:37', '5:58'],
    'genre': <String>['Rock', 'Jazz', 'Electronic', 'Ambient', 'Unknown'],
    'destination': <String>['missing target', 'moved target', 'self loop'],
    'error': <String>['No such file or directory'],
    'errors': <String>[
      'unsupported format',
      'truncated header',
      'checksum mismatch',
    ],
    'new_name': <String>['renamed_1', 'renamed_2', 'renamed_3'],
    'tags': <String>['camera, date', 'gps, date', 'none'],
    'info': <String>[
      'crop 12x0',
      'crop 0x24',
      'no black bars',
      'transcode to h264',
    ],
    'current_extension': <String>['jpg', 'png', 'mp4', 'mkv'],
    'proper_group': <String>['image', 'video', 'audio', 'archive'],
    'proper_extension': <String>['png', 'mp4', 'flac', 'zip'],
  };

  bool _scanning = false;
  bool _stopRequested = false;

  @override
  List<ToolSpec> listTools() => ToolSeed.tools();

  @override
  List<FieldDef> fieldDefs(String tool) => ToolSeed.fields(tool);

  @override
  List<FieldValue> defaultFields(String tool) => ToolSeed.defaults(tool);

  @override
  EngineInfo engineInfo() => EngineInfo(
    coreVersion: 'seed',
    apiVersion: 1,
    os: Platform.operatingSystem,
    threadLimit: Platform.numberOfProcessors,
  );

  @override
  bool isScanning() => _scanning;

  @override
  bool requestStop() {
    if (!_scanning) {
      return false;
    }
    _stopRequested = true;
    return true;
  }

  @override
  Stream<ScanEvent> startScan(ScanRequest request) async* {
    final List<String> roots = <String>[
      ...request.included,
      ...request.reference,
    ];
    if (roots.isEmpty) {
      yield const ScanEventFailed(
        'Seed scan needs at least one included or reference path',
      );
      return;
    }

    _scanning = true;
    _stopRequested = false;
    final ToolSpec? tool = ToolSeed.spec(request.tool);
    try {
      int reached = 0;
      for (final int percent in _ticks) {
        yield ScanEventProgress(
          ProgressUpdate(
            stageLabelKey: 'status_scanning',
            current: percent,
            total: 100,
            percent: percent,
            detail: 'seed ${request.tool}',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        reached = percent;
        if (_stopRequested) {
          break;
        }
      }
      final List<String> scanned = _traversed(
        roots,
        _stopRequested ? reached : 100,
      );
      final List<ScanRow> rows = _rows(request, tool, scanned);
      yield ScanEventCompleted(_outcome(request, tool, rows, _stopRequested));
    } finally {
      _scanning = false;
    }
  }

  @override
  Future<DeleteOutcome> deleteFiles(DeleteRequest request) async {
    // No file API is reached: the seed engine only reports what it would have touched.
    final List<String> log = <String>[
      for (final ScanRow row in request.rows)
        '${request.dryRun ? 'would remove' : 'removed'} ${row.path}',
    ];
    final int bytes = request.dryRun
        ? 0
        : request.rows.fold<int>(
            0,
            (int sum, ScanRow row) => sum + row.sizeBytes,
          );
    return DeleteOutcome(
      affected: request.dryRun ? 0 : request.rows.length,
      errors: 0,
      reclaimedBytes: bytes,
      messages: request.dryRun
          ? 'dry run: ${request.rows.length} seed paths planned, nothing removed'
          : 'seed engine: ${request.rows.length} paths reported as removed',
      log: log,
    );
  }

  @override
  Future<String> exportResults(ExportRequest request) async => request.path;

  /// Roots the scan got through at the reported percentage, always at least one.
  static List<String> _traversed(List<String> roots, int percent) {
    if (percent >= 100) {
      return roots;
    }
    final int taken = (roots.length * percent + 99) ~/ 100;
    return roots.sublist(0, taken < 1 ? 1 : taken);
  }

  List<ScanRow> _rows(ScanRequest request, ToolSpec? tool, List<String> roots) {
    final bool grouped = tool?.grouped ?? false;
    final bool supportsReference = tool?.supportsReference ?? false;
    final String suffix = _suffixFor(request.tool);
    final List<ScanRow> rows = <ScanRow>[];
    int counter = 0;
    int groupIndex = 0;
    for (final String root in roots) {
      final String directory = _trimSlashes(root);
      final bool isReference =
          supportsReference && request.reference.contains(root);
      if (!grouped) {
        for (int hit = 0; hit < _flatRowsPerRoot; hit++) {
          rows.add(
            _row(
              tool,
              directory,
              suffix,
              counter,
              groupIndex: -1,
              groupSize: 0,
              isGroupStart: false,
              isReference: isReference,
            ),
          );
          counter++;
        }
        continue;
      }
      for (int group = 0; group < _groupsPerRoot; group++) {
        for (int member = 0; member < _membersPerGroup; member++) {
          rows.add(
            _row(
              tool,
              directory,
              suffix,
              counter,
              groupIndex: groupIndex,
              groupSize: _membersPerGroup,
              isGroupStart: member == 0,
              isReference: isReference,
            ),
          );
          counter++;
        }
        groupIndex++;
      }
    }
    return rows;
  }

  /// One fake hit: name and metrics come from `counter`, so the same request always renders
  /// the same table.
  ScanRow _row(
    ToolSpec? tool,
    String directory,
    String suffix,
    int counter, {
    required int groupIndex,
    required int groupSize,
    required bool isGroupStart,
    required bool isReference,
  }) {
    final String name = 'seed_${counter + 1}$suffix';
    final bool empty = _zeroSized.contains(tool?.id ?? '');
    final int sizeBytes = empty
        ? 0
        : 4096 + (counter * 7919) % (8 * 1024 * 1024);
    final int modifiedTs = _baseTs + counter * 5400;
    final List<String> cells = <String>[];
    final List<int> sortKeys = <int>[];
    _fillCells(tool, counter, sizeBytes, modifiedTs, cells, sortKeys);
    return ScanRow(
      path: '$directory/$name',
      name: name,
      directory: directory,
      cells: cells,
      sizeBytes: sizeBytes,
      modifiedTs: modifiedTs,
      groupIndex: groupIndex,
      groupSize: groupSize,
      isGroupStart: isGroupStart,
      isReference: isReference,
      sortKeys: sortKeys,
    );
  }

  /// One display string and one numeric sort key per declared column, in column order.
  void _fillCells(
    ToolSpec? tool,
    int counter,
    int sizeBytes,
    int modifiedTs,
    List<String> cells,
    List<int> sortKeys,
  ) {
    for (final ColumnDef column in tool?.columns ?? const <ColumnDef>[]) {
      final String id = _columnId(column);
      switch (id) {
        case 'size':
          cells.add(humanBytes(sizeBytes));
          sortKeys.add(sizeBytes);
        case 'modified':
          cells.add(humanDate(modifiedTs));
          sortKeys.add(modifiedTs);
        default:
          final List<String> options = _vocabulary[id] ?? const <String>['-'];
          final int slot = counter % options.length;
          cells.add(options[slot]);
          sortKeys.add(slot);
      }
    }
  }

  ScanOutcome _outcome(
    ScanRequest request,
    ToolSpec? tool,
    List<ScanRow> rows,
    bool stopped,
  ) {
    final int total = rows.fold<int>(
      0,
      (int sum, ScanRow row) => sum + row.sizeBytes,
    );
    final Set<int> groups = rows
        .map((ScanRow row) => row.groupIndex)
        .where((int index) => index >= 0)
        .toSet();
    return ScanOutcome(
      tool: request.tool,
      rows: rows,
      stopped: stopped,
      grouped: tool?.grouped ?? false,
      fileCount: rows.length,
      groupCount: groups.length,
      totalBytes: total,
      reclaimableBytes: _reclaimable(rows, total, groups),
      messages: 'seed engine: synthetic rows, no files were read',
      critical: null,
    );
  }

  /// Grouped scanners keep one member per set, so only the rest counts as reclaimable.
  static int _reclaimable(List<ScanRow> rows, int total, Set<int> groups) {
    if (groups.isEmpty) {
      return total;
    }
    final Map<int, int> kept = <int, int>{};
    for (final ScanRow row in rows) {
      if (row.groupIndex < 0) {
        continue;
      }
      final int current = kept[row.groupIndex] ?? 0;
      if (row.sizeBytes > current) {
        kept[row.groupIndex] = row.sizeBytes;
      }
    }
    return total -
        kept.values.fold<int>(0, (int sum, int value) => sum + value);
  }

  static String _suffixFor(String toolId) {
    final String extension = _extensions[toolId] ?? 'dat';
    return extension.isEmpty ? '' : '.$extension';
  }

  static String _trimSlashes(String path) {
    String trimmed = path;
    while (trimmed.length > 1 && trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// The seed uses short column keys; the bridge may send the `col_*` form, so accept both.
  static String _columnId(ColumnDef column) {
    return column.key.startsWith('col_') ? column.key.substring(4) : column.key;
  }
}
