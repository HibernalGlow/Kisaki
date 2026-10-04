import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/card_layout.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// The reference offers two arrangements of the same blocks - a stack, and one card at a time behind a
/// strip - so the board has to switch between them without ever losing a block or its selection.
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

  Future<void> useTabs(WidgetTester tester, CardPanel panel) async {
    await tester.tap(find.byKey(Key('cards-display-${panel.name}')));
    await tester.pumpAndSettle();
  }

  group('the display rules', () {
    test('a lane starts stacked and the switch is per lane', () {
      controller.addIncluded(<String>['/data']);
      expect(controller.cardDisplay(CardPanel.analysis), CardDisplay.stack);

      controller.toggleCardDisplay(CardPanel.analysis);
      expect(controller.cardDisplay(CardPanel.analysis), CardDisplay.tabs);
      expect(controller.cardDisplay(CardPanel.source), CardDisplay.stack);

      controller.toggleCardDisplay(CardPanel.analysis);
      expect(controller.cardDisplay(CardPanel.analysis), CardDisplay.stack);
    });

    test('the open tab is the first visible card when nothing was chosen', () {
      controller.addIncluded(<String>['/data']);
      expect(controller.activeCard(CardPanel.analysis), CardId.preview);
      expect(controller.activeCard(CardPanel.source), CardId.sourceSettings);
    });

    test('hiding the open card falls back instead of showing nothing', () {
      controller.addIncluded(<String>['/data']);
      controller.setActiveCard(CardPanel.analysis, CardId.logs);
      expect(controller.activeCard(CardPanel.analysis), CardId.logs);

      controller.setCardVisible(CardId.logs, false);
      expect(
        controller.activeCard(CardPanel.analysis),
        CardId.preview,
        reason: 'a hidden card cannot stay the open tab',
      );

      controller.setCardVisible(CardId.preview, false);
      controller.setCardVisible(CardId.analysis, false);
      controller.setCardVisible(CardId.selection, false);
      controller.setCardVisible(CardId.operations, false);
      expect(
        controller.activeCard(CardPanel.analysis),
        isNull,
        reason: 'a lane with no visible card has no tab at all',
      );
    });

    test('choosing the tab that is already open wakes nobody', () {
      controller.addIncluded(<String>['/data']);
      int notified = 0;
      controller.addListener(() => notified += 1);
      controller.setActiveCard(CardPanel.analysis, CardId.preview);
      expect(notified, 0);

      controller.setActiveCard(CardPanel.analysis, CardId.logs);
      expect(notified, 1);
    });

    test('a lane emptied of visible cards reports no tab', () {
      controller.addIncluded(<String>['/data']);
      for (final CardId id in CardId.values) {
        controller.setCardVisible(id, false);
      }
      expect(controller.activeCard(CardPanel.analysis), isNull);
      expect(controller.activeCard(CardPanel.source), isNull);
    });
  });

  group('the strip over the lane', () {
    testWidgets('switching to tabs keeps exactly one block painted', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);
      await useTabs(tester, CardPanel.analysis);

      expect(find.byKey(const Key('card-tab-preview')), findsOneWidget);
      expect(find.byKey(const Key('card-tab-logs')), findsOneWidget);
      expect(find.byKey(const Key('card-collapse-analysis')), findsNothing);
      expect(
        find.byKey(const Key('analysis-card')),
        findsNothing,
        reason: 'the preview card is the first tab, so the statistics are behind it',
      );
      expect(
        find.byKey(const Key('activity-card')),
        findsNothing,
        reason: 'only the open block is painted',
      );
    });

    testWidgets('a tab paints its own block and nothing else', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);
      await useTabs(tester, CardPanel.analysis);

      await tester.tap(find.byKey(const Key('card-tab-analysis')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analysis-card')), findsOneWidget);
      expect(find.byKey(const Key('activity-card')), findsNothing);

      await tester.tap(find.byKey(const Key('card-tab-logs')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('activity-card')), findsOneWidget);
      expect(find.byKey(const Key('analysis-card')), findsNothing);
    });

    testWidgets('switching back to tabs leaves the stack behind', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);
      await useTabs(tester, CardPanel.analysis);
      await tester.tap(find.byKey(const Key('card-tab-logs')));
      await tester.pumpAndSettle();

      await useTabs(tester, CardPanel.analysis);

      expect(find.byKey(const Key('card-tab-logs')), findsNothing);
      expect(find.byKey(const Key('card-collapse-logs')), findsOneWidget);
      expect(
        find.byKey(const Key('activity-card')),
        findsOneWidget,
        reason: 'the stacked lane shows every visible card again',
      );
    });

    testWidgets('a lane with one visible card never grows a strip', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);
      for (final CardId id in CardId.values) {
        if (id != CardId.logs) {
          controller.setCardVisible(id, false);
        }
      }
      await tester.pumpAndSettle();

      await useTabs(tester, CardPanel.analysis);

      expect(find.byKey(const Key('card-tab-logs')), findsNothing);
      expect(find.byKey(const Key('card-collapse-logs')), findsOneWidget);
    });

    testWidgets('a lane with nothing visible says so in both arrangements', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);
      for (final CardId id in CardId.values) {
        controller.setCardVisible(id, false);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cards-empty-analysis')), findsOneWidget);

      await useTabs(tester, CardPanel.analysis);

      expect(find.byKey(const Key('cards-empty-analysis')), findsOneWidget);
    });

    testWidgets('every label the tab strip paints is authored', (
      WidgetTester tester,
    ) async {
      await pumpScannedBoard(tester);
      await useTabs(tester, CardPanel.analysis);
      Labels.fallbackKeys.clear();

      await tester.tap(find.byKey(const Key('card-tab-operations')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-tab-selection')));
      await tester.pumpAndSettle();

      expect(Labels.fallbackKeys, isEmpty);
    });
  });
}
