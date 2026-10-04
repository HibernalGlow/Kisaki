import 'dart:math' as math;

import 'lane_config.dart';
import 'swimlane_layout.dart';

/// One slot of the horizontal strip: either a lane, or the handle between two
/// lanes.
class SwimlaneStripSlot {
  /// Lane id; `null` marks a resizer slot.
  final String? laneId;

  /// Width this slot occupies.
  final double width;

  /// Whether this lane is drawn as the compact rail. Always `false` for handles.
  final bool collapsed;

  /// The two lanes a handle sits between (`null` for lane slots).
  ///
  /// The handle remembers its own pair: a drag callback has to change the
  /// ratio **of a pair**, and making the caller reconstruct "previous / next
  /// lane" from strip order duplicates that bookkeeping in the host.
  /// Rossi `WorkspaceStripSlot.beforeLaneId` / `afterLaneId`.
  final String? beforeLaneId;
  final String? afterLaneId;

  const SwimlaneStripSlot.lane(String id, this.width, {this.collapsed = false})
    : laneId = id,
      beforeLaneId = null,
      afterLaneId = null;

  const SwimlaneStripSlot.resizer(
    this.width, {
    required String before,
    required String after,
  }) : laneId = null,
       collapsed = false,
       beforeLaneId = before,
       afterLaneId = after;

  bool get isResizer => laneId == null;

  @override
  String toString() => isResizer
      ? 'resizer(${width}px, $beforeLaneId to $afterLaneId)'
      : '$laneId(${width}px${collapsed ? ', rail' : ''})';
}

/// Width allocation for the whole strip. **Pure calculation**, no widget.
///
/// This is the only place in the package where a wrong number shows up as a
/// yellow-and-black stripes overlay instead of a compile error: when the slots
/// add up to more than the row's available width, Flutter paints the overflow
/// indicator over the right 10% of the container. Rossi hit exactly that
/// (2026-09-18, "RIGHT OVERFLOWED BY 16 PIXELS", 16 = the strip's two paddings)
/// because the spare width was computed against the **viewport** while the `Row`
/// only ever gets the **padded** width. So [resolve] takes both, and the
/// invariant is `contentWidth <= availableWidth` unless [needsScroll].
class SwimlaneStripMetrics {
  final List<SwimlaneStripSlot> slots;

  /// Sum of all slot widths. Less than or equal to the available width whenever
  /// [needsScroll] is false.
  final double contentWidth;

  /// The strip does not fit: it scrolls sideways, lanes never overlap.
  final bool needsScroll;

  /// Strip padding, one on each side. This **is** the difference between the
  /// available width and the viewport width.
  /// Rossi `WorkspaceStripMetrics.defaultPadding`.
  static const double defaultPadding = 8.0;

  /// Width of the handle between two lanes. Rossi
  /// `WorkspaceStripMetrics.defaultResizerWidth` (neoview `RESIZER_WIDTH`).
  ///
  /// Lives in the model, not in the handle widget, because the handle width
  /// takes part in the width allocation and both sides must read one number.
  /// `SwimlaneResizer.width` refers to this value.
  static const double defaultResizerWidth = 10.0;

  /// Sub-pixel tolerance: a difference this small is absorbed by the elastic
  /// lane instead of turning on the scroller.
  ///
  /// Testing `spare > 0` is not enough: at 0.3px over budget `needsScroll` would
  /// stay false while the `Row` still overflows, because Flutter's overflow test
  /// is `overflow.right > 0.0` with **no** tolerance. The "do not scroll" rule has
  /// to be stricter than the "paint stripes" rule.
  /// Rossi `WorkspaceStripMetrics.fitTolerance`.
  static const double fitTolerance = 0.5;

  /// How much of the viewport a single lane may eat at most.
  /// Rossi `WorkspaceStripMetrics.maxLaneViewportFactor`.
  ///
  /// 0.85 and not 1.0, so a sliver of the neighbour stays visible and "there is
  /// more beside this lane" remains something the user can see.
  static const double maxLaneViewportFactor = 0.85;

  const SwimlaneStripMetrics({
    required this.slots,
    required this.contentWidth,
    required this.needsScroll,
  });

  /// A lane must never be **wider than the viewport**.
  ///
  /// The contract says panel lanes are absolute pixels, not clamped to the
  /// window width - but the precondition for that is "the whole strip then
  /// scrolls". On a scrollable desktop strip that holds. A single lane wider than
  /// the viewport does not read as "there is more content": it reads as "this
  /// lane got cut in half", because the entire scroll slack is spent on it and
  /// nothing hints that other lanes exist. Rossi
  /// `WorkspaceStripMetrics._fitToViewport`.
  ///
  /// The floor is `min(lane.minWidth, cap)` rather than `lane.minWidth`: on a
  /// narrow viewport the minimum itself can exceed the cap, and clamping to an
  /// unreachable floor would make this function do nothing on exactly the devices
  /// that need it. `minWidth` is a desktop readability number; when it does not
  /// fit, "this lane is whole" wins.
  static double _fitToViewport(LaneConfig lane, double viewportWidth) {
    final resolved = lane.resolveWidth(viewportWidth);
    if (viewportWidth <= 0) return resolved;
    final cap = viewportWidth * maxLaneViewportFactor;
    final floor = math.min(lane.minWidth, cap);
    return resolved.clamp(floor, cap).toDouble();
  }

  /// Allocate widths. The three invariants (Rossi `WorkspaceStripMetrics.resolve`,
  /// itself the neoview lane contract):
  ///
  /// 1. panel lanes are **absolute pixels**, not clamped to the current window
  ///    width; reader lanes are a **viewport ratio**, so [viewportWidth] is what
  ///    the ratio multiplies. The one exception is [_fitToViewport];
  /// 2. spare width goes to the **elastic lane** (centre fills);
  /// 3. when it does not fit, every lane keeps its stored width and the **whole
  ///    strip scrolls** - lanes never overlap.
  ///
  /// [availableWidth] must be the width **after** the strip padding. It is not
  /// interchangeable with [viewportWidth]: computing the spare from the viewport
  /// over-counts it by the padding, the `Row` gets pushed out of its container,
  /// and the interface grows a stripes overlay.
  ///
  /// [soloLaneId] is the solo lane: its width for this pass becomes the whole
  /// available width. "Solo" is therefore not a second layout - it is one width
  /// inside the same strip, which is what makes scrolling to reveal a lane work
  /// at all.
  ///
  /// [activeLaneId] only decides **who gets expanded**: the active lane keeps its
  /// width, everyone else may be squeezed into the compact rail.
  static SwimlaneStripMetrics resolve({
    required SwimlaneLayout layout,
    required double viewportWidth,
    required double availableWidth,
    required double resizerWidth,
    String? soloLaneId,
    String? activeLaneId,
    bool showLaneNavigatorInSolo = false,
  }) {
    // 1. Each lane first, by its own measuring unit.
    final widths = <String, double>{};
    final collapsed = <String, bool>{};
    final solo = soloLaneId;
    // "Show the lane navigator while solo" means: everything except the solo lane
    // and the active lane becomes a rail, and the rails *are* the navigator -
    // tapping one hands the interaction over to that lane.
    // A solo lane that is itself collapsed gets no navigator: collapsing it is the
    // more explicit intent, and then no lane is solo in the viewport anyway.
    final railsArmed =
        solo != null &&
        showLaneNavigatorInSolo &&
        layout.lanes[solo]?.collapsed != true;
    for (final String laneId in layout.laneOrder) {
      final LaneConfig? lane = layout.lanes[laneId];
      if (lane == null) continue;
      final bool isSolo = laneId == solo;
      // **Whichever lane is active gets expanded.** The navigator exists to hand
      // the interaction elsewhere; squeezing the lane that already has it back to
      // 44px means the user taps a rail and still cannot touch anything inside it.
      final bool isRail =
          railsArmed && laneId != activeLaneId && laneId != solo;
      // A collapse flag the user set wins over the rail: it is the more explicit
      // intent, and a rail looks exactly the same in the navigator anyway.
      final bool isCollapsed = lane.collapsed || isRail;
      widths[laneId] = isCollapsed
          ? SwimlaneLayout.collapsedLaneWidth
          : isSolo
          ? availableWidth
          : _fitToViewport(lane, viewportWidth);
      collapsed[laneId] = isCollapsed;
    }

    // 1a. The rails' width is **taken off the solo lane**, not added next to it.
    //
    // Letting the solo lane eat the whole `availableWidth` and then placing 44px
    // rails beside it puts the strip over budget by exactly one rail width, which
    // means `needsScroll` - and the rails get scrolled out of the viewport. The
    // navigator would then show nothing at all, worse than not asking for it.
    //
    // Only the lanes that really became rails (44px) are subtracted. The active
    // lane is already expanded to its own width; subtracting that would make
    // "focus" squeeze the solo lane, which is precisely what this file stopped
    // doing (see [SwimlaneLayout.effectiveSoloLaneId]).
    if (railsArmed) {
      final double? soloWidth = widths[solo];
      if (soloWidth != null) {
        var railTotal = 0.0;
        for (final MapEntry<String, double> entry in widths.entries) {
          if (entry.key == solo) continue;
          if (collapsed[entry.key] != true) continue;
          railTotal += entry.value;
        }
        // When the window is too narrow for "one solo lane + the rails" the rails
        // still take their space (the strip scrolls), and the solo lane keeps a
        // rail width as its floor: a zero-width lane would hand the `Column`
        // inside it illegal constraints.
        widths[solo] = math.max(
          SwimlaneLayout.collapsedLaneWidth,
          soloWidth - railTotal,
        );
      }
    }

    // 1b. The handle count must follow **the rule that draws handles**, not
    //     "visible lanes - 1". The two differ when a collapsed lane sits in the
    //     middle: expanded / rail / expanded paints **zero** handles (no handle
    //     beside a rail), while "lanes - 1" says one. That extra handle inflates
    //     `contentWidth`, starts the scroller earlier than it should, and breaks
    //     the equality with the sum of the slots - which is the real occupied
    //     width.
    var resizerCount = 0;
    String? previousLane;
    for (final String laneId in layout.laneOrder) {
      if (!widths.containsKey(laneId)) continue;
      final bool isCollapsed = collapsed[laneId]!;
      if (previousLane != null &&
          !isCollapsed &&
          collapsed[previousLane] == false) {
        resizerCount++;
      }
      previousLane = laneId;
    }

    var contentWidth = resizerWidth * resizerCount;
    for (final double width in widths.values) {
      contentWidth += width;
    }

    // 2. Spare width goes to the elastic lane - computed against the **available**
    //    width. The elastic lane is the only flexible one, so it also absorbs
    //    sub-pixel differences: a positive difference is the spare (take what
    //    there is), and a small negative one is swallowed rather than paying a
    //    stripes overlay for 0.3px. Only a real shortfall (below
    //    -[fitTolerance]) is left to the horizontal scroller.
    //    After absorbing, `contentWidth == availableWidth` is **assigned, not
    //    summed**: the floating-point tail of a sum is exactly what triggers the
    //    zero-tolerance overflow warning.
    final spare = availableWidth - contentWidth;
    final String? elasticLaneId = _elasticLaneId(layout, widths);
    final double? elasticWidth = elasticLaneId == null
        ? null
        : widths[elasticLaneId];
    final bool elasticIsElastic =
        (elasticWidth ?? 0) > 0 && collapsed[elasticLaneId!] == false;
    if (elasticIsElastic &&
        spare >= -fitTolerance &&
        elasticWidth! + spare > 0) {
      widths[elasticLaneId] = elasticWidth + spare;
      contentWidth = availableWidth;
    }

    // 3. From here "scroll or not" is a plain binary choice with no tolerance in
    //    between: not scrolling means the slots sum to at most the available
    //    width, so the `Row` cannot overflow.
    final needsScroll = contentWidth > availableWidth;

    // 4. Assemble in order: lanes plus the handles between adjacent lanes. The
    //    handle test must be **the same text** as 1b, or `contentWidth` and the
    //    slot sum drift apart.
    final slots = <SwimlaneStripSlot>[];
    String? previous;
    for (final String laneId in layout.laneOrder) {
      final double? width = widths[laneId];
      if (width == null) continue;
      final bool isCollapsed = collapsed[laneId]!;
      if (previous != null && !isCollapsed && collapsed[previous] == false) {
        slots.add(
          SwimlaneStripSlot.resizer(
            resizerWidth,
            before: previous,
            after: laneId,
          ),
        );
      }
      slots.add(SwimlaneStripSlot.lane(laneId, width, collapsed: isCollapsed));
      previous = laneId;
    }

    return SwimlaneStripMetrics(
      slots: slots,
      contentWidth: contentWidth,
      needsScroll: needsScroll,
    );
  }

  /// The elastic lane: the first laid-out lane of [LaneKind.reader].
  ///
  /// Rossi hard-codes `LaneId.reader`, a single string the application owns; a
  /// package has to ask the lane instead. The `?? 0 > 0` and `collapsed == false`
  /// guards below are his, unchanged, and they already cover "no reader lane":
  /// `widths[missing]` is null, so nothing absorbs the spare.
  static String? _elasticLaneId(
    SwimlaneLayout layout,
    Map<String, double> widths,
  ) {
    for (final String laneId in layout.laneOrder) {
      if (!widths.containsKey(laneId)) continue;
      if (layout.lanes[laneId]?.kind == LaneKind.reader) return laneId;
    }
    return null;
  }
}
