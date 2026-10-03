import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/row_projection.dart' show formatReversePath;
import 'package:kisaki_app/state/row_selection.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// Mirrors the selection rules of `czkawka/result-table.test.ts`, then checks that the table wires
/// them to the mouse: one click picks, Control adds, Shift ranges, and a reference row cannot be picked.
void main() {
  List<ScanRow> rows() => <ScanRow>[
    StubEngine.row('a', size: 30),
    StubEngine.row('b', size: 10),
    StubEngine.row('c', size: 20),
  ];

  group('the ported rules', () {
    test('supports replace, ctrl toggle, and shift range selection', () {
      expect(
        applyResultSelection(
          current: <String>['a'],
          visible: rows(),
          path: 'b',
          checked: true,
          mode: ClickMode.replace,
        ),
        <String>['b'],
      );
      expect(
        applyResultSelection(
          current: <String>['a'],
          visible: rows(),
          path: 'b',
          checked: true,
          mode: ClickMode.toggle,
        ),
        <String>['a', 'b'],
      );
      expect(
        applyResultSelection(
          current: <String>['a'],
          visible: rows(),
          path: 'c',
          checked: true,
          mode: ClickMode.range,
          anchor: 'a',
        ),
        <String>['a', 'b', 'c'],
      );
    });

    test('a range without a known anchor falls back to that one row', () {
      expect(
        applyResultSelection(
          current: <String>['outside'],
          visible: rows(),
          path: 'c',
          checked: true,
          mode: ClickMode.range,
        ),
        <String>['outside', 'c'],
      );
    });

    test(
      'box selection replaces, adds and subtracts but never takes a reference',
      () {
        final List<String> covered = <String>['a', 'c'];
        expect(
          applyBoxPaths(<String>['outside'], covered, BoxMode.replace),
          <String>['a', 'c'],
        );
        expect(
          applyBoxPaths(<String>['outside'], covered, BoxMode.add),
          <String>['outside', 'a', 'c'],
        );
        expect(
          applyBoxPaths(<String>['outside', 'a', 'c'], covered, BoxMode.remove),
          <String>['outside'],
        );
      },
    );

    test(
      'reverses path segments for display without changing the source path',
      () {
        expect(
          formatReversePath(r'C:\photos\2026\cover.jpg'),
          'cover.jpg ‹ 2026 ‹ photos ‹ C:',
        );
        expect(formatReversePath('cover.jpg'), 'cover.jpg');
        expect(
          formatReversePath('//server/share/a.jpg'),
          'a.jpg ‹ share ‹ server',
        );
      },
    );
  });

  const ColumnDef sizeCol = ColumnDef(
    key: 'size',
    labelKey: 'col_size',
    flex: 0.5,
    minWidth: 84,
    alignRight: true,
  );

  const List<ToolSpec> tools = <ToolSpec>[
    ToolSpec(
      id: 'duplicate_files',
      glyph: 'D',
      labelKey: 'tool_duplicate_files',
      grouped: true,
      supportsReference: true,
      columns: <ColumnDef>[sizeCol],
      fieldIds: <String>[],
    ),
  ];

  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine(tools: tools);
    controller = BoardController(engine: engine);
  });

  Future<void> pumpRows(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['/data']);
    controller.selectTool('duplicate_files');
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row('/data/1', size: 100, group: 0, start: true),
          StubEngine.row('/data/2', size: 100, group: 0),
          StubEngine.row('/data/3', size: 100, group: 1),
          StubEngine.row('/data/keep', size: 100, group: 1, reference: true),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> click(
    WidgetTester tester,
    String path, {
    LogicalKeyboardKey? key,
  }) async {
    if (key != null) {
      await tester.sendKeyDownEvent(key);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(Key('result-row-$path')));
    await tester.pumpAndSettle();
    if (key != null) {
      await tester.sendKeyUpEvent(key);
      await tester.pumpAndSettle();
    }
  }

  List<String> selected() =>
      controller.selectedRows.map((ScanRow row) => row.path).toList();

  testWidgets('a plain click picks one row and the next click picks another', (
    WidgetTester tester,
  ) async {
    await pumpRows(tester);
    await click(tester, '/data/1');
    expect(selected(), <String>['/data/1']);

    await click(tester, '/data/2');
    expect(selected(), <String>['/data/2']);
  });

  testWidgets('control adds to the selection', (WidgetTester tester) async {
    await pumpRows(tester);
    await click(tester, '/data/1');
    await click(tester, '/data/3', key: LogicalKeyboardKey.controlLeft);

    expect(selected(), <String>['/data/1', '/data/3']);
  });

  testWidgets('shift ranges from the last plain click', (
    WidgetTester tester,
  ) async {
    await pumpRows(tester);
    await click(tester, '/data/1');
    await click(tester, '/data/3', key: LogicalKeyboardKey.shiftLeft);

    expect(selected(), <String>['/data/1', '/data/2', '/data/3']);
  });

  testWidgets('a reference row cannot be clicked or checked', (
    WidgetTester tester,
  ) async {
    await pumpRows(tester);
    final Checkbox box = tester.widget<Checkbox>(
      find.byKey(const Key('row-select-/data/keep')),
    );
    expect(
      box.onChanged,
      isNull,
      reason: 'the keeper of a duplicate group is never a delete target',
    );

    await click(tester, '/data/1');
    await click(tester, '/data/keep');
    expect(selected(), <String>['/data/1']);
  });

  testWidgets('the path-last switch rewrites the cell, the source stays', (
    WidgetTester tester,
  ) async {
    await pumpRows(tester);
    expect(find.text('1'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('toggle-reverse-path')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toggle-reverse-path')));
    await tester.pumpAndSettle();

    expect(controller.reversePath, isTrue);
    expect(find.text('1 ‹ data'), findsOneWidget);
    expect(controller.rows.first.path, '/data/1');
  });

  testWidgets('wrap text makes the rows taller and says so in the layout', (
    WidgetTester tester,
  ) async {
    await pumpRows(tester);
    final double before = tester
        .getSize(find.byKey(const Key('result-row-/data/1')))
        .height;

    await tester.ensureVisible(find.byKey(const Key('toggle-wrap-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toggle-wrap-text')));
    await tester.pumpAndSettle();

    expect(controller.wrapText, isTrue);
    expect(
      tester.getSize(find.byKey(const Key('result-row-/data/1'))).height,
      greaterThan(before),
    );
  });

  testWidgets('the display switches are labelled with authored text', (
    WidgetTester tester,
  ) async {
    await pumpRows(tester);
    Labels.fallbackKeys.clear();
    await tester.ensureVisible(find.byKey(const Key('toggle-wrap-text')));
    await tester.pumpAndSettle();

    expect(find.text(Labels.of('label-reverse-path')), findsOneWidget);
    expect(find.text(Labels.of('label-wrap-text')), findsOneWidget);
    expect(Labels.fallbackKeys, isEmpty);
  });
}
