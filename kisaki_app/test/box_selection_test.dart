import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// Dragging a rectangle over the table is the mouse route to a range of rows. The reference draws a
/// box with a plain drag; a Flutter list cannot do both a box and a scroll with the same pointer, so
/// Shift draws the box (it also stops the scroll) and Control or Command draws one that adds. A plain
/// drag still scrolls, and a click that misses a target changes nothing.
void main() {
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

  Future<void> pumpFourRows(WidgetTester tester) async {
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
          StubEngine.row('/data/3', size: 100, group: 0),
          StubEngine.row('/data/4', size: 100, group: 0),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  /// A box needs Shift, because that is what stops the list from scrolling under the drag.
  Future<void> dragOver(
    WidgetTester tester,
    String from,
    String to, {
    LogicalKeyboardKey? also,
  }) async {
    final Offset start =
        tester.getCenter(find.byKey(Key('result-row-$from'))) +
        const Offset(60, 4);
    final Offset end =
        tester.getCenter(find.byKey(Key('result-row-$to'))) -
        const Offset(60, 4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (also != null) {
      await tester.sendKeyDownEvent(also);
    }
    // The physics change that lets a box be drawn needs a frame to land.
    await tester.pumpAndSettle();
    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(end);
    await gesture.up();
    if (also != null) {
      await tester.sendKeyUpEvent(also);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  List<String> selected() =>
      controller.selectedRows.map((ScanRow row) => row.path).toList();

  testWidgets('the rectangle selects exactly the rows it crosses', (
    WidgetTester tester,
  ) async {
    await pumpFourRows(tester);
    await dragOver(tester, '/data/2', '/data/4');

    expect(selected(), <String>['/data/2', '/data/3', '/data/4']);
  });

  testWidgets('a rectangle replaces the earlier selection', (
    WidgetTester tester,
  ) async {
    await pumpFourRows(tester);
    await tester.tap(find.byKey(const Key('row-select-/data/1')));
    await tester.pumpAndSettle();
    expect(selected(), <String>['/data/1']);

    await dragOver(tester, '/data/3', '/data/4');
    expect(selected(), <String>['/data/3', '/data/4']);
  });

  testWidgets('holding control adds the rectangle to what was selected', (
    WidgetTester tester,
  ) async {
    await pumpFourRows(tester);
    await tester.tap(find.byKey(const Key('row-select-/data/1')));
    await tester.pumpAndSettle();

    await dragOver(
      tester,
      '/data/3',
      '/data/4',
      also: LogicalKeyboardKey.controlLeft,
    );

    expect(selected(), <String>['/data/1', '/data/3', '/data/4']);
  });

  testWidgets('the box is drawn only while the pointer is down', (
    WidgetTester tester,
  ) async {
    await pumpFourRows(tester);
    final Offset start =
        tester.getCenter(find.byKey(const Key('result-row-/data/2'))) +
        const Offset(60, 4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(30, 60));
    await tester.pump();

    expect(find.byKey(const Key('selection-box')), findsOneWidget);

    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selection-box')), findsNothing);
  });

  testWidgets('a press without the modifier never draws a box', (
    WidgetTester tester,
  ) async {
    await pumpFourRows(tester);
    final Offset start =
        tester.getCenter(find.byKey(const Key('result-row-/data/2'))) +
        const Offset(60, 4);
    final TestGesture gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(30, 60));
    await tester.pump();

    expect(
      find.byKey(const Key('selection-box')),
      findsNothing,
      reason: 'a plain drag belongs to the scroll view',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a press below the rows leaves the selection alone', (
    WidgetTester tester,
  ) async {
    await pumpFourRows(tester);
    await tester.tap(find.byKey(const Key('row-select-/data/2')));
    await tester.pumpAndSettle();

    // Empty space under the last row: no row is toggled and no box is drawn.
    final Offset at =
        tester.getBottomLeft(find.byKey(const Key('result-row-/data/4'))) +
        const Offset(60, 40);
    final TestGesture gesture = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(2, 2));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected(), <String>['/data/2']);
  });
}
