import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/group_organize.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// Mirrors `packages/nodes/czkawka/src/operations.test.ts` and adds the wiring the board needs: the
/// card belongs to the image scanner in scanner mode, and the plan is executed one folder per move.
void main() {
  List<List<ScanRow>> fixtureGroups() => <List<ScanRow>>[
    <ScanRow>[
      StubEngine.row('D:/photos/a.jpg', group: 7),
      StubEngine.row('D:/photos/b.jpg', group: 7),
      StubEngine.row(r'E:\other\c.jpg', group: 7),
    ],
    <ScanRow>[
      StubEngine.row('D:/reference/ref.jpg', group: 8, reference: true),
      StubEngine.row('D:/single/candidate.jpg', group: 8),
    ],
  ];

  group('the organize plan', () {
    test(
      'expands one selected row to every non-reference row in its group',
      () {
        final OrganizePlan plan = buildGroupOrganizePlan(
          fixtureGroups(),
          <String>['D:/photos/a.jpg'],
          const OrganizeOptions(),
        );

        expect(plan.items, const <OrganizeItem>[
          OrganizeItem(
            path: 'D:/photos/a.jpg',
            destination: 'D:/photos/variants_0007',
          ),
          OrganizeItem(
            path: 'D:/photos/b.jpg',
            destination: 'D:/photos/variants_0007',
          ),
        ]);
        expect(plan.selectedGroupCount, 1);
        expect(plan.targetFolderCount, 1);
      },
    );

    test('can keep single-file source folders and portable separators', () {
      final OrganizePlan plan = buildGroupOrganizePlan(
        fixtureGroups(),
        <String>[r'E:\other\c.jpg'],
        const OrganizeOptions(
          skipSingleFileFolders: false,
          subfolderTemplate: 'set_{groupId}',
        ),
      );

      expect(plan.items, const <OrganizeItem>[
        OrganizeItem(
          path: 'D:/photos/a.jpg',
          destination: 'D:/photos/set_0007',
        ),
        OrganizeItem(
          path: 'D:/photos/b.jpg',
          destination: 'D:/photos/set_0007',
        ),
        OrganizeItem(
          path: r'E:\other\c.jpg',
          destination: r'E:\other\set_0007',
        ),
      ]);
      expect(plan.targetFolderCount, 2);
    });

    test('a lone variant is skipped until the option is turned off', () {
      const List<String> selected = <String>['D:/single/candidate.jpg'];
      expect(
        buildGroupOrganizePlan(
          fixtureGroups(),
          selected,
          const OrganizeOptions(),
        ).items,
        isEmpty,
      );

      final OrganizePlan kept = buildGroupOrganizePlan(
        fixtureGroups(),
        selected,
        const OrganizeOptions(skipSingleFileFolders: false),
      );
      expect(kept.items, const <OrganizeItem>[
        OrganizeItem(
          path: 'D:/single/candidate.jpg',
          destination: 'D:/single/variants_0008',
        ),
      ]);
      expect(
        kept.items.map((OrganizeItem item) => item.path),
        isNot(contains('D:/reference/ref.jpg')),
        reason: 'the reference of a set is never moved',
      );
    });

    test('sanitizes invalid folder characters', () {
      expect(
        resolveSubfolderName('variants:<{groupId}>', 2),
        'variants__0002_',
      );
      expect(resolveSubfolderName('   ', 3), 'variants_0003');
    });
  });

  const ColumnDef sizeCol = ColumnDef(
    key: 'size',
    labelKey: 'col_size',
    flex: 0.5,
    minWidth: 84,
    alignRight: true,
  );

  const List<ToolSpec> tools = <ToolSpec>[
    ToolSpec(
      id: 'similar_images',
      glyph: 'I',
      labelKey: 'tool_similar_images',
      grouped: true,
      supportsReference: true,
      columns: <ColumnDef>[sizeCol],
      fieldIds: <String>[],
    ),
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
    engine.moveOutcome = const MoveOutcome(
      moved: 2,
      copied: 0,
      planned: 0,
      skipped: 0,
      failed: 0,
      items: <MoveItem>[],
      messages: 'moved 2',
    );
  });

  Future<void> pumpImageBoard(
    WidgetTester tester, {
    String tool = 'similar_images',
    bool sets = false,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['D:/photos']);
    controller.selectTool(tool);
    controller.setSimiuEnabled(sets);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome(tool, <ScanRow>[
          StubEngine.row('D:/photos/a.jpg', size: 100, group: 7, start: true),
          StubEngine.row('D:/photos/b.jpg', size: 200, group: 7),
          StubEngine.row('D:/photos/c.jpg', size: 300, group: 7),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets('the card belongs to the image scanner in scanner mode', (
    WidgetTester tester,
  ) async {
    await pumpImageBoard(tester, tool: 'big_files');
    expect(find.byKey(const Key('organize-card')), findsNothing);

    await pumpImageBoard(tester);
    expect(find.byKey(const Key('organize-card')), findsOneWidget);

    await pumpImageBoard(tester, sets: true);
    expect(
      find.byKey(const Key('organize-card')),
      findsNothing,
      reason: 'the reference hides it while Simiu sets are planned',
    );
  });

  testWidgets('the template is used by the plan the card shows', (
    WidgetTester tester,
  ) async {
    await pumpImageBoard(tester);
    await tester.tap(find.byKey(const Key('row-select-D:/photos/a.jpg')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('organize-template')),
      'set_{groupId}',
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        Labels.of(
          'organize-plan',
          args: const <String, Object>{'count': 3, 'groups': 1, 'folders': 1},
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('\u2192 D:/photos/set_0007'), findsNWidgets(3));
  });

  testWidgets('one move call per target folder, confirmed first', (
    WidgetTester tester,
  ) async {
    await pumpImageBoard(tester);
    await tester.tap(find.byKey(const Key('row-select-D:/photos/a.jpg')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('organize-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-dialog')), findsOneWidget);
    expect(engine.moves, isEmpty);

    await tester.tap(find.byKey(const Key('confirm-accept')));
    await tester.pumpAndSettle();

    expect(engine.moves, hasLength(1));
    final MoveRequest request = engine.moves.single;
    expect(request.destination, 'D:/photos/variants_0007');
    expect(request.paths, <String>[
      'D:/photos/a.jpg',
      'D:/photos/b.jpg',
      'D:/photos/c.jpg',
    ]);
    expect(request.conflict, MoveConflictPolicy.rename);
    expect(request.dryRun, isTrue);
  });
}
