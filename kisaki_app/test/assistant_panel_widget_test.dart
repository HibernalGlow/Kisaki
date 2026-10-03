import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/assistant_panel.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/widgets/primitives.dart';

import 'support/stub_engine.dart';

/// Proves the assistant is reachable, drives the ported rule engine, and can be worked from the
/// keyboard, rather than only rendering controls.
void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  Future<void> pumpGroupedBoard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
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
          dup('/data/a.bin', 100, 1000),
          dup('/data/b.bin', 200, 2000),
          dup('/data/c.bin', 300, 3000),
          dup('/data/ref.bin', 400, 4000, reference: true),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.visibleRows, hasLength(4));
  }

  Future<void> openAssistant(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-assistant')));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantPanel), findsOneWidget);
  }

  /// The dialog scrolls, so a control below the fold has to be brought into view first; tapping a
  /// stale center hits the clip instead of the button.
  Future<void> tapControl(WidgetTester tester, String key) async {
    final Finder finder = find.byKey(Key(key), skipOffstage: false);
    expect(finder, findsOneWidget, reason: 'missing the $key control');
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('the header opens the assistant with every rule control', (
    WidgetTester tester,
  ) async {
    await pumpGroupedBoard(tester);
    await openAssistant(tester);

    for (final String key in <String>[
      'assistant-apply-mode',
      'assistant-tab-group',
      'assistant-tab-text',
      'assistant-tab-directory',
      'assistant-group-mode',
      'assistant-criterion-field-0',
      'assistant-criterion-direction-0',
      'assistant-criterion-condition-0',
      'assistant-criterion-value-0',
      'assistant-criterion-enabled-0',
      'assistant-criterion-prefer-empty-0',
      'assistant-add-criterion',
      'assistant-apply-group',
      'assistant-select-all',
      'assistant-invert',
      'assistant-clear',
      'assistant-export',
      'assistant-import',
      'assistant-reset',
      'assistant-undo',
      'assistant-redo',
    ]) {
      expect(
        find.byKey(Key(key), skipOffstage: false),
        findsOneWidget,
        reason: 'missing the $key control',
      );
    }
  });

  testWidgets('every label the assistant paints is authored', (
    WidgetTester tester,
  ) async {
    await pumpGroupedBoard(tester);
    Labels.fallbackKeys.clear();
    await openAssistant(tester);

    await tapControl(tester, 'assistant-tab-text');
    await tapControl(tester, 'assistant-tab-directory');
    await tapControl(tester, 'assistant-tab-group');
    await tapControl(tester, 'assistant-add-criterion');
    await tapControl(tester, 'assistant-export');

    expect(Labels.fallbackKeys, isEmpty);
  });

  testWidgets('the group rule keeps the newest entry, and undo takes it back', (
    WidgetTester tester,
  ) async {
    await pumpGroupedBoard(tester);
    await openAssistant(tester);

    await tapControl(tester, 'assistant-apply-group');

    // Default criterion: modification date descending, everything but the first of the group.
    expect(controller.selectedCount, 2);
    expect(
      controller.selectedRows.map((ScanRow row) => row.path),
      containsAll(<String>['/data/a.bin', '/data/b.bin']),
    );
    expect(
      controller.selectedRows.map((ScanRow row) => row.path),
      isNot(contains('/data/ref.bin')),
      reason: 'a reference entry must never enter the selection',
    );
    expect(
      find.byKey(const Key('assistant-message')),
      findsOneWidget,
      reason: 'the apply result has to be visible, not only applied',
    );
    expect(
      find.text(
        Labels.of(
          'assistant-matched',
          args: const <String, Object>{'matched': 2, 'affected': 2},
        ),
      ),
      findsOneWidget,
    );

    await tapControl(tester, 'assistant-undo');
    expect(controller.selectedCount, 0);

    await tapControl(tester, 'assistant-redo');
    expect(controller.selectedCount, 2);
  });

  testWidgets('Ctrl+Enter applies the rule on the open tab', (
    WidgetTester tester,
  ) async {
    await pumpGroupedBoard(tester);
    await openAssistant(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(controller.selectedCount, 2);
  });

  testWidgets('Ctrl+Backspace clears the selection from the dialog', (
    WidgetTester tester,
  ) async {
    await pumpGroupedBoard(tester);
    await openAssistant(tester);
    await tapControl(tester, 'assistant-select-all');
    expect(controller.selectedCount, 3);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(controller.selectedCount, 0);
  });

  testWidgets('the text rule needs a pattern before it can apply', (
    WidgetTester tester,
  ) async {
    await pumpGroupedBoard(tester);
    await openAssistant(tester);
    await tapControl(tester, 'assistant-tab-text');

    await tester.tap(
      find.byKey(const Key('assistant-apply-text')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      controller.selectedCount,
      0,
      reason: 'an empty pattern must not select anything',
    );

    await tester.enterText(
      find.byKey(const Key('assistant-text-pattern')),
      'a.bin',
    );
    await tester.pumpAndSettle();
    await tapControl(tester, 'assistant-apply-text');

    expect(controller.selectedCount, 1);
    expect(controller.selectedRows.single.path, '/data/a.bin');
  });

  testWidgets(
    'the directory rule reports a missing directory instead of clearing',
    (WidgetTester tester) async {
      await pumpGroupedBoard(tester);
      await openAssistant(tester);
      await tapControl(tester, 'assistant-tab-directory');
      await tapControl(tester, 'assistant-directory-mode');

      await tester.tap(
        find
            .text(Labels.of('assistant-directory-select-all-in-directory'))
            .last,
      );
      await tester.pumpAndSettle();
      await tapControl(tester, 'assistant-apply-directory');

      expect(
        find.text(Labels.of('assistant-directory-required')),
        findsOneWidget,
      );
      expect(controller.selectedCount, 0);
    },
  );

  testWidgets('invert and select-all skip reference entries', (
    WidgetTester tester,
  ) async {
    await pumpGroupedBoard(tester);
    await openAssistant(tester);

    await tapControl(tester, 'assistant-select-all');
    expect(controller.selectedCount, 3);

    await tapControl(tester, 'assistant-invert');
    expect(controller.selectedCount, 0);

    await tapControl(tester, 'assistant-select-all');
    await tapControl(tester, 'assistant-clear');
    expect(controller.selectedCount, 0);
    expect(controller.canUndoSelection, isTrue);
  });

  testWidgets('the transfer field round-trips the rules', (
    WidgetTester tester,
  ) async {
    await pumpGroupedBoard(tester);
    await openAssistant(tester);

    await tapControl(tester, 'assistant-add-criterion');
    await tapControl(tester, 'assistant-export');

    final String exported = tester
        .widget<BoardField>(find.byKey(const Key('assistant-transfer')))
        .value;
    expect(controller.assistant.group.sortCriteria, hasLength(2));

    await tapControl(tester, 'assistant-reset');
    expect(controller.assistant.group.sortCriteria, hasLength(1));

    await tester.enterText(
      find.byKey(const Key('assistant-transfer')),
      exported,
    );
    await tester.pumpAndSettle();
    await tapControl(tester, 'assistant-import');
    expect(controller.assistant.group.sortCriteria, hasLength(2));

    await tester.enterText(
      find.byKey(const Key('assistant-transfer')),
      'not json',
    );
    await tester.pumpAndSettle();
    await tapControl(tester, 'assistant-import');
    expect(find.byKey(const Key('assistant-message')), findsOneWidget);
  });
}

ScanRow dup(String path, int size, int modified, {bool reference = false}) =>
    ScanRow(
      path: path,
      name: path.split('/').last,
      directory: '/data',
      cells: const <String>[],
      sizeBytes: size,
      modifiedTs: modified,
      groupIndex: 0,
      groupSize: 4,
      isGroupStart: false,
      isReference: reference,
      sortKeys: <int>[size, modified],
    );
