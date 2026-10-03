import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/results_panel.dart';

import 'support/stub_engine.dart';

/// A column a reader widened stays widened for that scanner, and the layout can be given back.
void main() {
  test('an override replaces the flexed width for its own tool and column', () {
    final ToolSpec tool = stubTools.first;
    final List<double> plain = tableWidths(1200, tool, true);
    final List<double> widened = tableWidths(
      1200,
      tool,
      true,
      overrides: <String, double>{
        '${tool.id}:name': 400,
        '${tool.id}:size': 200,
        'other_tool:size': 999,
      },
    );

    // Layout order is select, group, name, then the tool's own columns.
    expect(widened[2], 400);
    expect(widened[3], 200);
    expect(plain[3], isNot(200));
    expect(widened, hasLength(plain.length));
  });

  test(
    'an override still applies when the lane is narrower than the minimums',
    () {
      final ToolSpec tool = stubTools.first;
      final List<double> squeezed = tableWidths(
        100,
        tool,
        true,
        overrides: <String, double>{'${tool.id}:size': 300},
      );

      expect(squeezed[3], 300);
    },
  );

  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine(tools: stubTools);
    controller = BoardController(engine: engine);
  });

  Future<void> pumpRows(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['/data']);
    controller.selectTool('big_files');
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('big_files', <ScanRow>[
          StubEngine.row('/data/a', size: 100),
          StubEngine.row('/data/b', size: 200),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets('dragging the hairline widens that column only', (
    WidgetTester tester,
  ) async {
    await pumpRows(tester);
    final double before = tester
        .getSize(find.byKey(Key('column-header-${Labels.of('col_size')}')))
        .width;

    await tester.drag(
      find.byKey(const Key('column-resize-size')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    final double after = tester
        .getSize(find.byKey(Key('column-header-${Labels.of('col_size')}')))
        .width;
    expect(after - before, closeTo(60, 1));
    expect(controller.columnWidths['big_files:size'], after);
    expect(
      tester
          .getSize(
            find.byKey(Key('column-header-${Labels.of('col_modified')}')),
          )
          .width,
      isNot(after),
      reason: 'the neighbour keeps its own width',
    );
  });

  testWidgets('the reset action gives the columns back to the layout', (
    WidgetTester tester,
  ) async {
    await pumpRows(tester);
    final double before = tester
        .getSize(find.byKey(Key('column-header-${Labels.of('col_size')}')))
        .width;
    await tester.drag(
      find.byKey(const Key('column-resize-size')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(controller.columnWidths['big_files:size'], isNotNull);

    await tester.ensureVisible(find.byKey(const Key('reset-columns')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-columns')));
    await tester.pumpAndSettle();

    expect(controller.columnWidths.containsKey('big_files:size'), isFalse);
    expect(
      tester
          .getSize(find.byKey(Key('column-header-${Labels.of('col_size')}')))
          .width,
      before,
    );
    expect(
      find.byKey(const Key('reset-columns')),
      findsNothing,
      reason: 'the action leaves once there is nothing to reset',
    );
  });

  testWidgets('a dragged width survives switching tools and coming back', (
    WidgetTester tester,
  ) async {
    await pumpRows(tester);
    await tester.drag(
      find.byKey(const Key('column-resize-size')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    final double widened = controller.columnWidths['big_files:size']!;

    controller.selectTool('duplicate_files');
    await tester.pumpAndSettle();
    controller.selectTool('big_files');
    await tester.pumpAndSettle();

    expect(controller.columnWidths['big_files:size'], widened);
  });
}
