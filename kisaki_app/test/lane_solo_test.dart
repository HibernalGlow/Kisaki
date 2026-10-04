import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// One lane at the size of the whole board, the reference's solo lane: the reader points at the table
/// or at the numbers and the other two get out of the way.
void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  void useWideWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> pumpScannedBoard(WidgetTester tester) async {
    useWideWindow(tester);
    controller.addIncluded(<String>['/data']);
    controller.selectTool('duplicate_files');
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row('/data/one.jpg', size: 100, group: 0, start: true),
          StubEngine.row('/data/two.png', size: 200, group: 0),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> tapSolo(WidgetTester tester, String lane) async {
    await tester.tap(find.byKey(Key('lane-solo-$lane')));
    await tester.pumpAndSettle();
  }

  group('the solo rules', () {
    test('the board starts with all three lanes', () {
      controller.addIncluded(<String>['/data']);
      expect(controller.layout.soloLane, isNull);
    });

    test('a lane takes the board and gives it back', () {
      controller.addIncluded(<String>['/data']);
      controller.toggleSoloLane('results');
      expect(controller.layout.soloLane, 'results');

      controller.toggleSoloLane('source');
      expect(
        controller.layout.soloLane,
        'source',
        reason: 'the newest claim wins, as in the reference',
      );

      controller.toggleSoloLane('source');
      expect(controller.layout.soloLane, isNull);
    });

    test('a collapsed lane opens when it goes solo', () {
      controller.addIncluded(<String>['/data']);
      controller.toggleLane('analysis');
      expect(controller.layout.analysisCollapsed, isTrue);

      controller.toggleSoloLane('analysis');
      expect(controller.layout.analysisCollapsed, isFalse);
      expect(
        controller.layout.soloLane,
        'analysis',
        reason: 'a 48 pixel strip would leave no control on the board',
      );
    });

    test('resetting the layout brings the other lanes back', () {
      controller.addIncluded(<String>['/data']);
      controller.toggleSoloLane('source');
      controller.resetLayout();
      expect(controller.layout.soloLane, isNull);
    });
  });

  group('the board with one lane', () {
    testWidgets('the table keeps the width and the other lanes leave', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);
      await tapSolo(tester, 'results');

      expect(find.byKey(const Key('lane-R')), findsOneWidget);
      expect(find.byKey(const Key('lane-S')), findsNothing);
      expect(find.byKey(const Key('lane-A')), findsNothing);
      expect(
        find.byKey(const Key('row-select-/data/one.jpg')),
        findsOneWidget,
        reason: 'the soloed table still shows its rows',
      );

      await tapSolo(tester, 'results');
      expect(find.byKey(const Key('lane-S')), findsOneWidget);
      expect(find.byKey(const Key('lane-A')), findsOneWidget);
    });

    testWidgets('the header button asks for the way back', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);
      Labels.fallbackKeys.clear();

      await tapSolo(tester, 'source');

      expect(
        find.descendant(
          of: find.byKey(const Key('lane-S')),
          matching: find.text(Labels.of('lane-unsolo')),
        ),
        findsNothing,
        reason: 'the button is icon only, so its label is a tooltip',
      );
      expect(find.byKey(const Key('lane-solo-source')), findsOneWidget);
      expect(Labels.fallbackKeys, isEmpty);
    });
  });
}
