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

  FieldValue withValue(FieldPayload payload) =>
      FieldValue(id: id, value: payload);
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

/// The names the engine considers correct, applied to the two scanners that can fix them.
class RenameRequest {
  const RenameRequest({
    required this.tool,
    required this.scan,
    required this.paths,
    required this.dryRun,
  });

  final String tool;
  final ScanRequest scan;
  final List<String> paths;
  final bool dryRun;
}

enum RenameStatus { renamed, planned, failed, skipped }

class RenameItem {
  const RenameItem({
    required this.from,
    required this.to,
    required this.status,
    required this.detail,
  });

  final String from;
  final String to;
  final RenameStatus status;
  final String detail;
}

class RenameOutcome {
  const RenameOutcome({
    required this.renamed,
    required this.planned,
    required this.failed,
    required this.skipped,
    required this.items,
    required this.messages,
  });

  final int renamed;
  final int planned;
  final int failed;
  final int skipped;
  final List<RenameItem> items;
  final String messages;
}

enum MoveAction { move, copy }

enum MoveConflictPolicy { skip, overwrite, rename, error }

enum MoveStatus { moved, copied, planned, skipped, failed }

class MoveItem {
  const MoveItem({
    required this.from,
    required this.to,
    required this.status,
    required this.detail,
  });

  final String from;
  final String to;
  final MoveStatus status;
  final String detail;
}

/// Move and copy share a request because the engine decides per item, and the dry run reports the
/// same plan the real run would follow.
class MoveRequest {
  const MoveRequest({
    required this.paths,
    required this.destination,
    required this.action,
    required this.conflict,
    required this.preserveStructure,
    required this.dryRun,
  });

  final List<String> paths;
  final String destination;
  final MoveAction action;
  final MoveConflictPolicy conflict;
  final bool preserveStructure;
  final bool dryRun;
}

class MoveOutcome {
  const MoveOutcome({
    required this.moved,
    required this.copied,
    required this.planned,
    required this.skipped,
    required this.failed,
    required this.items,
    required this.messages,
  });

  final int moved;
  final int copied;
  final int planned;
  final int skipped;
  final int failed;
  final List<MoveItem> items;
  final String messages;
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

/// How a file reaches its set folder: relocated, duplicated, or a second name for the same bytes.
enum SimiuMode { move, copy, link }

/// One "put this file in that set folder" decision, as the bridge performs it.
class SimiuOperation {
  const SimiuOperation({
    required this.root,
    required this.source,
    required this.target,
  });

  /// The scanned root the set folder lives under; the bridge writes one undo journal per root.
  final String root;
  final String source;
  final String target;

  @override
  bool operator ==(Object other) =>
      other is SimiuOperation &&
      other.root == root &&
      other.source == source &&
      other.target == target;

  @override
  int get hashCode => Object.hash(root, source, target);

  @override
  String toString() => 'SimiuOperation($source -> $target in $root)';
}

class SimiuApplyRequest {
  const SimiuApplyRequest({
    required this.mode,
    required this.operations,
    required this.dryRun,
  });

  final SimiuMode mode;
  final List<SimiuOperation> operations;
  final bool dryRun;
}

/// What happened to one file, for both the apply and the undo direction.
enum SimiuStatus { planned, moved, copied, linked, restored, removed, failed }

class SimiuItem {
  const SimiuItem({
    required this.from,
    required this.to,
    required this.status,
    required this.detail,
  });

  final String from;
  final String to;
  final SimiuStatus status;
  final String detail;
}

class SimiuApplyOutcome {
  const SimiuApplyOutcome({
    required this.done,
    required this.planned,
    required this.failed,
    required this.items,
    required this.journals,
    required this.messages,
  });

  final int done;
  final int planned;
  final int failed;
  final List<SimiuItem> items;

  /// The undo journals written, newest last. Empty for a dry run.
  final List<String> journals;
  final String messages;
}

class SimiuUndoRequest {
  const SimiuUndoRequest({
    required this.journal,
    required this.cleanEmptyDirectories,
    required this.dryRun,
  });

  final String journal;

  /// Removes the set folders an apply created, as long as they are empty by then.
  final bool cleanEmptyDirectories;
  final bool dryRun;
}

class SimiuUndoOutcome {
  const SimiuUndoOutcome({
    required this.done,
    required this.planned,
    required this.failed,
    required this.items,
    required this.messages,
  });

  final int done;
  final int planned;
  final int failed;
  final List<SimiuItem> items;
  final String messages;
}
