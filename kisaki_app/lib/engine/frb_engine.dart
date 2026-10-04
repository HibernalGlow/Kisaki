import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Int64List;

import '../src/rust/api/actions.dart' as g_actions;
import '../src/rust/api/info.dart' as g_info;
import '../src/rust/api/scan.dart' as g_scan;
import '../src/rust/api/schema.dart' as g_schema;
import '../src/rust/api/types.dart' as g;
import 'kisaki_engine.dart';
import 'models.dart' as m;

/// Forwards the board's engine seam onto the generated bindings.
///
/// The generated and hand-written models share names but are different types, so every call
/// crosses a conversion here rather than leaking `lib/src/rust` into the widgets.
class FrbEngine implements KisakiEngine {
  const FrbEngine();

  @override
  List<m.ToolSpec> listTools() => g_schema.listTools().map(_tool).toList();

  @override
  List<m.FieldDef> fieldDefs(String tool) =>
      g_schema.fieldDefs(tool: tool).map(_field).toList();

  @override
  List<m.FieldValue> defaultFields(String tool) =>
      g_schema.defaultFields(tool: tool).map(_storedField).toList();

  @override
  m.EngineInfo engineInfo() {
    final g.EngineInfo info = g_info.engineInfo();
    return m.EngineInfo(
      coreVersion: info.coreVersion,
      apiVersion: info.apiVersion,
      os: info.os,
      threadLimit: info.threadLimit,
    );
  }

  @override
  m.CodecInfo codecInfo() {
    final g.CodecInfo info = g_info.codecInfo();
    return m.CodecInfo(
      heif: info.heifBuild,
      libraw: info.librawBuild,
      libavif: info.libavifBuild,
      diagnostic: info.diagnostic,
    );
  }

  @override
  Stream<m.ScanEvent> startScan(m.ScanRequest request) =>
      g_scan.startScan(request: _scanRequest(request)).map(_event);

  @override
  bool requestStop() => g_scan.requestStop();

  @override
  bool isScanning() => g_scan.isScanning();

  @override
  Future<m.DeleteOutcome> deleteFiles(m.DeleteRequest request) async {
    final g.DeleteOutcome outcome = await g_actions.deleteFiles(
      request: _deleteRequest(request),
    );
    return m.DeleteOutcome(
      affected: outcome.affected,
      errors: outcome.errors,
      reclaimedBytes: outcome.reclaimedBytes,
      messages: outcome.messages,
      log: outcome.log,
    );
  }

  @override
  Future<String> exportResults(m.ExportRequest request) =>
      g_actions.exportResults(request: _exportRequest(request));

  @override
  Future<m.RenameOutcome> renameFiles(m.RenameRequest request) async {
    final g.RenameOutcome outcome = await g_actions.renameFiles(
      request: g.RenameRequest(
        tool: request.tool,
        scan: _scanRequest(request.scan),
        paths: request.paths,
        dryRun: request.dryRun,
      ),
    );
    return m.RenameOutcome(
      renamed: outcome.renamed,
      planned: outcome.planned,
      failed: outcome.failed,
      skipped: outcome.skipped,
      messages: outcome.messages,
      items: outcome.items.map(_renameItem).toList(),
    );
  }

  @override
  Future<m.MoveOutcome> moveFiles(m.MoveRequest request) async {
    final g.MoveOutcome outcome = await g_actions.moveFiles(
      request: g.MoveRequest(
        paths: request.paths,
        destination: request.destination,
        action: g.MoveAction.values[request.action.index],
        conflict: g.ConflictPolicy.values[request.conflict.index],
        preserveStructure: request.preserveStructure,
        dryRun: request.dryRun,
      ),
    );
    return m.MoveOutcome(
      moved: outcome.moved,
      copied: outcome.copied,
      planned: outcome.planned,
      skipped: outcome.skipped,
      failed: outcome.failed,
      messages: outcome.messages,
      items: outcome.items.map(_moveItem).toList(),
    );
  }

  m.RenameItem _renameItem(g.RenameItem item) => m.RenameItem(
    from: item.from,
    to: item.to,
    detail: item.detail,
    status: m.RenameStatus.values[item.status.index],
  );

  m.MoveItem _moveItem(g.MoveItem item) => m.MoveItem(
    from: item.from,
    to: item.to,
    detail: item.detail,
    status: m.MoveStatus.values[item.status.index],
  );

  @override
  Future<m.SimiuApplyOutcome> applySimiuSet(m.SimiuApplyRequest request) async {
    final g.SimiuApplyOutcome outcome = await g_actions.applySimiuSet(
      request: g.SimiuApplyRequest(
        mode: g.SimiuMode.values[request.mode.index],
        operations: request.operations
            .map(
              (m.SimiuOperation operation) => g.SimiuOperation(
                root: operation.root,
                source: operation.source,
                target: operation.target,
              ),
            )
            .toList(),
        dryRun: request.dryRun,
      ),
    );
    return m.SimiuApplyOutcome(
      done: outcome.done,
      planned: outcome.planned,
      failed: outcome.failed,
      items: outcome.items.map(_simiuItem).toList(),
      journals: outcome.journals,
      messages: outcome.messages,
    );
  }

  @override
  Future<m.SimiuUndoOutcome> undoSimiuSet(m.SimiuUndoRequest request) async {
    final g.SimiuUndoOutcome outcome = await g_actions.undoSimiuSet(
      request: g.SimiuUndoRequest(
        journal: request.journal,
        cleanEmptyDirectories: request.cleanEmptyDirectories,
        dryRun: request.dryRun,
      ),
    );
    return m.SimiuUndoOutcome(
      done: outcome.done,
      planned: outcome.planned,
      failed: outcome.failed,
      items: outcome.items.map(_simiuItem).toList(),
      messages: outcome.messages,
    );
  }

  m.SimiuItem _simiuItem(g.SimiuItem item) => m.SimiuItem(
    from: item.from,
    to: item.to,
    detail: item.detail,
    status: m.SimiuStatus.values[item.status.index],
  );

  @override
  Future<m.OptimizeOutcome> optimizeVideos(m.OptimizeRequest request) async {
    final g.OptimizeOutcome outcome = await g_actions.optimizeVideos(
      request: g.OptimizeRequest(
        scan: _scanRequest(request.scan),
        paths: request.paths,
        transcode: request.transcode == null
            ? null
            : _transcode(request.transcode!),
        crop: request.crop == null ? null : _crop(request.crop!),
        dryRun: request.dryRun,
      ),
    );
    return m.OptimizeOutcome(
      transcoded: outcome.transcoded,
      cropped: outcome.cropped,
      planned: outcome.planned,
      skipped: outcome.skipped,
      failed: outcome.failed,
      messages: outcome.messages,
      items: outcome.items
          .map(
            (g.OptimizeItem item) => m.OptimizeItem(
              path: item.path,
              target: item.target,
              detail: item.detail,
              sizeBefore: item.sizeBefore,
              sizeAfter: item.sizeAfter,
              status: m.OptimizeStatus.values[item.status.index],
            ),
          )
          .toList(),
    );
  }

  g.TranscodeOptions _transcode(m.TranscodeOptions options) =>
      g.TranscodeOptions(
        codec: options.codec,
        hardwareEncoder: options.hardwareEncoder,
        quality: options.quality,
        failIfNotSmaller: options.failIfNotSmaller,
        overwriteOriginal: options.overwriteOriginal,
        limitVideoSize: options.limitVideoSize,
        maxWidth: options.maxWidth,
        maxHeight: options.maxHeight,
        noiseReduction: options.noiseReduction,
        noiseReductionStrength: options.noiseReductionStrength,
        customFfmpegCommand: options.customFfmpegCommand,
      );

  g.CropOptions _crop(m.CropOptions options) => g.CropOptions(
    overwriteOriginal: options.overwriteOriginal,
    targetCodec: options.targetCodec,
    quality: options.quality,
  );

  @override
  Future<m.ExifOutcome> cleanExif(m.ExifRequest request) async {
    final g.ExifOutcome outcome = await g_actions.cleanExif(
      request: g.ExifRequest(
        scan: _scanRequest(request.scan),
        paths: request.paths,
        overrideFile: request.overrideFile,
        dryRun: request.dryRun,
      ),
    );
    return m.ExifOutcome(
      stripped: outcome.stripped,
      candidates: outcome.candidates,
      planned: outcome.planned,
      skipped: outcome.skipped,
      failed: outcome.failed,
      messages: outcome.messages,
      items: outcome.items
          .map(
            (g.ExifItem item) => m.ExifItem(
              path: item.path,
              target: item.target,
              tagsRemoved: item.tagsRemoved,
              detail: item.detail,
              status: m.ExifStatus.values[item.status.index],
            ),
          )
          .toList(),
    );
  }

  m.ToolSpec _tool(g.ToolSpec spec) => m.ToolSpec(
    id: spec.id,
    glyph: spec.glyph,
    labelKey: spec.labelKey,
    grouped: spec.grouped,
    supportsReference: spec.supportsReference,
    columns: spec.columns
        .map(
          (column) => m.ColumnDef(
            key: column.key,
            labelKey: column.labelKey,
            flex: column.flex,
            minWidth: column.minWidth,
            alignRight: column.alignRight,
          ),
        )
        .toList(),
    fieldIds: spec.fieldIds,
  );

  m.FieldDef _field(g.FieldDef def) => m.FieldDef(
    id: def.id,
    labelKey: def.labelKey,
    kind: switch (def.kind) {
      g.FieldKind.flag => m.FieldKind.flag,
      g.FieldKind.choice => m.FieldKind.choice,
      g.FieldKind.integer => m.FieldKind.integer,
      g.FieldKind.text => m.FieldKind.text,
      g.FieldKind.tokenList => m.FieldKind.tokenList,
    },
    options: def.options,
    min: def.min,
    max: def.max,
  );

  m.FieldValue _storedField(g.FieldValue value) =>
      m.FieldValue(id: value.id, value: _payload(value.value));

  m.FieldPayload _payload(g.FieldPayload payload) => switch (payload) {
    g.FieldPayload_Flag(:final field0) => m.FieldPayloadFlag(field0),
    g.FieldPayload_Choice(:final field0) => m.FieldPayloadChoice(field0),
    g.FieldPayload_Integer(:final field0) => m.FieldPayloadInteger(
      field0.toInt(),
    ),
    g.FieldPayload_Text(:final field0) => m.FieldPayloadText(field0),
    g.FieldPayload_Tokens(:final field0) => m.FieldPayloadTokens(field0),
  };

  g.FieldPayload _toPayload(m.FieldPayload payload) => switch (payload) {
    m.FieldPayloadFlag(:final value) => g.FieldPayload.flag(value),
    m.FieldPayloadChoice(:final value) => g.FieldPayload.choice(value),
    m.FieldPayloadInteger(:final value) => g.FieldPayload.integer(value),
    m.FieldPayloadText(:final value) => g.FieldPayload.text(value),
    m.FieldPayloadTokens(:final value) => g.FieldPayload.tokens(value),
  };

  g.ScanRequest _scanRequest(m.ScanRequest request) => g.ScanRequest(
    tool: request.tool,
    included: request.included,
    reference: request.reference,
    excludedPaths: request.excludedPaths,
    excludedItems: request.excludedItems,
    allowedExtensions: request.allowedExtensions,
    excludedExtensions: request.excludedExtensions,
    recursive: request.recursive,
    useCache: request.useCache,
    minSizeKib: request.minSizeKib,
    maxSizeKib: request.maxSizeKib,
    fields: request.fields.map(_toStored).toList(),
  );

  g.FieldValue _toStored(m.FieldValue value) =>
      g.FieldValue(id: value.id, value: _toPayload(value.value));

  g.ScanRow _row(m.ScanRow row) => g.ScanRow(
    path: row.path,
    name: row.name,
    directory: row.directory,
    cells: row.cells,
    sizeBytes: row.sizeBytes,
    modifiedTs: row.modifiedTs,
    groupIndex: row.groupIndex,
    groupSize: row.groupSize,
    isGroupStart: row.isGroupStart,
    isReference: row.isReference,
    sortKeys: Int64List.fromList(row.sortKeys),
  );

  m.ScanRow _fromRow(g.ScanRow row) => m.ScanRow(
    path: row.path,
    name: row.name,
    directory: row.directory,
    cells: row.cells,
    sizeBytes: row.sizeBytes,
    modifiedTs: row.modifiedTs,
    groupIndex: row.groupIndex,
    groupSize: row.groupSize,
    isGroupStart: row.isGroupStart,
    isReference: row.isReference,
    sortKeys: row.sortKeys.map((value) => value.toInt()).toList(),
  );

  g.DeleteRequest _deleteRequest(m.DeleteRequest request) => g.DeleteRequest(
    tool: request.tool,
    rows: request.rows.map(_row).toList(),
    deleteToTrash: request.deleteToTrash,
    dryRun: request.dryRun,
  );

  g.ExportRequest _exportRequest(m.ExportRequest request) => g.ExportRequest(
    tool: request.tool,
    rows: request.rows.map(_row).toList(),
    path: request.path,
    format: request.format,
    grouped: request.grouped,
  );

  m.ScanEvent _event(g.ScanEvent event) => switch (event) {
    g.ScanEvent_Progress(:final field0) => m.ScanEventProgress(
      _progress(field0),
    ),
    g.ScanEvent_Completed(:final field0) => m.ScanEventCompleted(
      _outcome(field0),
    ),
    g.ScanEvent_Failed(:final field0) => m.ScanEventFailed(field0),
  };

  m.ProgressUpdate _progress(g.ProgressUpdate update) => m.ProgressUpdate(
    stageLabelKey: update.stageLabelKey,
    current: update.current,
    total: update.total,
    percent: update.percent,
    detail: update.detail,
  );

  m.ScanOutcome _outcome(g.ScanOutcome outcome) => m.ScanOutcome(
    tool: outcome.tool,
    rows: outcome.rows.map(_fromRow).toList(),
    stopped: outcome.stopped,
    grouped: outcome.grouped,
    fileCount: outcome.fileCount,
    groupCount: outcome.groupCount,
    totalBytes: outcome.totalBytes,
    reclaimableBytes: outcome.reclaimableBytes,
    messages: outcome.messages,
    critical: outcome.critical,
  );
}
