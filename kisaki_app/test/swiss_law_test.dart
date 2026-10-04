import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  /// The corner sweep must reach what a lane hides below its fold, or a card only painted on scroll
  /// can carry a rounded corner the gate never sees.
  testWidgets(
    'no corner is rounded anywhere the reader has to scroll to reach',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      controller.addIncluded(<String>['/data']);
      controller.selectTool('duplicate_files');
      controller.startScan();
      engine.emit(
        ScanEventCompleted(
          StubEngine.outcome('duplicate_files', <ScanRow>[
            StubEngine.row('/data/alpha.bin', group: 0, start: true),
            StubEngine.row('/data/beta.bin', group: 0),
            StubEngine.row('/data/keep.bin', group: 1, reference: true),
          ]),
        ),
      );
      await tester.pumpWidget(
        BoardTheme(dark: true, child: KisakiBoardApp(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Every card in the analysis lane, then the row badges, get built and then swept.
      // Re-query each step: scrolling builds new cards and deflates the ones it left behind, so a
      // list collected up front would point at dead elements.
      for (int index = 0; index < 12; index++) {
        final List<Widget> cards = tester
            .widgetList(find.byType(SectionCard))
            .toList();
        if (index >= cards.length) {
          break;
        }
        await tester.ensureVisible(find.byWidget(cards[index]));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byType(MetricTile).last);
      await tester.pumpAndSettle();

      final List<Widget> badges = tester
          .widgetList<Widget>(find.byType(DecoratedBox))
          .where(
            (widget) => (widget as DecoratedBox).decoration is BoxDecoration,
          )
          .where((widget) {
            final BoxDecoration decoration =
                (widget as DecoratedBox).decoration as BoxDecoration;
            return decoration.borderRadius != null &&
                decoration.borderRadius! != BorderRadius.zero;
          })
          .toList();

      expect(
        badges,
        isEmpty,
        reason: 'the board paints no rounded surface, not even a badge',
      );
    },
  );

  /// A desktop window is whatever the reader made it, and the reader may also have enlarged the
  /// text, so nothing may be clipped on the way down or on the way up. Overflow is a framework
  /// exception, which makes this a gate with teeth rather than an opinion.
  testWidgets('a narrow window or large text clips nothing', (
    WidgetTester tester,
  ) async {
    for (final Size size in <Size>[
      const Size(1440, 900),
      const Size(1024, 768),
      const Size(800, 600),
    ]) {
      for (final double scale in <double>[1.0, 1.3, 2.0]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        controller.addIncluded(<String>['/data']);
        controller.selectTool('duplicate_files');
        controller.startScan();
        engine.emit(
          ScanEventCompleted(
            StubEngine.outcome('duplicate_files', <ScanRow>[
              StubEngine.row('/data/alpha.bin', group: 0, start: true),
              StubEngine.row('/data/beta.bin', group: 0),
              StubEngine.row('/data/keep.bin', group: 1, reference: true),
            ]),
          ),
        );
        await tester.pumpWidget(
          BoardTheme(dark: true, child: KisakiBoardApp(controller: controller)),
        );
        await tester.pumpAndSettle();
        for (int index = 0; index < 12; index++) {
          final List<Widget> cards = tester
              .widgetList(find.byType(SectionCard))
              .toList();
          if (index >= cards.length) {
            break;
          }
          await tester.ensureVisible(find.byWidget(cards[index]));
          await tester.pumpAndSettle();
        }

        final List<String> clipped = clippedFlexes(tester);
        final Object? error = tester.takeException();
        // No corner is excused any more: the strip button that needed 88 of the 86.8 the header left
        // it now flexes, so an 800 wide window at text scale 2.0 clips nothing too.
        expect(
          clipped,
          isEmpty,
          reason: 'clipped at $size with text scale $scale: $clipped',
        );
        expect(
          error,
          isNull,
          reason:
              'the board must lay out cleanly at $size with text scale $scale',
        );
      }
    }
  });

  /// A corner is the one thing the law forbids outright, so it is checked where it is written, not
  /// only where it happens to be painted: a widget scan only sees the branches a test reached.
  /// Only a *literal* radius is an offence - `BoardTokens.radius` is the law's own spelling of zero.
  test('no widget file rounds a surface', () {
    final List<File> sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList();
    expect(
      sources,
      isNotEmpty,
      reason: 'a gate that reads nothing must not look green',
    );

    final RegExp literal = RegExp(r'BorderRadius\.circular\(\s*\d');
    final List<String> offenders = <String>[];
    for (final File file in sources) {
      final List<String> lines = file.readAsLinesSync();
      for (final (int index, String line) in lines.indexed) {
        if (literal.hasMatch(line) || line.contains('BorderRadius.only(')) {
          offenders.add('${file.path}:${index + 1} ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'corners come from BoardTokens.radius, which is 0: $offenders',
    );
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

/// Names every flex whose children do not fit, so a clip points at a widget instead of at a pixel
/// count. The framework's own overflow report carries no site once a test takes the exception.
List<String> clippedFlexes(WidgetTester tester) {
  final List<String> found = <String>[];
  for (final RenderObject object in tester.allRenderObjects) {
    if (object is! RenderFlex) {
      continue;
    }
    final bool horizontal = object.direction == Axis.horizontal;
    final double limit = horizontal
        ? object.constraints.maxWidth
        : object.constraints.maxHeight;
    if (!limit.isFinite) {
      continue;
    }
    double used = 0;
    object.visitChildren((RenderObject child) {
      if (child is RenderBox) {
        used += horizontal ? child.size.width : child.size.height;
      }
    });
    if (used > limit + 0.5) {
      final StringBuffer trail = StringBuffer();
      RenderObject? walk = object;
      for (int depth = 0; depth < 6 && walk != null; depth++) {
        final Object? creator = walk.debugCreator;
        if (creator is DebugCreator) {
          trail.write(' ${creator.element.widget.runtimeType}');
        }
        walk = walk.parent;
      }
      final List<String> kids = <String>[];
      object.visitChildren((RenderObject child) {
        if (child is RenderBox) {
          kids.add(
            '${child.runtimeType} ${horizontal ? child.size.width : child.size.height}',
          );
        }
      });
      found.add(
        '${horizontal ? "row" : "column"} needs ${used.toStringAsFixed(1)} of '
        '${limit.toStringAsFixed(1)} at$trail children=$kids',
      );
    }
  }
  return found;
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
