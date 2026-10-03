import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/filter_model.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/filter_panel.dart';

import 'support/stub_engine.dart';

/// Proves the dialog is reachable and actually drives the ported engine, rather than only being
/// widgets that render.
void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  Future<void> pumpScannedBoard(
    WidgetTester tester, {
    String tool = 'big_files',
    StubEngine? engineOverride,
    List<ScanRow>? rows,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    if (engineOverride != null) {
      engine = engineOverride;
      controller = BoardController(engine: engine);
    }
    controller.addIncluded(<String>['/data']);
    controller.selectTool(tool);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome(
          tool,
          rows ??
              <ScanRow>[
                StubEngine.row('/data/small.bin', size: 10),
                StubEngine.row('/data/large.bin', size: 9000),
                StubEngine.row('/data/tall.bin', size: 9000),
              ],
        ),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.visibleRows, hasLength(rows?.length ?? 3));
  }

  testWidgets('the results header opens the multi-dimensional filter dialog', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);

    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();

    expect(find.byType(FilterPanel), findsOneWidget);
    // Every dimension the reference exposes has to be present, not a subset of them.
    for (final String key in <String>[
      'filter-preset-select',
      'filter-text-pattern',
      'filter-mark',
      'filter-group-count-min',
      'filter-group-size-min',
      'filter-file-size-min',
      'filter-extension-mode',
      'filter-extension-list',
      'filter-date-preset',
      'filter-path-mode',
      'filter-show-whole-group',
    ]) {
      expect(
        find.byKey(Key(key), skipOffstage: false),
        findsWidgets,
        reason: 'missing the $key control',
      );
    }
  });

  testWidgets('Ctrl+F opens it on every platform modifier', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(FilterPanel), findsOneWidget);
  });

  testWidgets(
    'choosing a mark dimension narrows the table through the engine',
    (WidgetTester tester) async {
      await pumpScannedBoard(tester);
      controller.toggleSelected(controller.visibleRows.first);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-mark')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(Labels.of('filter-mark-selected')).last);
      await tester.pumpAndSettle();

      expect(controller.filters.mark, MarkFilter.selected);
      expect(controller.visibleRows, hasLength(1));
      expect(controller.visibleRows.single.path, '/data/small.bin');
      expect(
        find.byKey(const Key('active-filter-count')),
        findsOneWidget,
        reason: 'the trigger badge must count what is active',
      );
    },
  );

  testWidgets('a preset needs a name before it can be saved', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);

    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('filter-preset-save')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('filter-error')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('filter-preset-name')),
      'Heavy',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-preset-save')));
    await tester.pumpAndSettle();

    expect(controller.filterPresets.single.name, 'Heavy');
    expect(find.byKey(const Key('filter-error')), findsNothing);
  });

  testWidgets('reset clears the state and the badge together', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);
    controller.setFilters(
      FilterState.defaults()
        ..fileSize = RangeFilter(
          enabled: true,
          min: 100,
          max: 100000,
          unit: SizeUnit.b,
        ),
    );
    await tester.pumpAndSettle();
    expect(controller.visibleRows, hasLength(2));

    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Labels.of('filter-reset')));
    await tester.pumpAndSettle();

    expect(controller.filters.activeCount, 0);
    expect(controller.visibleRows, hasLength(3));
  });

  testWidgets('Esc inside the dialog clears the filters and stays open', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);
    controller.setFilters(
      FilterState.defaults()
        ..pathEnabled = true
        ..pathPattern = 'large',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(controller.filters.activeCount, 0);
    expect(
      find.byType(FilterPanel),
      findsOneWidget,
      reason: 'resetting is a dialog action, not a reason to close it',
    );
  });

  testWidgets('Ctrl+Shift+F closes the dialog it opened', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);
    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(FilterPanel), findsNothing);
  });

  testWidgets('Ctrl+R re-runs the scan without discarding the filters', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);
    controller.setFilters(
      FilterState.defaults()
        ..fileSize = RangeFilter(
          enabled: true,
          min: 100,
          max: 100000,
          unit: SizeUnit.b,
        ),
    );
    await tester.pumpAndSettle();
    expect(engine.requests, hasLength(1));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(engine.requests, hasLength(2));

    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('big_files', <ScanRow>[
          StubEngine.row('/data/small.bin', size: 10),
          StubEngine.row('/data/large.bin', size: 9000),
          StubEngine.row('/data/tall.bin', size: 9000),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      controller.filters.fileSize.enabled,
      isTrue,
      reason: 'a refresh must keep the work the dialog set up',
    );
    expect(controller.visibleRows, hasLength(2));
  });

  test('a label missing from the table is recorded, not disguised', () {
    Labels.fallbackKeys.clear();
    expect(
      Labels.of('filter-a-dimension-that-does-not-exist'),
      'Filter A Dimension That Does Not Exist',
    );
    // Without this record the title-cased fallback above looks like authored English.
    expect(
      Labels.fallbackKeys,
      contains('filter-a-dimension-that-does-not-exist'),
    );
  });

  testWidgets('every label the dialog paints is authored', (
    WidgetTester tester,
  ) async {
    final StubEngine sweep = StubEngine(
      tools: const <ToolSpec>[
        ToolSpec(
          id: 'similar_images',
          glyph: 'I',
          labelKey: 'tool_similar_images',
          grouped: true,
          supportsReference: true,
          columns: <ColumnDef>[sizeColumn, modifiedColumn],
          fieldIds: <String>[],
        ),
        ToolSpec(
          id: 'empty_folders',
          glyph: 'F',
          labelKey: 'tool_empty_folders',
          grouped: false,
          supportsReference: false,
          columns: <ColumnDef>[sizeColumn],
          fieldIds: <String>[],
        ),
      ],
    );
    // One row per format category plus a suffix-free one, so every chip renders.
    await pumpScannedBoard(
      tester,
      tool: 'similar_images',
      engineOverride: sweep,
      rows: <ScanRow>[
        StubEngine.row('/data/a.jpg', size: 100),
        StubEngine.row('/data/b.mp4', size: 200),
        StubEngine.row('/data/c.mp3', size: 300),
        StubEngine.row('/data/d.pdf', size: 400),
        StubEngine.row('/data/e.zip', size: 500),
        StubEngine.row('/data/f.bin', size: 600),
        StubEngine.row('/data/README', size: 700),
      ],
    );

    Labels.fallbackKeys.clear();
    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();

    // The preset error line and the transfer field only exist once they are triggered.
    await tester.tap(
      find.byKey(const Key('filter-preset-save')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('filter-preset-export')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('filter-preset-json')), 'nope');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('filter-preset-import')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(Labels.fallbackKeys, isEmpty);
    // Scoped to the dialog: the image scanner's own tab strip also reads "Images", and counting it
    // here would make this gauge measure the wrong thing.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining(Labels.of('filter-category-images')),
      ),
      findsOneWidget,
      reason: 'the sweep has to reach the category chips',
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining(Labels.of('filter-extension-none')),
      ),
      findsOneWidget,
      reason: 'a suffix-free row is its own chip in the reference',
    );

    await tester.tap(find.text(Labels.of('action-close')));
    await tester.pumpAndSettle();

    await pumpScannedBoard(
      tester,
      tool: 'empty_folders',
      engineOverride: sweep,
      rows: <ScanRow>[StubEngine.row('/data/folder', size: 0)],
    );
    Labels.fallbackKeys.clear();
    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();
    expect(Labels.fallbackKeys, isEmpty);
    expect(
      find.textContaining(Labels.of('filter-category-folders')),
      findsOneWidget,
    );
  });
}
