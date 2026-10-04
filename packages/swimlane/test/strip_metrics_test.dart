import 'package:flutter_test/flutter_test.dart';
import 'package:swimlane/swimlane.dart';

import 'support/harness.dart';

void main() {
  // The fixture on a 1600px viewport, which is the size Rossi's default widths were
  // picked for: a 380, b 800 (ratio 0.5), c 360, two handles of 10.
  SwimlaneStripMetrics resolve({
    SwimlaneLayout? layout,
    double viewport = 1600,
    double? available,
    String? solo,
    String? active,
    bool railsInSolo = false,
  }) {
    return SwimlaneStripMetrics.resolve(
      layout: layout ?? threeLanes(),
      viewportWidth: viewport,
      availableWidth:
          available ?? (viewport - 2 * SwimlaneStripMetrics.defaultPadding),
      resizerWidth: SwimlaneStripMetrics.defaultResizerWidth,
      soloLaneId: solo,
      activeLaneId: active,
      showLaneNavigatorInSolo: railsInSolo,
    );
  }

  double widthOf(SwimlaneStripMetrics metrics, String laneId) {
    for (final SwimlaneStripSlot slot in metrics.slots) {
      if (slot.laneId == laneId) return slot.width;
    }
    return double.nan;
  }

  int handleCount(SwimlaneStripMetrics metrics) =>
      metrics.slots.where((SwimlaneStripSlot slot) => slot.isResizer).length;

  double slotSum(SwimlaneStripMetrics metrics) => metrics.slots.fold(
    0.0,
    (double total, SwimlaneStripSlot slot) => total + slot.width,
  );

  group('strip metrics', () {
    test('spare width goes to the reader lane and the total equals the available width', () {
      final metrics = resolve();
      expect(
        widthOf(metrics, 'a'),
        380,
        reason: 'panel lanes keep their pixels',
      );
      expect(widthOf(metrics, 'b'), 824, reason: '800 nominal + 24 spare');
      expect(widthOf(metrics, 'c'), 360);
      expect(handleCount(metrics), 2);
      expect(metrics.contentWidth, 1584);
      expect(metrics.needsScroll, isFalse);
      // The 2026-09-18 regression this exists to prevent: the spare was computed
      // against the **viewport** (1600), so the Row was 16px wider than its box and
      // Flutter painted the overflow stripes.
      expect(metrics.contentWidth, isNot(1600));
      expect(metrics.contentWidth, slotSum(metrics));
    });

    test('no single lane is wider than 85 percent of the viewport', () {
      // Rossi's phone-portrait case: a 369dp viewport with the desktop defaults
      // 380 / 650 / 360 would otherwise cut all three lanes in half.
      const viewport = 369.0;
      final metrics = resolve(viewport: viewport);
      const cap = viewport * SwimlaneStripMetrics.maxLaneViewportFactor;
      expect(cap, 313.65);
      for (final SwimlaneStripSlot slot in metrics.slots) {
        if (slot.laneId == null) continue;
        expect(slot.width, lessThanOrEqualTo(cap + 0.001));
      }
      expect(widthOf(metrics, 'a'), closeTo(313.65, 0.001));
      expect(metrics.needsScroll, isTrue);

      // POSITIVE CONTROL: without the cap, 'a' would be its stored 380px, which is
      // wider than the whole viewport - the exact thing this rule forbids.
      expect(laneA().resolveWidth(viewport), 380);
      expect(widthOf(metrics, 'a'), isNot(380));
    });

    test('the viewport floor can go below a lanes minWidth, on purpose', () {
      // b is a reader lane with minWidth 400. At a 369dp viewport the cap is
      // 313.65, so clamping to [minWidth, cap] would be unsatisfiable and the rule
      // would do nothing on the device that needs it. Rossi takes the floor as
      // min(minWidth, cap): "this lane whole" outranks a desktop number.
      final metrics = resolve(viewport: 369);
      expect(widthOf(metrics, 'b'), closeTo(313.65, 0.001));
      expect(widthOf(metrics, 'b'), lessThan(laneB().minWidth));
      // The control in the other direction: on a wide viewport the same lane is
      // never pushed under its minWidth.
      expect(widthOf(resolve(), 'b'), greaterThanOrEqualTo(laneB().minWidth));
    });

    test('a collapsed lane is 44dp and gets no handle beside it', () {
      final metrics = resolve(layout: threeLanes(aCollapsed: true));
      expect(widthOf(metrics, 'a'), SwimlaneLayout.collapsedLaneWidth);
      expect(
        handleCount(metrics),
        1,
        reason: 'a is a rail, so only the b / c seam has a handle',
      );
      expect(
        metrics.slots.where((s) => s.isResizer).map((s) => s.beforeLaneId),
        isNot(contains('a')),
      );
      // The rail is what is painted, so the slot says so too.
      expect(
        metrics.slots.firstWhere((s) => s.laneId == 'a').collapsed,
        isTrue,
      );
      // A lane that is not collapsed keeps two handles: the control that shows the
      // rail rule is not simply "always one fewer".
      expect(handleCount(resolve()), 2);
    });

    test('a rail in the middle leaves zero handles, not one', () {
      // expanded / rail / expanded draws no handle at all, while "visible lanes - 1"
      // would say one. An extra handle inflates contentWidth and starts the
      // scroller early - and breaks the equality with the slot sum, which is the
      // real occupied width.
      final layout = threeLanes();
      final collapsed = layout.copyWith(
        lanes: <String, LaneConfig>{
          ...layout.lanes,
          'b': layout.lane('b')!.copyWith(collapsed: true),
        },
      );
      final metrics = resolve(layout: collapsed);
      expect(handleCount(metrics), 0);
      expect(metrics.slots.length, 3);
      expect(metrics.contentWidth, 380 + 44 + 360);
      expect(metrics.contentWidth, slotSum(metrics));
      expect(
        metrics.contentWidth,
        lessThan(1600 - 2 * SwimlaneStripMetrics.defaultPadding),
      );
      expect(metrics.needsScroll, isFalse);
    });

    test('solo takes the available width and the rails come off the solo lane', () {
      final metrics = resolve(solo: 'b', active: 'b', railsInSolo: true);
      expect(widthOf(metrics, 'a'), SwimlaneLayout.collapsedLaneWidth);
      expect(widthOf(metrics, 'c'), SwimlaneLayout.collapsedLaneWidth);
      // 1584 - 44 - 44: the rails are subtracted **from** the solo lane.
      expect(widthOf(metrics, 'b'), 1496);
      expect(metrics.contentWidth, 1584);
      expect(metrics.needsScroll, isFalse);

      // POSITIVE CONTROL: letting solo eat the full available width and adding the
      // rails beside it puts the strip over budget by 88px, which turns needsScroll
      // on - and the rails, the point of the switch, get scrolled out of sight.
      expect(metrics.contentWidth, isNot(greaterThan(1584)));
      expect(widthOf(metrics, 'b'), isNot(1584));
    });

    test('the active lane is never a rail, and its width is not taken from solo', () {
      // Solo b, but the user is working in a.
      final metrics = resolve(solo: 'b', active: 'a', railsInSolo: true);
      expect(widthOf(metrics, 'a'), 380, reason: 'focused, so expanded');
      expect(widthOf(metrics, 'c'), SwimlaneLayout.collapsedLaneWidth);
      // Only the real rail (c) is subtracted: 1584 - 44.
      expect(widthOf(metrics, 'b'), 1540);
      // POSITIVE CONTROL: subtracting the expanded lane too would be 1584 - 88,
      // which is "focus squeezed the reader" - the thing this rule exists to stop.
      expect(widthOf(metrics, 'b'), isNot(1496));
      expect(handleCount(metrics), 1, reason: 'a and b are both expanded');
      expect(metrics.needsScroll, isTrue);
    });

    test('a solo lane that is itself collapsed gets no navigator', () {
      final layout = threeLanes();
      final soloCollapsed = layout.copyWith(
        soloLaneId: () => 'b',
        lanes: <String, LaneConfig>{
          ...layout.lanes,
          'b': layout.lane('b')!.copyWith(collapsed: true),
        },
      );
      final metrics = resolve(
        layout: soloCollapsed,
        solo: 'b',
        active: 'b',
        railsInSolo: true,
      );
      // Collapsing is the more explicit intent, and no lane is solo in the viewport
      // then, so nobody gets squeezed into a rail.
      expect(widthOf(metrics, 'a'), 380);
      expect(widthOf(metrics, 'c'), 360);
      expect(widthOf(metrics, 'b'), SwimlaneLayout.collapsedLaneWidth);
    });

    test(
      'a sub-pixel overrun is absorbed instead of starting the scroller',
      () {
        // contentWidth for a two-lane strip is 380 + 800 + one 10px handle = 1190.
        final twoLanes = SwimlaneLayout(
          laneOrder: const <String>['a', 'b'],
          lanes: <String, LaneConfig>{'a': laneA(), 'b': laneB()},
        );
        // available 1189.7: 0.3px over budget. Flutter flags an overflow at
        // `overflow.right > 0.0`, so "do not scroll" has to be stricter.
        final tight = resolve(layout: twoLanes, available: 1189.7);
        expect(tight.needsScroll, isFalse);
        expect(tight.contentWidth, 1189.7);
        expect(widthOf(tight, 'b'), closeTo(799.7, 0.001));

        // POSITIVE CONTROL: a real shortfall (beyond fitTolerance) must **not** be
        // absorbed - that would silently shrink a lane the user sized.
        final short = resolve(layout: twoLanes, available: 1189.0);
        expect(short.needsScroll, isTrue);
        expect(
          widthOf(short, 'b'),
          800,
          reason: 'stays at its own width, strip scrolls',
        );
        expect(short.contentWidth, 1190);
      },
    );

    test(
      'an id in the order with no config is skipped, leaving no empty slot',
      () {
        final layout = SwimlaneLayout(
          laneOrder: const <String>['a', 'ghost', 'b', 'c'],
          lanes: threeLanes().lanes,
        );
        final metrics = resolve(layout: layout);
        expect(metrics.slots.where((s) => !s.isResizer).length, 3);
        expect(handleCount(metrics), 2);
        expect(
          metrics.slots.map((s) => s.laneId).whereType<String>(),
          isNot(contains('ghost')),
        );
      },
    );
  });

  group('focus geometry', () {
    // a 380 + handle 10 + b 824 + handle 10 + c 360 = 1584, viewport 1600: no slack.
    final metrics = resolve();
    final geometry = SwimlaneFocusGeometry.fromMetrics(metrics);

    test('coordinates come from the slots, handles included', () {
      expect(geometry.start['a'], 0);
      expect(geometry.start['b'], 390, reason: '380 + the 10px handle');
      expect(geometry.start['c'], 1224, reason: '390 + 824 + 10');
      expect(geometry.contentWidth, 1584);
      // Skipping handles would shift every later lane, which by the third lane is a
      // visible misalignment.
      expect(geometry.start['c'], isNot(1214));
    });

    test('nothing to scroll means maxOffset is 0, not negative', () {
      expect(geometry.maxOffset(1600), 0);
      expect(geometry.clampOffset(-500, 1600), 0);
      // A negative floor would let a negative offset through and show blank space.
      expect(geometry.clampOffset(-1, 1600), isNot(-1));
    });

    test('a lane that is already whole does not move at all', () {
      final wide = SwimlaneStripMetrics(
        slots: const <SwimlaneStripSlot>[
          SwimlaneStripSlot.lane('a', 300),
          SwimlaneStripSlot.lane('b', 700),
          SwimlaneStripSlot.lane('c', 300),
        ],
        contentWidth: 1300,
        needsScroll: true,
      );
      final geo = SwimlaneFocusGeometry.fromMetrics(wide);
      // b spans 300..1000 and the viewport is 1000 wide: already visible.
      expect(
        geo.focusOffset(laneId: 'b', viewportWidth: 1000, currentOffset: 0),
        0,
      );
      // POSITIVE CONTROL: "centre the focused lane" would move to 150. That is the
      // mistake this rule exists to stop - the user clicks a lane right in front of
      // them and the picture slides.
      expect(
        geo.focusOffset(laneId: 'b', viewportWidth: 1000, currentOffset: 0),
        isNot(150),
      );
    });

    test('a clipped lane moves exactly far enough, from the nearer side', () {
      final wide = SwimlaneStripMetrics(
        slots: const <SwimlaneStripSlot>[
          SwimlaneStripSlot.lane('a', 300),
          SwimlaneStripSlot.lane('b', 700),
          SwimlaneStripSlot.lane('c', 300),
        ],
        contentWidth: 1300,
        needsScroll: true,
      );
      final geo = SwimlaneFocusGeometry.fromMetrics(wide);
      // c (1000..1300) is clipped on the right: 300 is the minimum move.
      expect(
        geo.focusOffset(laneId: 'c', viewportWidth: 1000, currentOffset: 0),
        300,
      );
      // a (0..300) is clipped on the left when the strip sits at 1000: pull back.
      expect(
        geo.focusOffset(laneId: 'a', viewportWidth: 1000, currentOffset: 300),
        0,
      );
    });

    test('a lane wider than the viewport aligns the nearer edge', () {
      final solo = SwimlaneStripMetrics(
        slots: const <SwimlaneStripSlot>[
          SwimlaneStripSlot.lane('a', 200),
          SwimlaneStripSlot.lane('b', 1400),
        ],
        contentWidth: 1600,
        needsScroll: true,
      );
      final geo = SwimlaneFocusGeometry.fromMetrics(solo);
      // b spans 200..1600 in a 1000 viewport: candidates 200 and 600.
      expect(
        geo.focusOffset(laneId: 'b', viewportWidth: 1000, currentOffset: 0),
        200,
        reason: 'came from the left, so align the start',
      );
      expect(
        geo.focusOffset(laneId: 'b', viewportWidth: 1000, currentOffset: 600),
        600,
        reason: 'came from the right, so align the end',
      );
    });

    test('the reader sliver outranks making the target lane whole', () {
      final wide = SwimlaneStripMetrics(
        slots: const <SwimlaneStripSlot>[
          SwimlaneStripSlot.lane('a', 300),
          SwimlaneStripSlot.lane('b', 700),
          SwimlaneStripSlot.lane('c', 300),
        ],
        contentWidth: 1300,
        needsScroll: true,
      );
      final geo = SwimlaneFocusGeometry.fromMetrics(wide);
      // Focusing c would move to 300; keeping 56px of a (which sits left of c) holds
      // it back at 300 - ... = 244.
      expect(
        geo.focusOffset(
          laneId: 'c',
          viewportWidth: 1000,
          currentOffset: 0,
          keepReaderPeekOf: 'a',
          peekWidth: 56,
        ),
        244,
      );
      // POSITIVE CONTROL: without the sliver the same call goes to 300, which pushes
      // a out entirely and loses the one-click way back to solo.
      expect(
        geo.focusOffset(laneId: 'c', viewportWidth: 1000, currentOffset: 0),
        300,
      );
      // A sliver wider than the lane or half the viewport is capped, or the target
      // lane stops being visible at all.
      expect(
        geo.focusOffset(
          laneId: 'c',
          viewportWidth: 1000,
          currentOffset: 0,
          keepReaderPeekOf: 'a',
          peekWidth: 900,
        ),
        0,
      );
    });

    test('reveal pushes the neighbour fully in and protects nothing', () {
      final wide = SwimlaneStripMetrics(
        slots: const <SwimlaneStripSlot>[
          SwimlaneStripSlot.lane('a', 300),
          SwimlaneStripSlot.lane('b', 700),
          SwimlaneStripSlot.lane('c', 300),
        ],
        contentWidth: 1300,
        needsScroll: true,
      );
      final geo = SwimlaneFocusGeometry.fromMetrics(wide);
      expect(geo.revealOffset(laneId: 'c', viewportWidth: 1000), 300);
      // Wider than the viewport: align its left edge instead.
      final solo = SwimlaneFocusGeometry.fromMetrics(
        const SwimlaneStripMetrics(
          slots: <SwimlaneStripSlot>[
            SwimlaneStripSlot.lane('a', 200),
            SwimlaneStripSlot.lane('b', 1400),
          ],
          contentWidth: 1600,
          needsScroll: true,
        ),
      );
      expect(solo.revealOffset(laneId: 'b', viewportWidth: 1000), 200);
      // A lane that is not in the strip cannot be revealed.
      expect(solo.revealOffset(laneId: 'zz', viewportWidth: 1000), 0);
      // A zero viewport has nothing to move.
      expect(solo.revealOffset(laneId: 'b', viewportWidth: 0), 0);
    });
  });

  group('header give-way budget', () {
    test('a mounted strip keeps its full width before any button', () {
      // Rossi's documented case: a 389px lane with a strip needing ~210. The old
      // version reserved space for the title first and cut the last icon off.
      final fit = resolveLaneHeaderFit(
        laneWidth: 389,
        isActive: false,
        stripNeed: 210,
      );
      expect(fit.stripMaxWidth, 210, reason: 'the strip has to stay whole');
      expect(fit.showMore, isTrue);
      expect(fit.showCollapse, isTrue);
      expect(fit.showSolo, isTrue);
      expect(fit.showBadge, isFalse, reason: 'the badge is the first to go');
    });

    test('the badge disappears at the width the constants predict', () {
      // Everything except the badge fits at 226, and the 1px of an active lane's
      // fatter border is enough to push it out - which is the "440px lane overflows
      // by 1px" arithmetic Rossi records.
      expect(
        resolveLaneHeaderFit(laneWidth: 226, isActive: false).showBadge,
        isTrue,
      );
      expect(
        resolveLaneHeaderFit(laneWidth: 225.9, isActive: false).showBadge,
        isFalse,
      );
      expect(
        resolveLaneHeaderFit(laneWidth: 226, isActive: true).showBadge,
        isFalse,
        reason: 'an active lane has 1px less to spend',
      );
      expect(
        resolveLaneHeaderFit(laneWidth: 227, isActive: true).showBadge,
        isTrue,
      );
    });

    test('give-way order is more, collapse, solo, badge', () {
      final fit = resolveLaneHeaderFit(laneWidth: 140, isActive: false);
      expect(fit.showMore, isTrue);
      expect(fit.showCollapse, isTrue);
      expect(fit.showSolo, isFalse);
      expect(fit.showBadge, isFalse);
      // One notch tighter: the 40px collapse button goes and the 24px "more" stays,
      // because whoever gives way **last** is the one served first.
      final tighter = resolveLaneHeaderFit(laneWidth: 102, isActive: false);
      expect(tighter.showMore, isTrue);
      expect(tighter.showCollapse, isFalse);
      // POSITIVE CONTROL: the budget is `laneWidth - 22 border/padding - 22 handle`,
      // so 66 leaves 22 and even "more" (24) has to go.
      final bare = resolveLaneHeaderFit(laneWidth: 66, isActive: false);
      expect(bare.showMore, isFalse);
      expect(bare.showCollapse, isFalse);
    });

    test('stripMaxWidth is never negative, so a flexible row gets 0', () {
      // A strip that cannot fit: the non-flexible items already sum past the row, so
      // the leftover is negative. A negative Expanded budget is the stripes overlay.
      final fit = resolveLaneHeaderFit(
        laneWidth: 100,
        isActive: false,
        stripNeed: 300,
      );
      expect(fit.stripMaxWidth, greaterThanOrEqualTo(0));
      expect(fit.showMore, isFalse);
      expect(fit.showCollapse, isFalse);
      expect(fit.showSolo, isFalse);
      expect(fit.showBadge, isFalse);
    });

    test('each host header action costs one compact icon button', () {
      final none = resolveLaneHeaderFit(laneWidth: 300, isActive: false);
      expect(none.showBadge, isTrue);
      // Four actions (4 x 40 = 160) push the badge out.
      final crowded = resolveLaneHeaderFit(
        laneWidth: 300,
        isActive: false,
        headerActionCount: 4,
      );
      expect(crowded.showBadge, isFalse);
    });
  });

  group('constants Rossi chose', () {
    test('the numbers the geometry and the widgets must agree on', () {
      // LaneResizer.width and the allocation read the same constant, or the strip
      // overflows by exactly one handle.
      expect(SwimlaneResizer.width, SwimlaneStripMetrics.defaultResizerWidth);
      expect(SwimlaneStripMetrics.defaultResizerWidth, 10.0);
      expect(SwimlaneStripMetrics.defaultPadding, 8.0);
      expect(SwimlaneLayout.collapsedLaneWidth, 44.0);
      expect(SwimlaneStripMetrics.fitTolerance, 0.5);
      expect(SwimlaneStripMetrics.maxLaneViewportFactor, 0.85);
      expect(const SwimlaneInteraction().stripPadding, 8.0);
      expect(const SwimlaneInteraction().resizerWidth, 10.0);
      expect(LaneChrome.badgeInner, 72);
      expect(LaneChrome.moreButton, 24);
      expect(LaneChrome.iconButton, 40);
      expect(LaneChrome.handle, 22);
    });
  });
}
