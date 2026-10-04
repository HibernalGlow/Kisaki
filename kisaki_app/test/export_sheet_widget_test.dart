import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/export_scope.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// The export sheet has to say what it will write before it writes it: the scope, the row count that
/// scope resolves to, and a confirm that stays shut when either the path or the scope is empty.
void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  Future<void> pumpScanned(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
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
          StubEngine.row('/data/one.jpg', size: 100, group: 0, start: true),
          StubEngine.row('/data/two.jpg', size: 200, group: 0),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('export-results')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('export-results')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-results')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-dialog')), findsOneWidget);
  }

  Future<void> typePath(WidgetTester tester, String path) async {
    await tester.enterText(find.byKey(const Key('export-path')), path);
    await tester.pumpAndSettle();
  }

  FilledButton confirm(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('export-confirm')));

  testWidgets(
    'the sheet opens on the selection and says how many rows that is',
    (WidgetTester tester) async {
      await pumpScanned(tester);
      await tester.tap(find.byKey(const Key('row-select-/data/two.jpg')));
      await tester.pumpAndSettle();
      await openSheet(tester);

      expect(controller.exportScope, ExportScope.selected);
      expect(
        find.text(
          Labels.of(
            'export-scope-count',
            args: const <String, Object>{'count': 1},
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(Labels.of('export-scope-selected')),
        findsWidgets,
        reason: 'the chosen scope is printed, not implied',
      );
    },
  );

  testWidgets('confirm stays shut without a path, and without rows in scope', (
    WidgetTester tester,
  ) async {
    await pumpScanned(tester);
    await openSheet(tester);

    expect(confirm(tester).onPressed, isNull, reason: 'no path typed yet');

    await typePath(tester, '/tmp/out');
    expect(confirm(tester).onPressed, isNull, reason: 'nothing is selected');

    controller.toggleSelected(controller.rows.first);
    await tester.pumpAndSettle();
    expect(confirm(tester).onPressed, isNotNull);
  });

  testWidgets('switching the scope rewrites the count and the rows it sends', (
    WidgetTester tester,
  ) async {
    await pumpScanned(tester);
    controller.toggleSelected(controller.rows.first);
    await openSheet(tester);
    await typePath(tester, '/tmp/out');

    await tester.tap(find.byKey(const Key('export-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Labels.of('export-scope-all')).last);
    await tester.pumpAndSettle();

    expect(controller.exportScope, ExportScope.all);
    expect(
      find.text(
        Labels.of(
          'export-scope-count',
          args: const <String, Object>{'count': 2},
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('export-format-csv')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-confirm')));
    await tester.pumpAndSettle();

    final ExportRequest request = engine.exports.single;
    expect(request.rows, hasLength(2));
    expect(request.format, 'csv');
    expect(request.path, '/tmp/out');
  });

  testWidgets('the scope the reader picked survives closing the sheet', (
    WidgetTester tester,
  ) async {
    await pumpScanned(tester);
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('export-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Labels.of('export-scope-visible')).last);
    await tester.pumpAndSettle();
    await typePath(tester, '/tmp/out');
    await tester.tap(find.byKey(const Key('export-confirm')));
    await tester.pumpAndSettle();

    expect(controller.exportScope, ExportScope.visible);
    await openSheet(tester);
    expect(find.text(Labels.of('export-scope-visible')), findsWidgets);
  });

  testWidgets('every label the sheet paints is authored', (
    WidgetTester tester,
  ) async {
    await pumpScanned(tester);
    await openSheet(tester);
    Labels.fallbackKeys.clear();
    await tester.pumpAndSettle();

    expect(Labels.fallbackKeys, isEmpty);
    Labels.of('export-key-that-does-not-exist');
    expect(Labels.fallbackKeys, <String>['export-key-that-does-not-exist']);
  });
}
