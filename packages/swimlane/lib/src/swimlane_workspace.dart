import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'dwell_pump.dart';
import 'lane_config.dart';
import 'lane_focus.dart';
import 'lane_host.dart';
import 'strip_metrics.dart';
import 'swimlane_column.dart';
import 'swimlane_interaction.dart';
import 'swimlane_layout.dart';
import 'swimlane_resizer.dart';

part 'swimlane_workspace_lane_info.dart';
part 'swimlane_workspace_strip.dart';

/// The horizontal lane strip: one flat band of lanes, laid out, resized,
/// reordered, scrolled, and focused by dwelling.
///
/// Four invariants, ported from Rossi's `SwimlaneWorkspace` (which states them as
/// the neoview lane contract):
///
/// 1. every lane lives in **one horizontal strip**; showing a lane means **moving
///    the strip**. Lanes never overlap and never float above each other;
/// 2. panel lanes are absolute pixels, not clamped to the window width; reader
///    lanes are a viewport ratio;
/// 3. spare width goes to the elastic lane; when it does not fit, the whole strip
///    scrolls sideways;
/// 4. **solo is not a second layout**: it is one lane whose width for this pass is
///    the available width, inside the same strip - which is what gives
///    scroll-to-reveal something to scroll.
///
/// ## State
///
/// The widget is **controlled**: [layout] and [activeLaneId] come from the host, and
/// every change leaves through [onLayoutChanged] / [onActiveLaneChanged]. Nothing is
/// persisted here, so the host can veto, debounce, or store it. Transient state that
/// only this layer can own (the dwell timers, the armed highlight, the scroll
/// position) stays inside.
///
/// ## Dwell
///
/// This widget hosts "dwell". The timing rules are pure (`SwimlaneDwell`),
/// `SwimlaneDwellPump` supplies the clock, and here a deadline turns into "focus this
/// lane" - with the border lit one step earlier so the last stretch feels answered.
class SwimlaneWorkspace extends StatefulWidget {
  const SwimlaneWorkspace({
    super.key,
    required this.layout,
    required this.laneBuilder,
    this.activeLaneId,
    this.onLayoutChanged,
    this.onActiveLaneChanged,
    this.interaction = const SwimlaneInteraction(),
    this.pointerMode,
    this.focusResolver,
    this.menuHost,
    this.headerStrip,
    this.headerActionsBuilder,
    this.iconBuilder,
    this.titleBuilder,
    this.absorbInactiveContent = true,
    this.dwellSuppressed = false,
    this.scrollController,
  });

  /// Lane order, widths, collapse flags, solo. Host-owned.
  final SwimlaneLayout layout;

  /// The lane the workspace handed the interaction to, or `null` when nobody has
  /// been focused yet.
  ///
  /// `null` is a real state, and with [absorbInactiveContent] it means "eat nothing":
  /// a cold start must not swallow the user's first click because of a default focus
  /// nobody chose (Rossi `WorkspaceState.activeLaneId`).
  final String? activeLaneId;

  /// Draws one lane's content. The package never renders lane content itself.
  ///
  /// Content must not depend on `SwimlaneLaneInfo.isActive`: instances are kept
  /// across a focus change on purpose, see `_syncLaneContent`.
  final SwimlaneWidgetBuilder laneBuilder;

  /// Every lane-model change: reorder, drag resize, collapse, solo, width reset.
  final ValueChanged<SwimlaneLayout>? onLayoutChanged;

  /// Focus moved to another lane (click, drop, or dwell).
  final ValueChanged<String?>? onActiveLaneChanged;

  final SwimlaneInteraction interaction;

  /// Overrides the platform-derived pointer mode. `null` = derive it, see
  /// [SwimlanePointerMode].
  final SwimlanePointerMode? pointerMode;

  /// Lets the host redirect a focus request, e.g. "focusing the reader lane while a
  /// modal is open means nothing". `null` means "the requested lane".
  /// Rossi `LaneFocusResolver`.
  final String? Function(SwimlaneLayout layout, String? requestedLaneId)?
  focusResolver;

  final SwimlaneMenuHost? menuHost;
  final SwimlaneHeaderStripHost? headerStrip;
  final SwimlaneHeaderActionsBuilder? headerActionsBuilder;
  final SwimlaneIconBuilder? iconBuilder;
  final SwimlaneTitleBuilder? titleBuilder;

  /// Rossi's contract for a non-active lane: `That click is consumed by the workspace
  /// and must not reach Reader area bindings, page navigation, video controls, or the
  /// radial menu`.
  ///
  /// Done with [AbsorbPointer] rather than an outer gesture barrier: the whole subtree
  /// fails hit testing, so "was this click eaten" is one boolean and does not depend
  /// on some child not registering a gesture. It wraps **content only, never the
  /// header** - the header buttons are this lane's own controls and the first click on
  /// them should work. "I pressed collapse and nothing happened" is much harder to
  /// explain than "I pressed collapse and it also focused the lane".
  final bool absorbInactiveContent;

  /// While true, no pending dwell may fire and no new one starts.
  ///
  /// The contract's suppression list is "Reader pointer capture, an active drag,
  /// composition, a modal, or a floating menu" - none of which this package can see.
  /// Rossi drives that same suppression from the app side; here it is one prop.
  /// Entering suppression drops the pending target immediately, so nothing armed
  /// behind a modal gets delivered when it closes.
  final bool dwellSuppressed;

  /// Optional: the host may drive the strip's scroll position itself.
  final ScrollController? scrollController;

  @override
  State<SwimlaneWorkspace> createState() => _SwimlaneWorkspaceState();
}

class _SwimlaneWorkspaceState extends State<SwimlaneWorkspace>
    with SingleTickerProviderStateMixin {
  ScrollController? _ownedScroll;
  ScrollController get _scroll => widget.scrollController ?? _ownedScroll!;

  late final SwimlaneDwellPump _pump = SwimlaneDwellPump(
    vsync: this,
    onDue: _deliverDwellDue,
    onArmedChanged: _setArmedHoverLane,
  );

  /// A button is being held: pending dwells are voided, as in Rossi's
  /// `_handleLanePointerDown`.
  bool _pointerDown = false;

  /// The armed highlight's lane: the pointer settled, the last stretch of the delay
  /// is still running. Border colour only - no geometry, no host state, because
  /// emitting a state change per hover would make "armed" indistinguishable from "it
  /// already moved".
  String? _armedHoverLaneId;

  // ── Results cached from the last build ────────────────────────────────
  //
  // Pure `LayoutBuilder` outputs that are also needed outside build, by timer and
  // pointer callbacks. Caching a pure function's result is safe: same input, same
  // output. Rossi `_viewportWidth` / `_geometry`.
  double _viewportWidth = 0;

  /// The scroller's own extent: [_viewportWidth] **minus** the strip padding, which
  /// wraps it from outside.
  ///
  /// Lane *ratios* multiply [_viewportWidth] (Rossi's rule, and `resolveLaneHeaderFit`
  /// and the host's `laidOutWidth` both read that one), but the offsets are computed in
  /// content coordinates, so their viewport is the box the `SingleChildScrollView`
  /// actually paints into. Passing the padded width there - which is what Rossi does
  /// (`_targetOffset` gets `_viewportWidth`) - makes "move just enough for this lane to
  /// be whole" come up `2 * stripPadding` short, and a solo lane keeps its right edge
  /// clipped by that much on every window size. The package differs from him here on
  /// purpose; see deviation 8 in `README.md`.
  double _scrollViewportWidth = 0;
  SwimlaneFocusGeometry? _geometry;

  // ── Lane content instances ────────────────────────────────────────────
  //
  // Handing the interaction to another lane should only re-run the **shell** (the
  // border, the header, where the strip sits). The content slot must get **the same
  // widget instance**: Flutter's `Element.updateChild` skips the whole subtree when
  // `child.widget == newWidget`. Not a micro-optimisation - it is the difference
  // between "the reader re-laid out a whole page" and nothing, because a new content
  // instance pushes every stateful child below it through `changedExternalState`.
  //
  // Invalidation is a **signature**, not "I remember which fields were read"; prefer
  // one rebuild too many over one missed. The transient focus state is left out on
  // purpose - that is the point.
  Object? _contentSignature;
  final Map<String, Widget> _laneContent = <String, Widget>{};

  bool get _hasHoverPointer =>
      (widget.pointerMode ??
          SwimlanePointerMode.forTargetPlatform(defaultTargetPlatform)) ==
      SwimlanePointerMode.hover;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController == null) {
      _ownedScroll = ScrollController();
    }
    _pump.setSuppressed(widget.dwellSuppressed);
  }

  @override
  void didUpdateWidget(SwimlaneWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The prop is the truth, on every update: a request the host did not take (a veto,
    // or a resolver that redirected it) must not keep blocking that lane.
    if (widget.activeLaneId != _requestedActiveLaneId) {
      _requestedActiveLaneId = widget.activeLaneId;
    }
    // The host's version of Rossi's `BlocListener`: focus, solo preference, order or
    // widths moved, so the strip has to re-choose where it sits. Deferred past this
    // frame, because `_geometry` only becomes new when this build is over.
    if (oldWidget.activeLaneId != widget.activeLaneId ||
        oldWidget.layout.soloLaneId != widget.layout.soloLaneId ||
        oldWidget.layout.laneOrder != widget.layout.laneOrder ||
        oldWidget.layout.lanes != widget.layout.lanes) {
      _scheduleFocus();
    }
    if (oldWidget.scrollController != widget.scrollController) {
      _ownedScroll?.dispose();
      _ownedScroll = widget.scrollController == null
          ? ScrollController()
          : null;
    }
    if (oldWidget.dwellSuppressed != widget.dwellSuppressed) {
      _pump.setSuppressed(widget.dwellSuppressed);
    }
  }

  @override
  void dispose() {
    _pump.dispose();
    _ownedScroll?.dispose();
    super.dispose();
  }

  // ── Host state changes ────────────────────────────────────────────────

  void _emitLayout(SwimlaneLayout next) {
    if (identical(next, widget.layout)) return;
    widget.onLayoutChanged?.call(next);
  }

  /// Move the interaction to [laneId].
  ///
  /// Rossi's `activateLane`, guards included: unknown lane = nothing, already active
  /// = nothing. `autoSoloOnFocus` adds solo **on this path only**, and focusing
  /// another lane never clears a solo preference: leaving solo should be the user's
  /// own press, not something "clicking the left lane" did for them.
  ///
  /// The second guard is what a controlled widget has to add: Rossi's `activateLane`
  /// reads `state.activeLaneId`, and his `emit` updates that state **synchronously**,
  /// so a second request in the same frame is a no-op for free. Here the answer only
  /// comes back as a prop after the host has rebuilt, so "pressing solo", which emits
  /// a layout and then asks for the same focus the pointer-down already asked for,
  /// would report the intent twice. `_requestedActiveLaneId` remembers the request for
  /// the length of one frame, and the prop is the truth as soon as it arrives.
  void _activateLane(String laneId) {
    if (widget.activeLaneId == laneId) return;
    if (_requestedActiveLaneId == laneId) return;
    final LaneConfig? lane = widget.layout.lane(laneId);
    if (lane == null) return;

    if (widget.interaction.autoSoloOnFocus &&
        lane.kind == LaneKind.reader &&
        widget.layout.soloLaneId != laneId) {
      _emitLayout(widget.layout.withSolo(laneId));
    }
    final resolved =
        widget.focusResolver?.call(widget.layout, laneId) ?? laneId;
    if (resolved == widget.activeLaneId) return;
    _requestedActiveLaneId = resolved;
    widget.onActiveLaneChanged?.call(resolved);
  }

  /// The focus this package last asked for, until the host's prop says otherwise.
  String? _requestedActiveLaneId;

  /// Hand a dwell that came due to the lane, **after** this frame is built.
  ///
  /// The pump's ticker runs in the scheduler's begin-frame callback, which comes
  /// before the widget tree is rebuilt. A host that raises [dwellSuppressed] in the
  /// same frame - a modal opening, a menu popping - would still read as `false` at
  /// that moment, and the dwell would be delivered behind the very thing that
  /// suppressed it. One frame against a 210ms dwell is free; the rule "while
  /// suppressed nothing fires" then also holds for the frame the flag arrives in.
  void _deliverDwellDue(String laneId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.dwellSuppressed) return;
      _activateLane(laneId);
    });
  }

  void _setArmedHoverLane(String? laneId) {
    if (laneId == _armedHoverLaneId || !mounted) return;
    setState(() => _armedHoverLaneId = laneId);
  }

  void _scheduleFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyOffset();
    });
  }

  /// Scroll the strip to where it should sit.
  ///
  /// The 0.5px threshold matters: `animateTo` starts an animation even to a position
  /// the offset is already a hair away from, and a strip that visibly re-settles on
  /// every focus is exactly the jitter this geometry exists to prevent.
  void _applyOffset() {
    final geometry = _geometry;
    if (geometry == null || !_scroll.hasClients) return;
    if (_scrollViewportWidth <= 0) return;
    final target = _targetOffset(geometry);
    if ((_scroll.offset - target).abs() < 0.5) return;
    _scroll.animateTo(
      target,
      duration: widget.interaction.scrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  double _targetOffset(SwimlaneFocusGeometry geometry) {
    final active = widget.activeLaneId;
    if (active == null || !geometry.containsLane(active)) {
      return geometry.clampOffset(_scroll.offset, _scrollViewportWidth);
    }
    final reader = _readerLaneId;
    // Only while the reader lane holds the *stored* solo preference and the user is
    // working elsewhere: keep a sliver of it visible so one click on that sliver
    // restores solo. The contract's wording is "where possible", so the sliver
    // outranks making the target lane fully visible.
    final keepPeek =
        reader != null &&
        widget.layout.soloLaneId == reader &&
        active != reader;
    return geometry.focusOffset(
      laneId: active,
      viewportWidth: _scrollViewportWidth,
      currentOffset: _scroll.offset,
      keepReaderPeekOf: keepPeek ? reader : null,
      peekWidth: widget.interaction.readerPeekWidth,
    );
  }

  /// The reader lane's id, or `null` when the host has none.
  ///
  /// Rossi hard-codes `LaneId.reader` here too; the package asks the lane model,
  /// because the sliver rule and the spare rule are both about the **kind** of lane,
  /// not about an id string an application happens to use.
  String? get _readerLaneId {
    for (final String laneId in widget.layout.laidOutLanes) {
      if (widget.layout.lane(laneId)?.kind == LaneKind.reader) return laneId;
    }
    return null;
  }

  // ── Pointer ───────────────────────────────────────────────────────────

  /// Whether parking inside [laneId] may take focus at all.
  ///
  /// Two switches, like Rossi: [LaneKind.reader] lanes use `hoverFocusEnabled`,
  /// everything else `panelHoverFocusEnabled` (the contract defines dwell focus on the
  /// reader lane only - "a dwell inside an inactive **Reader** lane activates it" -
  /// because moving the pointer over a panel to check something should not steal
  /// focus; Rossi defaults the panel side open and keeps this switch as the way
  /// back). Both share **one delay**, because the difference is "does it take focus",
  /// not "how long".
  bool _hoverFocusEnabledFor(String laneId) =>
      widget.layout.lane(laneId)?.kind == LaneKind.reader
      ? widget.interaction.hoverFocusEnabled
      : widget.interaction.panelHoverFocusEnabled;

  /// Dwell-to-focus: parking in an inactive lane hands the interaction over.
  ///
  /// Lanes drawn as a rail are **always skipped**: 44px is either collapsed by the
  /// user or a navigator rail, and both are already handles for switching lanes - so
  /// parking on one to read a label would become a focus jump, turning the handle into
  /// a trap.
  void _handleLaneHoverEnter(String laneId, {required bool isRail}) {
    if (isRail) return;
    if (!_hoverFocusEnabledFor(laneId)) return;
    if (laneId == widget.activeLaneId) return;
    if (_pointerDown) return;
    _pump.enter(laneId, delayMs: widget.interaction.hoverFocusDelayMs);
  }

  void _handleLaneHoverExit(String laneId) {
    // Cancel **only** this lane's dwell: A's exit is delivered before B's enter and
    // the order is not guaranteed. An unconditional cancel wipes B's timing, which
    // reads as "I had to sweep over three lanes before one focused".
    _pump.leave(laneId);
  }

  /// The pointer moved inside the strip: "still moving means not dwelling yet".
  void _handlePointerMotion() => _pump.noteMotion();

  void _handleStripExit() => _pump.cancel();

  /// Pointer went down inside a lane.
  ///
  /// Two things at once: **focus this lane**, and void every pending dwell - the user
  /// expressed their intent with a click, so nothing should move again by itself a
  /// moment later.
  void _handleLanePointerDown(String laneId) {
    _pointerDown = true;
    _pump.cancel();
    _activateLane(laneId);
  }

  void _handlePointerUp() => _pointerDown = false;

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The two widths have different jobs and must not be merged:
        // - `viewportWidth`: a reader lane's ratio multiplies **this** one; using the
        //   available width would compute the ratio crooked;
        // - `availableWidth`: what the strip can actually occupy, so it is the basis
        //   for the spare and for "does this need scrolling".
        // Confusing them over-counts the spare by the padding, the `Row` gets pushed
        // out of its container, and the interface grows a yellow-and-black stripes
        // overlay. Rossi documents hitting exactly that on 2026-09-18.
        final viewportWidth = constraints.maxWidth;
        final padding = widget.interaction.stripPadding;
        final availableWidth = math.max(0.0, viewportWidth - padding * 2);
        _viewportWidth = viewportWidth;
        _scrollViewportWidth = availableWidth;

        final metrics = SwimlaneStripMetrics.resolve(
          layout: widget.layout,
          viewportWidth: viewportWidth,
          availableWidth: availableWidth,
          resizerWidth: widget.interaction.resizerWidth,
          // **A reader lane's solo does not look at the active lane**: focusing
          // elsewhere must only move the strip, not re-lay-out and re-decode the
          // reader at a new width. Panel lanes keep the older rule; both halves are
          // in `SwimlaneLayout.effectiveSoloLaneId`.
          soloLaneId: widget.layout.effectiveSoloLaneId(
            activeLaneId: widget.activeLaneId,
          ),
          // Rails go to everyone **except** the active lane: whoever is active is
          // expanded.
          activeLaneId: widget.activeLaneId,
          // On touch the rail **is** the only handle: with one lane solo the others
          // are pushed out of the viewport, edge dwell cannot fire without hover
          // events, and swiping the strip collides with the host's own horizontal
          // gestures. So the rails come from "is there a pointer", and the stored
          // preference - the user's setting - stays untouched.
          showLaneNavigatorInSolo:
              widget.interaction.showLaneNavigatorInSolo || !_hasHoverPointer,
        );
        _geometry = SwimlaneFocusGeometry.fromMetrics(metrics);
        _syncLaneContent(context, metrics);

        return MouseRegion(
          onHover: (_) => _handlePointerMotion(),
          onExit: (_) => _handleStripExit(),
          child: Listener(
            onPointerUp: (_) => _handlePointerUp(),
            onPointerCancel: (_) => _handlePointerUp(),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: _SwimlaneStrip(
                state: this,
                metrics: metrics,
                availableWidth: availableWidth,
              ),
            ),
          ),
        );
      },
    );
  }
}
