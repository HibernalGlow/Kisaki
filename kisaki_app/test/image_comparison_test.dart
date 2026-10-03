import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/image_comparison.dart';

/// Mirrors `Xiranite/packages/nodes/czkawka/src/image-comparison.test.ts` case for case, with the
/// same group and paths, so the ported state cannot drift from the reference controls.
void main() {
  List<List<ScanRow>> groups() => <List<ScanRow>>[
    <ScanRow>[
      image('D:/a.jpg', 10, 1, width: 100, height: 80),
      image('D:/b.jpg', 20, 2, width: 80, height: 100),
      image('D:/c.jpg', 30, 3, width: 100, height: 100),
    ],
  ];

  test('opens against another image from the same result group', () {
    final ComparisonState state = comparisonOpen(
      const ComparisonState(),
      groups(),
      'D:/b.jpg',
    );

    expect(state.activePath, 'D:/b.jpg');
    expect(state.targetPath, 'D:/a.jpg');
    expect(state.mode, ComparisonMode.single);
    expect(state.swipePercent, 50);
    expect(state.onionOpacity, 50);

    final ComparisonEntries entries = comparisonEntries(state, groups());
    expect(entries.active?.path, 'D:/b.jpg');
    expect(entries.target?.path, 'D:/a.jpg');
    expect(entries.group.map((ScanRow row) => row.path), contains('D:/c.jpg'));
    expect(entries.canCompare, isTrue);
  });

  test('resets comparison controls when the source or target changes', () {
    ComparisonState state = comparisonOpen(
      const ComparisonState(),
      groups(),
      'D:/a.jpg',
    );
    state = comparisonSetSwipe(state, 72);
    state = comparisonSetOpacity(state, 24);
    state = comparisonSetTarget(state, groups(), 'D:/c.jpg');

    expect(state.activePath, 'D:/a.jpg');
    expect(state.targetPath, 'D:/c.jpg');
    expect(state.swipePercent, 50);
    expect(state.onionOpacity, 50);

    state = comparisonOpen(
      state.copyWith(swipePercent: 10, onionOpacity: 90),
      groups(),
      'D:/b.jpg',
    );
    expect(state.activePath, 'D:/b.jpg');
    expect(state.targetPath, 'D:/a.jpg');
    expect(state.swipePercent, 50);
    expect(state.onionOpacity, 50);
  });

  test('keeps only valid group targets and clamps slider values', () {
    ComparisonState state = comparisonOpen(
      const ComparisonState(),
      groups(),
      'D:/a.jpg',
    );
    state = comparisonSetTarget(state, groups(), 'D:/a.jpg');
    expect(
      state.targetPath,
      'D:/b.jpg',
      reason: 'a row cannot be its own comparison target',
    );
    state = comparisonSetTarget(state, groups(), 'D:/missing.jpg');
    expect(
      state.targetPath,
      'D:/b.jpg',
      reason: 'a path outside the group must be refused',
    );

    state = comparisonSetSwipe(state, 110.4);
    state = comparisonSetOpacity(state, -4);
    expect(state.swipePercent, 100);
    expect(state.onionOpacity, 0);
    state = comparisonSetSwipe(state, double.nan);
    expect(
      state.swipePercent,
      50,
      reason: 'an unreadable slider value falls back to the middle',
    );
  });

  test('a path that left the results closes the comparison', () {
    final ComparisonState open = comparisonOpen(
      const ComparisonState(),
      groups(),
      'D:/a.jpg',
    );
    final ComparisonState closed = comparisonOpen(
      open,
      groups(),
      'D:/gone.jpg',
    );
    expect(closed.isOpen, isFalse);
    expect(closed.activePath, isNull);
    expect(closed.targetPath, isNull);
  });

  test('keeps only the durable view preferences', () {
    ComparisonState state = const ComparisonState();
    state = comparisonSetMode(state, ComparisonMode.onionSkin);
    state = comparisonSetColorCoding(state, true);

    expect(state.mode, ComparisonMode.onionSkin);
    expect(state.colorCoding, isTrue);
    expect(comparisonSetMode(state, ComparisonMode.onionSkin), same(state));
    expect(
      comparisonSetColorCoding(state, true),
      same(state),
      reason:
          'unchanged writes must not rebuild the state and repaint the dialog',
    );
  });
}

ScanRow image(
  String path,
  int size,
  int modified, {
  int width = 0,
  int height = 0,
}) => ScanRow(
  path: path,
  name: path.split('/').last,
  directory: path.substring(0, path.lastIndexOf('/')),
  cells: <String>['$size B', '$modified', if (width > 0) '${width}x$height'],
  sizeBytes: size,
  modifiedTs: modified,
  groupIndex: 4,
  groupSize: 3,
  isGroupStart: false,
  isReference: false,
  sortKeys: <int>[size, modified],
);
