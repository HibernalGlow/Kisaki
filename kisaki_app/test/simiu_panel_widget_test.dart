import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/widgets/primitives.dart';

import 'support/stub_engine.dart';

/// The Simiu set mode: the selector belongs to the image scanner only, the plan is visible before it
/// is applied, and both verbs go through the same confirm gate as deletion.
void main() {
  const ColumnDef sizeCol = ColumnDef(
    key: 'size',
    labelKey: 'col_size',
    flex: 0.5,
    minWidth: 84,
    alignRight: true,
  );
  const ColumnDef modifiedCol = ColumnDef(
    key: 'modified',
    labelKey: 'col_modified',
    flex: 1,
    minWidth: 140,
    alignRight: false,
  );

  const List<ToolSpec> tools = <ToolSpec>[
    ToolSpec(
      id: 'similar_images',
      glyph: 'I',
      labelKey: 'tool_similar_images',
      grouped: true,
      supportsReference: true,
      columns: <ColumnDef>[sizeCol, modifiedCol],
      fieldIds: <String>[],
    ),
    ToolSpec(
      id: 'duplicate_files',
      glyph: 'D',
      labelKey: 'tool_duplicate_files',
      grouped: true,
      supportsReference: true,
      columns: <ColumnDef>[sizeCol, modifiedCol],
      fieldIds: <String>[],
    ),
  ];

  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine(tools: tools);
    controller = BoardController(engine: engine);
    engine.simiuApplyOutcome = const SimiuApplyOutcome(
      done: 2,
      planned: 0,
      failed: 0,
      items: <SimiuItem>[],
      journals: <String>['/data/.simiu-undo-1.json'],
      messages: 'moved',
    );
  });

  Future<void> pumpSetsBoard(
    WidgetTester tester, {
    String tool = 'similar_images',
    bool sets = false,
  }) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['/data']);
    controller.selectTool(tool);
    controller.setSimiuEnabled(sets);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome(tool, <ScanRow>[
          StubEngine.row('/data/library/a.jpg', size: 100, group: 0),
          StubEngine.row('/data/library/b.jpg', size: 200, group: 0),
          StubEngine.row('/data/library/alone.jpg', size: 300, group: 1),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> acceptConfirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('confirm-accept')));
    await tester.pumpAndSettle();
  }

  Future<void> openAlgorithmTab(WidgetTester tester) async {
    await tester.tap(find.text(Labels.of('tab-algorithm')));
    await tester.pumpAndSettle();
  }

  testWidgets('only the image scanner offers the set mode', (
    WidgetTester tester,
  ) async {
    await pumpSetsBoard(tester, tool: 'duplicate_files', sets: true);
    await openAlgorithmTab(tester);
    expect(
      find.byKey(const Key('simiu-mode')),
      findsNothing,
      reason: 'the reference shows the selector for similar images only',
    );

    await pumpSetsBoard(tester);
    await openAlgorithmTab(tester);
    expect(find.byKey(const Key('simiu-mode')), findsOneWidget);
    expect(
      find.byKey(const Key('simiu-prefix')),
      findsNothing,
      reason: 'the set fields stay hidden while the scanner mode is chosen',
    );
  });

  testWidgets('switching the dropdown reveals the set fields', (
    WidgetTester tester,
  ) async {
    await pumpSetsBoard(tester);
    await openAlgorithmTab(tester);
    await tester.ensureVisible(find.byKey(const Key('simiu-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simiu-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Labels.of('simiu-mode-sets')).last);
    await tester.pumpAndSettle();

    expect(controller.simiu.enabled, isTrue);
    expect(find.byKey(const Key('simiu-prefix')), findsOneWidget);
    expect(find.byKey(const Key('simiu-min-group')), findsOneWidget);
    expect(find.byKey(const Key('simiu-scan-order')), findsOneWidget);
    expect(
      find.byKey(const Key('view-folders')),
      findsNothing,
      reason: 'the reference hides the folder roll-up while sets are planned',
    );
  });

  testWidgets('the card counts the plan and previews the moves', (
    WidgetTester tester,
  ) async {
    await pumpSetsBoard(tester, sets: true);
    await tester.ensureVisible(find.byKey(const Key('simiu-plan-count')));
    await tester.pumpAndSettle();

    expect(controller.simiuPlan.operations, hasLength(2));
    expect(find.byKey(const Key('simiu-plan-count')), findsOneWidget);
    expect(
      find.text(
        Labels.of(
          'simiu-plan-count',
          args: const <String, Object>{'count': 2, 'folders': 1},
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('/data/library/a.jpg'), findsWidgets);
    expect(
      find.textContaining('/data/library/simiu_set__set_001/a.jpg'),
      findsOneWidget,
    );
  });

  testWidgets('applying asks first and carries the plan to the engine', (
    WidgetTester tester,
  ) async {
    await pumpSetsBoard(tester, sets: true);
    await tester.ensureVisible(find.byKey(const Key('simiu-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simiu-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-dialog')), findsOneWidget);
    expect(
      engine.simiuApplies,
      isEmpty,
      reason: 'nothing runs before the answer',
    );

    await acceptConfirm(tester);
    expect(engine.simiuApplies, hasLength(1));
    final SimiuApplyRequest request = engine.simiuApplies.single;
    expect(request.dryRun, isTrue, reason: 'the board starts in dry run');
    expect(request.mode, SimiuMode.move);
    expect(request.operations, hasLength(2));
    expect(
      request.operations.first.target,
      '/data/library/simiu_set__set_001/a.jpg',
    );

    controller.setDryRun(false);
    controller.setSimiuMode(SimiuMode.link);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('simiu-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simiu-apply')));
    await tester.pumpAndSettle();
    await acceptConfirm(tester);

    expect(engine.simiuApplies, hasLength(2));
    expect(engine.simiuApplies.last.dryRun, isFalse);
    expect(engine.simiuApplies.last.mode, SimiuMode.link);
    expect(
      find.byKey(const Key('simiu-undo')),
      findsOneWidget,
      reason: 'a real apply leaves a journal behind',
    );
  });

  testWidgets('undo replays the newest journal with the cleanup choice', (
    WidgetTester tester,
  ) async {
    await pumpSetsBoard(tester, sets: true);
    expect(
      find.byKey(const Key('simiu-undo')),
      findsNothing,
      reason: 'no journal yet means no undo button',
    );

    controller.setDryRun(false);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('simiu-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simiu-apply')));
    await tester.pumpAndSettle();
    await acceptConfirm(tester);
    expect(controller.simiu.journal, '/data/.simiu-undo-1.json');

    controller.setSimiuCleanEmptyDirectories(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simiu-undo')));
    await tester.pumpAndSettle();
    await acceptConfirm(tester);

    expect(engine.simiuUndos, hasLength(1));
    expect(engine.simiuUndos.single.journal, '/data/.simiu-undo-1.json');
    expect(engine.simiuUndos.single.cleanEmptyDirectories, isTrue);
  });

  testWidgets('every label the set mode paints is authored', (
    WidgetTester tester,
  ) async {
    await pumpSetsBoard(tester, sets: true);
    Labels.fallbackKeys.clear();
    await tester.ensureVisible(find.byKey(const Key('simiu-plan-count')));
    await tester.pumpAndSettle();

    expect(Labels.fallbackKeys, isEmpty);
    // Positive control: the gauge does record a key that has no table entry.
    Labels.of('simiu-key-that-does-not-exist');
    expect(Labels.fallbackKeys, <String>['simiu-key-that-does-not-exist']);
  });

  testWidgets('an empty plan offers no apply', (WidgetTester tester) async {
    await pumpSetsBoard(tester, sets: true);
    controller.setSimiuMinimumGroupSize(9);
    await tester.pumpAndSettle();

    expect(controller.simiuPlan.operations, isEmpty);
    expect(
      tester
          .widget<BoardAction>(find.byKey(const Key('simiu-apply')))
          .onPressed,
      isNull,
    );
    expect(
      controller.simiuPlan.directoryCount,
      1,
      reason: 'the folder is still counted, only the moves are refused',
    );
  });
}
