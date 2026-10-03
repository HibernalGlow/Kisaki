/// Dart mirror of the bridge types in `rust/src/api/types.rs`.
///
/// Field names and shapes stay one-to-one with the Rust side so the generated
/// flutter_rust_bridge bindings can be adapted without touching the UI layer.
library;

enum FieldKind { flag, choice, integer, text, tokenList }

class ColumnDef {
  const ColumnDef({
    required this.key,
    required this.labelKey,
    required this.flex,
    required this.minWidth,
    required this.alignRight,
  });

  final String key;
  final String labelKey;
  final double flex;
  final double minWidth;
  final bool alignRight;
}

class ToolSpec {
  const ToolSpec({
    required this.id,
    required this.glyph,
    required this.labelKey,
    required this.grouped,
    required this.supportsReference,
    required this.columns,
    required this.fieldIds,
  });

  final String id;
  final String glyph;
  final String labelKey;

  /// Grouped scanners return sets of related rows; flat scanners return one row per hit.
  final bool grouped;
  final bool supportsReference;
  final List<ColumnDef> columns;
  final List<String> fieldIds;
}

class FieldDef {
  const FieldDef({
    required this.id,
    required this.labelKey,
    required this.kind,
    required this.options,
    required this.min,
    required this.max,
  });

  final String id;
  final String labelKey;
  final FieldKind kind;

  /// Choice labels are themselves translation keys (`option_*`).
  final List<String> options;
  final int min;
  final int max;
}

sealed class FieldPayload {
  const FieldPayload();

  FieldKind get kind;
}

final class FieldPayloadFlag extends FieldPayload {
  const FieldPayloadFlag(this.value);

  final bool value;

  @override
  FieldKind get kind => FieldKind.flag;
}

final class FieldPayloadChoice extends FieldPayload {
  const FieldPayloadChoice(this.value);

  final String value;

  @override
  FieldKind get kind => FieldKind.choice;
}

final class FieldPayloadInteger extends FieldPayload {
  const FieldPayloadInteger(this.value);

  final int value;

  @override
  FieldKind get kind => FieldKind.integer;
}

final class FieldPayloadText extends FieldPayload {
  const FieldPayloadText(this.value);

  final String value;

  @override
  FieldKind get kind => FieldKind.text;
}

final class FieldPayloadTokens extends FieldPayload {
  const FieldPayloadTokens(this.value);

  final List<String> value;

  @override
  FieldKind get kind => FieldKind.tokenList;
}

class FieldValue {
  const FieldValue({required this.id, required this.value});

  final String id;
  final FieldPayload value;

  FieldValue withValue(FieldPayload payload) => FieldValue(id: id, value: payload);
}

class ScanRequest {
  const ScanRequest({
    required this.tool,
    required this.included,
    required this.reference,
    required this.excludedPaths,
    required this.excludedItems,
    required this.allowedExtensions,
    required this.excludedExtensions,
    required this.recursive,
    required this.useCache,
    required this.minSizeKib,
    required this.maxSizeKib,
    required this.fields,
  });

  final String tool;
  final List<String> included;
  final List<String> reference;
  final List<String> excludedPaths;
  final List<String> excludedItems;
  final List<String> allowedExtensions;
  final List<String> excludedExtensions;
  final bool recursive;
  final bool useCache;

  /// Size bounds travel as text so the fields stay editable while incomplete.
  final String minSizeKib;
  final String maxSizeKib;
  final List<FieldValue> fields;

  ScanRequest copyWith({
    String? tool,
    List<String>? included,
    List<String>? reference,
    List<String>? excludedPaths,
    List<String>? excludedItems,
    List<String>? allowedExtensions,
    List<String>? excludedExtensions,
    bool? recursive,
    bool? useCache,
    String? minSizeKib,
    String? maxSizeKib,
    List<FieldValue>? fields,
  }) {
    return ScanRequest(
      tool: tool ?? this.tool,
      included: included ?? this.included,
      reference: reference ?? this.reference,
      excludedPaths: excludedPaths ?? this.excludedPaths,
      excludedItems: excludedItems ?? this.excludedItems,
      allowedExtensions: allowedExtensions ?? this.allowedExtensions,
      excludedExtensions: excludedExtensions ?? this.excludedExtensions,
      recursive: recursive ?? this.recursive,
      useCache: useCache ?? this.useCache,
      minSizeKib: minSizeKib ?? this.minSizeKib,
      maxSizeKib: maxSizeKib ?? this.maxSizeKib,
      fields: fields ?? this.fields,
    );
  }
}

class ProgressUpdate {
  const ProgressUpdate({
    required this.stageLabelKey,
    required this.current,
    required this.total,
    required this.percent,
    required this.detail,
  });

  final String stageLabelKey;
  final int current;
  final int total;

  /// -1 when the engine cannot estimate progress.
  final int percent;
  final String detail;
}

class ScanRow {
  const ScanRow({
    required this.path,
    required this.name,
    required this.directory,
    required this.cells,
    required this.sizeBytes,
    required this.modifiedTs,
    required this.groupIndex,
    required this.groupSize,
    required this.isGroupStart,
    required this.isReference,
    required this.sortKeys,
  });

  final String path;
  final String name;
  final String directory;

  /// Extra cells aligned with `ToolSpec.columns`, already formatted for display.
  final List<String> cells;
  final int sizeBytes;
  final int modifiedTs;
  final int groupIndex;
  final int groupSize;
  final bool isGroupStart;
  final bool isReference;

  /// Numeric sort keys aligned with `cells`, so Dart sorts without parsing display text.
  final List<int> sortKeys;
}

class ScanOutcome {
  const ScanOutcome({
    required this.tool,
    required this.rows,
    required this.stopped,
    required this.grouped,
    required this.fileCount,
    required this.groupCount,
    required this.totalBytes,
    required this.reclaimableBytes,
    required this.messages,
    required this.critical,
  });

  final String tool;
  final List<ScanRow> rows;
  final bool stopped;
  final bool grouped;
  final int fileCount;
  final int groupCount;
  final int totalBytes;
  final int reclaimableBytes;
  final String messages;
  final String? critical;
}

sealed class ScanEvent {
  const ScanEvent();
}

final class ScanEventProgress extends ScanEvent {
  const ScanEventProgress(this.progress);

  final ProgressUpdate progress;
}

final class ScanEventCompleted extends ScanEvent {
  const ScanEventCompleted(this.outcome);

  final ScanOutcome outcome;
}

final class ScanEventFailed extends ScanEvent {
  const ScanEventFailed(this.error);

  final String error;
}

class DeleteRequest {
  const DeleteRequest({
    required this.tool,
    required this.rows,
    required this.deleteToTrash,
    required this.dryRun,
  });

  final String tool;
  final List<ScanRow> rows;
  final bool deleteToTrash;
  final bool dryRun;
}

class DeleteOutcome {
  const DeleteOutcome({
    required this.affected,
    required this.errors,
    required this.reclaimedBytes,
    required this.messages,
    required this.log,
  });

  final int affected;
  final int errors;
  final int reclaimedBytes;
  final String messages;
  final List<String> log;
}

class ExportRequest {
  const ExportRequest({
    required this.tool,
    required this.rows,
    required this.path,
    required this.format,
    required this.grouped,
  });

  final String tool;
  final List<ScanRow> rows;
  final String path;
  final String format;
  final bool grouped;
}

class EngineInfo {
  const EngineInfo({
    required this.coreVersion,
    required this.apiVersion,
    required this.os,
    required this.threadLimit,
  });

  final String coreVersion;
  final int apiVersion;
  final String os;
  final int threadLimit;
}
