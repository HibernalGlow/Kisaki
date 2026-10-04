import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/ui/board.dart';
import 'package:kisaki_app/ui/widgets/primitives.dart';

import 'support/stub_engine.dart';

/// The reference list is a subset of what the board scans, and the node lets the reader say so per
/// path (the star) or for the whole list at once. Both routes have to keep that subset true, so these
/// tests watch the reference list itself rather than the pixels.
void main() {
  late BoardController controller;

  setUp(() {
    controller = BoardController(engine: StubEngine());
    controller.addIncluded(<String>['/data/one', '/data/two']);
  });

  test('one star, one unstar', () {
    controller.toggleIncludedReference('/data/one');
    expect(controller.reference, <String>['/data/one']);
    expect(controller.isIncludedReference('/data/one'), isTrue);

    controller.toggleIncludedReference('/data/one');
    expect(controller.reference, isEmpty);
  });

  test('a path the board does not scan cannot be made a reference', () {
    controller.toggleIncludedReference('/data/not-included');
    expect(
      controller.reference,
      isEmpty,
      reason:
          'the reference list guards this and Kisaki must not accept it either',
    );
  });

  test('set all and clear all', () {
    controller.setAllIncludedReferences(true);
    expect(controller.reference, <String>['/data/one', '/data/two']);
    expect(controller.everyIncludedIsReference, isTrue);

    controller.setAllIncludedReferences(false);
    expect(controller.reference, isEmpty);
    expect(controller.everyIncludedIsReference, isFalse);
  });

  test('removing a path drops its reference with it', () {
    controller.toggleIncludedReference('/data/one');
    controller.removeIncluded(0);
    expect(controller.included, <String>['/data/two']);
    expect(
      controller.reference,
      isEmpty,
      reason: 'a reference the board never scans is not a reference',
    );

    controller.setAllIncludedReferences(true);
    controller.clearIncluded();
    expect(controller.reference, isEmpty);
  });

  testWidgets('the star and the set all button drive the same list', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('reference-/data/one')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reference-/data/one')));
    await tester.pumpAndSettle();
    expect(controller.reference, <String>['/data/one']);

    await tester.ensureVisible(find.byKey(const Key('reference-set-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reference-set-all')));
    await tester.pumpAndSettle();
    expect(controller.reference, <String>[
      '/data/one',
      '/data/two',
    ], reason: 'the button offers the whole list, not just what is on screen');
    expect(
      tester
          .widget<BoardAction>(find.byKey(const Key('reference-set-all')))
          .labelKey,
      'reference-unmark-all',
      reason:
          'once everything is a reference the button turns into its inverse',
    );

    await tester.tap(find.byKey(const Key('reference-set-all')));
    await tester.pumpAndSettle();
    expect(controller.reference, isEmpty);
    expect(
      find.text(Labels.of('reference-star')),
      findsNothing,
      reason: 'the star stays an icon, so the row does not grow with a label',
    );
  });
}
