import '../engine/models.dart';

/// Dart port of `packages/nodes/czkawka/src/image-comparison.ts`.
///
/// The state is deliberately pure: the dialog reads the two paths and the two sliders from here,
/// so opening a comparison from the table and driving it by keyboard share one rule set.
enum ComparisonMode {
  single('single'),
  sideBySide('side-by-side'),
  swipe('swipe'),
  onionSkin('onion-skin');

  const ComparisonMode(this.wire);
  final String wire;

  static ComparisonMode fromWire(String? value) =>
      ComparisonMode.values.firstWhere(
        (ComparisonMode mode) => mode.wire == value,
        orElse: () => ComparisonMode.single,
      );
}

class ComparisonState {
  const ComparisonState({
    this.mode = ComparisonMode.single,
    this.colorCoding = false,
    this.activePath,
    this.targetPath,
    this.swipePercent = 50,
    this.onionOpacity = 50,
  });

  final ComparisonMode mode;
  final bool colorCoding;
  final String? activePath;
  final String? targetPath;
  final double swipePercent;
  final double onionOpacity;

  bool get isOpen => activePath != null;

  /// Opening or re-targeting has to start the sliders from the middle, or the first comparison the
  /// user makes inherits the split they left on another pair.
  ComparisonState copyWith({
    ComparisonMode? mode,
    bool? colorCoding,
    String? activePath,
    String? targetPath,
    double? swipePercent,
    double? onionOpacity,
    bool clearPaths = false,
  }) => ComparisonState(
    mode: mode ?? this.mode,
    colorCoding: colorCoding ?? this.colorCoding,
    activePath: clearPaths ? null : activePath ?? this.activePath,
    targetPath: clearPaths ? null : targetPath ?? this.targetPath,
    swipePercent: swipePercent ?? this.swipePercent,
    onionOpacity: onionOpacity ?? this.onionOpacity,
  );
}

class ComparisonEntries {
  const ComparisonEntries({this.active, this.target, required this.group});

  final ScanRow? active;
  final ScanRow? target;
  final List<ScanRow> group;

  bool get canCompare => active != null && target != null;
}

ComparisonState comparisonOpen(
  ComparisonState state,
  List<List<ScanRow>> groups,
  String activePath,
) {
  final List<ScanRow>? group = _findGroup(groups, activePath);
  if (group == null) {
    return comparisonClose(state);
  }
  return state.copyWith(
    activePath: activePath,
    targetPath: _firstOther(group, activePath)?.path,
    swipePercent: 50,
    onionOpacity: 50,
  );
}

ComparisonState comparisonClose(ComparisonState state) =>
    state.copyWith(activePath: null, targetPath: null, clearPaths: true);

ComparisonState comparisonSetTarget(
  ComparisonState state,
  List<List<ScanRow>> groups,
  String targetPath,
) {
  final List<ScanRow>? group = state.activePath == null
      ? null
      : _findGroup(groups, state.activePath!);
  if (group == null ||
      targetPath == state.activePath ||
      !group.any((ScanRow row) => row.path == targetPath)) {
    return state;
  }
  return state.copyWith(
    targetPath: targetPath,
    swipePercent: 50,
    onionOpacity: 50,
  );
}

ComparisonState comparisonSetMode(ComparisonState state, ComparisonMode mode) =>
    state.mode == mode ? state : state.copyWith(mode: mode);

ComparisonState comparisonSetColorCoding(
  ComparisonState state,
  bool colorCoding,
) => state.colorCoding == colorCoding
    ? state
    : state.copyWith(colorCoding: colorCoding);

ComparisonState comparisonSetSwipe(ComparisonState state, double swipePercent) {
  final double next = _percentage(swipePercent);
  return state.swipePercent == next
      ? state
      : state.copyWith(swipePercent: next);
}

ComparisonState comparisonSetOpacity(
  ComparisonState state,
  double onionOpacity,
) {
  final double next = _percentage(onionOpacity);
  return state.onionOpacity == next
      ? state
      : state.copyWith(onionOpacity: next);
}

ComparisonEntries comparisonEntries(
  ComparisonState state,
  List<List<ScanRow>> groups,
) {
  final List<ScanRow>? group = state.activePath == null
      ? null
      : _findGroup(groups, state.activePath!);
  if (group == null) {
    return ComparisonEntries(group: const <ScanRow>[]);
  }
  return ComparisonEntries(
    active: _first(group, (ScanRow row) => row.path == state.activePath),
    target: _first(group, (ScanRow row) => row.path == state.targetPath),
    group: group,
  );
}

ScanRow? _firstOther(List<ScanRow> group, String path) =>
    _first(group, (ScanRow row) => row.path != path);

ScanRow? _first(List<ScanRow> rows, bool Function(ScanRow row) test) {
  for (final ScanRow row in rows) {
    if (test(row)) {
      return row;
    }
  }
  return null;
}

List<ScanRow>? _findGroup(List<List<ScanRow>> groups, String path) {
  for (final List<ScanRow> group in groups) {
    if (group.any((ScanRow row) => row.path == path)) {
      return group;
    }
  }
  return null;
}

double _percentage(double value) {
  if (!value.isFinite) {
    return 50;
  }
  return value.clamp(0.0, 100.0).roundToDouble();
}
