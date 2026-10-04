import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/kisaki_engine.dart';
import '../engine/models.dart';
import '../l10n/labels.dart';
import '../util/format.dart';
import 'activity_log.dart';
import 'analysis_stats.dart';
import 'export_scope.dart';
import 'filter_apply.dart';
import 'filter_model.dart';
import 'group_organize.dart';
import 'image_comparison.dart';
import 'row_projection.dart';
import 'row_selection.dart';
import 'scan_presets.dart';

import 'selection_model.dart';
import 'similar_folders.dart';
import 'simiu_model.dart';
import 'simiu_sets.dart' show isSimiuSetImage;
import 'video_optimize.dart';
import 'selection_rules.dart';

export 'row_projection.dart' show GroupSelection;

part 'board_activity.dart';
part 'board_analysis.dart';
part 'board_cursor.dart';
part 'board_display.dart';
part 'board_operations.dart';
part 'board_source_lists.dart';
part 'board_scan_presets.dart';

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

  /// Saved scan configurations, held in memory like the reference holds them in its node store.
  final List<ScanPreset> _scanPresets = <ScanPreset>[];
  FilterResult? _filterResult;
  SelectionConfig _assistant = SelectionConfig.defaults();
  SelectionHistory _history = createSelectionHistory(const <String>[]);
  String _assistantMessageKey = '';
  Map<String, Object> _assistantMessageArgs = const <String, Object>{};
  bool _assistantMessageIsError = false;
  ComparisonState _comparison = const ComparisonState();
  String? _previewPath;
  bool _pinnedPreview = false;
  bool _folderView = false;
  final SimiuModel _simiu = SimiuModel();
  String _selectionAnchor = '';

  /// Which row set the export card writes. The reference opens on the selection, not the result.
  ExportScope _exportScope = ExportScope.selected;

  /// Index into [_visible]: the row the keyboard works on. -1 means the table has no cursor yet.
  int _cursor = -1;
  bool _reversePath = false;
  bool _wrapText = false;
  final Map<String, double> _columnWidths = <String, double>{};
  bool _showThumbnails = true;
  OrganizeOptions _organize = const OrganizeOptions();
  VideoOptions _video = const VideoOptions();
  OptimizeOutcome? _videoOutcome;
  bool _exifOverrideFile = false;
  ExifOutcome? _exifOutcome;
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

  /// Public route to [notifyListeners]: a part file's extension is not an instance member of
  /// this class, so it cannot call the protected method itself.
  void publish() => notifyListeners();

  ScanPhase get phase => _phase;
  bool get scanning =>
      _phase == ScanPhase.running || _phase == ScanPhase.stopping;
  ProgressUpdate? get progress => _progress;
  ScanOutcome? get outcome => _outcome;
  String get statusText => Labels.of(_statusKey, args: _statusArgs);
  String get messages => _messages;
  String? get critical => _critical;

  final List<ActivityEntry> _activity = <ActivityEntry>[];
  String _activityQuery = '';
  String _lastProgressStage = '';

  /// Counts from the engine answer of the verb that just ran; a verb whose outcome has no
  /// comparable numbers leaves them null, so the log shows only its status line.
  int? _operationAffected;
  int? _operationErrors;

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
      logActivity(
        ActivityKind.system,
        ActivityLevel.error,
        Labels.of('rust_no_included_paths'),
      );
      notifyListeners();
      return false;
    }
    _generation++;
    final int generation = _generation;
    _clearResults(keepStatus: true);
    _phase = ScanPhase.running;
    _setStatus('status_scanning');
    _lastProgressStage = '';
    logActivity(
      ActivityKind.scan,
      ActivityLevel.info,
      Labels.of('log-scan-started'),
      progress: 0,
    );
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
    logActivity(
      ActivityKind.system,
      ActivityLevel.warning,
      Labels.of('log-stopping'),
    );
    notifyListeners();
  }

  void _handleEvent(ScanEvent event) {
    switch (event) {
      case ScanEventProgress():
        _progress = event.progress;
        logProgress(event.progress);
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
    logActivity(
      ActivityKind.scan,
      outcome.stopped ? ActivityLevel.warning : ActivityLevel.success,
      statusText,
      progress: 100,
    );
    _recomputeVisible();
  }

  void _fail(String error) {
    _phase = ScanPhase.failed;
    _progress = null;
    _critical = error;
    logActivity(ActivityKind.scan, ActivityLevel.error, error);
    _setStatus('empty-error');
    _recomputeVisible();
  }

  void _clearResults({bool keepStatus = false}) {
    _rows = <ScanRow>[];
    _visible = <ScanRow>[];
    _cursor = -1;
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
    clampCursor();
  }

  /// Keeps the keyboard cursor inside the rows the table shows after a filter, a sort or a scan.
  void clampCursor() {
    if (_visible.isEmpty) {
      _cursor = -1;
      return;
    }
    if (_cursor >= _visible.length) {
      _cursor = _visible.length - 1;
    }
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

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }
}
