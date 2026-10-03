import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// A stopped or failed scan has to stay explainable while its rows are still on screen, and the
/// mouse has to be able to retry it: the keyboard route (Ctrl+R) alone was the gap.
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
      id: 'big_files',
      glyph: 'B',
      labelKey: 'tool_big_files',
      grouped: false,
      supportsReference: false,
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

  Future<void> pumpBoard(WidgetTester tester, ScanEvent event) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['/data']);
    controller.selectTool('big_files');
    controller.startScan();
    engine.emit(event);
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  ScanOutcome outcome({bool stopped = false}) =>
      StubEngine.outcome('big_files', <ScanRow>[
        StubEngine.row('/data/a', size: 100),
        StubEngine.row('/data/b', size: 200),
      ], stopped: stopped);

  testWidgets('a normal scan shows no warning strip', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester, ScanEventCompleted(outcome()));
    expect(controller.rows, hasLength(2));
    expect(find.byKey(const Key('scan-notice')), findsNothing);
  });

  testWidgets('a stopped scan keeps its rows and offers one retry', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester, ScanEventCompleted(outcome(stopped: true)));

    expect(find.byKey(const Key('scan-notice')), findsOneWidget);
    expect(find.text(controller.statusText), findsWidgets);
    expect(find.text('Scan again'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rescan-scan')));
    await tester.pump();
    expect(controller.phase, ScanPhase.running);
  });

  testWidgets('a failed scan says what broke, not just that it broke', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester, ScanEventCompleted(outcome()));
    engine.emit(const ScanEventFailed('cannot read /data: permission denied'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan-notice')), findsOneWidget);
    expect(find.text('cannot read /data: permission denied'), findsOneWidget);
    expect(controller.rows, hasLength(2));
  });

  testWidgets('a fresh scan retires the strip until it has rows again', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester, ScanEventCompleted(outcome(stopped: true)));
    expect(find.byKey(const Key('scan-notice')), findsOneWidget);

    controller.startScan();
    await tester.pump();

    expect(controller.scanning, isTrue);
    expect(
      find.byKey(const Key('scan-notice')),
      findsNothing,
      reason: 'the stale rows are gone, so there is nothing to warn about yet',
    );
  });
}
