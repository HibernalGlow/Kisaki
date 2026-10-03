import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/theme/board_theme.dart';
import 'package:kisaki_app/theme/swiss_grid.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/widgets/primitives.dart';

import 'support/stub_engine.dart';

/// The Swiss law is a contract, not a mood: square corners, zero elevation, one-pixel rules,
/// hierarchy by tone instead of hue, figures in tabular numerals, content on a 12-column grid.
/// Each of those is asserted here so a later commit cannot quietly drift back to a Material skin.
void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  Future<void> pumpBoard(WidgetTester tester, {bool dark = true}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    // The test harness scales text by 3x on some platforms, which would fake every layout claim.
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['/data']);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row('/data/alpha.bin', group: 0, start: true),
          StubEngine.row('/data/beta.bin', group: 0),
        ]),
      ),
    );

    await tester.pumpWidget(
      BoardTheme(
        dark: dark,
        child: KisakiBoardApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no surface is rounded - Swiss corners are square', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    final List<Radius> rounded = _radiiIn(tester)
        .where((radius) => radius != Radius.zero)
        .toList();

    expect(
      rounded,
      isEmpty,
      reason: 'BoardTokens.radius must stay 0 everywhere in the board',
    );
  });

  testWidgets(
    'nothing floats - separation comes from hairlines and background steps',
    (WidgetTester tester) async {
      await pumpBoard(tester);
      final BoardPalette palette = tester
          .widgetList<BoardTheme>(find.byType(BoardTheme))
          .first
          .palette;
      final ThemeData theme = boardThemeData(palette);

      expect(theme.cardTheme.elevation, 0);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
      expect(theme.dialogTheme.elevation, 0);
      expect(theme.dividerTheme.thickness, BoardTokens.hairline);
      expect(theme.splashFactory, same(NoSplash.splashFactory));

      final List<double> elevated = tester
          .widgetList<Material>(find.byType(Material))
          .map((material) => material.elevation)
          .where((elevation) => elevation > 0)
          .toList();
      expect(elevated, isEmpty);
    },
  );

  testWidgets('hierarchy is tone, not hue', (WidgetTester tester) async {
    for (final bool dark in <bool>[true, false]) {
      final BoardPalette palette = BoardPalette(dark: dark);

      expect(palette.fgMuted.r, palette.fg.r, reason: 'dark=$dark');
      expect(palette.fgMuted.g, palette.fg.g);
      expect(palette.fgMuted.b, palette.fg.b);
      expect(palette.fgMuted.a, closeTo(0.72, 0.001));

      expect(palette.fgFaint.r, palette.fg.r);
      expect(palette.fgFaint.g, palette.fg.g);
      expect(palette.fgFaint.b, palette.fg.b);
      expect(palette.fgFaint.a, closeTo(0.46, 0.001));
    }
  });

  testWidgets('every figure is set in tabular numerals', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);
    final BoardPalette palette = tester
        .widgetList<BoardTheme>(find.byType(BoardTheme))
        .first
        .palette;

    const FontFeature tabular = FontFeature.tabularFigures();
    expect(palette.tableFigure().fontFeatures, contains(tabular));
    expect(palette.metricFigure().fontFeatures, contains(tabular));

    // The rendered table must actually use it, not just expose the style.
    final List<Text> tabularTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((text) => text.style?.fontFeatures?.contains(tabular) ?? false)
        .toList();
    expect(
      tabularTexts,
      isNotEmpty,
      reason: 'a numeric column or metric must render in tabular figures',
    );
  });

  testWidgets('the metric block sits on the 12-column grid, two per row', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    expect(SwissGrid.columns, 12);
    expect(BoardTokens.gridColumns, 12);

    final List<Offset> tiles = tester
        .widgetList(find.byType(MetricTile))
        .map((tile) => tester.getTopLeft(find.byWidget(tile)))
        .toList();
    expect(tiles, hasLength(6));

    final Set<double> leftEdges = tiles.map((o) => o.dx).toSet();
    final Set<double> topEdges = tiles.map((o) => o.dy).toSet();
    expect(leftEdges, hasLength(2), reason: 'two half-width columns');
    expect(topEdges, hasLength(3), reason: 'three rows of figures');
  });

  testWidgets('the analysis lane breathes on the section rhythm', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    expect(BoardTokens.section, BoardTokens.gap * 3);
    expect(BoardTokens.gapSmall, BoardTokens.gap / 2);
    expect(BoardTokens.gridColumns, 12);

    final ListView lane = tester.widget<ListView>(
      find.ancestor(
        of: find.byType(MetricTile).first,
        matching: find.byType(ListView),
      ),
    );
    final EdgeInsets padding = lane.padding! as EdgeInsets;
    expect(padding.top, BoardTokens.section);
    expect(padding.left, BoardTokens.section);
  });

  testWidgets('grid spans wrap instead of overflowing twelve columns', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      BoardTheme(
        dark: true,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 600,
            child: SwissGrid(
              children: <SwissCell>[
                for (int index = 0; index < 5; index++)
                  SwissCell(
                    span: 4,
                    child: SizedBox(height: 10, key: Key('cell-$index')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // Five spans of four must land as three on the first row and two on the second.
    final double firstRow = tester
        .getTopLeft(find.byKey(const Key('cell-0')))
        .dy;
    expect(tester.getTopLeft(find.byKey(const Key('cell-2'))).dy, firstRow);
    expect(
      tester.getTopLeft(find.byKey(const Key('cell-3'))).dy,
      greaterThan(firstRow),
    );
  });
}

/// Every corner the board actually paints, so a single rounded corner cannot hide behind a
/// uniform radius on some element nobody rendered.
List<Radius> _radiiIn(WidgetTester tester) {
  final List<Radius> found = <Radius>[];

  void add(BorderRadiusGeometry? geometry) {
    if (geometry is BorderRadius) {
      found.addAll(<Radius>[
        geometry.topLeft,
        geometry.topRight,
        geometry.bottomLeft,
        geometry.bottomRight,
      ]);
    }
  }

  for (final Widget widget in tester.allWidgets) {
    if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      add((widget.decoration as BoxDecoration).borderRadius);
    } else if (widget is Material && widget.shape is RoundedRectangleBorder) {
      add((widget.shape as RoundedRectangleBorder).borderRadius);
    } else if (widget is Card && widget.shape is RoundedRectangleBorder) {
      add((widget.shape as RoundedRectangleBorder).borderRadius);
    } else if (widget is InputDecorator &&
        widget.decoration.border is OutlineInputBorder) {
      add((widget.decoration.border! as OutlineInputBorder).borderRadius);
    }
  }

  return found;
}
