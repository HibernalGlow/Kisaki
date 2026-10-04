import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/widgets/primitives.dart';

import 'support/stub_engine.dart';

/// Which lane comes first is the reader's call, not the board's: the reference lets a lane be dropped
/// onto its neighbour, and the last lane in that order is the one that stretches.
void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  group('the order rules', () {
    test('a stored order is repaired to hold each lane exactly once', () {
      expect(
        normalizeLaneOrder(<String>['results', 'results', 'source']),
        <String>['results', 'source', 'analysis'],
      );
      expect(
        normalizeLaneOrder(<String>['analysis', 'nowhere', 'results']),
        <String>['analysis', 'results', 'source'],
        reason: 'an unknown lane is dropped and the missing one is appended',
      );
      expect(normalizeLaneOrder(<String>[]), <String>[
        'source',
        'results',
        'analysis',
      ]);
    });

    test('a lane moves one place and stops at the ends', () {
      const List<String> start = <String>['source', 'results', 'analysis'];
      expect(reorderLanes(start, 'source', 1), <String>[
        'results',
        'source',
        'analysis',
      ]);
      expect(reorderLanes(start, 'analysis', -5), <String>[
        'analysis',
        'source',
        'results',
      ]);
      expect(reorderLanes(start, 'source', 99), <String>[
        'results',
        'analysis',
        'source',
      ]);
    });

    test('the controller records the move and wakes the board', () {
      controller.addIncluded(<String>['/data']);
      int notified = 0;
      controller.addListener(() => notified += 1);

      controller.moveLane('analysis', 0);

      expect(controller.layout.laneOrder, <String>[
        'analysis',
        'source',
        'results',
      ]);
      expect(notified, 1);

      controller.resetLayout();
      expect(controller.layout.laneOrder, <String>[
        'source',
        'results',
        'analysis',
      ]);
    });
  });

  group('the board in the reader order', () {
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

    Future<void> openLayoutDialog(WidgetTester tester) async {
      // The card manager rides with the analysis blocks, so its button sits on that lane's header.
      await tester.tap(find.byKey(const Key('cards-manage')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card-manager-dialog')), findsOneWidget);
    }

    Future<void> closeLayoutDialog(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('cards-manager-close')));
      await tester.pumpAndSettle();
    }

    double widthOf(WidgetTester tester, String letter) =>
        tester.getSize(find.byKey(Key('lane-$letter'))).width;

    double leftOf(WidgetTester tester, String letter) =>
        tester.getTopLeft(find.byKey(Key('lane-$letter'))).dx;

    testWidgets('the lanes sit in the order the reader chose', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);

      expect(leftOf(tester, 'S'), lessThan(leftOf(tester, 'R')));
      expect(leftOf(tester, 'R'), lessThan(leftOf(tester, 'A')));

      await openLayoutDialog(tester);
      await tester.tap(find.byKey(const Key('lane-later-source')));
      await tester.pumpAndSettle();
      expect(controller.layout.laneOrder, <String>[
        'results',
        'source',
        'analysis',
      ]);

      await tester.tap(find.byKey(const Key('lane-later-source')));
      await tester.pumpAndSettle();
      expect(controller.layout.laneOrder, <String>[
        'results',
        'analysis',
        'source',
      ]);
      await closeLayoutDialog(tester);

      expect(leftOf(tester, 'R'), lessThan(leftOf(tester, 'A')));
      expect(leftOf(tester, 'A'), lessThan(leftOf(tester, 'S')));
      expect(
        widthOf(tester, 'S'),
        greaterThan(widthOf(tester, 'R')),
        reason: 'the last lane in the order takes whatever the board leaves',
      );
    });

    testWidgets('the ends have nowhere to go', (WidgetTester tester) async {
      await pumpScannedBoard(tester);
      await openLayoutDialog(tester);

      expect(
        tester
            .widget<BoardAction>(find.byKey(const Key('lane-earlier-source')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<BoardAction>(find.byKey(const Key('lane-later-analysis')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('lane-earlier-source')));
      await tester.pumpAndSettle();
      expect(controller.layout.laneOrder, <String>[
        'source',
        'results',
        'analysis',
      ]);
    });

    testWidgets('a reordered board still paints every lane and its labels', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);
      await openLayoutDialog(tester);
      await tester.tap(find.byKey(const Key('lane-earlier-analysis')));
      await tester.pumpAndSettle();
      expect(controller.layout.laneOrder, <String>[
        'source',
        'analysis',
        'results',
      ]);
      await closeLayoutDialog(tester);
      Labels.fallbackKeys.clear();
      for (final String letter in <String>['A', 'S', 'R']) {
        expect(find.byKey(Key('lane-$letter')), findsOneWidget);
      }
      expect(
        find.descendant(
          of: find.byKey(const Key('lane-A')),
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is KeyHeading && widget.labelKey == 'lane-analysis',
          ),
        ),
        findsOneWidget,
        reason: 'the micro heading is painted in caps, so the key is the stable claim',
      );
      expect(Labels.fallbackKeys, isEmpty);
    });

    testWidgets('solo and order agree that the soloed lane fills the board', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);
      controller.moveLane('source', 2);
      await tester.pumpAndSettle();

      controller.toggleSoloLane('results');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lane-R')), findsOneWidget);
      expect(find.byKey(const Key('lane-S')), findsNothing);
      expect(
        widthOf(tester, 'R'),
        greaterThan(400),
        reason: 'a solo lane keeps the whole width even when it is last in the order',
      );
    });
  });
}
