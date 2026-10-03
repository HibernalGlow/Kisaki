import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// The reference paints a picture per row when thumbnails are on. Kisaki decodes only rows whose
/// suffix can be a picture, and the slot must never steal the row's click.
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
    tester.view.physicalSize = const Size(1500, 1000);
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
          StubEngine.row('/data/b.png', size: 100, group: 0),
          StubEngine.row('/data/notes.txt', size: 100, group: 1),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets('a decodable row gets a slot and a text row does not', (
    WidgetTester tester,
  ) async {
    await pumpPictures(tester);

    expect(controller.showThumbnails, isTrue);
    expect(find.byKey(const Key('row-thumb-/data/a.jpg')), findsOneWidget);
    expect(find.byKey(const Key('row-thumb-/data/b.png')), findsOneWidget);
    expect(
      find.byKey(const Key('row-thumb-/data/notes.txt')),
      findsNothing,
      reason: 'a text file is not something an image codec can show',
    );
  });

  testWidgets('the header switch takes the pictures away', (
    WidgetTester tester,
  ) async {
    await pumpPictures(tester);
    await tester.tap(find.byKey(const Key('toggle-thumbnails')));
    await tester.pumpAndSettle();

    expect(controller.showThumbnails, isFalse);
    expect(find.byKey(const Key('row-thumb-/data/a.jpg')), findsNothing);
  });

  testWidgets('the picture is its own target and the row still toggles', (
    WidgetTester tester,
  ) async {
    await pumpPictures(tester);
    expect(controller.selectedCount, 0);

    // The picture opens the preview instead of selecting, like the reference's preview button.
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('row-thumb-/data/a.jpg'))),
    );
    await tester.pumpAndSettle();
    expect(controller.previewOpen, isTrue);
    expect(controller.selectedCount, 0);

    await tester.tap(find.byKey(const Key('preview-close')));
    await tester.pumpAndSettle();

    // A press on the row, away from the picture, is the selection click.
    final Rect row = tester.getRect(
      find.byKey(const Key('result-row-/data/a.jpg')),
    );
    await tester.tapAt(Offset(row.center.dx + 40, row.center.dy));
    await tester.pumpAndSettle();
    expect(controller.selectedCount, 1);
    expect(controller.isSelected(controller.rows.first), isTrue);
  });

  testWidgets('turning the switch back on brings the pictures back', (
    WidgetTester tester,
  ) async {
    await pumpPictures(tester);
    await tester.tap(find.byKey(const Key('toggle-thumbnails')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row-thumb-/data/a.jpg')), findsNothing);

    await tester.tap(find.byKey(const Key('toggle-thumbnails')));
    await tester.pumpAndSettle();
    expect(controller.showThumbnails, isTrue);
    expect(find.byKey(const Key('row-thumb-/data/a.jpg')), findsOneWidget);
  });
}
