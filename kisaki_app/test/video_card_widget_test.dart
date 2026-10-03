import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/video_optimize.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/util/format.dart';

import 'support/stub_engine.dart';

/// The video optimizer is the one card whose options must reach the engine exactly as the reference
/// clamps them, and whose answer explains why a selected video was left alone.
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
      id: 'video_optimizer',
      glyph: 'V',
      labelKey: 'tool_video_optimizer',
      grouped: false,
      supportsReference: false,
      columns: <ColumnDef>[sizeCol],
      fieldIds: <String>[],
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
    engine.optimizeOutcome = const OptimizeOutcome(
      transcoded: 1,
      cropped: 0,
      planned: 0,
      skipped: 1,
      failed: 0,
      items: <OptimizeItem>[
        OptimizeItem(
          path: '/data/one.mkv',
          target: '/data/one.mkv',
          status: OptimizeStatus.transcoded,
          detail: '',
          sizeBefore: 5000000,
          sizeAfter: 3000000,
        ),
        OptimizeItem(
          path: '/data/two.mkv',
          target: '',
          status: OptimizeStatus.skipped,
          detail: 'already smaller',
          sizeBefore: 0,
          sizeAfter: 0,
        ),
      ],
      messages: 'encoded',
    );
  });

  Future<void> pumpVideoBoard(WidgetTester tester, String tool) async {
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
          StubEngine.row('/data/one.mkv', size: 5000000),
          StubEngine.row('/data/two.mkv', size: 7000000),
        ]),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> selectFirst(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('row-select-/data/one.mkv')));
    await tester.pumpAndSettle();
    expect(controller.selectedCount, 1);
  }

  Future<void> acceptConfirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('confirm-accept')));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final Finder finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> chooseSwitch(WidgetTester tester, String key) async {
    final Finder switchFinder = find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(switchFinder);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
  }

  Future<void> runToEngine(WidgetTester tester) async {
    await tapKey(tester, 'video-optimize');
    await tester.pumpAndSettle();
    await acceptConfirm(tester);
  }

  testWidgets('only the video optimizer offers the fix', (
    WidgetTester tester,
  ) async {
    await pumpVideoBoard(tester, 'empty_files');
    expect(find.byKey(const Key('video-card')), findsNothing);

    await pumpVideoBoard(tester, 'video_optimizer');
    expect(find.byKey(const Key('video-card')), findsOneWidget);
    expect(controller.video.codec, VideoCodec.h265);
    expect(controller.video.quality, 23);
    expect(controller.video.failIfNotSmaller, isTrue);
    expect(controller.video.hardware, VideoHardware.none);
  });

  testWidgets(
    'the transcode request carries the wire names the engine expects',
    (WidgetTester tester) async {
      await pumpVideoBoard(tester, 'video_optimizer');
      await selectFirst(tester);
      await runToEngine(tester);

      expect(engine.optimizeCalls, hasLength(1));
      final OptimizeRequest request = engine.optimizeCalls.single;
      expect(request.dryRun, isTrue);
      expect(request.paths, <String>['/data/one.mkv']);
      expect(request.crop, isNull);
      expect(request.transcode, isNotNull);
      expect(request.transcode!.codec, 'h265');
      expect(request.transcode!.hardwareEncoder, 'none');
      expect(request.transcode!.quality, 23);
      expect(request.transcode!.customFfmpegCommand, '');
      expect(request.transcode!.limitVideoSize, isFalse);
    },
  );

  testWidgets('a quality above the table is clamped before it is sent', (
    WidgetTester tester,
  ) async {
    await pumpVideoBoard(tester, 'video_optimizer');
    await selectFirst(tester);
    await tester.enterText(find.byKey(const Key('video-quality')), '999');
    await tester.pumpAndSettle();
    expect(
      controller.video.quality,
      999,
      reason: 'the card keeps what was typed',
    );

    await runToEngine(tester);
    expect(engine.optimizeCalls.single.transcode!.quality, 51);
  });

  testWidgets('crop mode sends crop options and keeps the source codec', (
    WidgetTester tester,
  ) async {
    await pumpVideoBoard(tester, 'video_optimizer');
    await selectFirst(tester);
    await tapKey(tester, 'video-mode');
    await tester.tap(find.text(Labels.of('video-mode-crop')).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-crop-transcode')), findsOneWidget);
    expect(
      find.byKey(const Key('video-hardware')),
      findsNothing,
      reason: 'the encoder-only fields have no meaning for a crop',
    );

    await runToEngine(tester);
    final OptimizeRequest request = engine.optimizeCalls.single;
    expect(request.transcode, isNull);
    expect(request.crop!.targetCodec, '');
    expect(request.crop!.quality, -1);

    await chooseSwitch(tester, 'video-crop-transcode');
    await runToEngine(tester);
    expect(engine.optimizeCalls.last.crop!.targetCodec, 'h265');
    expect(engine.optimizeCalls.last.crop!.quality, 23);
  });

  testWidgets('the encoder answer explains what it left alone', (
    WidgetTester tester,
  ) async {
    await pumpVideoBoard(tester, 'video_optimizer');
    await selectFirst(tester);
    controller.setDryRun(false);
    await tester.pumpAndSettle();
    await runToEngine(tester);

    expect(
      find.textContaining(
        '${Labels.of('video-result-transcoded')} '
        '${humanBytes(5000000)} -> ${humanBytes(3000000)}',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${Labels.of('video-result-skipped')} already smaller',
      ),
      findsOneWidget,
      reason: 'a skipped video has to say why, like the reference does',
    );
  });

  testWidgets('every label the card paints is authored', (
    WidgetTester tester,
  ) async {
    await pumpVideoBoard(tester, 'video_optimizer');
    Labels.fallbackKeys.clear();
    await chooseSwitch(tester, 'video-limit-size');
    expect(controller.video.limitVideoSize, isTrue);
    await tester.ensureVisible(find.byKey(const Key('video-card')));
    await tester.pumpAndSettle();

    expect(Labels.fallbackKeys, isEmpty);
    Labels.of('video-key-that-does-not-exist');
    expect(Labels.fallbackKeys, <String>['video-key-that-does-not-exist']);
  });
}
