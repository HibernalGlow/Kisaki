import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/floating_panel.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// The float keeps the numbers on screen while the lanes use the whole width, so the tests check that
/// it opens over the board, takes the lane's place, and answers both a pointer and the keyboard.
void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  void useWideWindow(
    WidgetTester tester, {
    Size size = const Size(1600, 1200),
  }) {
    tester.view.physicalSize = size;
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

  Future<void> openFloat(WidgetTester tester) async {
    await pumpScannedBoard(tester);
    await tester.tap(find.byKey(const Key('floating-analysis-toggle')));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.pumpAndSettle();
  }

  /// A press with a modifier held for its duration.
  Future<void> pressWith(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await press(tester, key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  FloatingRect rectNow() => controller.floatingPanel.rect;

  group('the float over the board', () {
    testWidgets('the toggle floats the analysis and takes the lane back', (
      WidgetTester tester,
    ) async {
      await openFloat(tester);

      expect(find.byKey(const Key('floating-analysis')), findsOneWidget);
      expect(find.byKey(const Key('analysis-lane-hidden')), findsOneWidget);
      expect(find.byKey(const Key('lane-A')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('floating-analysis')),
          matching: find.byKey(const Key('analysis-card')),
        ),
        findsOneWidget,
        reason: 'the float carries the same numbers the lane showed',
      );
    });

    testWidgets('the header names itself and the label is authored', (
      WidgetTester tester,
    ) async {
      await openFloat(tester);
      Labels.fallbackKeys.clear();

      expect(
        find.descendant(
          of: find.byKey(const Key('floating-analysis')),
          matching: find.text(Labels.of('floating-title')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('floating-analysis')),
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Semantics &&
                widget.properties.label == Labels.of('floating-move'),
          ),
        ),
        findsOneWidget,
        reason:
            'the drag surface says what it does, as the reference header does',
      );
      expect(Labels.fallbackKeys, isEmpty);
    });

    testWidgets('closing it docks the lane again', (WidgetTester tester) async {
      await openFloat(tester);
      await tester.tap(find.byKey(const Key('floating-close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('floating-analysis')), findsNothing);
      expect(find.byKey(const Key('lane-A')), findsOneWidget);
      expect(controller.floatingAnalysisOpen, isFalse);
    });

    testWidgets('a drag of the header moves the panel by the same distance', (
      WidgetTester tester,
    ) async {
      await openFloat(tester);
      final FloatingRect before = rectNow();

      await tester.drag(
        find.byKey(const Key('floating-header')),
        const Offset(-120, 80),
      );
      await tester.pumpAndSettle();

      expect(rectNow().x, before.x - 120);
      expect(rectNow().y, before.y + 80);
      expect(
        rectNow().width,
        before.width,
        reason: 'a drag of the header never resizes',
      );
    });

    testWidgets('a drag past the board edge sticks there and drags back', (
      WidgetTester tester,
    ) async {
      await openFloat(tester);

      await tester.drag(
        find.byKey(const Key('floating-header')),
        const Offset(5000, 0),
      );
      await tester.pumpAndSettle();
      expect(
        rectNow().x,
        controller.floatingViewport.width - rectNow().width - kFloatingMargin,
        reason: 'the panel stops at the margin instead of leaving the board',
      );

      await tester.drag(
        find.byKey(const Key('floating-header')),
        const Offset(-200, 0),
      );
      await tester.pumpAndSettle();
      expect(
        rectNow().x,
        controller.floatingViewport.width -
            rectNow().width -
            kFloatingMargin -
            200,
      );
    });

    testWidgets('the east handle widens it and the origin stays', (
      WidgetTester tester,
    ) async {
      await openFloat(tester);
      final FloatingRect before = rectNow();

      await tester.drag(
        find.byKey(const Key('floating-resize-east')),
        const Offset(100, 0),
      );
      await tester.pumpAndSettle();

      expect(rectNow().width, before.width + 100);
      expect(rectNow().x, before.x);
      expect(rectNow().height, before.height);
    });

    testWidgets(
      'a west drag stops at the narrowest panel with the far edge anchored',
      (WidgetTester tester) async {
        await openFloat(tester);
        final FloatingRect before = rectNow();

        await tester.drag(
          find.byKey(const Key('floating-resize-west')),
          const Offset(200, 0),
        );
        await tester.pumpAndSettle();

        expect(rectNow().width, kFloatingMinWidth);
        expect(
          rectNow().x + rectNow().width,
          before.x + before.width,
          reason: 'the edge the reader is dragging away from must not move',
        );
      },
    );

    testWidgets('the corner square pulls both of its edges', (
      WidgetTester tester,
    ) async {
      await openFloat(tester);
      final FloatingRect before = rectNow();

      await tester.drag(
        find.byKey(const Key('floating-resize-southEast')),
        const Offset(30, -40),
      );
      await tester.pumpAndSettle();

      expect(rectNow().width, before.width + 30);
      expect(rectNow().height, before.height - 40);
    });

    testWidgets(
      'the keyboard moves it by twelve and by thirty-two with Shift',
      (WidgetTester tester) async {
        await openFloat(tester);
        await tester.tap(find.byKey(const Key('floating-header')));
        await tester.pumpAndSettle();
        final FloatingRect before = rectNow();

        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(rectNow().x, before.x - 12);

        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(rectNow().y, before.y - 12);

        await pressWith(
          tester,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.arrowRight,
        );
        expect(rectNow().x, before.x - 12 + 32);
      },
    );

    testWidgets('Alt turns the arrows into a resize', (
      WidgetTester tester,
    ) async {
      await openFloat(tester);
      await tester.tap(find.byKey(const Key('floating-header')));
      await tester.pumpAndSettle();
      final FloatingRect before = rectNow();

      await pressWith(
        tester,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.arrowRight,
      );
      await tester.pumpAndSettle();

      expect(rectNow().width, before.width + 12);
      expect(
        rectNow().x,
        before.x,
        reason: 'Alt resizes from the south east corner',
      );
    });

    testWidgets('a plain key the panel does not use is left for the board', (
      WidgetTester tester,
    ) async {
      await openFloat(tester);
      await tester.tap(find.byKey(const Key('floating-header')));
      await tester.pumpAndSettle();
      final FloatingRect before = rectNow();

      await press(tester, LogicalKeyboardKey.keyZ);

      expect(rectNow(), before);
    });

    testWidgets('a window shrunk around it pulls the panel back inside', (
      WidgetTester tester,
    ) async {
      await openFloat(tester);
      await tester.drag(
        find.byKey(const Key('floating-header')),
        const Offset(5000, 0),
      );
      await tester.pumpAndSettle();
      final double wideBefore = rectNow().x;

      tester.view.physicalSize = const Size(1000, 900);
      await tester.pumpAndSettle();

      expect(
        rectNow().x + rectNow().width,
        lessThanOrEqualTo(controller.floatingViewport.width - kFloatingMargin),
      );
      final Offset body = tester.getTopLeft(find.byKey(const Key('lane-S')));
      final Offset painted = tester.getTopLeft(
        find.byKey(const Key('floating-analysis')),
      );
      expect(
        Offset(painted.dx - body.dx, painted.dy - body.dy),
        Offset(rectNow().x, rectNow().y),
        reason: 'the painted panel is the one the model holds',
      );
      expect(rectNow().x, lessThan(wideBefore));
    });
  });

  group('who may float', () {
    test('a board narrower than the reference cutoff refuses the float', () {
      controller.addIncluded(<String>['/data']);
      controller.reportFloatingViewport(700, 900);

      expect(controller.floatingAnalysisAvailable, isFalse);
      controller.toggleFloatingPanel();
      expect(
        controller.floatingAnalysisOpen,
        isFalse,
        reason: 'a panel on top of a 700 pixel board would cover the table it reports on',
      );
      expect(controller.dockedAnalysisVisible, isTrue);

      controller.reportFloatingViewport(1584, 1136);
      expect(controller.floatingAnalysisAvailable, isTrue);
      controller.toggleFloatingPanel();
      expect(controller.floatingAnalysisOpen, isTrue);
      expect(controller.dockedAnalysisVisible, isFalse);
    });

    test(
      'resetting the layout docks the panel and puts it back where it started',
      () {
        controller.addIncluded(<String>['/data']);
        controller.reportFloatingViewport(1584, 1136);
        controller.toggleFloatingPanel();
        controller.moveFloatingPanel(-600, 300);

        controller.resetLayout();

        expect(controller.floatingAnalysisOpen, isFalse);
        expect(
          controller.floatingPanel.rect,
          createDefaultFloatingPanel(controller.floatingViewport).rect,
        );
      },
    );

    test('a viewport is only reported once per size, so the board is not rebuilt for nothing', () {
      int notified = 0;
      controller.addListener(() => notified += 1);
      controller.reportFloatingViewport(1584, 1136);
      controller.reportFloatingViewport(1584, 1136);
      expect(notified, 0);

      controller.reportFloatingViewport(1200, 900);
      expect(controller.floatingViewport.width, 1200);
    });
  });
}
