import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// The reference table is pointer-only; the board promises keyboard too, so the cursor has to obey
/// the same selection rules a click does and stay inside the rows the table actually shows.
Future<void> drain() => Future<void>.delayed(Duration.zero);

/// A key press the board can see: the handler answers the down event, and the up event releases the
/// modifiers a test may be holding.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  /// Starts a scan that answers immediately. A `testWidgets` body runs in fake async, so a widget
  /// test must not await the drain: the event lands during its first pump instead.
  void prepareScan(List<ScanRow> rows) {
    controller.addIncluded(<String>['/data']);
    controller.selectTool('duplicate_files');
    controller.startScan();
    engine.emit(
      ScanEventCompleted(StubEngine.outcome('duplicate_files', rows)),
    );
  }

  Future<void> scan(List<ScanRow> rows) async {
    prepareScan(rows);
    await drain();
  }

  List<ScanRow> three() => <ScanRow>[
    StubEngine.row('/data/one.jpg', size: 100),
    StubEngine.row('/data/two.jpg', size: 200),
    StubEngine.row('/data/three.jpg', size: 300),
  ];

  group('cursor rules', () {
    test(
      'a result set starts without a cursor and an empty table ignores arrows',
      () async {
        controller.addIncluded(<String>['/data']);
        controller.selectTool('duplicate_files');
        controller.moveCursor(1);
        controller.setCursor(3);
        expect(controller.cursorIndex, -1);
        expect(controller.cursorRow, isNull);

        await scan(three());
        expect(controller.cursorIndex, -1);
        controller.setCursor(1);
        expect(controller.cursorIndex, 1);

        // A new scan replaces the rows, so the cursor may not keep pointing at the last result.
        controller.startScan();
        engine.emit(
          ScanEventCompleted(
            StubEngine.outcome('duplicate_files', <ScanRow>[]),
          ),
        );
        await drain();
        expect(controller.cursorIndex, -1);
      },
    );

    test('the first arrow lands on the end it points at', () async {
      await scan(three());
      controller.moveCursor(-1);
      expect(controller.cursorRow?.path, '/data/three.jpg');

      await scan(three());
      controller.moveCursor(1);
      expect(controller.cursorRow?.path, '/data/one.jpg');
    });

    test('the cursor stops at both ends instead of wrapping', () async {
      await scan(three());

      for (int step = 0; step < 10; step++) {
        controller.moveCursor(1);
      }
      expect(controller.cursorIndex, 2);

      for (int step = 0; step < 10; step++) {
        controller.moveCursor(-1);
      }
      expect(controller.cursorIndex, 0);

      controller.setCursor(99);
      expect(controller.cursorIndex, 2);
      controller.setCursor(-5);
      expect(controller.cursorIndex, 0);
    });

    test(
      'a filter that hides the cursor row leaves it on a row the table shows',
      () async {
        await scan(three());
        controller.setCursor(2);

        controller.setFilter('two');
        expect(controller.visibleRows, hasLength(1));
        expect(controller.cursorIndex, 0);
        expect(controller.cursorRow?.path, '/data/two.jpg');
      },
    );

    test('a click places the cursor where the reader pointed', () async {
      await scan(three());

      controller.placeCursor('/data/two.jpg');
      expect(controller.cursorIndex, 1);
      expect(controller.isCursor(controller.visibleRows[1]), isTrue);

      controller.placeCursor('/data/not-here');
      expect(controller.cursorIndex, 1);
    });

    test('space checks the cursor row and checks it off again', () async {
      await scan(three());
      controller.setCursor(1);

      controller.toggleCursorSelection();
      expect(controller.selectedCount, 1);
      expect(controller.isSelected(controller.visibleRows[1]), isTrue);

      controller.toggleCursorSelection();
      expect(controller.selectedCount, 0);
    });

    test('shift at the cursor extends from the last plain click', () async {
      await scan(three());

      controller.clickSelect(
        controller.visibleRows[0],
        additive: false,
        ranged: false,
      );
      controller.setCursor(2);
      controller.extendCursorSelection();

      expect(controller.selectedCount, 3);
    });

    test('a reference row is not a keyboard target', () async {
      await scan(<ScanRow>[
        StubEngine.row('/data/keep.jpg', size: 100, group: 0, start: true),
        StubEngine.row('/data/ref.jpg', size: 100, group: 0, reference: true),
      ]);
      final int reference = controller.visibleRows.indexWhere(
        (ScanRow row) => row.isReference,
      );
      controller.setCursor(reference);

      controller.toggleCursorSelection();
      controller.extendCursorSelection();

      expect(controller.selectedCount, 0);
    });
  });

  group('keys reach the table', () {
    Future<void> pumpScanned(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      prepareScan(three());
      await tester.pumpWidget(KisakiBoardApp(controller: controller));
      await tester.pumpAndSettle();
    }

    Future<void> focusTable(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('result-row-/data/one.jpg')));
      await tester.pumpAndSettle();
      expect(controller.cursorIndex, 0);
    }

    testWidgets(
      'a click hands focus to the table, then the arrows move the cursor',
      (WidgetTester tester) async {
        await pumpScanned(tester);
        await focusTable(tester);

        expect(
          Focus.of(
            tester.element(find.byKey(const Key('result-row-/data/one.jpg'))),
          ).hasFocus,
          isTrue,
        );

        await press(tester, LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(controller.cursorIndex, 1);

        await press(tester, LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(controller.cursorIndex, 0);
      },
    );

    testWidgets('space checks the row under the cursor without a mouse', (
      WidgetTester tester,
    ) async {
      await pumpScanned(tester);
      await focusTable(tester);
      expect(
        controller.selectedCount,
        1,
        reason: 'the click that brought focus already picked that row',
      );

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(controller.selectedCount, 2);
      expect(
        tester
            .widget<Checkbox>(find.byKey(const Key('row-select-/data/two.jpg')))
            .value,
        isTrue,
      );

      await press(tester, LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.selectedCount, 1);
      expect(
        tester
            .widget<Checkbox>(find.byKey(const Key('row-select-/data/two.jpg')))
            .value,
        isFalse,
      );
    });

    testWidgets('shift with an arrow ranges the rows over', (
      WidgetTester tester,
    ) async {
      await pumpScanned(tester);
      await focusTable(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(controller.cursorIndex, 2);
      expect(controller.selectedCount, 3);
    });

    testWidgets('home and end jump, page down steps ten rows', (
      WidgetTester tester,
    ) async {
      await pumpScanned(tester);
      await focusTable(tester);

      await press(tester, LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(controller.cursorIndex, 2);

      await press(tester, LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(controller.cursorIndex, 0);

      await press(tester, LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(controller.cursorIndex, 2);
    });

    testWidgets('enter opens the picture under the cursor', (
      WidgetTester tester,
    ) async {
      await pumpScanned(tester);
      await focusTable(tester);

      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('preview-close')), findsOneWidget);
      expect(controller.previewOpen, isTrue);

      await tester.tap(find.byKey(const Key('preview-close')));
      await tester.pumpAndSettle();
      expect(controller.previewOpen, isFalse);
    });

    testWidgets(
      'the cursor rule is drawn on the row the keyboard holds, and only there',
      (WidgetTester tester) async {
        await pumpScanned(tester);
        Finder rule(String path) => find.descendant(
          of: find.byKey(Key('result-row-$path')),
          matching: find.byKey(const Key('cursor-rule')),
        );

        expect(
          rule('/data/one.jpg'),
          findsNothing,
          reason: 'no row owns the rule before the keyboard takes one',
        );

        await focusTable(tester);
        expect(rule('/data/one.jpg'), findsOneWidget);
        expect(rule('/data/two.jpg'), findsNothing);

        await press(tester, LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(rule('/data/one.jpg'), findsNothing);
        expect(rule('/data/two.jpg'), findsOneWidget);
      },
    );
  });
}
