import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/filter_apply.dart';
import 'package:kisaki_app/state/filter_model.dart';

/// Windows hands the engine backslashes, and a directory name may contain a dot of its own
/// (`Photo.2024`), so an extension has to be read off the last path segment only.
ScanRow _row(String path, int group) => ScanRow(
  path: path,
  name: path.split(RegExp(r'[/\\]')).last,
  directory: path,
  cells: const <String>[],
  sizeBytes: 10,
  modifiedTs: 0,
  groupIndex: group,
  groupSize: 1,
  isGroupStart: false,
  isReference: false,
  sortKeys: const <int>[10, 0],
);

void main() {
  test('a dotted directory does not become the extension of a nameless file', () {
    final List<ScanRow> rows = <ScanRow>[
      _row(r'D:\Photo.2024\LICENSE', 0),
      _row(r'D:\Photo.2024\shot.jpg', 1),
    ];
    // Each row is its own group, so a keep cannot be explained by the group rule.
    final FilterState state = FilterState.defaults()
      ..extensionEnabled = true
      ..extensionMode = true
      ..showAllInFilteredGroups = false
      ..extensions = <String>[kNoExtension];

    final List<String> kept = applyFilters(
      rows: rows,
      selected: const <String>{},
      state: state,
      now: 0,
    ).rows.map((ScanRow row) => row.path).toList();

    expect(
      kept,
      <String>[r'D:\Photo.2024\LICENSE'],
      reason: 'LICENSE has no extension; shot.jpg does, and only jpg is listed',
    );
  });

  test('posix rows keep answering the same way', () {
    final FilterState state = FilterState.defaults()
      ..extensionEnabled = true
      ..extensionMode = true
      ..showAllInFilteredGroups = false
      ..extensions = <String>['jpg'];

    expect(
      applyFilters(
        rows: <ScanRow>[_row('/data/a.jpg', 0), _row('/data/README', 1)],
        selected: const <String>{},
        state: state,
        now: 0,
      ).rows.map((ScanRow row) => row.path).toList(),
      <String>['/data/a.jpg'],
    );
  });
}
