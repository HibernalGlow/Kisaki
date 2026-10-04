import 'dart:async';

import 'package:kisaki_app/engine/kisaki_engine.dart';
import 'package:kisaki_app/engine/models.dart';

const ColumnDef sizeColumn = ColumnDef(
  key: 'size',
  labelKey: 'col_size',
  flex: 0.5,
  minWidth: 84,
  alignRight: true,
);

const ColumnDef modifiedColumn = ColumnDef(
  key: 'modified',
  labelKey: 'col_modified',
  flex: 1,
  minWidth: 140,
  alignRight: false,
);

const List<ToolSpec> stubTools = <ToolSpec>[
  ToolSpec(
    id: 'duplicate_files',
    glyph: 'D',
    labelKey: 'tool_duplicate_files',
    grouped: true,
    supportsReference: true,
    columns: <ColumnDef>[sizeColumn, modifiedColumn],
    fieldIds: <String>[
      'dup_use_prehash',
      'dup_hash_type',
      'dup_prehash_cache_size',
    ],
  ),
  ToolSpec(
    id: 'big_files',
    glyph: 'B',
    labelKey: 'tool_big_files',
    grouped: false,
    supportsReference: false,
    columns: <ColumnDef>[sizeColumn, modifiedColumn],
    fieldIds: <String>['big_number_of_files'],
  ),
];

const List<FieldDef> stubFields = <FieldDef>[
  FieldDef(
    id: 'dup_use_prehash',
    labelKey: 'field_dup_use_prehash',
    kind: FieldKind.flag,
    options: <String>[],
    min: 0,
    max: 0,
  ),
  FieldDef(
    id: 'dup_hash_type',
    labelKey: 'field_dup_hash_type',
    kind: FieldKind.choice,
    options: <String>['option_check_method_hash', 'option_check_method_name'],
    min: 0,
    max: 0,
  ),
  FieldDef(
    id: 'dup_prehash_cache_size',
    labelKey: 'field_dup_prehash_cache_size',
    kind: FieldKind.integer,
    options: <String>[],
    min: 0,
    max: 100000,
  ),
];

const List<FieldValue> stubValues = <FieldValue>[
  FieldValue(id: 'dup_use_prehash', value: FieldPayloadFlag(true)),
  FieldValue(
    id: 'dup_hash_type',
    value: FieldPayloadChoice('option_check_method_hash'),
  ),
  FieldValue(id: 'dup_prehash_cache_size', value: FieldPayloadInteger(256)),
];

/// Scriptable stand-in for the Rust bridge: the tests decide every engine reply.
class StubEngine implements KisakiEngine {
  StubEngine({
    List<ToolSpec>? tools,
    List<FieldDef>? fields,
    List<FieldValue>? defaults,
  }) : tools = tools ?? stubTools,
       _fields = fields ?? stubFields,
       _defaults = defaults ?? stubValues;

  final List<ToolSpec> tools;
  final List<FieldDef> _fields;
  final List<FieldValue> _defaults;

  final List<ScanRequest> requests = <ScanRequest>[];
  final List<StreamController<ScanEvent>> streams =
      <StreamController<ScanEvent>>[];
  final List<DeleteRequest> deletes = <DeleteRequest>[];
  final List<ExportRequest> exports = <ExportRequest>[];

  int stopRequests = 0;
  bool scanningFlag = false;
  DeleteOutcome deleteOutcome = const DeleteOutcome(
    affected: 0,
    errors: 0,
    reclaimedBytes: 0,
    messages: '',
    log: <String>[],
  );
  String exportFolder = '/tmp/kisaki';
  Exception? deleteFailure;
  Exception? exportFailure;

  StreamController<ScanEvent> get lastStream => streams.last;

  @override
  List<ToolSpec> listTools() => tools;

  @override
  List<FieldDef> fieldDefs(String tool) => _fields;

  @override
  List<FieldValue> defaultFields(String tool) => _defaults;

  @override
  EngineInfo engineInfo() => const EngineInfo(
    coreVersion: '12.0.2',
    apiVersion: 1,
    os: 'macos',
    threadLimit: 8,
  );

  /// The three decoders the stub claims. A test flips them to prove the caption follows the flags.
  bool heifBuild = true;
  bool rawBuild = false;
  bool avifBuild = true;

  @override
  CodecInfo codecInfo() => CodecInfo(
    heif: heifBuild,
    libraw: rawBuild,
    libavif: avifBuild,
    diagnostic: 'Kisaki stub build',
  );

  @override
  Stream<ScanEvent> startScan(ScanRequest request) {
    requests.add(request);
    scanningFlag = true;
    final StreamController<ScanEvent> controller =
        StreamController<ScanEvent>();
    streams.add(controller);
    return controller.stream;
  }

  @override
  bool requestStop() {
    stopRequests++;
    return true;
  }

  @override
  bool isScanning() => scanningFlag;

  @override
  Future<DeleteOutcome> deleteFiles(DeleteRequest request) async {
    deletes.add(request);
    if (deleteFailure != null) {
      throw deleteFailure!;
    }
    return deleteOutcome;
  }

  final List<RenameRequest> renames = <RenameRequest>[];
  final List<MoveRequest> moves = <MoveRequest>[];
  RenameOutcome renameOutcome = const RenameOutcome(
    renamed: 0,
    planned: 0,
    failed: 0,
    skipped: 0,
    items: <RenameItem>[],
    messages: '',
  );
  MoveOutcome moveOutcome = const MoveOutcome(
    moved: 0,
    copied: 0,
    planned: 0,
    skipped: 0,
    failed: 0,
    items: <MoveItem>[],
    messages: '',
  );

  @override
  Future<RenameOutcome> renameFiles(RenameRequest request) async {
    renames.add(request);
    return renameOutcome;
  }

  @override
  Future<MoveOutcome> moveFiles(MoveRequest request) async {
    moves.add(request);
    return moveOutcome;
  }

  final List<SimiuApplyRequest> simiuApplies = <SimiuApplyRequest>[];
  final List<SimiuUndoRequest> simiuUndos = <SimiuUndoRequest>[];
  SimiuApplyOutcome simiuApplyOutcome = const SimiuApplyOutcome(
    done: 0,
    planned: 0,
    failed: 0,
    items: <SimiuItem>[],
    journals: <String>[],
    messages: '',
  );
  SimiuUndoOutcome simiuUndoOutcome = const SimiuUndoOutcome(
    done: 0,
    planned: 0,
    failed: 0,
    items: <SimiuItem>[],
    messages: '',
  );

  @override
  Future<SimiuApplyOutcome> applySimiuSet(SimiuApplyRequest request) async {
    simiuApplies.add(request);
    return simiuApplyOutcome;
  }

  @override
  Future<SimiuUndoOutcome> undoSimiuSet(SimiuUndoRequest request) async {
    simiuUndos.add(request);
    return simiuUndoOutcome;
  }

  final List<ExifRequest> exifCalls = <ExifRequest>[];
  ExifOutcome exifOutcome = const ExifOutcome(
    stripped: 0,
    candidates: 0,
    planned: 0,
    skipped: 0,
    failed: 0,
    items: <ExifItem>[],
    messages: '',
  );

  @override
  Future<ExifOutcome> cleanExif(ExifRequest request) async {
    exifCalls.add(request);
    return exifOutcome;
  }

  final List<OptimizeRequest> optimizeCalls = <OptimizeRequest>[];
  OptimizeOutcome optimizeOutcome = const OptimizeOutcome(
    transcoded: 0,
    cropped: 0,
    planned: 0,
    skipped: 0,
    failed: 0,
    items: <OptimizeItem>[],
    messages: '',
  );

  @override
  Future<OptimizeOutcome> optimizeVideos(OptimizeRequest request) async {
    optimizeCalls.add(request);
    return optimizeOutcome;
  }

  @override
  Future<String> exportResults(ExportRequest request) async {
    exports.add(request);
    if (exportFailure != null) {
      throw exportFailure!;
    }
    return exportFolder;
  }

  void emit(ScanEvent event) => lastStream.add(event);

  void emitTo(StreamController<ScanEvent> controller, ScanEvent event) =>
      controller.add(event);

  Future<void> closeLast() => lastStream.close();

  static ScanRow row(
    String path, {
    int size = 1024,
    int group = -1,
    bool start = false,
    bool reference = false,
  }) {
    final int slash = path.lastIndexOf('/');
    final int backslash = path.lastIndexOf(r'\');
    final int cut = slash > backslash ? slash : backslash;
    return ScanRow(
      path: path,
      name: cut < 0 ? path : path.substring(cut + 1),
      directory: cut < 0 ? '' : path.substring(0, cut),
      cells: <String>['${size}B', '2026-01-02'],
      sizeBytes: size,
      modifiedTs: 1700000000,
      groupIndex: group,
      groupSize: group < 0 ? 0 : 2,
      isGroupStart: start,
      isReference: reference,
      sortKeys: <int>[size, 1700000000],
    );
  }

  static ScanOutcome outcome(
    String tool,
    List<ScanRow> rows, {
    bool stopped = false,
  }) => ScanOutcome(
    tool: tool,
    rows: rows,
    stopped: stopped,
    grouped: rows.any((ScanRow row) => row.groupIndex >= 0),
    fileCount: rows.length,
    groupCount: rows.map((ScanRow row) => row.groupIndex).toSet().length,
    totalBytes: rows.fold<int>(
      0,
      (int sum, ScanRow row) => sum + row.sizeBytes,
    ),
    reclaimableBytes: rows.fold<int>(
      0,
      (int sum, ScanRow row) => sum + row.sizeBytes,
    ),
    messages: 'warning: skipped 1 unreadable path',
    critical: null,
  );
}
