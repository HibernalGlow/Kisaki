import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/source_panel.dart';

import 'support/stub_engine.dart';

void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  Future<void> pumpBoard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> seedGroupedResults(WidgetTester tester) async {
    controller.addIncluded(<String>['/data']);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row('/data/alpha.bin', group: 0, start: true),
          StubEngine.row('/data/beta.bin', group: 0),
        ]),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the board lays out the header and the three lanes', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    expect(find.text('Kisaki'), findsOneWidget);
    expect(find.text('SCAN CONDITIONS'), findsOneWidget);
    expect(find.text('RESULTS'), findsOneWidget);
    expect(find.text('ANALYSIS AND ACTIONS'), findsOneWidget);
    expect(find.text('Duplicate files'), findsOneWidget);
    expect(find.text('Kisaki is ready.'), findsWidgets);
    expect(find.text('Duplicate files'), findsOneWidget);
  });

  testWidgets('the scanner menu switches tool and reloads its options', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    await tester.tap(find.byKey(const Key('scanner-picker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tool-menu')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tool-big_files')));
    await tester.pumpAndSettle();

    expect(controller.tool?.id, 'big_files');
    expect(find.text('Big files'), findsOneWidget);
  });

  testWidgets(
    'scanning with no paths added explains itself instead of calling the engine',
    (WidgetTester tester) async {
      await pumpBoard(tester);

      await tester.tap(find.byKey(const Key('scan-control')));
      await tester.pumpAndSettle();

      expect(engine.requests, isEmpty);
      expect(
        find.text('Add at least one included directory before scanning'),
        findsWidgets,
      );
    },
  );

  testWidgets('a typed path and a scan fill the results table', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    await tester.enterText(
      find.byKey(const Key('token-field-Included')),
      '/data/set',
    );
    await tester.tap(find.byKey(const Key('token-add-Included')));
    await tester.pumpAndSettle();
    expect(controller.included, <String>['/data/set']);

    await tester.tap(find.byKey(const Key('scan-control')));
    // The rail is indeterminate while scanning, so settling would never finish.
    await tester.pump();
    expect(controller.scanning, isTrue);

    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row('/data/alpha.bin', group: 0, start: true),
          StubEngine.row('/data/beta.bin', group: 0),
          StubEngine.row('/data/gamma.bin', group: 1, start: true),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('results-list')), findsOneWidget);
    expect(find.text('Group 1'), findsOneWidget);
    expect(find.text('alpha.bin'), findsOneWidget);
    expect(find.text('Delete selected'), findsOneWidget);
    expect(find.textContaining('Found 3 files in 2 groups'), findsWidgets);
  });

  testWidgets(
    'selecting rows and confirming a dry run reaches the engine once',
    (WidgetTester tester) async {
      await pumpBoard(tester);
      await seedGroupedResults(tester);

      await tester.tap(find.byKey(const Key('row-select-/data/alpha.bin')));
      await tester.pumpAndSettle();
      expect(controller.selectedCount, 1);

      await tester.tap(find.byKey(const Key('delete-selected')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-dialog')), findsOneWidget);
      expect(find.textContaining('Dry run: plans 1 paths'), findsOneWidget);
      expect(engine.deletes, isEmpty);

      await tester.tap(find.byKey(const Key('confirm-accept')));
      await tester.pumpAndSettle();

      expect(engine.deletes.length, 1);
      expect(engine.deletes.single.dryRun, isTrue);
      expect(controller.rows.length, 2);
      expect(controller.confirm, isNull);
    },
  );

  testWidgets('cancelling the confirm dialog does not touch the filesystem', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);
    await seedGroupedResults(tester);

    controller.toggleSelected(controller.rows.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(engine.deletes, isEmpty);
    expect(controller.confirm, isNull);
    expect(controller.rows.length, 2);
  });

  testWidgets('a group toggle selects the whole block from the strip', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    controller.addIncluded(<String>['/data']);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row('/data/alpha.bin', group: 0, start: true),
          StubEngine.row('/data/beta.bin', group: 0),
          StubEngine.row('/data/gamma.bin', group: 1, start: true),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group-toggle-1')));
    await tester.pumpAndSettle();
    expect(controller.selectedCount, 1);
    expect(controller.isSelected(controller.rows.last), isTrue);
  });

  testWidgets('the theme toggle repaints without losing scan state', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);
    await seedGroupedResults(tester);

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme?.brightness,
      Brightness.dark,
    );

    await tester.tap(find.text('Toggle theme'));
    await tester.pumpAndSettle();

    expect(controller.dark, isFalse);
    expect(controller.rows.length, 2);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme?.brightness,
      Brightness.light,
    );
  });

  testWidgets('collapsed lanes shrink to a single letter and expand again', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('lane-S')),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.layout.sourceCollapsed, isTrue);
    expect(find.byType(SourcePanel), findsNothing);
    expect(find.text('S'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lane-S')));
    await tester.pumpAndSettle();
    expect(controller.layout.sourceCollapsed, isFalse);
    expect(find.text('SCAN CONDITIONS'), findsOneWidget);
  });

  testWidgets('column headers sort and the filter narrows the list', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    controller.addIncluded(<String>['/data']);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('big_files', <ScanRow>[
          StubEngine.row('/data/small.bin', size: 10),
          StubEngine.row('/data/large.bin', size: 9000),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('column-header-Size')));
    await tester.pumpAndSettle();
    expect(controller.sortColumn, 0);
    expect(controller.sortAscending, isTrue);
    expect(controller.visibleRows.first.path, '/data/small.bin');

    await tester.tap(find.byKey(const Key('column-header-Size')));
    await tester.pumpAndSettle();
    expect(controller.visibleRows.first.path, '/data/large.bin');

    await tester.enterText(find.byKey(const Key('results-filter')), 'large');
    await tester.pumpAndSettle();
    expect(controller.visibleRows.single.path, '/data/large.bin');
    expect(find.text('small.bin'), findsNothing);
  });
}
