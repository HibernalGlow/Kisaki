import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/source_panel.dart';

import 'support/stub_engine.dart';

/// czkawka_core checks the allowed list and, only when it is empty, the excluded list
/// (`czkawka_core/src/common/extensions.rs:78-88`), so filling both is not an intersection. The board
/// says so, but only in the one state where the reader could be misled.
void main() {
  late BoardController controller;
  const Key hint = Key('ext-priority-hint');

  setUp(() {
    controller = BoardController(engine: StubEngine());
    controller.addIncluded(<String>['/data']);
  });

  /// The panel is pumped on its own: inside the board it lives in a lane that culls the rows below
  /// the fold, so an absent hint there would only prove the reader had not scrolled.
  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The panel brings its own ListView, so it needs a bounded box rather than an outer scroll
          // view: the lane gives it a height, and here the window is that height.
          body: SizedBox.expand(
            child: AnimatedBuilder(
              animation: controller,
              // The lane hosts the panel the same way: SourcePanel itself does not listen, so a
              // change to the extension lists only reaches the tree through a listening ancestor.
              builder: (BuildContext context, Widget? _) =>
                  SourcePanel(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('token-field-Excluded extensions')),
      findsOneWidget,
      reason:
          'the hint sits under this row, so paint it before claiming absence; '
          'the heading itself is uppercased by MicroHeading',
    );
  }

  testWidgets('the warning appears only while both lists have entries', (
    WidgetTester tester,
  ) async {
    controller.addAllowedExtension(<String>['jpg']);
    await pumpPanel(tester);
    expect(
      find.byKey(hint),
      findsNothing,
      reason: 'an empty excluded list leaves nothing ambiguous to warn about',
    );

    controller.addExcludedExtension(<String>['tmp']);
    await tester.pumpAndSettle();
    expect(
      find.byKey(hint),
      findsOneWidget,
      reason:
          'an excluded list that cannot take effect has to be named out loud',
    );

    controller.removeAllowedExtension(0);
    await tester.pumpAndSettle();
    expect(
      find.byKey(hint),
      findsNothing,
      reason: 'with the allowed list empty the excluded list really does apply',
    );
  });
}
