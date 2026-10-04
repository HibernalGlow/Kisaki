import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/theme/board_theme.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// The Material kind is only "standard Material 3" if the framework's own derivations are what reach
/// the screen. Each gate reads a value back off the seeded scheme or off the painted board, so a
/// hand-picked colour or a copied corner cannot pass as M3.
void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  BoardPalette paletteOf(bool dark) =>
      BoardPalette(dark: dark, kind: BoardThemeKind.material);

  Future<void> pumpMaterialBoard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
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
      KisakiBoardApp(
        controller: controller,
        themeKind: BoardThemeKind.material,
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final bool dark in <bool>[true, false]) {
    test('the surfaces are the M3 container tiers (dark=$dark)', () {
      final BoardPalette palette = paletteOf(dark);
      final ColorScheme scheme = palette.scheme;

      expect(palette.bg, scheme.surfaceContainerLow);
      expect(palette.card, scheme.surfaceContainer);
      expect(palette.raised, scheme.surfaceContainerHigh);
      expect(palette.sunken, scheme.surfaceContainerHighest);
      expect(palette.border, scheme.outlineVariant);
      expect(palette.fgMuted, scheme.onSurfaceVariant);

      // Positive control: the tier ladder must actually be four different tones, or "tiers" is a
      // name for one colour.
      final Set<int> grounds = <int>{
        palette.bg.toARGB32(),
        palette.card.toARGB32(),
        palette.raised.toARGB32(),
        palette.sunken.toARGB32(),
      };
      expect(grounds, hasLength(4), reason: 'dark=$dark');
    });

    test('selection is secondaryContainer and never the accent (dark=$dark)', () {
      final BoardPalette palette = paletteOf(dark);
      expect(palette.selection, palette.scheme.secondaryContainer);
      expect(palette.selectionInk, palette.scheme.onSecondaryContainer);
      expect(
        palette.selectionInk,
        isNot(palette.primary),
        reason: 'M3 keeps selection off the primary hue, as the cassette skin does',
      );
    });

    test('a panel is filleted from the theme radius (dark=$dark)', () {
      final BoardPalette palette = paletteOf(dark);
      final RoundedRectangleBorder shape =
          palette.panelShape(palette.border) as RoundedRectangleBorder;
      expect(
        shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
        BoardTokens.radiusPanel,
      );
      final RoundedRectangleBorder block =
          palette.blockShape(palette.border) as RoundedRectangleBorder;
      expect(
        block.borderRadius.resolve(TextDirection.ltr).topLeft.x,
        greaterThan(BoardTokens.radiusPanel),
      );
    });
  }

  test('the shell comes from the scheme, not from a copied palette', () {
    final BoardPalette palette = paletteOf(false);
    final ThemeData theme = boardThemeData(palette);

    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme, palette.scheme);
    expect(theme.scaffoldBackgroundColor, palette.bg);
    expect(theme.dividerTheme.thickness, BoardTokens.hairline);
    // M3 keeps its own elevation for a dialog; the board's flatness is only about its panels.
    expect(theme.dialogTheme.elevation ?? 6, greaterThan(0));
  });

  testWidgets('the material board paints flat panels and one lit step', (
    WidgetTester tester,
  ) async {
    await pumpMaterialBoard(tester);
    final BoardPalette palette = BoardTheme.of(
      tester.element(find.byType(KisakiBoard)),
    );

    final List<double> elevated = tester
        .widgetList<Material>(find.byType(Material))
        .map((material) => material.elevation)
        .where((elevation) => elevation > 0)
        .toList();
    expect(
      elevated,
      isEmpty,
      reason: 'panels separate by ground tier here, the way Rossi does it',
    );

    final List<String> lit = <String>['S', 'R', 'A']
        .where(
          (letter) =>
              tester
                  .widget<ColoredBox>(find.byKey(Key('lane-rule-$letter')))
                  .color ==
              palette.primary,
        )
        .toList();
    expect(lit, <String>['R'], reason: 'rows exist, so results holds the work');
  });
}
