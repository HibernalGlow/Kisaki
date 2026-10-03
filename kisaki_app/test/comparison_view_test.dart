import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/comparison_view.dart';

import 'support/stub_engine.dart';

/// Drives the ported comparison dialog the way the reference wires it: a row opens it, the four
/// modes stay honest about whether a second image exists, and the sliders write back to the state.
void main() {
  late Directory temp;
  late String first;
  late String second;
  late String broken;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('kisaki-compare');
    first = '${temp.path}/first.png';
    second = '${temp.path}/second.png';
    broken = '${temp.path}/broken.png';
    await File(first).writeAsBytes(await png(255, 0, 0));
    await File(second).writeAsBytes(await png(0, 0, 255));
    await File(broken).writeAsString('this is not a png');
  });

  tearDownAll(() async {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  Future<void> pumpPairBoard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>[temp.path]);
    controller.selectTool('duplicate_files');
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row(first, size: 1000, group: 0, start: true),
          StubEngine.row(second, size: 2000, group: 0),
          StubEngine.row(broken, size: 3000, group: 0),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.visibleRows, hasLength(3));
  }

  Future<void> openFromRow(WidgetTester tester, String path) async {
    await tester.tap(find.byKey(Key('row-select-$path')));
    await tester.pumpAndSettle();
    expect(controller.canCompareSelection, isTrue);
    await tester.tap(find.byKey(const Key('open-comparison')));
    await tester.pumpAndSettle();
  }

  testWidgets('a row opens the comparison with its sibling as target', (
    WidgetTester tester,
  ) async {
    await pumpPairBoard(tester);
    Labels.fallbackKeys.clear();
    await openFromRow(tester, first);

    expect(controller.comparison.activePath, first);
    expect(controller.comparison.targetPath, second);
    for (final String key in <String>[
      'comparison-mode-single',
      'comparison-mode-side-by-side',
      'comparison-mode-swipe',
      'comparison-mode-onion-skin',
      'comparison-color-coding',
      'comparison-target-$second',
      'comparison-close',
    ]) {
      expect(
        find.byKey(Key(key), skipOffstage: false),
        findsOneWidget,
        reason: 'missing the $key control',
      );
    }
    expect(Labels.fallbackKeys, isEmpty);
  });

  testWidgets(
    'side by side shows both images and swipe gives the split a slider',
    (WidgetTester tester) async {
      await pumpPairBoard(tester);
      await openFromRow(tester, first);

      await tester.tap(find.byKey(const Key('comparison-mode-side-by-side')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('comparison-pane-comparison-source')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('comparison-pane-comparison-target')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('comparison-mode-swipe')));
      await tester.pumpAndSettle();
      final Slider slider = tester.widget<Slider>(
        find.byKey(const Key('comparison-swipe-position-slider')),
      );
      expect(slider.value, 50);

      await tester.drag(
        find.byKey(const Key('comparison-swipe-position-slider')),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      expect(
        controller.comparison.swipePercent,
        lessThan(50),
        reason: 'the split must follow the handle',
      );

      await tester.tap(find.byKey(const Key('comparison-color-coding')));
      await tester.pumpAndSettle();
      expect(controller.comparison.colorCoding, isTrue);
    },
  );

  testWidgets(
    'the onion stage drives opacity and the target strip re-targets',
    (WidgetTester tester) async {
      await pumpPairBoard(tester);
      await openFromRow(tester, second);

      await tester.tap(find.byKey(const Key('comparison-mode-onion-skin')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('comparison-onion-opacity-slider')),
        const Offset(-100, 0),
      );
      await tester.pumpAndSettle();
      expect(controller.comparison.onionOpacity, lessThan(50));

      await tester.tap(
        find.byKey(Key('comparison-target-$first'), skipOffstage: false),
      );
      await tester.pumpAndSettle();
      expect(controller.comparison.targetPath, first);
      expect(controller.comparison.onionOpacity, 50);
    },
  );

  testWidgets('closing the dialog drops the comparison state', (
    WidgetTester tester,
  ) async {
    await pumpPairBoard(tester);
    await openFromRow(tester, first);
    expect(controller.comparison.isOpen, isTrue);

    await tester.tap(find.byKey(const Key('comparison-close')));
    await tester.pumpAndSettle();

    expect(controller.comparison.isOpen, isFalse);
    expect(find.byType(ComparisonView), findsNothing);
  });

  testWidgets(
    'both panes hold their slot and nothing claims failure while decoding',
    (WidgetTester tester) async {
      await pumpPairBoard(tester);
      Labels.fallbackKeys.clear();
      await openFromRow(tester, first);

      await tester.tap(
        find.byKey(Key('comparison-target-$broken'), skipOffstage: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comparison-mode-side-by-side')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('comparison-pane-comparison-source')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('comparison-pane-comparison-target')),
        findsOneWidget,
      );
      // Decoding is still in flight on the test clock, so the pane must not report a broken file.
      expect(find.byKey(const Key('comparison-missing')), findsNothing);
      expect(controller.comparison.targetPath, broken);
      expect(Labels.fallbackKeys, isEmpty);
    },
  );

  test('a lone row has nothing to compare against', () {
    expect(controller.canCompareSelection, isFalse);
  });

  group('imageDestRect', () {
    test('contain fits the whole picture and centres it', () {
      expect(
        imageDestRect(const Size(50, 50), const Size(100, 50), BoxFit.contain),
        const Rect.fromLTWH(0, 12.5, 50, 25),
      );
    });

    test('cover fills the box and crops the overflow', () {
      expect(
        imageDestRect(const Size(50, 50), const Size(100, 50), BoxFit.cover),
        const Rect.fromLTWH(-25, 0, 100, 50),
      );
    });

    test(
      'an empty canvas or picture falls back to nothing rather than NaN',
      () {
        expect(
          imageDestRect(const Size(0, 50), const Size(100, 50), BoxFit.contain),
          Rect.zero,
        );
        expect(
          imageDestRect(const Size(50, 50), const Size(0, 0), BoxFit.cover),
          Rect.zero,
        );
      },
    );
  });
}

Future<Uint8List> png(int red, int green, int blue) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()
      ..color = Color.from(
        alpha: 1,
        red: red / 255,
        green: green / 255,
        blue: blue / 255,
      ),
  );
  final ui.Image image = await recorder.endRecording().toImage(4, 4);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
