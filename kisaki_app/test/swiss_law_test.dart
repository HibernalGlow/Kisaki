import 'dart:io';
import 'dart:math';

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

/// The board's visual law is a contract, not a mood: chamfered or square corners and no fillet,
/// zero elevation and no cast shadow, one-pixel rules, a warm neutral type ramp, one accent kept
/// off the selected rows, figures in tabular monospace, content on a 12-column grid, and exactly one
/// lane lit as the stage in progress. Each is asserted here so a later commit cannot quietly drift
/// back to a Material skin.
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
        kind: BoardThemeKind.cassette,
        child: KisakiBoardApp(
          controller: controller,
          themeKind: BoardThemeKind.cassette,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no surface is filleted - a corner is a chamfer or it is square', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);

    final List<Radius> rounded = _radiiIn(tester)
        .where((radius) => radius != Radius.zero)
        .toList();

    expect(
      rounded,
      isEmpty,
      reason:
          'the only non-square corner is BoardShape\'s chamfer, never a radius: $rounded',
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

  testWidgets('hierarchy is a warm neutral step, not a tinted grey', (
    WidgetTester tester,
  ) async {
    for (final bool dark in <bool>[true, false]) {
      final BoardPalette palette = BoardPalette(dark: dark);

      // The panel greys carry a polyester cast, so the law is no longer "zero chroma" but "low
      // chroma": a step may be warm, and may not be a coloured grey pretending to be a hierarchy.
      double chroma(Color color) {
        final List<double> channels = <double>[color.r, color.g, color.b];
        return (channels.reduce(max) - channels.reduce(min)) / 255;
      }

      for (final Color grey in <Color>[
        palette.fg,
        palette.fgMuted,
        palette.fgFaint,
        palette.hairline,
        palette.card,
        palette.bg,
      ]) {
        expect(
          chroma(grey),
          lessThan(0.12),
          reason:
              'dark=$dark ${_hex(grey)} is a coloured grey, not a neutral step',
        );
      }

      // The ground is warm: polyester white reads with more red than blue, and that is the one
      // colour claim the event actually documents.
      expect(palette.card.r, greaterThan(palette.card.b));
      expect(palette.bg.r, greaterThan(palette.bg.b));

      // Each step sits closer to the ground than the one above it.
      final double ground = palette.bg.r;
      double distance(Color color) => (color.r - ground).abs();
      expect(distance(palette.fg), greaterThan(distance(palette.fgMuted)));
      expect(distance(palette.fgMuted), greaterThan(distance(palette.fgFaint)));
      expect(
        distance(palette.fgFaint),
        greaterThan(0),
        reason: 'a step equal to the ground would be invisible, not quiet',
      );
    }
  });

  test('the panel grounds are two, and the accent is orange', () {
    for (final bool dark in <bool>[true, false]) {
      final BoardPalette palette = BoardPalette(dark: dark);
      // Two grounds only: a field is inset by returning to the page ground, not by a third grey.
      expect(palette.raised, palette.card);
      expect(palette.sunken, palette.bg);
      expect(palette.primary, const Color(0xFFF6540E));
    }
    // Positive control: a cool grey would have failed the warmth claim above.
    expect(const Color(0xFF686878).r > const Color(0xFF686878).b, isFalse);
  });

  /// A glow is feedback, never a surface: the extracted Arknights contract forbids a permanent
  /// shadow, and elevation is already pinned at zero by the other gate.
  test('nothing casts a shadow', () {
    final RegExp banned = RegExp(r'BoxShadow\(|boxShadow:|elevation:\s*[1-9]');
    final List<String> offenders = _libLinesMatching(banned);
    expect(
      offenders,
      isEmpty,
      reason: 'separation comes from rules and grounds: $offenders',
    );
    expect(
      banned.hasMatch('const List<BoxShadow> s = [BoxShadow(color: c)];'),
      isTrue,
    );
  });

  /// A theme axis that nothing reads is a field, not a theme: the kind must change the corner.
  test('the theme kind decides whether a corner is cut or filleted', () {
    final BoardPalette cassette = BoardPalette(dark: false);
    final BoardPalette material = BoardPalette(
      dark: false,
      kind: BoardThemeKind.material,
    );

    expect(
      cassette.kind,
      BoardThemeKind.cassette,
      reason: 'cassette is the default',
    );
    expect(
      cassette.panelShape(cassette.hairline),
      isA<BeveledRectangleBorder>(),
    );
    expect(
      material.panelShape(material.hairline),
      isA<RoundedRectangleBorder>(),
    );

    // Positive control: the two kinds must disagree on size, not merely on type.
    expect(
      _corner(material.panelShape(material.hairline)),
      BoardTokens.radiusPanel,
    );
    expect(_corner(cassette.blockShape(cassette.border)), BoardTokens.cutBlock);
  });

  /// Chamfers may only be cut through the theme: a widget that invents its own corner is the same
  /// defect as one that invents its own colour.
  test('only the theme cuts a corner', () {
    final List<String> offenders = _libLinesMatching(
      RegExp(r'BeveledRectangleBorder'),
      skip: <String>{'lib/theme/board_theme.dart'},
    );
    expect(
      offenders,
      isEmpty,
      reason: 'use BoardShape.panel / BoardShape.block: $offenders',
    );
    expect(
      RegExp(r'BeveledRectangleBorder')
          .hasMatch('shape: BeveledRectangleBorder(borderRadius: r),'),
      isTrue,
    );
  });

  test('the type scale is SBB seven steps with SBB line heights', () {
    expect(
      <double>[
        BoardTokens.fsCaption,
        BoardTokens.fsMicro,
        BoardTokens.fsLabel,
        BoardTokens.fsBody,
        BoardTokens.fsTitle,
        BoardTokens.fsHeadline,
        BoardTokens.fsDisplay,
      ],
      <double>[10, 12, 14, 16, 18, 24, 30],
      reason: 'sbb_typography.dart sizes are 10/12/14/16/18/24/30',
    );
    expect(
      <double>[
        BoardTokens.lhCaption,
        BoardTokens.lhMicro,
        BoardTokens.lhLabel,
        BoardTokens.lhBody,
        BoardTokens.lhTitle,
        BoardTokens.lhHeadline,
        BoardTokens.lhDisplay,
      ],
      <double>[12, 16, 20, 20, 24, 32, 32],
      reason: 'sbb_typography.dart line heights are 12/16/20/20/24/32/32',
    );
  });

  test('SBB touch heights carry the board', () {
    // 44 is SBB's minimum for a single-line row and 56 is its small header. The results row carries
    // a second line (name over directory), so it may only ever be taller than that minimum - never
    // squeezed back under it by shrinking the type.
    expect(BoardTokens.laneHeaderHeight, 44);
    expect(BoardTokens.headerHeight, 56);
    expect(BoardTokens.rowHeight, greaterThanOrEqualTo(44));
    expect(
      BoardTokens.rowHeight % BoardTokens.gapSmall,
      0,
      reason: 'row height stays on the 4px step',
    );
  });

  /// SBB sets `letterSpacing` nowhere, and the two Swiss label devices are the only places this
  /// board tracks text - so tracking may only be written in the token file.
  test('tracking lives in the theme, not in a widget', () {
    final List<String> offenders = _libLinesMatching(
      RegExp(r'letterSpacing'),
      skip: <String>{'lib/theme/board_theme.dart'},
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'use BoardTokens.trackingMicro / trackingStep via palette.microLabel: $offenders',
    );
    // Positive control: the sweep is blind if it cannot see the offence it forbids.
    expect(
      RegExp(r'letterSpacing').hasMatch('style: TextStyle(letterSpacing: 0.7)'),
      isTrue,
    );
  });

  test('two weights only - the Material intermediates are banned', () {
    final RegExp banned = RegExp(
      r'FontWeight\.w(?:100|200|300|500|600|800|900)',
    );
    final List<String> offenders = _libLinesMatching(banned);
    expect(
      offenders,
      isEmpty,
      reason: 'hierarchy is w400 text against w700 emphasis: $offenders',
    );
    expect(banned.hasMatch('fontWeight: FontWeight.w600,'), isTrue);
  });

  testWidgets('selection is never the accent', (WidgetTester tester) async {
    for (final bool dark in <bool>[true, false]) {
      final BoardPalette palette = BoardPalette(dark: dark);
      expect(
        palette.selectionInk.toARGB32() & 0xFFFFFF,
        isNot(palette.primary.toARGB32() & 0xFFFFFF),
        reason: 'a picked row must not read as the primary action or as the live step',
      );
      expect(palette.selection.a, lessThan(1), reason: 'dark=$dark');
    }
  });

  /// The law only means something if the board actually paints it: a picked row is the reader's
  /// selection, so it wears the selection colour, and the accent stays reserved for the app's own
  /// interaction - the primary action and the stage in progress.
  testWidgets('a picked row wears the selection colour, not the accent', (
    WidgetTester tester,
  ) async {
    await pumpBoard(tester);
    final BoardPalette palette = BoardTheme.of(
      tester.element(find.byType(KisakiBoard)),
    );
    const Key rowKey = Key('result-row-/data/beta.bin');

    List<Color> emphasised() => tester
        .widgetList<Text>(
          find.descendant(of: find.byKey(rowKey), matching: find.byType(Text)),
        )
        .where((text) => text.style?.fontWeight == BoardTokens.weightEmphasis)
        .map((text) => text.style!.color!)
        .toList();

    // Positive control: before anything is picked the name is plain ink, so a green run cannot come
    // from the row never painting a colour at all.
    expect(emphasised(), contains(palette.fg));

    controller.toggleSelected(
      controller.rows.firstWhere((ScanRow row) => row.path == '/data/beta.bin'),
    );
    await tester.pumpAndSettle();

    final List<Color> picked = emphasised();
    expect(picked, contains(palette.selectionInk));
    expect(
      picked,
      isNot(contains(palette.primary)),
      reason: 'orange means the live stage or the primary action, never a picked row',
    );
  });

  /// The one functional addition of this pass: the board says which stage is in progress, and it
  /// says it from state - never more than one lane may carry the rule.
  testWidgets('exactly one lane carries the step rule, and state decides which', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      BoardTheme(
        dark: true,
        kind: BoardThemeKind.cassette,
        child: KisakiBoardApp(
          controller: controller,
          themeKind: BoardThemeKind.cassette,
        ),
      ),
    );
    await tester.pumpAndSettle();

    List<String> litLanes() {
      final BoardPalette palette = BoardTheme.of(
        tester.element(find.byType(KisakiBoard)),
      );
      return <String>['S', 'R', 'A']
          .where(
            (letter) =>
                tester
                    .widget<ColoredBox>(find.byKey(Key('lane-rule-$letter')))
                    .color ==
                palette.primary,
          )
          .toList();
    }

    // Nothing scanned yet: the reader is still naming folders.
    expect(litLanes(), <String>[
      'S',
    ], reason: 'source is the step before a scan exists');

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
    await tester.pumpAndSettle();
    expect(litLanes(), <String>[
      'R',
    ], reason: 'results holds the work once rows exist');

    controller.toggleSelected(
      controller.rows.firstWhere((ScanRow row) => row.path == '/data/beta.bin'),
    );
    await tester.pumpAndSettle();
    expect(litLanes(), <String>[
      'A',
    ], reason: 'analysis takes over on a selection');

    // The numbers are printed on every lane, live or not, so the order stays readable.
    for (final (String letter, String number) in <(String, String)>[
      ('S', '01'),
      ('R', '02'),
      ('A', '03'),
    ]) {
      expect(
        tester.widget<Text>(find.byKey(Key('lane-step-$letter'))).data,
        number,
        reason:
            'lane $letter must print its step number whether or not it is live',
      );
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

    final SingleChildScrollView lane = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('card-stack-analysis')),
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
        BoardTheme(
          dark: true,
          kind: BoardThemeKind.cassette,
          child: KisakiBoardApp(
            controller: controller,
            themeKind: BoardThemeKind.cassette,
          ),
        ),
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
    // The sweep stops at the floor the app itself enforces: `main.dart` pins the window to
    // `BoardTokens.minWindowWidth x minWindowHeight` through `windowManager.setMinimumSize`, so a
    // 800 x 600 window is one the platform will not hand the board. Testing at the floor keeps the
    // claim honest - below it, this gate would only measure an unreachable state.
    for (final Size size in <Size>[
      const Size(1440, 900),
      const Size(1024, 768),
      const Size(BoardTokens.minWindowWidth, BoardTokens.minWindowHeight),
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
          BoardTheme(
            dark: true,
            kind: BoardThemeKind.cassette,
            child: KisakiBoardApp(
              controller: controller,
              themeKind: BoardThemeKind.cassette,
            ),
          ),
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

  /// A hard-coded colour reaches only the theme it was written in, so the palette file is the one
  /// place a hex value may appear.
  test('no widget file names a colour', () {
    final List<String> offenders = _libLinesMatching(
      RegExp(r'Color\(0x'),
      skip: <String>{'lib/theme/board_theme.dart'},
    );
    expect(offenders, isEmpty, reason: 'take it from BoardPalette: $offenders');
    expect(
      RegExp(r'Color\(0x').hasMatch('const c = Color(0xFFEB0000);'),
      isTrue,
      reason: 'the sweep must see a literal it forbids',
    );
  });

  testWidgets('grid spans wrap instead of overflowing twelve columns', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      BoardTheme(
        dark: true,
        kind: BoardThemeKind.cassette,
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
      String? nearestKey;
      for (int depth = 0; depth < 14 && walk != null; depth++) {
        final Object? creator = walk.debugCreator;
        if (creator is DebugCreator) {
          trail.write(' ${creator.element.widget.runtimeType}');
          // The closest keyed widget names the site, which a render-object trail never does.
          final Key? key = creator.element.widget.key;
          nearestKey ??= key == null ? null : '$key';
        }
        walk = walk.parent;
      }
      if (nearestKey != null) {
        trail.write('  keyedBy=$nearestKey');
      }
      final List<String> kids = <String>[];
      object.visitChildren((RenderObject child) {
        if (child is RenderBox) {
          final Object? childCreator = child.debugCreator;
          kids.add(
            '${childCreator is DebugCreator ? childCreator.element.widget.runtimeType : child.runtimeType}'
            ' ${horizontal ? child.size.width : child.size.height}',
          );
        }
      });
      // The flex that starved this one: its sibling heights say who ate the lane.
      final StringBuffer parent = StringBuffer();
      RenderObject? up = object.parent;
      int hops = 0;
      while (up != null && hops < 3) {
        if (up is RenderFlex) {
          final List<String> sib = <String>[];
          up.visitChildren((RenderObject child) {
            if (child is RenderBox) {
              final Object? c = child.debugCreator;
              final String name = c is DebugCreator
                  ? '${c.element.widget.runtimeType}'
                  : '${child.runtimeType}';
              sib.add('$name ${child.size.height.toStringAsFixed(0)}');
            }
          });
          parent.write(' flex$hops=[$sib]');
          hops++;
        }
        up = up.parent;
      }
      found.add(
        '${horizontal ? "row" : "column"} needs ${used.toStringAsFixed(1)} of '
        '${limit.toStringAsFixed(1)} at$trail children=$kids$parent',
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
    } else if (widget is DecoratedBox && widget.decoration is ShapeDecoration) {
      // A chamfered panel paints through ShapeDecoration, and only a radius inside it is an offence.
      final ShapeBorder shape = (widget.decoration as ShapeDecoration).shape;
      if (shape is RoundedRectangleBorder) {
        add(shape.borderRadius);
      }
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

/// Every `file:line` in `lib/` whose text matches [pattern], except the files the law allows.
List<String> _libLinesMatching(
  RegExp pattern, {
  Set<String> skip = const <String>{},
}) {
  final List<String> found = <String>[];
  for (final File file in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart') || skip.contains(file.path)) {
      continue;
    }
    for (final (int index, String line) in file.readAsLinesSync().indexed) {
      if (pattern.hasMatch(line)) {
        found.add('${file.path}:${index + 1} ${line.trim()}');
      }
    }
  }
  return found;
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// A shape's corner size, whichever kind of corner it is.
double _corner(OutlinedBorder shape) => switch (shape) {
  RoundedRectangleBorder() =>
    shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
  BeveledRectangleBorder() =>
    shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
  _ => 0,
};
