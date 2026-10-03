import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/widgets/primitives.dart';

import 'support/stub_engine.dart';

/// The picture preview is the reference's dialog: name and path on top, arrows to step through the
/// rows on screen, and only the pictures the table actually shows.
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
      id: 'similar_images',
      glyph: 'I',
      labelKey: 'tool_similar_images',
      grouped: true,
      supportsReference: true,
      columns: <ColumnDef>[sizeCol],
      fieldIds: <String>[],
    ),
  ];

  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine(tools: tools);
    controller = BoardController(engine: engine);
  });

  Future<void> pumpPictures(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['/data']);
    controller.selectTool('similar_images');
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('similar_images', <ScanRow>[
          StubEngine.row('/data/a.jpg', size: 100, group: 0, start: true),
          StubEngine.row('/data/notes.txt', size: 100, group: 0),
          StubEngine.row('/data/b.png', size: 200, group: 1),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> openPreview(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('row-thumb-/data/a.jpg')));
    await tester.pumpAndSettle();
  }

  testWidgets('the preview only offers pictures', (WidgetTester tester) async {
    await pumpPictures(tester);
    expect(controller.previewPaths, <String>['/data/a.jpg', '/data/b.png']);
    expect(controller.previewOpen, isFalse);

    await openPreview(tester);
    expect(controller.previewOpen, isTrue);
    expect(find.text(Labels.of('preview-title')), findsOneWidget);
    expect(find.text('/data/a.jpg'), findsWidgets);
  });

  testWidgets('the arrows step through the pictures and say where', (
    WidgetTester tester,
  ) async {
    await pumpPictures(tester);
    await openPreview(tester);
    expect(find.byKey(const Key('preview-index')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.previewPath, '/data/b.png');
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      controller.previewPath,
      '/data/b.png',
      reason: 'the last picture has no next, so the walk stops at the end',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(controller.previewPath, '/data/a.jpg');
    expect(
      tester
          .widget<BoardAction>(find.byKey(const Key('preview-prev')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('closing the dialog leaves no preview state behind', (
    WidgetTester tester,
  ) async {
    await pumpPictures(tester);
    await openPreview(tester);
    await tester.tap(find.byKey(const Key('preview-close')));
    await tester.pumpAndSettle();

    expect(controller.previewOpen, isFalse);
    expect(find.byKey(const Key('preview-index')), findsNothing);
  });

  testWidgets(
    'the pinned panel docks beside the table and steps the same way',
    (WidgetTester tester) async {
      await pumpPictures(tester);
      expect(find.byKey(const Key('preview-panel')), findsNothing);

      await tester.tap(find.byKey(const Key('pin-preview')));
      await tester.pumpAndSettle();

      expect(controller.previewPanelOpen, isTrue);
      expect(find.byKey(const Key('preview-panel')), findsOneWidget);
      expect(
        find.byKey(const Key('preview-panel-image-/data/a.jpg')),
        findsOneWidget,
      );
      expect(find.text('1 / 2'), findsOneWidget);
      expect(
        find.byKey(const Key('results-list')),
        findsOneWidget,
        reason: 'the panel takes a slice of the lane, it does not replace the table',
      );

      await tester.tap(find.byKey(const Key('preview-panel-next')));
      await tester.pumpAndSettle();
      expect(controller.previewPath, '/data/b.png');
      expect(find.text('2 / 2'), findsOneWidget);
      expect(
        tester
            .widget<BoardAction>(find.byKey(const Key('preview-panel-next')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('preview-panel-close')));
      await tester.pumpAndSettle();
      expect(controller.previewPanelOpen, isFalse);
      expect(find.byKey(const Key('preview-panel')), findsNothing);
    },
  );

  testWidgets('every label the pinned panel paints is authored', (
    WidgetTester tester,
  ) async {
    await pumpPictures(tester);
    await tester.tap(find.byKey(const Key('pin-preview')));
    await tester.pumpAndSettle();
    Labels.fallbackKeys.clear();
    await tester.ensureVisible(find.byKey(const Key('preview-panel')));
    await tester.pumpAndSettle();

    expect(Labels.fallbackKeys, isEmpty);
    expect(
      find.text(
        Labels.of(
          'preview-panel-title',
          args: const <String, Object>{'name': 'a.jpg'},
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('every label the preview paints is authored', (
    WidgetTester tester,
  ) async {
    await pumpPictures(tester);
    Labels.fallbackKeys.clear();
    await openPreview(tester);

    expect(Labels.fallbackKeys, isEmpty);
    Labels.of('preview-key-that-does-not-exist');
    expect(Labels.fallbackKeys, <String>['preview-key-that-does-not-exist']);
  });
}
