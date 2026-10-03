import '../engine/models.dart' show ScanRow, SimiuMode;
import 'simiu_sets.dart';

export 'simiu_sets.dart'
    show SimiuOptions, SimiuPlan, SimiuScanOrder, SimiuSetGroup;

/// Simiu set state: the mode switch, its fields, the last undo journal, and the cached plan.
///
/// The plan is rebuilt only when the rows or the roots change, because the board asks for it on every
/// repaint while a large similar-images result is on screen.
class SimiuModel {
  bool _enabled = false;
  SimiuOptions _options = const SimiuOptions();
  SimiuMode _mode = SimiuMode.move;
  bool _cleanEmptyDirectories = true;
  List<String> _journals = const <String>[];

  List<ScanRow>? _cachedRows;
  String _cachedSignature = '';
  SimiuPlan? _cachedPlan;

  bool get enabled => _enabled;

  SimiuOptions get options => _options;

  SimiuMode get mode => _mode;

  bool get cleanEmptyDirectories => _cleanEmptyDirectories;

  /// Newest journal the board has produced; empty while nothing has been applied.
  String get journal => _journals.isEmpty ? '' : _journals.last;

  List<String> get journals => _journals;

  void setEnabled(bool value) => _enabled = value;

  void setMode(SimiuMode value) => _mode = value;

  void setCleanEmptyDirectories(bool value) => _cleanEmptyDirectories = value;

  void setNamePrefix(String value) {
    if (_options.namePrefix == value) {
      return;
    }
    _options = _options.copyWith(namePrefix: value);
    _invalidate();
  }

  void setMinimumGroupSize(int value) {
    if (_options.minimumGroupSize == value) {
      return;
    }
    _options = _options.copyWith(minimumGroupSize: value);
    _invalidate();
  }

  void setScanOrder(SimiuScanOrder value) {
    if (_options.scanOrder == value) {
      return;
    }
    _options = _options.copyWith(scanOrder: value);
    _invalidate();
  }

  /// Records the journals an apply wrote; the newest of them is what the undo button replays.
  void recordJournals(List<String> written) {
    if (written.isEmpty) {
      return;
    }
    _journals = <String>[..._journals, ...written];
  }

  /// Drops the cached plan, because a mutation moved files the plan was built from.
  void invalidate() => _invalidate();

  /// The plan for the current rows. Recursion follows the scan's own setting, because the rows the
  /// plan reads were produced by that traversal.
  SimiuPlan plan(
    List<ScanRow> rows,
    List<String> roots, {
    required bool recursive,
  }) {
    final List<String> kept = uniqueSimiuRoots(roots);
    final String signature = '${kept.join('\n')}|recursive=$recursive';
    if (!identical(_cachedRows, rows) || _cachedSignature != signature) {
      _cachedRows = rows;
      _cachedSignature = signature;
      _cachedPlan = planSimiuSets(
        rows: rows,
        options: SimiuOptions(
          roots: kept,
          recursive: recursive,
          scanOrder: _options.scanOrder,
          namePrefix: _options.namePrefix,
          minimumGroupSize: _options.minimumGroupSize,
        ),
      );
    }
    return _cachedPlan!;
  }

  void _invalidate() {
    _cachedRows = null;
    _cachedPlan = null;
  }
}
