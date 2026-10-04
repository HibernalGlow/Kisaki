import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/widgets/primitives.dart';

import 'support/stub_engine.dart';

/// EXIF cleanup is a metadata rewrite, so it is gated like deletion: offered only by the remover,
/// confirmed first, dry run by default, and the engine's per-file counts are shown when they arrive.
void main() {
  const ColumnDef sizeCol = ColumnDef(
    key: 'size',
    labelKey: 'col_size',
    flex: 0.5,
    minWidth: 84,
    alignRight: true,
  );

  const List<ToolSpec> tools = <ToolSpec>[
    ToolSpec(
      id: 'exif_remover',
      glyph: 'X',
      labelKey: 'tool_exif_remover',
      grouped: false,
      supportsReference: false,
      columns: <ColumnDef>[sizeCol],
      fieldIds: <String>['exif_ignored_tags'],
    ),
    ToolSpec(
      id: 'empty_files',
      glyph: 'E',
      labelKey: 'tool_empty_files',
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
    engine.exifOutcome = const ExifOutcome(
      stripped: 1,
      candidates: 0,
      planned: 0,
      skipped: 1,
      failed: 0,
      items: <ExifItem>[
        ExifItem(
          path: '/data/one.jpg',
          target: '/data/one.jpg',
          tagsRemoved: 14,
          status: ExifStatus.stripped,
          detail: '',
        ),
        ExifItem(
          path: '/data/two.jpg',
          target: '',
          tagsRemoved: 0,
          status: ExifStatus.skipped,
          detail: '',
        ),
      ],
      messages: 'cleaned',
    );
  });

  Future<void> pumpExifBoard(WidgetTester tester, String tool) async {
    tester.view.physicalSize = const Size(1600, 1200);
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
          StubEngine.row('/data/one.jpg', size: 100),
          StubEngine.row('/data/two.jpg', size: 200),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> selectFirst(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('row-select-/data/one.jpg')));
    await tester.pumpAndSettle();
    expect(controller.selectedCount, 1);
  }

  Future<void> acceptConfirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('confirm-accept')));
    await tester.pumpAndSettle();
  }

  Future<void> toggleOverride(WidgetTester tester) async {
    final Finder switchFinder = find.descendant(
      of: find.byKey(const Key('exif-override')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
  }

  testWidgets('only the metadata remover offers the cleanup', (
    WidgetTester tester,
  ) async {
    await pumpExifBoard(tester, 'empty_files');
    expect(find.byKey(const Key('exif-card')), findsNothing);

    await pumpExifBoard(tester, 'exif_remover');
    expect(find.byKey(const Key('exif-card')), findsOneWidget);
    expect(
      tester.widget<BoardAction>(find.byKey(const Key('exif-clean'))).onPressed,
      isNull,
      reason: 'nothing is selected yet',
    );
    await selectFirst(tester);
    expect(
      tester.widget<BoardAction>(find.byKey(const Key('exif-clean'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('cleaning asks first and plans while the dry run is on', (
    WidgetTester tester,
  ) async {
    await pumpExifBoard(tester, 'exif_remover');
    await selectFirst(tester);
    await tester.ensureVisible(find.byKey(const Key('exif-clean')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exif-clean')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-dialog')), findsOneWidget);
    expect(engine.exifCalls, isEmpty);

    await acceptConfirm(tester);
    expect(engine.exifCalls, hasLength(1));
    final ExifRequest request = engine.exifCalls.single;
    expect(request.dryRun, isTrue);
    expect(request.overrideFile, isFalse);
    expect(request.paths, <String>['/data/one.jpg']);
    expect(request.scan.tool, 'exif_remover');
  });

  testWidgets('the override choice reaches the engine on a live run', (
    WidgetTester tester,
  ) async {
    await pumpExifBoard(tester, 'exif_remover');
    await selectFirst(tester);
    controller.setDryRun(false);
    await tester.pumpAndSettle();
    await toggleOverride(tester);
    expect(controller.exifOverrideFile, isTrue);

    await tester.ensureVisible(find.byKey(const Key('exif-clean')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exif-clean')));
    await tester.pumpAndSettle();
    await acceptConfirm(tester);

    expect(engine.exifCalls.single.overrideFile, isTrue);
    expect(engine.exifCalls.single.dryRun, isFalse);
  });

  testWidgets('the engine answer shows the tags it removed per file', (
    WidgetTester tester,
  ) async {
    await pumpExifBoard(tester, 'exif_remover');
    await selectFirst(tester);
    controller.setDryRun(false);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('exif-clean')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exif-clean')));
    await tester.pumpAndSettle();
    await acceptConfirm(tester);

    expect(
      find.textContaining(
        Labels.of(
          'exif-result-count',
          args: const <String, Object>{'count': 14},
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(Labels.of('exif-result-skipped')),
      findsOneWidget,
    );
    expect(
      find.text(
        Labels.of(
          'exif-summary',
          args: const <String, Object>{
            'stripped': 1,
            'candidates': 0,
            'planned': 0,
            'skipped': 1,
          },
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('every label the card paints is authored', (
    WidgetTester tester,
  ) async {
    await pumpExifBoard(tester, 'exif_remover');
    Labels.fallbackKeys.clear();
    await tester.ensureVisible(find.byKey(const Key('exif-card')));
    await tester.pumpAndSettle();

    expect(Labels.fallbackKeys, isEmpty);
    Labels.of('exif-key-that-does-not-exist');
    expect(Labels.fallbackKeys, <String>['exif-key-that-does-not-exist']);
  });
}
