import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// The image scanner's folder roll-up: the switch only exists where the reference shows it, the
/// header search narrows it, and the copy action has a readback.
void main() {
  const ColumnDef modifiedColumn = ColumnDef(
    key: 'modified',
    labelKey: 'col_modified',
    flex: 1,
    minWidth: 140,
    alignRight: false,
  );
  const ColumnDef sizeColumn = ColumnDef(
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
      columns: <ColumnDef>[sizeColumn, modifiedColumn],
      fieldIds: <String>[],
    ),
    ToolSpec(
      id: 'big_files',
      glyph: 'B',
      labelKey: 'tool_big_files',
      grouped: false,
      supportsReference: false,
      columns: <ColumnDef>[sizeColumn, modifiedColumn],
      fieldIds: <String>[],
    ),
  ];

  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine(tools: tools);
    controller = BoardController(engine: engine);
  });

  Future<void> pumpScanned(WidgetTester tester, String tool) async {
    tester.view.physicalSize = const Size(1600, 1000);
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
          StubEngine.row(
            '/data/photos/a.jpg',
            size: 100,
            group: 0,
            start: true,
          ),
          StubEngine.row('/data/photos/b.jpg', size: 200, group: 0),
          StubEngine.row('/data/photos/c.jpg', size: 300, group: 1),
          StubEngine.row('/data/archive/d.jpg', size: 400, group: 1),
          StubEngine.row('/data/archive/e.jpg', size: 500, group: 2),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets('only the image scanner offers the folder roll-up', (
    WidgetTester tester,
  ) async {
    await pumpScanned(tester, 'big_files');
    expect(find.byKey(const Key('view-folders')), findsNothing);

    await pumpScanned(tester, 'similar_images');
    expect(find.byKey(const Key('view-folders')), findsOneWidget);
    expect(find.byKey(const Key('folders-count')), findsOneWidget);
    expect(find.text('2'), findsWidgets, reason: 'photos has 3, archive has 2');
  });

  testWidgets('the folders tab replaces the table and keeps the path column', (
    WidgetTester tester,
  ) async {
    await pumpScanned(tester, 'similar_images');
    expect(find.byKey(const Key('results-list')), findsOneWidget);
    // Positive control: the gauge below only means something while the header is on screen.
    expect(
      find.byKey(Key('column-header-${Labels.of('col-name')}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('view-folders')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('folders-list')), findsOneWidget);
    expect(
      find.byKey(const Key('results-list')),
      findsNothing,
      reason: 'the roll-up replaces the table rather than sitting under it',
    );
    expect(
      find.byKey(Key('column-header-${Labels.of('col-name')}')),
      findsNothing,
      reason: 'the table header would be a lie over folder rows',
    );
    expect(find.byKey(const Key('folder-path-/data/photos')), findsOneWidget);
    expect(find.byKey(const Key('folder-path-/data/archive')), findsOneWidget);
  });

  testWidgets(
    'the header search filters the folders and says when none match',
    (WidgetTester tester) async {
      await pumpScanned(tester, 'similar_images');
      await tester.tap(find.byKey(const Key('view-folders')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('results-filter')),
        'archive',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('folder-path-/data/archive')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('folder-path-/data/photos')), findsNothing);

      // The same box also filters the rows, so a needle that leaves nothing must say so inside the
      // roll-up rather than keeping a stale folder list on screen.
      await tester.enterText(find.byKey(const Key('results-filter')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('folders-empty')), findsOneWidget);
      expect(find.byKey(const Key('folders-list')), findsNothing);
    },
  );

  testWidgets('copying a folder path writes the clipboard and reports it', (
    WidgetTester tester,
  ) async {
    final List<String> copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpScanned(tester, 'similar_images');
    await tester.tap(find.byKey(const Key('view-folders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('folder-copy-/data/photos')));
    await tester.pumpAndSettle();

    expect(copied, <String>['/data/photos']);
    expect(
      find.text(
        Labels.of(
          'status_copied',
          args: const <String, Object>{'path': '/data/photos'},
        ),
      ),
      findsWidgets,
    );
  });
}
