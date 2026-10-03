import '../engine/models.dart' show ScanRow;

/// Dart port of the selection rules in `czkawka/result-table.tsx`.
///
/// A plain click picks one row, Ctrl or Command adds, Shift extends from the last picked row, and a
/// box never covers a reference row because the reference is the copy an action must keep.

enum ClickMode { replace, toggle, range }

List<String> applyResultSelection({
  required List<String> current,
  required List<ScanRow> visible,
  required String path,
  required bool checked,
  required ClickMode mode,
  String anchor = '',
}) {
  return switch (mode) {
    ClickMode.replace => checked ? <String>[path] : <String>[],
    ClickMode.toggle =>
      checked ? _unique(<String>[...current, path]) : _without(current, path),
    ClickMode.range => _range(current, visible, path, checked, anchor),
  };
}

List<String> _range(
  List<String> current,
  List<ScanRow> visible,
  String path,
  bool checked,
  String anchor,
) {
  final int start = visible.indexWhere((ScanRow row) => row.path == anchor);
  final int end = visible.indexWhere((ScanRow row) => row.path == path);
  if (start < 0 || end < 0) {
    return checked
        ? _unique(<String>[...current, path])
        : _without(current, path);
  }
  final int from = start < end ? start : end;
  final int to = start < end ? end : start;
  final List<String> span = visible
      .sublist(from, to + 1)
      .map((ScanRow row) => row.path)
      .toList();
  return checked
      ? _unique(<String>[...current, ...span])
      : current.where((String item) => !span.contains(item)).toList();
}

enum BoxMode { replace, add, remove }

List<String> applyBoxPaths(
  List<String> current,
  List<String> covered,
  BoxMode mode,
) {
  return switch (mode) {
    BoxMode.replace => _unique(covered),
    BoxMode.add => _unique(<String>[...current, ...covered]),
    BoxMode.remove =>
      current.where((String path) => !covered.contains(path)).toList(),
  };
}

List<String> _unique(List<String> paths) {
  final Set<String> seen = <String>{};
  return paths.where(seen.add).toList();
}

List<String> _without(List<String> current, String path) =>
    current.where((String item) => item != path).toList();
