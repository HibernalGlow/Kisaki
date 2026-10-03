import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/engine/seed_engine.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/registry/tool_seed.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';

/// Drives every scanner the registry advertises through the real board, using SeedEngine as the
/// data source. This is the schema gate: if the UI hardcodes an assumption that only holds for a
/// couple of tools (a missing field kind, a column count, grouped vs flat), a tool in this list
/// fails to render or fails to scan.
void main() {
  late SeedEngine engine;
  late BoardController controller;

  setUp(() {
    engine = SeedEngine();
    controller = BoardController(engine: engine);
  });

  Future<void> pumpBoard(WidgetTester tester) async {
    // A tall surface keeps every schema-driven control onstage: the option list and the path
    // blocks are lazy ListViews, so a normal window height hides fields below the fold.
    tester.view.physicalSize = const Size(1440, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> openAlgorithmTab(WidgetTester tester) async {
    await tester.tap(find.text('Algorithm'));
    await tester.pumpAndSettle();
  }

  test('every key the registry can hand the board is in the label catalog', () {
    final Set<String> keys = <String>{};
    for (final ToolSpec tool in ToolSeed.tools()) {
      keys.add(tool.labelKey);
      keys.addAll(tool.columns.map((ColumnDef column) => column.labelKey));
      for (final FieldDef field in ToolSeed.fields(tool.id)) {
        keys.add(field.labelKey);
        keys.addAll(field.options);
      }
    }
    // The registry mixes the two: some options are translation keys (option_check_method_hash),
    // others are engine literals that must render verbatim (Blake3, Nearest, 16).
    final RegExp keyShape = RegExp(r'^[a-z][a-z0-9]*([_-][a-z0-9]+)+$');
    final Set<String> ids = keys.where(keyShape.hasMatch).toSet();
    final Set<String> literals = keys
        .where((String value) => !keyShape.hasMatch(value))
        .toSet();
    final List<String> missing =
        ids.where((String key) => !Labels.knows(key)).toList()..sort();
    expect(missing, isEmpty, reason: 'unresolved keys: $missing');
    expect(
      ids.length,
      greaterThan(100),
      reason: 'the registry stopped feeding the board keys',
    );
    for (final String literal in literals) {
      expect(
        Labels.of(literal),
        literal,
        reason: '$literal was mangled by the label lookup',
      );
    }
  });

  testWidgets(
    'the registry really exposes the fourteen scanners the engine knows',
    (WidgetTester tester) async {
      await pumpBoard(tester);
      final List<ToolSpec> tools = engine.listTools();
      expect(tools.length, 14);
      expect(controller.tools.length, 14);
    },
  );

  testWidgets(
    'every scanner renders its options, scans, and shows its result shape',
    (WidgetTester tester) async {
      await pumpBoard(tester);

      for (final ToolSpec tool in engine.listTools()) {
        controller.selectTool(tool.id);
        await tester.pumpAndSettle();
        expect(
          controller.tool?.id,
          tool.id,
          reason: '${tool.id} is not selectable',
        );
        expect(
          find.text(Labels.of(tool.labelKey)),
          findsWidgets,
          reason: '${tool.id} header label missing',
        );

        await openAlgorithmTab(tester);
        final List<FieldDef> fields = engine.fieldDefs(tool.id);
        expect(
          controller.fields.length,
          fields.length,
          reason: '${tool.id} options not loaded into the board',
        );
        for (final FieldDef field in fields) {
          expect(
            find.text(Labels.of(field.labelKey).toUpperCase()),
            findsWidgets,
            reason:
                '${tool.id} does not render option ${field.id} (${field.kind})',
          );
        }

        controller.addIncluded(<String>['/tmp/kisaki-seed']);
        final bool started = controller.startScan();
        expect(started, isTrue, reason: '${tool.id} refused to start');
        await tester.pumpAndSettle();

        expect(
          controller.phase,
          ScanPhase.finished,
          reason: '${tool.id} ended in ${controller.phase}',
        );
        expect(
          controller.critical,
          isNull,
          reason: '${tool.id} reported ${controller.critical}',
        );
        expect(
          controller.rows.length,
          controller.visibleRows.length,
          reason: '${tool.id} hid its own rows',
        );

        if (tool.grouped) {
          expect(
            controller.groupCount,
            greaterThan(0),
            reason: '${tool.id} is grouped but reported no groups',
          );
          final Set<int> indices = controller.rows
              .map((ScanRow row) => row.groupIndex)
              .toSet();
          expect(
            indices.every((int index) => index >= 0),
            isTrue,
            reason: '${tool.id} emitted an ungrouped row',
          );
          expect(
            controller.rows.where((ScanRow row) => row.isGroupStart).length,
            indices.length,
          );
        } else {
          expect(
            controller.rows.every((ScanRow row) => row.groupIndex < 0),
            isTrue,
            reason: '${tool.id} is flat but emitted grouped rows',
          );
        }

        if (controller.rows.isNotEmpty) {
          expect(
            controller.rows.first.cells.length,
            tool.columns.length,
            reason: '${tool.id} cell/column mismatch',
          );
          expect(
            controller.rows.first.sortKeys.length,
            greaterThanOrEqualTo(tool.columns.length),
            reason:
                '${tool.id} cannot be sorted by ${tool.columns.length} columns',
          );
          controller.toggleSelected(controller.rows.first);
          expect(controller.selectedCount, 1);
          controller.requestDelete();
          expect(
            controller.confirm,
            isNotNull,
            reason: '${tool.id} delete skipped the confirm step',
          );
          expect(
            controller.confirm!.dryRun,
            isTrue,
            reason: '${tool.id} deleted without dry run',
          );
          controller.dismissConfirm();
        }
      }
    },
  );

  testWidgets(
    'sorting a seed scan by each column never reorders rows into different groups',
    (WidgetTester tester) async {
      await pumpBoard(tester);

      for (final ToolSpec tool in engine.listTools().take(6)) {
        controller
          ..selectTool(tool.id)
          ..addIncluded(<String>['/tmp/kisaki-seed', '/tmp/kisaki-seed-2']);
        controller.startScan();
        await tester.pumpAndSettle();

        for (int column = 0; column < tool.columns.length; column++) {
          controller.toggleSort(column);
          final List<ScanRow> visible = controller.visibleRows;
          expect(
            visible.length,
            controller.rows.length,
            reason: '${tool.id} lost rows while sorting',
          );
          if (tool.grouped) {
            for (int index = 1; index < visible.length; index++) {
              expect(
                visible[index].groupIndex >= visible[index - 1].groupIndex,
                isTrue,
                reason:
                    '${tool.id} split group blocks when sorting by ${tool.columns[column].key}',
              );
            }
          }
        }
        controller.clearSelection();
      }
    },
  );

  testWidgets('reference folders only appear for scanners that support them', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    for (final ToolSpec tool in engine.listTools()) {
      controller.selectTool(tool.id);
      await tester.pumpAndSettle();
      expect(
        find.text('REFERENCE FOLDER').evaluate().isNotEmpty,
        tool.supportsReference,
        reason: '${tool.id} shows reference UI = ${tool.supportsReference}',
      );
    }
  });
}
