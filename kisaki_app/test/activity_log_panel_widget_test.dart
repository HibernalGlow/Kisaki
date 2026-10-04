import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/activity_log.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/widgets/primitives.dart';

import 'support/stub_engine.dart';

/// The activity panel is the board's own memory, so the tests follow the reference rules: newest
/// first, one filter box over every searchable field, a copy of the whole history, and a clear.
void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  /// The board needs the desktop window it is laid out for; the default 800x600 test window clips
  /// the header and the preview strip.
  void useWideWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> pumpScannedBoard(WidgetTester tester) async {
    useWideWindow(tester);
    controller.addIncluded(<String>['/data']);
    controller.selectTool('duplicate_files');
    controller.startScan();
    engine.emit(
      const ScanEventProgress(
        ProgressUpdate(
          stageLabelKey: 'status_scanning',
          current: 10,
          total: 100,
          percent: 10,
          detail: '',
        ),
      ),
    );
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
    await tester.ensureVisible(find.byKey(const Key('activity-card')));
    await tester.pumpAndSettle();
  }

  Finder panelEntry(String id) => find.byKey(Key('activity-entry-$id'));

  List<ActivityEntry> entriesOf(ActivityKind kind) => controller.activityLog
      .where((ActivityEntry entry) => entry.kind == kind)
      .toList();

  testWidgets('a scan records its start, its stage and its answer', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);

    expect(
      controller.activityLog.map((ActivityEntry entry) => entry.kind),
      <ActivityKind>[
        ActivityKind.scan,
        ActivityKind.progress,
        ActivityKind.scan,
      ],
    );
    expect(controller.activityLog.first.progress, 0);
    expect(controller.activityLog.last.progress, 100);
    expect(find.text('3/3'), findsOneWidget);
    expect(find.textContaining('\u00b7 duplicate_files'), findsNWidgets(3));
  });

  testWidgets('the newest entry is painted above the older ones', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);

    final double newest = tester
        .getTopLeft(panelEntry(controller.activityLog.last.id))
        .dy;
    final double oldest = tester
        .getTopLeft(panelEntry(controller.activityLog.first.id))
        .dy;
    expect(newest, lessThan(oldest));
  });

  testWidgets('the filter narrows the list while the badge keeps both halves', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);

    await tester.enterText(
      find.byKey(const Key('activity-filter')),
      'progress',
    );
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    expect(panelEntry(controller.activityLog.first.id), findsNothing);
    expect(controller.activityQuery, 'progress');

    await tester.enterText(find.byKey(const Key('activity-filter')), '');
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);
  });

  testWidgets('copying puts the whole history on the clipboard', (
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

    await pumpScannedBoard(tester);
    await tester.tap(find.byKey(const Key('activity-copy')));
    await tester.pumpAndSettle();

    expect(copied, <String>[controller.activityText]);
    expect(copied.single, contains('duplicate_files \u00b7 scan'));
    // The count has to reach the status line, or the reader cannot tell what was copied.
    expect(
      find.text(
        Labels.of('activity-copied', args: const <String, Object>{'count': 3}),
      ),
      findsOneWidget,
    );
  });

  testWidgets('clearing empties the log and quietens both buttons', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);
    await tester.tap(find.byKey(const Key('activity-clear')));
    await tester.pumpAndSettle();

    expect(controller.activityLog, isEmpty);
    expect(find.byKey(const Key('activity-empty')), findsOneWidget);
    expect(find.text('0/0'), findsOneWidget);
    for (final String key in <String>['activity-copy', 'activity-clear']) {
      expect(
        tester.widget<BoardAction>(find.byKey(Key(key))).onPressed,
        isNull,
        reason: '$key has nothing to act on',
      );
    }
  });

  testWidgets('a stage that only moves the percentage is recorded once', (
    WidgetTester tester,
  ) async {
    useWideWindow(tester);
    controller.addIncluded(<String>['/data']);
    controller.selectTool('duplicate_files');
    controller.startScan();
    engine.emit(
      const ScanEventProgress(
        ProgressUpdate(
          stageLabelKey: 'status_scanning',
          current: 10,
          total: 100,
          percent: 10,
          detail: '',
        ),
      ),
    );
    engine.emit(
      const ScanEventProgress(
        ProgressUpdate(
          stageLabelKey: 'status_scanning',
          current: 90,
          total: 100,
          percent: 90,
          detail: '',
        ),
      ),
    );
    engine.emit(
      const ScanEventProgress(
        ProgressUpdate(
          stageLabelKey: 'action-compare',
          current: 0,
          total: 0,
          percent: -1,
          detail: '',
        ),
      ),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    // The scan is still running and its rail animates, so a settle would never return.
    await tester.pump();
    await tester.pump();

    expect(entriesOf(ActivityKind.progress), hasLength(2));
    expect(
      entriesOf(ActivityKind.progress).last.progress,
      isNull,
      reason: 'the engine reported no measurable percentage',
    );
  });

  testWidgets(
    'a confirmed delete logs the ask and the engine answer with counts',
    (WidgetTester tester) async {
      engine.deleteOutcome = const DeleteOutcome(
        affected: 1,
        errors: 0,
        reclaimedBytes: 100,
        messages: '',
        log: <String>[],
      );
      await pumpScannedBoard(tester);
      controller.setDryRun(false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-select-/data/one.jpg')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('delete-selected')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-selected')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-accept')));
      await tester.pumpAndSettle();

      final List<ActivityEntry> operations = entriesOf(ActivityKind.operation);
      expect(operations, hasLength(2));
      expect(operations.first.level, ActivityLevel.info);
      expect(operations.last.level, ActivityLevel.success);
      expect(operations.last.affectedCount, 1);
      expect(operations.last.errorCount, 0);

      await tester.ensureVisible(find.byKey(const Key('activity-card')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: panelEntry(operations.last.id),
          matching: find.text(
            Labels.of(
              'activity-result',
              args: const <String, Object>{'affected': 1, 'errors': 0},
            ),
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('an engine failure is recorded as an error, not a clean finish', (
    WidgetTester tester,
  ) async {
    engine.deleteFailure = Exception('disk vanished');
    await pumpScannedBoard(tester);
    controller.setDryRun(false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('row-select-/data/one.jpg')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-selected')));
    await tester.ensureVisible(find.byKey(const Key('delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-accept')));
    await tester.pumpAndSettle();

    final ActivityEntry answer = entriesOf(ActivityKind.operation).last;
    expect(answer.level, ActivityLevel.error);
    expect(answer.affectedCount, isNull);
  });

  testWidgets('every label the panel paints is authored', (
    WidgetTester tester,
  ) async {
    await pumpScannedBoard(tester);
    Labels.fallbackKeys.clear();
    await tester.ensureVisible(find.byKey(const Key('activity-card')));
    await tester.pumpAndSettle();

    expect(Labels.fallbackKeys, isEmpty);
    Labels.of('activity-key-that-does-not-exist');
    expect(Labels.fallbackKeys, <String>['activity-key-that-does-not-exist']);
  });
}
