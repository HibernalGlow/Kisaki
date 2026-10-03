import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show Int64List;

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
  List<m.FieldDef> fieldDefs(String tool) => g_schema.fieldDefs(tool: tool).map(_field).toList();

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
  Stream<m.ScanEvent> startScan(m.ScanRequest request) =>
      g_scan.startScan(request: _scanRequest(request)).map(_event);

  @override
  bool requestStop() => g_scan.requestStop();

  @override
  bool isScanning() => g_scan.isScanning();

  @override
  Future<m.DeleteOutcome> deleteFiles(m.DeleteRequest request) async {
    final g.DeleteOutcome outcome = await g_actions.deleteFiles(request: _deleteRequest(request));
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

  m.ToolSpec _tool(g.ToolSpec spec) => m.ToolSpec(
    id: spec.id,
    glyph: spec.glyph,
    labelKey: spec.labelKey,
    grouped: spec.grouped,
    supportsReference: spec.supportsReference,
    columns: spec.columns
        .map((column) => m.ColumnDef(
          key: column.key,
          labelKey: column.labelKey,
          flex: column.flex,
          minWidth: column.minWidth,
          alignRight: column.alignRight,
        ))
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
    g.FieldPayload_Integer(:final field0) => m.FieldPayloadInteger(field0.toInt()),
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
    g.ScanEvent_Progress(:final field0) => m.ScanEventProgress(_progress(field0)),
    g.ScanEvent_Completed(:final field0) => m.ScanEventCompleted(_outcome(field0)),
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

