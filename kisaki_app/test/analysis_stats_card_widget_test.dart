import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/analysis_stats.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/util/format.dart';

import 'support/stub_engine.dart';

/// The analysis card is the reference's distribution panel: formats by bytes, then the similarity
/// buckets the engine itself draws, then the quick reference that explains a hash size.
void main() {
  const List<ColumnDef> imageColumns = <ColumnDef>[
    ColumnDef(
      key: 'difference',
      labelKey: 'col_difference',
      flex: 0.7,
      minWidth: 90,
      alignRight: false,
    ),
    ColumnDef(
      key: 'size',
      labelKey: 'col_size',
      flex: 0.5,
      minWidth: 84,
      alignRight: true,
    ),
  ];

  const List<ColumnDef> sizeOnlyColumns = <ColumnDef>[
    ColumnDef(
      key: 'size',
      labelKey: 'col_size',
      flex: 0.5,
      minWidth: 84,
      alignRight: true,
    ),
  ];

  const List<ToolSpec> tools = <ToolSpec>[
    ToolSpec(
      id: 'similar_images',
      glyph: 'I',
      labelKey: 'tool_similar_images',
      grouped: true,
      supportsReference: true,
      columns: imageColumns,
      fieldIds: <String>['img_hash_size'],
    ),
    ToolSpec(
      id: 'big_files',
      glyph: 'B',
      labelKey: 'tool_big_files',
      grouped: false,
      supportsReference: false,
      columns: sizeOnlyColumns,
      fieldIds: <String>['big_number_of_files'],
    ),
  ];

  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine(tools: tools);
    controller = BoardController(engine: engine);
  });

  ScanRow image(String path, int bytes, int difference) => ScanRow(
    path: path,
    name: path.split('/').last,
    directory: '',
    cells: <String>['$difference', humanBytes(bytes)],
    sizeBytes: bytes,
    modifiedTs: 0,
    groupIndex: 0,
    groupSize: 2,
    isGroupStart: false,
    isReference: false,
    sortKeys: <int>[difference, bytes],
  );

  ScanRow sized(String path, int bytes) => ScanRow(
    path: path,
    name: path.split('/').last,
    directory: '',
    cells: <String>[humanBytes(bytes)],
    sizeBytes: bytes,
    modifiedTs: 0,
    groupIndex: -1,
    groupSize: 0,
    isGroupStart: false,
    isReference: false,
    sortKeys: <int>[bytes],
  );

  Future<void> pumpBoard(
    WidgetTester tester,
    String tool,
    List<ScanRow> rows,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['/data']);
    controller.selectTool(tool);
    controller.startScan();
    // The scan always answers, even with nothing in it, so the board settles and the card can be
    // seen declining to appear.
    engine.emit(ScanEventCompleted(StubEngine.outcome(tool, rows)));
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
    if (rows.isNotEmpty) {
      await tester.ensureVisible(find.byKey(const Key('analysis-card')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('the card waits for results and then reports them', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester, 'big_files', <ScanRow>[]);
    expect(find.byKey(const Key('analysis-card')), findsNothing);

    await pumpBoard(tester, 'big_files', <ScanRow>[sized('/data/a.bin', 10)]);
    expect(find.byKey(const Key('analysis-card')), findsOneWidget);
    expect(find.byKey(const Key('format-legend-bin')), findsOneWidget);
  });

  testWidgets('formats are ordered by bytes with their printed share', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester, 'similar_images', <ScanRow>[
      image('/data/archive.zip', 60, 0),
      image('/data/one.jpg', 30, 0),
      image('/data/two.jpg', 10, 2),
      image('/data/README', 0, 5),
    ]);

    expect(find.byKey(const Key('format-share-bar')), findsOneWidget);
    final double zip = tester
        .getTopLeft(find.byKey(const Key('format-legend-zip')))
        .dy;
    final double jpg = tester
        .getTopLeft(find.byKey(const Key('format-legend-jpg')))
        .dy;
    final double unknown = tester
        .getTopLeft(find.byKey(const Key('format-legend-unknown')))
        .dy;
    expect(zip, lessThan(jpg));
    expect(jpg, lessThan(unknown));
    expect(find.text('60.0%'), findsOneWidget);
    expect(find.text('40.0%'), findsOneWidget);
    expect(find.text('0.0%'), findsOneWidget);
    expect(find.text(humanBytes(40)), findsOneWidget);
  });

  testWidgets('similarity buckets hold only the levels the scan reached', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester, 'similar_images', <ScanRow>[
      image('/data/same.jpg', 10, 0),
      image('/data/close.jpg', 10, 2),
      image('/data/far.jpg', 10, 5),
    ]);

    expect(find.byKey(const Key('similarity-original')), findsOneWidget);
    expect(find.byKey(const Key('similarity-very-high')), findsOneWidget);
    expect(find.byKey(const Key('similarity-high')), findsOneWidget);
    expect(find.byKey(const Key('similarity-medium')), findsNothing);
    expect(
      find.textContaining(Labels.of('analysis-level-very-high')),
      findsOneWidget,
    );
  });

  testWidgets('the hash size the reader picked decides the bucket', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester, 'similar_images', <ScanRow>[
      image('/data/one.jpg', 10, 2),
    ]);
    expect(find.byKey(const Key('similarity-very-high')), findsOneWidget);

    controller.setFieldValue('img_hash_size', const FieldPayloadChoice('8'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('analysis-card')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('similarity-very-high')), findsNothing);
    expect(find.byKey(const Key('similarity-high')), findsOneWidget);
    expect(controller.analysisHashSize, 8);
  });

  testWidgets(
    'a tool without differences says so instead of inventing levels',
    (WidgetTester tester) async {
      await pumpBoard(tester, 'big_files', <ScanRow>[sized('/data/a.bin', 10)]);

      expect(controller.hasSimilarityStats, isFalse);
      expect(find.text(Labels.of('analysis-no-similarity')), findsOneWidget);
      expect(
        find.byKey(const Key('similarity-reference-open')),
        findsNothing,
        reason: 'only the two similarity scanners need the table',
      );
    },
  );

  testWidgets(
    'the quick reference opens with every hash size beside the level',
    (WidgetTester tester) async {
      await pumpBoard(tester, 'similar_images', <ScanRow>[
        image('/data/one.jpg', 10, 2),
      ]);
      await tester.tap(find.byKey(const Key('similarity-reference-open')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('similarity-reference-dialog')),
        findsOneWidget,
      );
      for (final SimilarityLevel level in similarityLevels) {
        expect(
          find.byKey(Key('similarity-reference-${level.wire}')),
          findsOneWidget,
        );
      }
      expect(
        find.text(
          Labels.of(
            'similarity-reference-hash',
            args: const <String, Object>{'size': 64},
          ),
        ),
        findsOneWidget,
      );
      // The whole point of the table: the same level means a different limit per hash size.
      expect(
        find.descendant(
          of: find.byKey(const Key('similarity-reference-very-high')),
          matching: find.text('\u2264 1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('similarity-reference-very-high')),
          matching: find.text('\u2264 6'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('similarity-reference-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('similarity-reference-dialog')),
        findsNothing,
      );
    },
  );

  testWidgets('every label the card paints is authored', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester, 'similar_images', <ScanRow>[
      image('/data/one.jpg', 10, 2),
    ]);
    Labels.fallbackKeys.clear();
    await tester.ensureVisible(find.byKey(const Key('analysis-card')));
    await tester.pumpAndSettle();

    expect(Labels.fallbackKeys, isEmpty);
    Labels.of('analysis-key-that-does-not-exist');
    expect(Labels.fallbackKeys, <String>['analysis-key-that-does-not-exist']);
  });
}
