import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/kisaki_engine.dart';
import '../engine/models.dart';
import '../l10n/labels.dart';
import '../util/format.dart';
import 'filter_apply.dart';
import 'filter_model.dart';
import 'image_comparison.dart';
import 'row_projection.dart';
import 'selection_model.dart';
import 'similar_folders.dart';
import 'simiu_model.dart';
import 'selection_rules.dart';

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
  FilterState _filters = FilterState.defaults();
  final List<FilterPreset> _presets = <FilterPreset>[];
  FilterResult? _filterResult;
  SelectionConfig _assistant = SelectionConfig.defaults();
  SelectionHistory _history = createSelectionHistory(const <String>[]);
  String _assistantMessageKey = '';
  Map<String, Object> _assistantMessageArgs = const <String, Object>{};
  bool _assistantMessageIsError = false;
  ComparisonState _comparison = const ComparisonState();
  bool _folderView = false;
  final SimiuModel _simiu = SimiuModel();
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
    _history = createSelectionHistory(const <String>[]);
    _clearAssistantMessage();
    _comparison = const ComparisonState();
    _folderView = false;
    _progress = null;
    _outcome = null;
    _messages = '';
    _critical = null;
    _filter = '';
    _filters = FilterState.defaults();
    _filterResult = null;
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

  /// Re-runs the scan but keeps the filtering and rule work the board is showing, which is what a
  /// refresh means; a plain [startScan] would discard it with the results.
  bool refreshScan() {
    final FilterState filters = _filters.copy();
    final SelectionConfig assistant = _assistant;
    final String query = _filter;
    final int column = _sortColumn;
    final bool ascending = _sortAscending;
    if (!startScan()) {
      return false;
    }
    _filters = filters;
    _assistant = assistant;
    _filter = query;
    _sortColumn = column;
    _sortAscending = ascending;
    _recomputeVisible();
    notifyListeners();
    return true;
  }

  void _recomputeVisible() {
    // The header search box is the reference's quick-text dimension, so it feeds the same state the
    // filter dialog edits instead of being a second, narrower filtering path.
    final FilterState state = _filters.copy()
      ..textPattern = _filter.trim()
      ..textEnabled = _filter.trim().isNotEmpty;
    final FilterResult result = applyFilters(
      rows: _rows,
      selected: _selected,
      state: state,
      tool: _tool,
    );
    _filters = state;
    _filterResult = result;
    _visible = projectRows(
      rows: result.rows,
      tool: _tool,
      filter: '',
      sortColumn: _sortColumn,
      sortAscending: _sortAscending,
    );
    _closeComparisonIfGone();
  }

  /// The comparison dialog reads the group the table shows, so it must not stay open on a row that
  /// filtering or a scan just removed.
  void _closeComparisonIfGone() {
    final String? path = _comparison.activePath;
    if (path == null) {
      return;
    }
    if (!_visible.any((ScanRow row) => row.path == path)) {
      _comparison = comparisonClose(_comparison);
    }
  }

  FilterState get filters => _filters;
  List<FilterPreset> get filterPresets =>
      List<FilterPreset>.unmodifiable(_presets);
  FilterStats get filterStats =>
      _filterResult?.stats ??
      FilterStats(
        totalItems: _rows.length,
        filteredItems: _visible.length,
        totalGroups: 0,
        filteredGroups: 0,
        selectedItems: _selected.length,
        activeFilterCount: _filters.activeCount,
        extensions: const <ExtensionStat>[],
        categories: const <CategoryStat>[],
      );
  String get filterPatternError =>
      _filterResult?.pathPatternError ?? _filterResult?.textPatternError ?? '';

  /// Replaces the whole filter state; the dialog edits a copy and commits it here.
  void setFilters(FilterState next) {
    _filters = next;
    _recomputeVisible();
    notifyListeners();
  }

  void resetFilters() {
    _filters = FilterState.defaults();
    _filter = '';
    _recomputeVisible();
    notifyListeners();
  }

  void applyBuiltinPreset(BuiltinPreset preset) {
    _filters = FilterState.fromPreset(preset);
    _filter = _filters.textPattern;
    _recomputeVisible();
    notifyListeners();
  }

  /// Overwrites a preset with the same name, like the reference's save button.
  void saveFilterPreset(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final int existing = _presets.indexWhere(
      (FilterPreset preset) => preset.name == trimmed,
    );
    final FilterPreset preset = FilterPreset(
      id: existing >= 0
          ? _presets[existing].id
          : 'filter-${DateTime.now().millisecondsSinceEpoch}',
      name: trimmed,
      state: _filters.copy(),
    );
    if (existing >= 0) {
      _presets[existing] = preset;
    } else {
      _presets.add(preset);
    }
    notifyListeners();
  }

  void removeFilterPreset(String id) {
    _presets.removeWhere((FilterPreset preset) => preset.id == id);
    notifyListeners();
  }

  String exportFilterPresets() => serializeFilterPresets(_presets);

  /// `false` keeps the current presets and the caller can show [filterPatternError]'s sibling.
  bool importFilterPresets(String text) {
    try {
      _presets
        ..clear()
        ..addAll(parseFilterPresets(text));
      notifyListeners();
      return true;
    } on FormatException {
      return false;
    }
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
    _commitSelection();
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
    _commitSelection();
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
    _commitSelection();
    notifyListeners();
  }

  /// The assistant and the comparison dialog work on the groups the table shows, so a filtered-out
  /// row is never touched.
  List<List<ScanRow>> get boardGroups => groupsOf(_visible, _tool);

  /// Only the image scanner rolls its groups up into folders, like the reference's view switch.
  /// The reference hides that switch while Simiu sets are being planned, because the sets replace
  /// the table rather than organising it.
  bool get supportsFolderView =>
      _tool?.id == 'similar_images' && !_simiu.enabled;
  bool get folderView => _folderView && supportsFolderView;
  void setFolderView(bool value) {
    if (_folderView == value) {
      return;
    }
    _folderView = value;
    notifyListeners();
  }

  /// The header search box filters the folder roll-up too, which is what the reference feeds in.
  List<FolderStat> get similarFolders {
    final String needle = _filter.trim().toLowerCase();
    final List<FolderStat> stats = buildSimilarFolders(boardGroups);
    if (needle.isEmpty) {
      return stats;
    }
    return stats
        .where((FolderStat stat) => stat.path.toLowerCase().contains(needle))
        .toList();
  }

  /// Puts text on the clipboard and reports it, so a copy has a readback instead of a silent action.
  Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _setStatus('status_copied', args: <String, Object>{'path': text});
    notifyListeners();
  }

  SimiuModel get simiu => _simiu;

  /// Only the image scanner has a set plan to make, like the reference's mode selector.
  bool get supportsSimiuSets => _tool?.id == 'similar_images';

  SimiuPlan get simiuPlan =>
      _simiu.plan(_rows, _included, recursive: recursive);

  void setSimiuEnabled(bool value) {
    if (_simiu.enabled == value) {
      return;
    }
    _simiu.setEnabled(value);
    if (value) {
      _folderView = false;
    }
    notifyListeners();
  }

  void setSimiuPrefix(String value) {
    _simiu.setNamePrefix(value);
    notifyListeners();
  }

  void setSimiuMinimumGroupSize(int value) {
    _simiu.setMinimumGroupSize(value);
    notifyListeners();
  }

  void setSimiuScanOrder(SimiuScanOrder value) {
    _simiu.setScanOrder(value);
    notifyListeners();
  }

  void setSimiuMode(SimiuMode value) {
    _simiu.setMode(value);
    notifyListeners();
  }

  void setSimiuCleanEmptyDirectories(bool value) {
    _simiu.setCleanEmptyDirectories(value);
    notifyListeners();
  }

  /// Asks the confirm overlay to plan or apply the set moves; the dry-run switch decides which.
  void requestSimiuApply() {
    final List<SimiuOperation> operations = simiuPlan.operations;
    if (operations.isEmpty) {
      _setStatus('status_simiu_nothing');
      notifyListeners();
      return;
    }
    _confirmAction = () => _applySimiu(operations);
    _confirm = ConfirmRequest(
      titleKey: dryRun
          ? 'confirm_simiu_plan_title'
          : 'confirm_simiu_apply_title',
      bodyKey: 'confirm_simiu_body',
      args: <String, Object>{'count': operations.length},
      dryRun: dryRun,
    );
    notifyListeners();
  }

  /// Replays the newest undo journal, so a set that went wrong can be walked back.
  void requestSimiuUndo() {
    final String journal = _simiu.journal;
    if (journal.isEmpty) {
      _setStatus('status_simiu_no_journal');
      notifyListeners();
      return;
    }
    _confirmAction = () => _undoSimiu(journal);
    _confirm = ConfirmRequest(
      titleKey: 'confirm_simiu_undo_title',
      bodyKey: 'confirm_simiu_undo_body',
      args: <String, Object>{'journal': journal},
      dryRun: dryRun,
    );
    notifyListeners();
  }

  Future<void> _applySimiu(List<SimiuOperation> operations) async {
    _actionRunning = true;
    _setStatus('status_simiu_applying');
    notifyListeners();
    try {
      final SimiuApplyOutcome outcome = await engine.applySimiuSet(
        SimiuApplyRequest(
          mode: _simiu.mode,
          operations: operations,
          dryRun: dryRun,
        ),
      );
      _messages = outcome.messages;
      if (!dryRun) {
        _simiu.recordJournals(outcome.journals);
      }
      _setStatus(
        dryRun ? 'status_simiu_planned' : 'status_simiu_applied',
        args: <String, Object>{
          'count': dryRun ? outcome.planned : outcome.done,
        },
      );
      if (outcome.failed > 0) {
        _critical = outcome.messages;
      }
      _invalidatePlan();
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
      notifyListeners();
    }
  }

  Future<void> _undoSimiu(String journal) async {
    _actionRunning = true;
    _setStatus('status_simiu_undoing');
    notifyListeners();
    try {
      final SimiuUndoOutcome outcome = await engine.undoSimiuSet(
        SimiuUndoRequest(
          journal: journal,
          cleanEmptyDirectories: _simiu.cleanEmptyDirectories,
          dryRun: dryRun,
        ),
      );
      _messages = outcome.messages;
      _setStatus(
        dryRun ? 'status_simiu_undo_planned' : 'status_simiu_undone',
        args: <String, Object>{
          'count': dryRun ? outcome.planned : outcome.done,
        },
      );
      if (outcome.failed > 0) {
        _critical = outcome.messages;
      }
      _invalidatePlan();
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
      notifyListeners();
    }
  }

  /// A mutation moves files the plan was built from, so the cached plan must not be reused.
  void _invalidatePlan() {
    _simiu.invalidate();
  }

  SelectionConfig get assistant => _assistant;
  bool get canUndoSelection => _history.canUndo;
  bool get canRedoSelection => _history.canRedo;
  bool get assistantMessageIsError => _assistantMessageIsError;
  String get assistantMessage => _assistantMessageKey.isEmpty
      ? ''
      : Labels.of(_assistantMessageKey, args: _assistantMessageArgs);

  SelectionStats get assistantStats => selectionStats(boardGroups, _selected);

  void setAssistantConfig(SelectionConfig next) {
    _assistant = next;
    notifyListeners();
  }

  void resetAssistant() {
    _assistant = SelectionConfig.defaults();
    _clearAssistantMessage();
    notifyListeners();
  }

  void applyAssistantRule(AssistantRuleKind kind) {
    final List<List<ScanRow>> groups = boardGroups;
    final SelectionResult result = switch (kind) {
      AssistantRuleKind.group => applyGroupSelection(
        groups: groups,
        current: _selected,
        rule: _assistant.group,
        mode: _assistant.applyMode,
      ),
      AssistantRuleKind.text => applyTextSelection(
        groups: groups,
        current: _selected,
        rule: _assistant.text,
        mode: _assistant.applyMode,
      ),
      AssistantRuleKind.directory => applyDirectorySelection(
        groups: groups,
        current: _selected,
        rule: _assistant.directory,
        mode: _assistant.applyMode,
      ),
    };
    final String? error = result.error;
    if (error != null) {
      _assistantMessageKey = result.directoryRequired
          ? 'assistant-directory-required'
          : 'assistant-error';
      _assistantMessageArgs = <String, Object>{'message': error};
      _assistantMessageIsError = true;
      notifyListeners();
      return;
    }
    _selected
      ..clear()
      ..addAll(result.paths);
    _commitSelection();
    _assistantMessageKey = 'assistant-matched';
    _assistantMessageArgs = <String, Object>{
      'matched': result.matchedPaths.length,
      'affected': result.affectedCount,
    };
    _assistantMessageIsError = false;
    notifyListeners();
  }

  void invertAssistantSelection() {
    final List<String> paths = invertSelection(boardGroups, _selected);
    _selected
      ..clear()
      ..addAll(paths);
    _commitSelection();
    notifyListeners();
  }

  void selectAllAssistantEntries() {
    final List<String> paths = selectAllEntries(boardGroups);
    _selected
      ..clear()
      ..addAll(paths);
    _commitSelection();
    notifyListeners();
  }

  void undoSelection() {
    _applyHistory(undoSelectionHistory(_history));
  }

  void redoSelection() {
    _applyHistory(redoSelectionHistory(_history));
  }

  String exportAssistant() => serializeSelectionConfig(_assistant);

  bool importAssistant(String document) {
    try {
      _assistant = parseSelectionConfig(document);
    } on FormatException catch (error) {
      _assistantMessageKey = 'assistant-error';
      _assistantMessageArgs = <String, Object>{'message': error.message};
      _assistantMessageIsError = true;
      notifyListeners();
      return false;
    }
    _clearAssistantMessage();
    notifyListeners();
    return true;
  }

  void _clearAssistantMessage() {
    _assistantMessageKey = '';
    _assistantMessageArgs = const <String, Object>{};
    _assistantMessageIsError = false;
  }

  /// The comparison dialog needs a second image from the same group, so a lone row has nothing to
  /// show against.
  bool get canCompareSelection {
    final List<ScanRow> picked = selectedRows;
    if (picked.isEmpty) {
      return false;
    }
    final String path = picked.first.path;
    return boardGroups.any(
      (List<ScanRow> group) =>
          group.length > 1 && group.any((ScanRow row) => row.path == path),
    );
  }

  ComparisonState get comparison => _comparison;
  ComparisonEntries get comparisonSelection =>
      comparisonEntries(_comparison, boardGroups);

  void openComparison(ScanRow row) {
    _comparison = comparisonOpen(_comparison, boardGroups, row.path);
    notifyListeners();
  }

  void closeComparison() {
    _comparison = comparisonClose(_comparison);
    notifyListeners();
  }

  void setComparisonTarget(String path) {
    _comparison = comparisonSetTarget(_comparison, boardGroups, path);
    notifyListeners();
  }

  void setComparisonMode(ComparisonMode mode) {
    _comparison = comparisonSetMode(_comparison, mode);
    notifyListeners();
  }

  void toggleComparisonColorCoding() {
    _comparison = comparisonSetColorCoding(
      _comparison,
      !_comparison.colorCoding,
    );
    notifyListeners();
  }

  void setComparisonSwipe(double percent) {
    _comparison = comparisonSetSwipe(_comparison, percent);
    notifyListeners();
  }

  void setComparisonOpacity(double percent) {
    _comparison = comparisonSetOpacity(_comparison, percent);
  }

  void _applyHistory(SelectionHistory next) {
    if (identical(next, _history)) {
      return;
    }
    _history = next;
    _selected
      ..clear()
      ..addAll(next.present);
    notifyListeners();
  }

  void _commitSelection() {
    _history = pushSelectionHistory(_history, _selected);
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

  /// The engine decides the corrected names, so the request carries the live scan settings and the
  /// selection; the dry run answers with the same plan the real run would follow.
  void requestRename() {
    final List<ScanRow> targets = selectedRows;
    if (targets.isEmpty) {
      _setStatus('status_nothing_selected');
      notifyListeners();
      return;
    }
    _confirmAction = () => _applyRename(targets);
    _confirm = ConfirmRequest(
      titleKey: dryRun ? 'label-dry-run' : 'confirm_rename_title',
      bodyKey: dryRun ? 'confirm_dry_run_body' : 'confirm_rename_body',
      args: <String, Object>{'count': targets.length},
      dryRun: dryRun,
    );
    notifyListeners();
  }

  Future<void> _applyRename(List<ScanRow> targets) async {
    _actionRunning = true;
    _setStatus('status_renaming');
    notifyListeners();
    try {
      final RenameOutcome outcome = await engine.renameFiles(
        RenameRequest(
          tool: _tool?.id ?? '',
          scan: buildRequest(),
          paths: targets.map((ScanRow row) => row.path).toList(),
          dryRun: dryRun,
        ),
      );
      _messages = outcome.messages;
      _setStatus(
        dryRun ? 'status_rename_planned' : 'status_renamed',
        args: <String, Object>{
          'count': dryRun ? outcome.planned : outcome.renamed,
        },
      );
      if (outcome.failed > 0) {
        _critical = outcome.messages;
      }
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
      notifyListeners();
    }
  }

  void requestMove(String destination, MoveAction action) {
    final List<ScanRow> targets = selectedRows;
    final String folder = destination.trim();
    if (targets.isEmpty || folder.isEmpty) {
      _setStatus('status_move_needs_destination');
      notifyListeners();
      return;
    }
    _confirmAction = () => _applyMove(targets, folder, action);
    _confirm = ConfirmRequest(
      titleKey: dryRun ? 'label-dry-run' : 'confirm_move_title',
      bodyKey: dryRun ? 'confirm_dry_run_body' : 'confirm_move_body',
      args: <String, Object>{'count': targets.length, 'destination': folder},
      dryRun: dryRun,
    );
    notifyListeners();
  }

  Future<void> _applyMove(
    List<ScanRow> targets,
    String destination,
    MoveAction action,
  ) async {
    _actionRunning = true;
    _setStatus('status_moving');
    notifyListeners();
    try {
      final MoveOutcome outcome = await engine.moveFiles(
        MoveRequest(
          paths: targets.map((ScanRow row) => row.path).toList(),
          destination: destination,
          action: action,
          conflict: MoveConflictPolicy.skip,
          preserveStructure: false,
          dryRun: dryRun,
        ),
      );
      _messages = outcome.messages;
      final int done = action == MoveAction.copy
          ? outcome.copied
          : outcome.moved;
      _setStatus(
        dryRun ? 'status_move_planned' : 'status_moved',
        args: <String, Object>{
          'count': dryRun ? outcome.planned : done,
          'destination': destination,
        },
      );
      if (outcome.failed > 0) {
        _critical = outcome.messages;
      }
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
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
