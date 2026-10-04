import 'dart:math' as math;

import 'strip_metrics.dart';

/// Bookkeeping for the strip's scroll position - **pure calculation**.
///
/// The lane contract defines "show a lane" as **moving the strip**, not lifting a
/// lane above the others. That forces two questions:
///
/// 1. when a lane becomes **active**, where should the strip sit? The contract
///    says "the **minimum** horizontal movement needed to make the lane usable",
///    not "centre it";
/// 2. when a viewport edge has been dwelled on, how far should the strip move to
///    **reveal** the neighbour?
///
/// Neither is just "scroll somewhere": they decide whether the picture jumps when
/// the user clicks. Re-centring a picture that already looked right is the easiest
/// mistake to make here, which is why it is pulled out of
/// `ScrollController.animateTo` and pinned by assertions.
///
/// Widths come from [SwimlaneStripMetrics] because the width a lane actually
/// occupies is often **not** its nominal one: 44dp while collapsed, the whole
/// viewport while solo, plus the spare when there is spare. Any second source of
/// widths diverges from the strip, and the computed offsets then point at
/// something else than what is drawn.
class SwimlaneFocusGeometry {
  /// Left edge of each lane, relative to the strip content origin.
  final Map<String, double> start;

  /// Laid-out width of each lane.
  final Map<String, double> width;

  /// Total content width, handles included.
  final double contentWidth;

  const SwimlaneFocusGeometry({
    required this.start,
    required this.width,
    required this.contentWidth,
  });

  /// Derive coordinates from **that same** [metrics]: one source for order and
  /// width.
  factory SwimlaneFocusGeometry.fromMetrics(SwimlaneStripMetrics metrics) {
    final starts = <String, double>{};
    final widths = <String, double>{};
    var cursor = 0.0;
    for (final SwimlaneStripSlot slot in metrics.slots) {
      // Handles take space too: skip one and the whole strip shifts left a
      // little, which by the third lane is a visible misalignment.
      cursor += slot.width;
      final String? laneId = slot.laneId;
      if (laneId == null) continue;
      starts[laneId] = cursor - slot.width;
      widths[laneId] = slot.width;
    }
    return SwimlaneFocusGeometry(
      start: starts,
      width: widths,
      contentWidth: metrics.contentWidth,
    );
  }

  bool containsLane(String laneId) => width.containsKey(laneId);

  double endOf(String laneId) => (start[laneId] ?? 0) + (width[laneId] ?? 0);

  /// The last legal offset. When the content is narrower than the viewport there
  /// is **nothing to scroll**, so 0 and not a negative number: a caller clamping
  /// against a negative max would treat a negative offset as legal and the
  /// picture would show blank space on the left.
  double maxOffset(double viewportWidth) =>
      math.max(0, contentWidth - viewportWidth);

  /// Pull [offset] into the legal range.
  double clampOffset(double offset, double viewportWidth) =>
      offset.clamp(0, maxOffset(viewportWidth)).toDouble();

  /// The offset the strip should sit at when [laneId] becomes **active**.
  ///
  /// Three rules, in the contract's priority order:
  ///
  /// 1. **already inside the viewport: do not move at all.** "Minimum horizontal
  ///    movement to make the lane usable" for a fully visible lane is 0. Treating
  ///    "centre it" as "focus it" is the classic mistake: the user clicks a lane
  ///    right in front of them and the picture slides - that is not focus, that
  ///    is jitter.
  /// 2. **wider than the viewport** (a solo lane is): align the **nearer** edge,
  ///    so the movement is the smaller one whichever side the user came from.
  /// 3. narrower than the viewport: move **exactly enough** for it to be whole
  ///    (push it left out of the right clip, pull it right out of the left one).
  ///
  /// [keepReaderPeekOf] adds a constraint: the lane named there keeps a sliver of
  /// [peekWidth] inside the viewport, so one click on that sliver returns to solo.
  /// The contract's wording is "where possible", so the peek outranks "whole".
  double focusOffset({
    required String laneId,
    required double viewportWidth,
    required double currentOffset,
    String? keepReaderPeekOf,
    double peekWidth = 0,
  }) {
    if (viewportWidth <= 0) return 0;
    final laneWidth = width[laneId];
    if (laneWidth == null) return clampOffset(currentOffset, viewportWidth);

    final current = clampOffset(currentOffset, viewportWidth);
    final laneStart = start[laneId]!;
    final laneEnd = laneStart + laneWidth;
    final limit = maxOffset(viewportWidth);

    double target;
    if (laneWidth >= viewportWidth) {
      // Two candidates that differ by exactly (laneWidth - viewportWidth): the
      // one nearer the current offset is the smaller move.
      final alignStart = laneStart;
      final alignEnd = laneEnd - viewportWidth;
      target = (alignStart - current).abs() <= (alignEnd - current).abs()
          ? alignStart
          : alignEnd;
    } else if (current <= laneStart && laneEnd <= current + viewportWidth) {
      target = current; // already whole - do not move
    } else if (laneStart < current) {
      target = laneStart; // left edge clipped: pull it back into view
    } else {
      target = laneEnd - viewportWidth; // right edge clipped: push it in
    }

    final String? peekLaneId = keepReaderPeekOf;
    if (peekLaneId != null &&
        peekLaneId != laneId &&
        containsLane(peekLaneId)) {
      final double peekLaneWidth = width[peekLaneId]!;
      // The sliver may not exceed the lane itself, nor half the viewport:
      // otherwise "keep a peek" becomes "the viewport is all leftover lane" and
      // the target lane is the thing that disappears.
      final peek = math.min(
        peekWidth,
        math.min(peekLaneWidth, viewportWidth / 2),
      );
      final readerStart = start[peekLaneId]!;
      final readerEnd = readerStart + peekLaneWidth;
      if (readerEnd <= laneStart) {
        // The peek lane is on the left: the offset may not push it out entirely.
        target = math.min(target, readerEnd - peek);
      } else if (readerStart >= laneEnd) {
        // On the right: it may not shrink below the sliver.
        target = math.max(target, readerStart - (viewportWidth - peek));
      }
    }

    return target.clamp(0, limit).toDouble();
  }

  /// The offset that **reveals** [laneId] after an edge dwell.
  ///
  /// Differs from [focusOffset] by not protecting the peek: the point of a reveal
  /// is to see the neighbour **whole**, so it is pushed fully into the viewport
  /// and whatever has to leave, leaves. A panel lane wider than the viewport
  /// falls back to aligning its left edge.
  double revealOffset({required String laneId, required double viewportWidth}) {
    if (viewportWidth <= 0) return 0;
    final laneWidth = width[laneId];
    if (laneWidth == null) return 0;
    final laneStart = start[laneId]!;
    final laneEnd = laneStart + laneWidth;
    final target = laneWidth >= viewportWidth
        ? laneStart
        : laneEnd - viewportWidth;
    return clampOffset(target, viewportWidth);
  }
}
