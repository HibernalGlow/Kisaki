import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/widgets/primitives.dart';

import 'support/stub_engine.dart';

/// The two fix verbs the bridge answers have to be gated the same way deletion is: offered only by
/// the scanners that can do them, confirmed first, and dry run by default.
void main() {
  const ColumnDef sizeCol = ColumnDef(
    key: 'size',
    labelKey: 'col_size',
    flex: 0.5,
    minWidth: 84,
    alignRight: true,
  );

  const List<ToolSpec> fixTools = <ToolSpec>[
    ToolSpec(
      id: 'duplicate_files',
      glyph: 'D',
      labelKey: 'tool_duplicate_files',
      grouped: true,
      supportsReference: true,
      columns: <ColumnDef>[sizeCol],
      fieldIds: <String>[],
    ),
    ToolSpec(
      id: 'bad_names',
      glyph: 'N',
      labelKey: 'tool_bad_names',
      grouped: false,
      supportsReference: false,
      columns: <ColumnDef>[sizeCol],
      fieldIds: <String>[],
    ),
  ];

  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine(tools: fixTools);
    controller = BoardController(engine: engine);
  });

  Future<void> pumpFixedBoard(WidgetTester tester, String tool) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['/data']);
    controller.selectTool(tool);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome(tool, <ScanRow>[
          StubEngine.row('/data/bad name.txt', size: 100),
          StubEngine.row('/data/also bad.txt', size: 200),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.visibleRows, hasLength(2));
  }

  Future<void> selectFirst(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('row-select-/data/bad name.txt')));
    await tester.pumpAndSettle();
    expect(controller.selectedCount, 1);
  }

  testWidgets('Fix names belongs only to the scanners that can rewrite names', (
    WidgetTester tester,
  ) async {
    await pumpFixedBoard(tester, 'duplicate_files');
    await selectFirst(tester);
    final Finder rename = find.byKey(const Key('fix-names'));
    expect(
      tester.widget<BoardAction>(rename).onPressed,
      isNull,
      reason: 'duplicates have no engine fix to run',
    );

    await pumpFixedBoard(tester, 'bad_names');
    await selectFirst(tester);
    expect(tester.widget<BoardAction>(rename).onPressed, isNotNull);
  });

  testWidgets('a dry-run rename confirms first and reports the planned count', (
    WidgetTester tester,
  ) async {
    await pumpFixedBoard(tester, 'bad_names');
    await selectFirst(tester);
    engine.renameOutcome = const RenameOutcome(
      renamed: 0,
      planned: 1,
      failed: 0,
      skipped: 0,
      items: <RenameItem>[],
      messages: 'dry run: 1 rename planned',
    );

    await tester.tap(find.byKey(const Key('fix-names')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-dialog')), findsOneWidget);
    expect(
      engine.renames,
      isEmpty,
      reason: 'nothing may reach the engine before the confirm',
    );

    await tester.tap(find.byKey(const Key('confirm-accept')));
    await tester.pumpAndSettle();

    expect(engine.renames, hasLength(1));
    expect(engine.renames.single.dryRun, isTrue);
    expect(engine.renames.single.tool, 'bad_names');
    expect(engine.renames.single.paths, <String>['/data/bad name.txt']);
    expect(controller.selectedRows, hasLength(1));
    expect(
      find.text(
        Labels.of(
          'status_rename_planned',
          args: const <String, Object>{'count': 1},
        ),
      ),
      findsWidgets,
    );
  });

  testWidgets('turning dry run off is what asks the engine to rename', (
    WidgetTester tester,
  ) async {
    await pumpFixedBoard(tester, 'bad_names');
    await selectFirst(tester);
    controller.setDryRun(false);
    await tester.pumpAndSettle();
    engine.renameOutcome = const RenameOutcome(
      renamed: 1,
      planned: 0,
      failed: 0,
      skipped: 0,
      items: <RenameItem>[],
      messages: 'renamed 1 path',
    );

    await tester.tap(find.byKey(const Key('fix-names')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-accept')));
    await tester.pumpAndSettle();

    expect(engine.renames.single.dryRun, isFalse);
    expect(
      find.text(
        Labels.of('status_renamed', args: const <String, Object>{'count': 1}),
      ),
      findsWidgets,
    );
  });

  testWidgets('the move sheet sends one request with skip-on-collision', (
    WidgetTester tester,
  ) async {
    await pumpFixedBoard(tester, 'bad_names');
    await selectFirst(tester);
    engine.moveOutcome = const MoveOutcome(
      moved: 0,
      copied: 0,
      planned: 1,
      skipped: 0,
      failed: 0,
      items: <MoveItem>[],
      messages: 'dry run: 1 move planned',
    );

    await tester.tap(find.byKey(const Key('move-selection')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('move-destination-field')),
      '/data/archive',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-sheet-move')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('confirm-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-accept')));
    await tester.pumpAndSettle();

    final MoveRequest sent = engine.moves.single;
    expect(sent.destination, '/data/archive');
    expect(sent.action, MoveAction.move);
    expect(sent.conflict, MoveConflictPolicy.skip);
    expect(sent.dryRun, isTrue);
    expect(sent.paths, <String>['/data/bad name.txt']);
    expect(
      find.text(
        Labels.of(
          'status_move_planned',
          args: const <String, Object>{
            'count': 1,
            'destination': '/data/archive',
          },
        ),
      ),
      findsWidgets,
    );
  });

  testWidgets('copy is a separate verb and an empty destination is refused', (
    WidgetTester tester,
  ) async {
    await pumpFixedBoard(tester, 'bad_names');
    await selectFirst(tester);

    await tester.tap(find.byKey(const Key('move-selection')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-sheet-copy')));
    await tester.pumpAndSettle();

    expect(
      engine.moves,
      isEmpty,
      reason: 'a sheet with no destination must not even ask for confirmation',
    );
    expect(find.text(Labels.of('status_move_needs_destination')), findsWidgets);

    await tester.tap(find.byKey(const Key('move-selection')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('move-destination-field')),
      '/data/keep',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-sheet-copy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-accept')));
    await tester.pumpAndSettle();

    expect(engine.moves.single.action, MoveAction.copy);
    expect(engine.moves.single.destination, '/data/keep');
  });
}
