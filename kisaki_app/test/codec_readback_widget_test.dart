import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/analysis_stats_card.dart';

import 'support/stub_engine.dart';

/// A build without `heif` does not fail on a folder of iPhone photos: the engine never collects those
/// extensions, so the statistics card ends with the decoders this build actually carries.
///
/// The card is pumped on its own because inside the board it sits in a lane that culls rows below the
/// fold, which is a layout fact rather than a question about the readback.
void main() {
  late StubEngine engine;

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnalysisStatsCard(
              controller: BoardController(engine: engine),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String caption(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('codec-caption'))).data ?? '';

  testWidgets('the footer prints one sign per decoder, straight from the engine', (
    WidgetTester tester,
  ) async {
    engine = StubEngine();
    await pumpCard(tester);

    expect(caption(tester), 'heif+ raw- avif+');
    expect(
      find.byKey(const Key('build-runtime-line')),
      findsOneWidget,
      reason: 'the engine version, os and thread limit were dead data before this',
    );
  });

  testWidgets('the caption follows the flags instead of a fixed string', (
    WidgetTester tester,
  ) async {
    engine = StubEngine();
    engine.heifBuild = false;
    engine.rawBuild = true;
    engine.avifBuild = false;
    await pumpCard(tester);

    expect(
      caption(tester),
      'heif- raw+ avif-',
      reason: 'a caption that cannot go red is not a readback',
    );
  });
}
