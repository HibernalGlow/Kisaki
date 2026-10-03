import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/kisaki_engine.dart';
import '../engine/models.dart';
import '../l10n/labels.dart';
import '../util/format.dart';
import 'row_projection.dart';

export 'row_projection.dart' show GroupSelection;

enum ScanPhase { idle, running, stopping, finished, failed }

/// A pending destructive action, shown by the confirm overlay before it runs.
class ConfirmRequest {
  const ConfirmRequest({
    required this.titleKey,
    required this.bodyKey,
    required this.args,
    required this.dryRun,
  });

  final String titleKey;
  final String bodyKey;
  final Map<String, Object> args;
  final bool dryRun;
}

class LaneLayout {
  LaneLayout();

  static const double sourceDefault = 300;
  static const double resultsDefault = 420;

  double sourceWidth = sourceDefault;
  double resultsWidth = resultsDefault;
  bool sourceCollapsed = false;
  bool resultsCollapsed = false;
  bool analysisCollapsed = false;

  void reset() {
    sourceWidth = sourceDefault;
    resultsWidth = resultsDefault;
    sourceCollapsed = false;
    resultsCollapsed = false;
    analysisCollapsed = false;
  }
}

/// Single source of truth for the board, mirroring `src/state.rs` `AppStore`.
///
/// The table renders [visibleRows]; selection is keyed by path so it survives re-sorting
/// and filtering, and a UI index never addresses the canonical rows directly.
class BoardController extends ChangeNotifier {
  BoardController({required this.engine, this.dark = true}) {
    _tools = engine.listTools();
    _info = engine.engineInfo();
    if (_tools.isNotEmpty) {
      _applyTool(_tools.first.id);
    }
  }

  final KisakiEngine engine;
  bool dark;
  LaneLayout layout = LaneLayout();

  EngineInfo? _info;
  List<ToolSpec> _tools = <ToolSpec>[];
  ToolSpec? _tool;
  List<FieldDef> _fields = <FieldDef>[];
  final Map<String, FieldValue> _values = <String, FieldValue>{};

  final List<String> _included = <String>[];
  final List<String> _reference = <String>[];
  final List<String> _excludedPaths = <String>[];
  final List<String> _excludedItems = <String>[];
  final List<String> _allowedExtensions = <String>[];
  final List<String> _excludedExtensions = <String>[];
  bool recursive = true;
  bool useCache = true;
  String minSizeKib = '';
  String maxSizeKib = '';
  bool dryRun = true;
  bool moveToTrash = true;

  ScanPhase _phase = ScanPhase.idle;
  ProgressUpdate? _progress;
  ScanOutcome? _outcome;
  String _statusKey = 'status-ready';
  Map<String, Object> _statusArgs = const <String, Object>{};
  String _messages = '';
  String? _critical;

  List<ScanRow> _rows = <ScanRow>[];
  List<ScanRow> _visible = <ScanRow>[];
  final Set<String> _selected = <String>{};
  String _filter = '';
  int _sortColumn = -1;
  bool _sortAscending = true;

  bool _actionRunning = false;
  ConfirmRequest? _confirm;
  Future<void> Function()? _confirmAction;

  /// Bumped per scan so a cancelled scan's late events cannot overwrite the next one.
  int _generation = 0;
  StreamSubscription<ScanEvent>? _scanSubscription;

  EngineInfo? get info => _info;
  List<ToolSpec> get tools => List<ToolSpec>.unmodifiable(_tools);
  ToolSpec? get tool => _tool;
  List<FieldDef> get fields => List<FieldDef>.unmodifiable(_fields);
  List<String> get included => List<String>.unmodifiable(_included);
  List<String> get reference => List<String>.unmodifiable(_reference);
  List<String> get excludedPaths => List<String>.unmodifiable(_excludedPaths);
  List<String> get excludedItems => List<String>.unmodifiable(_excludedItems);
  List<String> get allowedExtensions =>
      List<String>.unmodifiable(_allowedExtensions);
  List<String> get excludedExtensions =>
      List<String>.unmodifiable(_excludedExtensions);
  ScanPhase get phase => _phase;
  bool get scanning =>
      _phase == ScanPhase.running || _phase == ScanPhase.stopping;
  ProgressUpdate? get progress => _progress;
  ScanOutcome? get outcome => _outcome;
  String get statusText => Labels.of(_statusKey, args: _statusArgs);
  String get messages => _messages;
  String? get critical => _critical;
  List<ScanRow> get rows => List<ScanRow>.unmodifiable(_rows);
  List<ScanRow> get visibleRows => List<ScanRow>.unmodifiable(_visible);
  String get filter => _filter;
  int get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  bool get actionRunning => _actionRunning;
  ConfirmRequest? get confirm => _confirm;
  int get selectedCount => _selected.length;
  int get fileCount => _outcome?.fileCount ?? _rows.length;
  int get groupCount => _outcome?.groupCount ?? _groupIndices.length;
  int get totalBytes => _outcome?.totalBytes ?? 0;
  int get reclaimableBytes => _outcome?.reclaimableBytes ?? 0;

  int get selectedBytes => _rows
      .where((ScanRow row) => _selected.contains(row.path))
      .fold<int>(0, (int sum, ScanRow row) => sum + row.sizeBytes);

  String get selectedSizeText => humanBytes(selectedBytes);

  /// Progress rail value in 0..1; the engine reports a negative percent when unmeasurable.
  double? get progressValue {
    final ProgressUpdate? update = _progress;
    if (update == null || update.percent < 0) {
      return null;
    }
    return (update.percent / 100).clamp(0.0, 1.0);
  }

  List<int> get _groupIndices {
    final Set<int> indices = <int>{};
    for (final ScanRow row in _rows) {
      if (row.groupIndex >= 0) {
        indices.add(row.groupIndex);
      }
    }
    return indices.toList()..sort();
  }

  void toggleTheme() {
    dark = !dark;
    notifyListeners();
  }

  void resetLayout() {
    layout.reset();
    notifyListeners();
  }

  void setSourceWidth(double width) {
    layout.sourceWidth = width;
    notifyListeners();
  }

  void setResultsWidth(double width) {
    layout.resultsWidth = width;
    notifyListeners();
  }

  void toggleLane(String lane) {
    switch (lane) {
      case 'source':
        layout.sourceCollapsed = !layout.sourceCollapsed;
      case 'results':
        layout.resultsCollapsed = !layout.resultsCollapsed;
      default:
        layout.analysisCollapsed = !layout.analysisCollapsed;
    }
    notifyListeners();
  }

  void selectTool(String id) {
    if (id == _tool?.id) {
      return;
    }
    _applyTool(id);
    notifyListeners();
  }

  void _applyTool(String id) {
    ToolSpec? spec;
    for (final ToolSpec tool in _tools) {
      if (tool.id == id) {
        spec = tool;
        break;
      }
    }
    if (spec == null) {
      return;
    }
    _tool = spec;
    _fields = engine.fieldDefs(id);
    _values.clear();
    for (final FieldValue value in engine.defaultFields(id)) {
      _values[value.id] = value;
    }
    _clearResults();
  }

  FieldValue valueOf(String id) =>
      _values[id] ?? FieldValue(id: id, value: const FieldPayloadText(''));

  void setFieldValue(String id, FieldPayload payload) {
    _values[id] = FieldValue(id: id, value: payload);
    notifyListeners();
  }

  void addIncluded(Iterable<String> paths) => _addInto(_included, paths);

  void addReference(Iterable<String> paths) => _addInto(_reference, paths);

  void addExcludedPath(Iterable<String> paths) =>
      _addInto(_excludedPaths, paths);

  void addExcludedItem(Iterable<String> patterns) =>
      _addInto(_excludedItems, patterns);

  void addAllowedExtension(Iterable<String> extensions) =>
      _addInto(_allowedExtensions, extensions);

  void addExcludedExtension(Iterable<String> extensions) =>
      _addInto(_excludedExtensions, extensions);

  void _addInto(List<String> target, Iterable<String> values) {
    final Iterable<String> fresh = values
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty);
    if (fresh.isEmpty) {
      return;
    }
    for (final String value in fresh) {
      if (!target.contains(value)) {
        target.add(value);
      }
    }
    notifyListeners();
  }

  void removeIncluded(int index) => _removeAt(_included, index);

  void removeReference(int index) => _removeAt(_reference, index);

  void removeExcludedPath(int index) => _removeAt(_excludedPaths, index);

  void removeExcludedItem(int index) => _removeAt(_excludedItems, index);

  void removeAllowedExtension(int index) =>
      _removeAt(_allowedExtensions, index);

  void removeExcludedExtension(int index) =>
      _removeAt(_excludedExtensions, index);

  void _removeAt(List<String> target, int index) {
    if (index < 0 || index >= target.length) {
      return;
    }
    target.removeAt(index);
    notifyListeners();
  }

  void clearIncluded() => _clearList(_included);

  void clearReference() => _clearList(_reference);

  void clearExcludedPaths() => _clearList(_excludedPaths);

  void clearExcludedItems() => _clearList(_excludedItems);

  void clearAllowedExtensions() => _clearList(_allowedExtensions);

  void clearExcludedExtensions() => _clearList(_excludedExtensions);

  void _clearList(List<String> target) {
    if (target.isEmpty) {
      return;
    }
    target.clear();
    notifyListeners();
  }

  void setRecursive(bool value) {
    recursive = value;
    notifyListeners();
  }

  void setUseCache(bool value) {
    useCache = value;
    notifyListeners();
  }

  void setMinSize(String value) {
    minSizeKib = value;
    notifyListeners();
  }

  void setMaxSize(String value) {
    maxSizeKib = value;
    notifyListeners();
  }

  void setDryRun(bool value) {
    dryRun = value;
    notifyListeners();
  }

  void setMoveToTrash(bool value) {
    moveToTrash = value;
    notifyListeners();
  }

  ScanRequest buildRequest() {
    return ScanRequest(
      tool: _tool?.id ?? '',
      included: List<String>.of(_included),
      reference: List<String>.of(_reference),
      excludedPaths: List<String>.of(_excludedPaths),
      excludedItems: List<String>.of(_excludedItems),
      allowedExtensions: List<String>.of(_allowedExtensions),
      excludedExtensions: List<String>.of(_excludedExtensions),
      recursive: recursive,
      useCache: useCache,
      minSizeKib: minSizeKib,
      maxSizeKib: maxSizeKib,
      fields: _fields.map((FieldDef def) => valueOf(def.id)).toList(),
    );
  }

  /// Returns false and explains itself when the request cannot reach the engine.
  bool startScan() {
    final ToolSpec? spec = _tool;
    if (spec == null || scanning) {
      return false;
    }
    if (_included.isEmpty && _reference.isEmpty) {
      _setStatus('rust_no_included_paths');
      notifyListeners();
      return false;
    }
    _generation++;
    final int generation = _generation;
    _clearResults(keepStatus: true);
    _phase = ScanPhase.running;
    _setStatus('status_scanning');
    _scanSubscription?.cancel();
    _scanSubscription = engine
        .startScan(buildRequest())
        .listen(
          (ScanEvent event) {
            if (generation != _generation) {
              return;
            }
            _handleEvent(event);
          },
          onError: (Object error, StackTrace stack) {
            if (generation != _generation) {
              return;
            }
            _fail(error.toString());
            notifyListeners();
          },
          onDone: () {
            if (generation != _generation) {
              return;
            }
            if (_phase == ScanPhase.running || _phase == ScanPhase.stopping) {
              // The bridge promises exactly one terminal event before the stream closes.
              _fail('Scan stream ended without a result');
              notifyListeners();
            }
          },
        );
    notifyListeners();
    return true;
  }

  void stopScan() {
    if (_phase != ScanPhase.running) {
      return;
    }
    engine.requestStop();
    _phase = ScanPhase.stopping;
    _setStatus('status_stopping');
    notifyListeners();
  }

  void _handleEvent(ScanEvent event) {
    switch (event) {
      case ScanEventProgress():
        _progress = event.progress;
      case ScanEventCompleted():
        _finish(event.outcome);
      case ScanEventFailed():
        _fail(event.error);
    }
    notifyListeners();
  }

  void _finish(ScanOutcome outcome) {
    _phase = ScanPhase.finished;
    _progress = null;
    _outcome = outcome;
    _rows = List<ScanRow>.of(outcome.rows);
    _messages = outcome.messages;
    _critical = outcome.critical;
    if (outcome.stopped) {
      _setStatus('status_stopped');
    } else if (outcome.rows.isEmpty) {
      _setStatus('status_nothing_found');
    } else {
      _setStatus(
        'status_found',
        args: <String, Object>{
          'files': outcome.fileCount,
          'groups': outcome.groupCount,
          'size': humanBytes(outcome.totalBytes),
        },
      );
    }
    _recomputeVisible();
  }

  void _fail(String error) {
    _phase = ScanPhase.failed;
    _progress = null;
    _critical = error;
    _setStatus('empty-error');
    _recomputeVisible();
  }

  void _clearResults({bool keepStatus = false}) {
    _rows = <ScanRow>[];
    _visible = <ScanRow>[];
    _selected.clear();
    _progress = null;
    _outcome = null;
    _messages = '';
    _critical = null;
    _filter = '';
    _sortColumn = -1;
    _sortAscending = true;
    if (!keepStatus) {
      _phase = ScanPhase.idle;
      _setStatus('status-ready');
    }
  }

  void setFilter(String query) {
    _filter = query;
    _recomputeVisible();
    notifyListeners();
  }

  /// Column taps cycle ascending, descending, then back to engine order.
  void toggleSort(int column) {
    if (_sortColumn != column) {
      _sortColumn = column;
      _sortAscending = true;
    } else if (_sortAscending) {
      _sortAscending = false;
    } else {
      _sortColumn = -1;
      _sortAscending = true;
    }
    _recomputeVisible();
    notifyListeners();
  }

  void _recomputeVisible() {
    _visible = projectRows(
      rows: _rows,
      tool: _tool,
      filter: _filter,
      sortColumn: _sortColumn,
      sortAscending: _sortAscending,
    );
  }

  List<ScanRow> groupMembers(int groupIndex) =>
      _rows.where((ScanRow row) => row.groupIndex == groupIndex).toList();

  GroupSelection groupSelection(int groupIndex) =>
      groupSelectionOf(groupMembers(groupIndex), _selected);

  bool isSelected(ScanRow row) => _selected.contains(row.path);

  void toggleSelected(ScanRow row) {
    if (!_selected.remove(row.path)) {
      _selected.add(row.path);
    }
    notifyListeners();
  }

  void setGroupSelected(int groupIndex, bool selected) {
    for (final ScanRow row in groupMembers(groupIndex)) {
      if (selected) {
        _selected.add(row.path);
      } else {
        _selected.remove(row.path);
      }
    }
    notifyListeners();
  }

  void toggleGroup(int groupIndex) {
    final List<ScanRow> members = groupMembers(groupIndex);
    if (members.isEmpty) {
      return;
    }
    setGroupSelected(
      groupIndex,
      groupSelectionOf(members, _selected) != GroupSelection.all,
    );
  }

  void selectAllVisible() {
    for (final ScanRow row in _visible) {
      _selected.add(row.path);
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) {
      return;
    }
    _selected.clear();
    notifyListeners();
  }

  List<ScanRow> get selectedRows =>
      _rows.where((ScanRow row) => _selected.contains(row.path)).toList();

  /// Asks the confirm overlay first; the destructive path only runs from [acceptConfirm].
  void requestDelete() {
    final List<ScanRow> targets = selectedRows;
    if (targets.isEmpty) {
      _setStatus('status_nothing_selected');
      notifyListeners();
      return;
    }
    _confirmAction = () => _applyDelete(targets);
    _confirm = ConfirmRequest(
      titleKey: dryRun ? 'label-dry-run' : 'confirm_delete_title',
      bodyKey: dryRun ? 'confirm_dry_run_body' : 'confirm_delete_body',
      args: <String, Object>{
        'count': targets.length,
        'size': humanBytes(
          targets.fold<int>(0, (int sum, ScanRow row) => sum + row.sizeBytes),
        ),
      },
      dryRun: dryRun,
    );
    notifyListeners();
  }

  void dismissConfirm() {
    _confirm = null;
    _confirmAction = null;
    notifyListeners();
  }

  Future<void> acceptConfirm() async {
    final Future<void> Function()? action = _confirmAction;
    _confirm = null;
    _confirmAction = null;
    if (action != null) {
      await action();
    } else {
      notifyListeners();
    }
  }

  Future<void> _applyDelete(List<ScanRow> targets) async {
    _actionRunning = true;
    _setStatus('status_deleting');
    notifyListeners();
    try {
      final DeleteOutcome outcome = await engine.deleteFiles(
        DeleteRequest(
          tool: _tool?.id ?? '',
          rows: targets,
          deleteToTrash: moveToTrash,
          dryRun: dryRun,
        ),
      );
      _messages = outcome.messages;
      if (dryRun) {
        _setStatus('status_dry_run_only');
      } else if (outcome.errors > 0) {
        // The engine only reports counts, so nothing is dropped from the table: a row that
        // failed to delete would otherwise vanish while the file is still on disk.
        _setStatus(
          'status_removed_partial',
          args: <String, Object>{
            'removed': outcome.affected,
            'failed': outcome.errors,
          },
        );
        _selected.clear();
      } else {
        _setStatus(
          'status_removed_all',
          args: <String, Object>{'count': outcome.affected},
        );
        final Set<String> removed = targets
            .map((ScanRow row) => row.path)
            .toSet();
        _rows = _rows
            .where((ScanRow row) => !removed.contains(row.path))
            .toList();
        _selected.removeAll(removed);
        _recomputeVisible();
      }
    } catch (error) {
      _critical = error.toString();
      _setStatus('empty-error');
    } finally {
      _actionRunning = false;
      notifyListeners();
    }
  }

  Future<void> exportResults(String path, {String format = 'json'}) async {
    if (_rows.isEmpty) {
      _setStatus('status_nothing_to_export');
      notifyListeners();
      return;
    }
    _actionRunning = true;
    notifyListeners();
    try {
      final String folder = await engine.exportResults(
        ExportRequest(
          tool: _tool?.id ?? '',
          rows: _rows,
          path: path,
          format: format,
          grouped: _tool?.grouped ?? false,
        ),
      );
      _setStatus('status_exported', args: <String, Object>{'folder': folder});
    } catch (error) {
      _setStatus(
        'status_export_failed',
        args: <String, Object>{'error': '$error'},
      );
    } finally {
      _actionRunning = false;
      notifyListeners();
    }
  }

  void _setStatus(String key, {Map<String, Object>? args}) {
    _statusKey = key;
    _statusArgs = args ?? const <String, Object>{};
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }
}
