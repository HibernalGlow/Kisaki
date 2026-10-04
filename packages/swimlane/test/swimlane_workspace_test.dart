import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swimlane/swimlane.dart';

import 'support/harness.dart';

/// The five behaviours a host buys this package for, asserted through the widget:
/// reorder by drag, resize clamps, collapse and expand, solo and unsolo, and
/// dwell-to-focus.
///
/// Every clamp comes with a control that shows the gauge can see a violation: the
/// same operation with an in-band value must apply, and the unclamped result would
/// have been a different number.
void main() {
  LaneHarnessState host(WidgetTester tester) =>
      tester.state<LaneHarnessState>(find.byType(LaneHarness));

  Key laneKey(String name, String laneId) => ValueKey<String>('$name-$laneId');

  double paintedWidth(WidgetTester tester, String laneId) =>
      tester.getSize(find.byKey(laneKey('lane-drop', laneId))).width;

  double laneLeft(WidgetTester tester, String laneId) =>
      tester.getTopLeft(find.byKey(laneKey('lane-drop', laneId))).dx;

  setUp(() {
    contentBuilds.clear();
    contentTaps.clear();
    RecordingMenuHost.requests.clear();
  });

  group('reorder by drag', () {
    testWidgets(
      'holding a lane header icon and dropping it on another lane swaps them',
      (tester) async {
        await pumpHarness(tester, LaneHarness(layout: threeLanes()));
        final state = host(tester);
        expect(laneLeft(tester, 'a'), 8);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(laneKey('lane-drag', 'a'))),
        );
        // LongPressDraggable(delay: 200ms): hold still until the long press wins, then
        // move. An ordinary drag must never reorder.
        await tester.pump(const Duration(milliseconds: 300));
        await gesture.moveTo(
          tester.getCenter(find.byKey(laneKey('lane-title', 'c'))),
        );
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(state.layout.laneOrder, <String>['b', 'c', 'a']);
        // a is now the last lane in the strip.
        expect(laneLeft(tester, 'a'), greaterThan(laneLeft(tester, 'c')));
        // Reordering changes who is on the left and nothing else.
        expect(state.layout.lane('a')!.width, 380);
        expect(state.layout.lane('b')!.widthRatio, 0.5);
        expect(state.layout.lane('a')!.collapsed, isFalse);
        expect(state.layout.soloLaneId, isNull);
        expect(state.emittedLayouts, hasLength(1));
      },
    );

    testWidgets('dropping a lane on itself reorders nothing', (tester) async {
      await pumpHarness(tester, LaneHarness(layout: threeLanes()));
      final state = host(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(laneKey('lane-drag', 'a'))),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(
        tester.getCenter(find.byKey(laneKey('lane-title', 'a'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // POSITIVE CONTROL: without the "not this lane" guard the host would be handed
      // a layout for a drop that changed nothing.
      expect(state.layout.laneOrder, <String>['a', 'b', 'c']);
      expect(state.emittedLayouts, isEmpty);
    });
  });

  group('resize clamps', () {
    testWidgets('growing a lane stops at its own maxWidth', (tester) async {
      await pumpHarness(tester, LaneHarness(layout: threeLanes()));
      final state = host(tester);

      // 1000px of drag on a lane whose band tops out 320px away.
      await dragHandleBy(tester, 'a-b', 1000);
      await tester.pumpAndSettle();

      expect(state.layout.lane('a')!.width, 700);
      expect(state.layout.lane('b')!.width, 480);
      expect(paintedWidth(tester, 'a'), 700);
      // The badge reports the width the lane is actually laid out at.
      expect(find.text('700px'), findsOneWidget);
      // POSITIVE CONTROL: an unclamped drag would have handed back 1380, and the
      // neighbour would have gone under its 400px floor.
      expect(state.layout.lane('a')!.width, isNot(1380));
      for (final SwimlaneLayout emitted in state.emittedLayouts) {
        expect(emitted.lane('a')!.width, lessThanOrEqualTo(700));
        expect(emitted.lane('b')!.width, greaterThanOrEqualTo(400));
      }
    });

    testWidgets(
      'shrinking a lane stops at its own minWidth and the pair conserves width',
      (tester) async {
        await pumpHarness(tester, LaneHarness(layout: threeLanes()));
        final state = host(tester);

        await dragHandleBy(tester, 'a-b', -2000);
        await tester.pumpAndSettle();

        expect(state.layout.lane('a')!.width, 300);
        expect(find.text('300px'), findsOneWidget);
        expect(
          state.layout.lane('a')!.width + state.layout.lane('b')!.width,
          1180,
          reason:
              'a handle moves width between two lanes, it never creates any',
        );
        // POSITIVE CONTROL: a clamp that rejected everything would have left 380.
        expect(state.layout.lane('a')!.width, isNot(380));
      },
    );

    testWidgets(
      'an in-band drag is applied, so the two clamps above are not a stub',
      (tester) async {
        await pumpHarness(tester, LaneHarness(layout: threeLanes()));
        final state = host(tester);

        await dragHandleBy(tester, 'a-b', 100);
        await tester.pumpAndSettle();

        expect(state.layout.lane('a')!.width, 480);
        expect(state.layout.lane('b')!.width, 700);
        // A drag is a **stream** of deltas - the handle forwards one layout per pointer
        // move, and the clamp lives in the model, so every step on the way has to be a
        // legal width, not just the last one.
        expect(state.emittedLayouts, isNotEmpty);
        for (final SwimlaneLayout emitted in state.emittedLayouts) {
          expect(emitted.lane('a')!.width, inInclusiveRange(380, 700));
          expect(emitted.lane('b')!.width, inInclusiveRange(400, 2000));
        }
      },
    );

    testWidgets('a double tap on the handle resets both sides', (tester) async {
      await pumpHarness(tester, LaneHarness(layout: threeLanes()));
      final state = host(tester);

      await dragHandleBy(tester, 'a-b', 150);
      await tester.pumpAndSettle();
      expect(state.layout.lane('a')!.width, 530);
      expect(state.layout.lane('b')!.widthRatio, closeTo(650 / 1600, 1e-9));

      // Two taps inside the double-tap timeout, at the same place.
      await tester.tap(find.byKey(laneKey('resizer', 'a-b')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(laneKey('resizer', 'a-b')));
      await tester.pumpAndSettle();

      expect(state.layout.lane('a')!.width, 380);
      expect(state.layout.lane('b')!.width, 650);
      // The ratio is what matters: a lane dragged to 650px in a 1600px window stored
      // 0.40625, and resetting must put back the 0.5 it started with.
      expect(state.layout.lane('b')!.widthRatio, 0.5);
    });

    testWidgets(
      'a reader lane dragged wide remembers the ratio, not the pixels',
      (tester) async {
        await pumpHarness(tester, LaneHarness(layout: threeLanes()));
        final state = host(tester);

        // Push b out by dropping a to its floor.
        await dragHandleBy(tester, 'a-b', -80);
        await tester.pumpAndSettle();

        expect(state.layout.lane('a')!.width, 300);
        expect(state.layout.lane('b')!.width, 880);
        expect(
          state.layout.lane('b')!.widthRatio,
          closeTo(880 / 1600, 1e-9),
          reason:
              'a window resize must scale it instead of losing the user intent',
        );
      },
    );
  });

  group('collapse and expand', () {
    testWidgets('a collapsed lane becomes the 44dp rail and loses its handle', (
      tester,
    ) async {
      await pumpHarness(tester, LaneHarness(layout: threeLanes()));
      final state = host(tester);

      expect(paintedWidth(tester, 'a'), 380);
      await tester.tap(find.byKey(laneKey('lane-collapse', 'a')));
      await tester.pumpAndSettle();

      expect(state.layout.lane('a')!.collapsed, isTrue);
      expect(find.byKey(laneKey('lane-rail', 'a')), findsOneWidget);
      expect(find.byKey(laneKey('lane-content', 'a')), findsNothing);
      expect(paintedWidth(tester, 'a'), SwimlaneLayout.collapsedLaneWidth);
      // Rossi's handle rule: no handle is drawn beside a rail, and the strip has to
      // agree with that or contentWidth and the painted width diverge.
      expect(find.byKey(const ValueKey<String>('resizer-a-b')), findsNothing);
      expect(find.byKey(const ValueKey<String>('resizer-b-c')), findsOneWidget);

      await tester.tap(find.byKey(laneKey('lane-expand', 'a')));
      await tester.pumpAndSettle();

      expect(state.layout.lane('a')!.collapsed, isFalse);
      expect(find.byKey(laneKey('lane-content', 'a')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('resizer-a-b')), findsOneWidget);
      expect(paintedWidth(tester, 'a'), 380);
    });

    testWidgets(
      "a user-collapsed lane's rail expands it, and the press focuses once",
      (tester) async {
        await pumpHarness(
          tester,
          LaneHarness(layout: threeLanes(aCollapsed: true)),
        );
        final state = host(tester);

        expect(find.byKey(laneKey('lane-rail', 'a')), findsOneWidget);
        await tester.tap(find.byKey(laneKey('lane-expand', 'a')));
        await tester.pumpAndSettle();

        // This rail came from the `collapsed` flag, so its button belongs to that flag.
        // A navigator rail routes the same button to focus instead - see the solo group.
        expect(state.layout.lane('a')!.collapsed, isFalse);
        // Pressing anything inside a lane **also** hands it the interaction: Rossi
        // listens for the pointer down on the whole lane, header controls included
        // ("I pressed collapse and it also focused the lane" is the documented
        // trade-off; "I pressed collapse and nothing happened" is not). What the rail
        // button must not do is ask for focus **again** through its own route - the
        // second tap below proves the request is deduplicated, not repeated.
        expect(state.emittedFocus, <String?>['a']);

        await tester.tap(find.byKey(laneKey('lane-collapse', 'a')));
        await tester.pumpAndSettle();
        expect(state.emittedFocus, <String?>[
          'a',
        ], reason: 'focus already sits here');
        expect(state.layout.lane('a')!.collapsed, isTrue);
      },
    );

    testWidgets('right-clicking a rail still reaches the host menu', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        LaneHarness(layout: threeLanes(), menuHost: const RecordingMenuHost()),
      );

      await tester.tap(find.byKey(laneKey('lane-collapse', 'a')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(laneKey('lane-menu', 'a')),
        findsNothing,
        reason: '44px holds no button',
      );

      await tester.tap(
        find.byKey(laneKey('lane-rail', 'a')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(RecordingMenuHost.requests, hasLength(1));
      final request = RecordingMenuHost.requests.single;
      expect(request.laneId, 'a');
      expect(request.showsAsRail, isTrue);
      expect(
        request.lane.config.collapsed,
        isTrue,
        reason: 'the flag says how',
      );
      expect(request.viewportWidth, 1600);
    });
  });

  group('solo', () {
    testWidgets(
      'takes the viewport, squeezes the others into rails, then gives it back',
      (tester) async {
        await pumpHarness(
          tester,
          LaneHarness(
            layout: threeLanes(),
            interaction: const SwimlaneInteraction(
              showLaneNavigatorInSolo: true,
            ),
          ),
        );
        final state = host(tester);

        await tester.tap(find.byKey(laneKey('lane-solo', 'b')));
        await tester.pumpAndSettle();

        expect(state.layout.soloLaneId, 'b');
        // Pressing solo also hands over the interaction: solo should mean "let me see
        // it".
        expect(state.emittedFocus, <String?>['b']);
        // 1584 available, minus the two rails it paid for out of its own width.
        expect(paintedWidth(tester, 'b'), 1496);
        expect(find.text('1496px'), findsOneWidget);
        // The others stop being lanes: their content is not drawn at all.
        expect(find.byKey(laneKey('lane-content', 'a')), findsNothing);
        expect(find.byKey(laneKey('lane-content', 'c')), findsNothing);
        expect(find.byKey(laneKey('lane-rail', 'a')), findsOneWidget);
        expect(find.byKey(laneKey('lane-rail', 'c')), findsOneWidget);

        await tester.tap(find.byKey(laneKey('lane-solo', 'b')));
        await tester.pumpAndSettle();

        expect(state.layout.soloLaneId, isNull);
        expect(find.byKey(laneKey('lane-content', 'a')), findsOneWidget);
        expect(find.byKey(laneKey('lane-content', 'c')), findsOneWidget);
        expect(paintedWidth(tester, 'a'), 380);
        // Back to the nominal allocation, spare handed to the reader lane again.
        expect(paintedWidth(tester, 'b'), 824);
        // POSITIVE CONTROL: leaving solo must not move focus somewhere else.
        expect(state.emittedFocus, <String?>['b']);
      },
    );

    testWidgets(
      'tapping a navigator rail focuses it instead of collapsing it',
      (tester) async {
        await pumpHarness(
          tester,
          LaneHarness(
            layout: threeLanes(),
            interaction: const SwimlaneInteraction(
              showLaneNavigatorInSolo: true,
            ),
            startActive: 'b',
          ),
        );
        final state = host(tester);

        await tester.tap(find.byKey(laneKey('lane-solo', 'b')));
        await tester.pumpAndSettle();
        expect(find.byKey(laneKey('lane-rail', 'a')), findsOneWidget);
        final layouts = state.emittedLayouts.length;

        await tester.tap(
          find.byKey(laneKey('lane-rail', 'a')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // A navigator rail was never collapsed by the user, so toggling collapse would
        // turn "show the lane navigator" into "collapse this lane forever".
        expect(state.layout.lane('a')!.collapsed, isFalse);
        expect(state.emittedLayouts, hasLength(layouts));
        expect(state.emittedFocus, contains('a'));
      },
    );

    testWidgets('a reader solo keeps its width when another lane takes focus', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        LaneHarness(
          layout: threeLanes(),
          interaction: const SwimlaneInteraction(showLaneNavigatorInSolo: true),
          startActive: 'b',
        ),
      );
      final state = host(tester);

      await tester.tap(find.byKey(laneKey('lane-solo', 'b')));
      await tester.pumpAndSettle();
      expect(paintedWidth(tester, 'b'), 1496);

      // Focus moves to a panel lane. The reader keeps the width it is laid out at
      // (only the rail it pays for changes): re-laying out and re-decoding an
      // expensive lane on a hover is what the asymmetry in `effectiveSoloLaneId` is
      // for, and the newly active lane is expanded rather than squeezed into a rail.
      // Focus moves to a panel lane. The rail is the only handle it has - a lane
      // drawn as a rail carries no title - and pressing that rail is what routes to
      // "give this lane the interaction".
      await tester.tap(
        find.byKey(laneKey('lane-rail', 'a')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(state.active, 'a');
      expect(paintedWidth(tester, 'b'), 1540);
      expect(paintedWidth(tester, 'a'), 380);
      expect(find.byKey(laneKey('lane-content', 'a')), findsOneWidget);
      expect(find.byKey(laneKey('lane-rail', 'a')), findsNothing);
    });

    testWidgets(
      'a panel solo is only in effect while it is also the active lane',
      (tester) async {
        await pumpHarness(
          tester,
          LaneHarness(
            layout: threeLanes(),
            interaction: const SwimlaneInteraction(
              showLaneNavigatorInSolo: true,
            ),
          ),
        );
        final state = host(tester);

        await tester.tap(find.byKey(laneKey('lane-solo', 'a')));
        await tester.pumpAndSettle();
        expect(state.layout.soloLaneId, 'a');
        // Solo also focuses, so a panel lane's solo is in effect straight away.
        expect(state.active, 'a');
        expect(paintedWidth(tester, 'a'), 1496);

        // The only handle c offers while a is solo is its rail.
        await tester.tap(
          find.byKey(laneKey('lane-rail', 'c')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Focus left the solo panel lane, so its solo stops being effective and the
        // strip goes back to the ordinary allocation - the stored preference is intact.
        expect(state.layout.soloLaneId, 'a');
        expect(state.layout.effectiveSoloLaneId(activeLaneId: 'c'), isNull);
        expect(paintedWidth(tester, 'a'), 380);
      },
    );

    testWidgets(
      'on touch the navigator rails appear even when the preference is off',
      (tester) async {
        await pumpHarness(
          tester,
          LaneHarness(
            layout: threeLanes(),
            pointerMode: SwimlanePointerMode.touchOnly,
          ),
        );
        final state = host(tester);

        await tester.tap(find.byKey(laneKey('lane-solo', 'b')));
        await tester.pumpAndSettle();

        // Edge dwell needs PointerHoverEvent, which never fires on touch, and swiping
        // the strip collides with the host's own gestures - so the rails are the only
        // handle back. They come from "is there a pointer", not from the stored
        // preference.
        expect(state.interaction.showLaneNavigatorInSolo, isFalse);
        expect(find.byKey(laneKey('lane-rail', 'a')), findsOneWidget);
        expect(paintedWidth(tester, 'b'), 1496);
      },
    );

    testWidgets(
      'without the navigator the strip moves the others out instead',
      (tester) async {
        await pumpHarness(tester, LaneHarness(layout: threeLanes()));
        final state = host(tester);

        await tester.tap(find.byKey(laneKey('lane-solo', 'b')));
        await tester.pumpAndSettle();

        // b took the whole available width, so the strip is wider than the viewport and
        // moved to show it: "showing a lane means moving the strip", never re-stacking.
        expect(paintedWidth(tester, 'b'), 1584);
        expect(
          tester.getTopLeft(find.byKey(laneKey('lane-content', 'b'))).dx,
          closeTo(8 + (1584 - 40) / 2, 1),
        );
        expect(
          tester.getTopLeft(find.byKey(laneKey('lane-content', 'c'))).dx,
          greaterThan(1600),
        );
        // a kept its stored width; it is simply off the left edge now.
        expect(state.layout.lane('a')!.width, 380);
        expect(paintedWidth(tester, 'a'), 380);
      },
    );
  });

  group('dwell to focus', () {
    // settle (60ms) + hoverFocusDelayMs (150ms) = 210ms of sitting still.
    testWidgets(
      'hands the interaction over only after the dwell, and only once',
      (tester) async {
        await pumpHarness(tester, LaneHarness(layout: threeLanes()));
        final state = host(tester);
        final buildsBefore = contentBuilds.length;

        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(pointer.removePointer);
        // Start inside the strip padding: over no lane, so nothing is being timed.
        await pointer.addPointer(location: const Offset(2, 400));
        await tester.pump();
        await pointer.moveTo(
          tester.getCenter(find.byKey(laneKey('lane-title', 'c'))),
        );
        // The frame that starts the ticker reports zero elapsed.
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 100));
        // POSITIVE CONTROL: an implementation that fires on enter, or that ignores the
        // settle window, would already have moved focus.
        expect(state.emittedFocus, isEmpty);

        await tester.pump(const Duration(milliseconds: 109));
        expect(state.emittedFocus, isEmpty, reason: '209ms: one ms short');

        await tester.pump(const Duration(milliseconds: 1));
        expect(state.emittedFocus, <String?>['c']);
        expect(state.active, 'c');

        // Still parked there, long past the deadline: nothing re-fires, or the strip
        // would jitter sideways every frame.
        await tester.pump(const Duration(milliseconds: 500));
        expect(state.emittedFocus, <String?>[
          'c',
        ], reason: 'one dwell, one focus');

        // The interaction moved and no lane content was rebuilt: that is the instance
        // cache doing the job it is there for.
        expect(contentBuilds, hasLength(buildsBefore));
      },
    );

    testWidgets(
      'leaving before the deadline cancels, and the next lane starts fresh',
      (tester) async {
        await pumpHarness(tester, LaneHarness(layout: threeLanes()));
        final state = host(tester);

        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(pointer.removePointer);
        await pointer.addPointer(location: const Offset(2, 400));
        await tester.pump();
        await pointer.moveTo(
          tester.getCenter(find.byKey(laneKey('lane-title', 'c'))),
        );
        // `MouseTracker` delivers enter/exit from a **post-frame** callback, so the
        // frame after a move is where a dwell actually starts - the sibling test above
        // spends the same 60+150 from that point, and the numbers below are its clock.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Sweep away. Cancelling must be per-lane: c leaving must not wipe the timing b
        // has just started (the exit is delivered before the enter).
        await pointer.moveTo(
          tester.getCenter(find.byKey(laneKey('lane-title', 'b'))),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 170));
        // POSITIVE CONTROL: had c's dwell survived the sweep, it would have been 270ms
        // old here and fired, so this is the per-lane cancel and not a dead timer.
        expect(
          state.emittedFocus,
          isEmpty,
          reason: 'b has had 170ms of its own 210',
        );

        await tester.pump(const Duration(milliseconds: 40));
        expect(state.emittedFocus, <String?>['b']);
      },
    );

    testWidgets('a rail is skipped, so it stays a usable handle', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        LaneHarness(
          layout: threeLanes(aCollapsed: true),
          interaction: const SwimlaneInteraction(hoverFocusDelayMs: 10),
        ),
      );
      final state = host(tester);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      await pointer.addPointer(location: const Offset(2, 400));
      await tester.pump();
      // Park on the 44px rail, with a delay short enough that any other lane would
      // have taken focus several times over by now.
      await pointer.moveTo(
        tester.getCenter(find.byKey(laneKey('lane-rail', 'a'))),
      );
      await tester.pump(const Duration(milliseconds: 400));

      // POSITIVE CONTROL: the same dwell on a normal lane does fire (tests above), so
      // this is the rail guard and not a dead timer.
      expect(state.emittedFocus, isEmpty);
    });

    testWidgets('a pass-by never shows the armed border; stopping does', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        LaneHarness(
          layout: threeLanes(),
          headerActionsBuilder: (BuildContext context, SwimlaneLaneInfo lane) =>
              <Widget>[
                if (lane.focusArmed)
                  SizedBox(
                    key: laneKey('armed', lane.laneId),
                    width: 8,
                    height: 8,
                  ),
              ],
        ),
      );
      final state = host(tester);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      await pointer.addPointer(location: const Offset(2, 400));
      await tester.pump();
      await pointer.moveTo(
        tester.getCenter(find.byKey(laneKey('lane-title', 'c'))),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Moving continuously re-arms the settle window, so the preview never appears
      // and a sweep across the strip cannot be mistaken for "I want to be here".
      for (var i = 0; i < 8; i++) {
        await pointer.moveBy(const Offset(4, 0));
        await tester.pump(const Duration(milliseconds: 10));
        expect(find.byKey(laneKey('armed', 'c')), findsNothing);
      }
      expect(state.emittedFocus, isEmpty);

      // Now actually stop: the border comes first, the hand-over afterwards.
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(laneKey('armed', 'c')), findsOneWidget);
      expect(state.emittedFocus, isEmpty);

      await tester.pump(const Duration(milliseconds: 200));
      expect(state.emittedFocus, <String?>['c']);
      expect(
        find.byKey(laneKey('armed', 'c')),
        findsNothing,
        reason: 'delivered',
      );
    });

    testWidgets('dwellSuppressed stops it, and nothing is delivered late', (
      tester,
    ) async {
      await pumpHarness(tester, LaneHarness(layout: threeLanes()));
      final state = host(tester);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      await pointer.addPointer(location: const Offset(2, 400));
      await tester.pump();
      await pointer.moveTo(
        tester.getCenter(find.byKey(laneKey('lane-title', 'c'))),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // A modal came up while the pointer was parked here.
      state.setDwellSuppressed(true);
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.emittedFocus, isEmpty);

      // Lifting the suppression must not deliver the dwell that was armed behind it.
      state.setDwellSuppressed(false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.emittedFocus, isEmpty);
    });

    testWidgets('a click voids the pending dwell', (tester) async {
      await pumpHarness(tester, LaneHarness(layout: threeLanes()));
      final state = host(tester);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      await pointer.addPointer(location: const Offset(2, 400));
      await tester.pump();
      await pointer.moveTo(
        tester.getCenter(find.byKey(laneKey('lane-title', 'c'))),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // One click is an explicit intent: the user must not get a second, automatic
      // move a moment later.
      await pointer.down(
        tester.getCenter(find.byKey(laneKey('lane-title', 'c'))),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await pointer.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.emittedFocus, <String?>['c']);
      expect(state.emittedFocus, hasLength(1));
    });
  });

  group('host seams', () {
    testWidgets('the menu request carries the laid-out numbers', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        LaneHarness(layout: threeLanes(), menuHost: const RecordingMenuHost()),
      );

      await tester.tap(find.byKey(laneKey('lane-menu', 'a')));
      expect(RecordingMenuHost.requests, hasLength(1));
      final request = RecordingMenuHost.requests.single;
      expect(request.laneId, 'a');
      expect(request.showsAsRail, isFalse);
      expect(request.isSolo, isFalse);
      expect(request.viewportWidth, 1600);
      expect(request.lane.laidOutWidth, 380);
      expect(request.lane.config.title, 'Alpha');
      expect(request.onResetWidth, isNotNull);

      // Right-clicking the header is the other entrance into the same request.
      await tester.tap(
        find.byKey(laneKey('lane-title', 'b')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(RecordingMenuHost.requests, hasLength(2));
      expect(RecordingMenuHost.requests.last.laneId, 'b');
    });

    testWidgets(
      'a host header strip keeps its width while the badge gives way',
      (tester) async {
        // Lane c is 360 wide and the strip declares it needs 210: the budget must hand
        // the strip its full 210 and drop the width badge, never clip an icon.
        await pumpHarness(
          tester,
          LaneHarness(
            layout: threeLanes(),
            headerStrip: const FixedHeaderStrip(),
          ),
        );

        expect(find.byKey(laneKey('header-strip', 'c')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(laneKey('header-strip', 'c'))).width,
          210,
          reason: 'the icons stay whole - the user rule this budget implements',
        );
        expect(find.byKey(laneKey('lane-badge', 'c')), findsNothing);
        expect(find.byKey(laneKey('lane-content', 'c')), findsOneWidget);
        // A wide lane keeps both.
        expect(find.byKey(laneKey('lane-badge', 'b')), findsOneWidget);
        expect(find.byKey(laneKey('header-strip', 'b')), findsOneWidget);
      },
    );

    testWidgets(
      'the first click on inactive content focuses and never reaches it',
      (tester) async {
        await pumpHarness(
          tester,
          LaneHarness(layout: threeLanes(), startActive: 'a'),
        );
        final state = host(tester);

        await tester.tap(find.byKey(laneKey('lane-content', 'c')));
        await tester.pumpAndSettle();

        // The contract: that click is consumed by the workspace and must not reach the
        // lane content.
        expect(contentTaps, isEmpty);
        expect(state.emittedFocus, <String?>['c']);

        await tester.tap(find.byKey(laneKey('lane-content', 'c')));
        await tester.pumpAndSettle();
        // Active now, so the same click lands normally.
        expect(contentTaps, <String>['c']);
      },
    );

    testWidgets(
      'absorbInactiveContent false hands every click straight through',
      (tester) async {
        await pumpHarness(
          tester,
          LaneHarness(
            layout: threeLanes(),
            startActive: 'a',
            absorbInactiveContent: false,
          ),
        );

        await tester.tap(find.byKey(laneKey('lane-content', 'c')));
        await tester.pumpAndSettle();
        expect(contentTaps, <String>['c']);
      },
    );

    testWidgets('titles and icons come from the host', (tester) async {
      await pumpHarness(
        tester,
        LaneHarness(
          layout: threeLanes(),
          titleBuilder: (SwimlaneLaneInfo lane) =>
              lane.laneId == 'b' ? 'Renamed' : null,
          iconBuilder: (SwimlaneLaneInfo lane) =>
              lane.laneId == 'b' ? Icons.star_rounded : null,
        ),
      );

      expect(find.text('Renamed'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      expect(
        find.text('Alpha'),
        findsOneWidget,
        reason: 'null falls back to the model',
      );
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.byIcon(Icons.view_column_rounded), findsNWidgets(2));
    });

    testWidgets('the focus resolver can redirect a request', (tester) async {
      await pumpHarness(
        tester,
        LaneHarness(
          layout: threeLanes(),
          focusResolver: (SwimlaneLayout layout, String? requested) =>
              requested == 'c' ? 'a' : requested,
        ),
      );
      final state = host(tester);

      await tester.tap(find.byKey(laneKey('lane-title', 'c')));
      await tester.pumpAndSettle();

      expect(state.emittedFocus, <String?>['a']);
    });

    testWidgets('an empty layout draws nothing and throws nothing', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        LaneHarness(
          layout: const SwimlaneLayout(
            laneOrder: <String>[],
            lanes: <String, LaneConfig>{},
          ),
        ),
      );

      expect(find.byType(SwimlaneColumn), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
