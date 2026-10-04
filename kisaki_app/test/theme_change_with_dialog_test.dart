import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/theme/board_theme.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// `BoardTheme` carries a key built from `dark` and the theme kind, so changing either one replaces
/// the whole `MaterialApp` element - and a dialog lives *inside* that element, in the Navigator's
/// overlay. Framework asserts that an inherited widget has no dependents left when it is deactivated
/// (`_dependents.isEmpty`), which is the red screen that was reported.
///
/// Both ways of changing the theme are covered: the runtime one the user reaches (`toggleTheme`),
/// and the constructor seam.
void main() {
  late BoardController controller;

  setUp(() {
    controller = BoardController(engine: StubEngine());
  });

  Future<void> pumpBoard(WidgetTester tester, BoardThemeKind kind) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      KisakiBoardApp(controller: controller, themeKind: kind),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCardManager(WidgetTester tester) async {
    final Finder manage = find.byKey(const Key('cards-manage'));
    expect(manage, findsOneWidget, reason: 'the card manager entry is on the board');
    await tester.tap(manage, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget, reason: 'the dialog is on screen');
  }

  testWidgets('toggling dark mode with a dialog open keeps the tree alive', (
    tester,
  ) async {
    await pumpBoard(tester, BoardThemeKind.cassette);
    await openCardManager(tester);

    controller.toggleTheme();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsOneWidget, reason: 'the dialog survives the theme change');
  });

  testWidgets('switching the theme kind with a dialog open keeps the tree alive', (
    tester,
  ) async {
    await pumpBoard(tester, BoardThemeKind.cassette);
    await openCardManager(tester);

    await tester.pumpWidget(
      KisakiBoardApp(controller: controller, themeKind: BoardThemeKind.material),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsOneWidget, reason: 'the dialog survives the theme change');
  });

  testWidgets('toggling dark mode while the dialog route is animating', (
    tester,
  ) async {
    await pumpBoard(tester, BoardThemeKind.cassette);
    final Finder manage = find.byKey(const Key('cards-manage'));
    await tester.tap(manage, warnIfMissed: false);
    // Mid-transition: the route lives in the overlay as a GlobalKey'd entry, which is the state
    // where a remount of the inherited widget above it can leave a dependent behind.
    await tester.pump(const Duration(milliseconds: 50));
    controller.toggleTheme();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
