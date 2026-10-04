part of 'swimlane_workspace.dart';

/// The scrollable band of lanes plus the handles between them.
///
/// Split out of the workspace's state file by responsibility: this is the
/// rendering, the state above is the interaction. It reaches back into that state
/// for the lane model and the callbacks, which is why it holds it rather than
/// mirroring fifteen parameters.
class _SwimlaneStrip extends StatelessWidget {
  const _SwimlaneStrip({
    required this.state,
    required this.metrics,
    required this.availableWidth,
  });

  final _SwimlaneWorkspaceState state;
  final SwimlaneStripMetrics metrics;

  /// Kept only so a future overlay layer can place itself against the padded box;
  /// every width here comes from [metrics].
  final double availableWidth;

  SwimlaneLayout get _layout => state.widget.layout;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final SwimlaneStripSlot slot in metrics.slots) {
      final laneId = slot.laneId;
      if (laneId == null) {
        children.add(
          SwimlaneResizer(
            key: ValueKey<String>(
              'resizer-${slot.beforeLaneId}-${slot.afterLaneId}',
            ),
            onDragDelta: (delta) => state._emitLayout(
              _layout.draggedPair(
                leftLaneId: slot.beforeLaneId!,
                rightLaneId: slot.afterLaneId!,
                delta: delta,
                viewportWidth: state._viewportWidth,
              ),
            ),
            onDoubleTapReset: () => state._emitLayout(
              _layout.withResetPair(slot.beforeLaneId!, slot.afterLaneId!),
            ),
          ),
        );
        continue;
      }
      children.add(
        SizedBox(
          // The slot width, not `config.resolveWidth`: this lane may be a rail, the
          // solo lane, or the one that just ate the spare.
          width: slot.width,
          child: _lane(
            context,
            laneId: laneId,
            slotWidth: slot.width,
            isRail: slot.collapsed,
          ),
        ),
      );
    }

    // The strip's horizontal scroll is **controlled**: the offset comes from the
    // geometry in the state file, and the user's own drag is only for "I want to look
    // elsewhere".
    //
    // Refusing the user's drag goes through `shouldAcceptUserOffset`, not through
    // `NeverScrollableScrollPhysics`: that would also kill the programmatic
    // `animateTo`, so "focus the left lane" would stop moving the strip and look like
    // a dead button. Clamping, inertia and animation are inherited unchanged. Rossi
    // `_ProgrammaticScrollPhysics`.
    return SingleChildScrollView(
      controller: state._scroll,
      scrollDirection: Axis.horizontal,
      physics: state.widget.interaction.manualScrollEnabled
          ? const ClampingScrollPhysics()
          : const _ProgrammaticScrollPhysics(),
      child: SizedBox(
        width: metrics.contentWidth,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _lane(
    BuildContext context, {
    required String laneId,
    required double slotWidth,
    required bool isRail,
  }) {
    final isActive = state.widget.activeLaneId == laneId;
    final lane = state._laneInfo(
      laneId: laneId,
      slotWidth: slotWidth,
      isActive: isActive,
      isRail: isRail,
    );

    // A rail is already the switch handle, so its button must **not** toggle
    // collapse: a rail the navigator produced was never collapsed by the user, and
    // toggling would turn "show the lane navigator" into "collapse this lane
    // forever" - the opposite of what tapping a rail means. Rossi makes the same
    // swap in `SwimlaneWorkspace._buildLane`.
    final onToggleCollapse = isRail && !lane.config.collapsed
        ? () => state._activateLane(laneId)
        : () => state._emitLayout(_layout.toggledCollapsed(laneId));

    final column = SwimlaneColumn(
      lane: lane,
      onToggleCollapse: onToggleCollapse,
      onToggleSolo: () {
        final next = _layout.toggledSolo(laneId);
        state._emitLayout(next);
        // Entering solo also focuses: pressing solo should mean "let me see it".
        // Leaving solo does not move focus the other way - the user wanted "back to
        // several lanes", not "jump somewhere".
        if (next.soloLaneId == laneId) state._activateLane(laneId);
      },
      onResetWidth: () => state._emitLayout(_layout.withResetWidth(laneId)),
      menuHost: state.widget.menuHost,
      headerStrip: state.widget.headerStrip,
      headerActions:
          state.widget.headerActionsBuilder?.call(context, lane) ??
          const <Widget>[],
      iconBuilder: state.widget.iconBuilder,
      titleBuilder: state.widget.titleBuilder,
      child: _absorbingContent(laneId, isActive),
    );

    return MouseRegion(
      key: ValueKey<String>('lane-hover-$laneId'),
      onEnter: (_) => state._handleLaneHoverEnter(laneId, isRail: isRail),
      onExit: (_) => state._handleLaneHoverExit(laneId),
      onHover: (_) => state._handlePointerMotion(),
      child: Listener(
        // Listening on the **whole lane**: the header's own controls (collapse, solo,
        // width) also count as "the user gave this lane the interaction". Only the
        // content gets eaten, see [_absorbingContent].
        onPointerDown: (_) => state._handleLanePointerDown(laneId),
        child: _dropTarget(context, laneId, column),
      ),
    );
  }

  /// First click on a non-active lane's **content** is eaten.
  ///
  /// Wraps the cached instance, so a focus change only flips `absorbing` and never
  /// re-builds the host's subtree.
  Widget _absorbingContent(String laneId, bool isActive) {
    return AbsorbPointer(
      // `activeLaneId == null` means "nobody has been focused yet", and that must eat
      // nothing: otherwise a cold start swallows the first click in every lane.
      absorbing:
          state.widget.absorbInactiveContent &&
          state.widget.activeLaneId != null &&
          !isActive,
      child: state._laneContent[laneId] ?? const SizedBox.shrink(),
    );
  }

  /// Reorder target: hold a lane's header icon and drop it on another lane to swap
  /// their places. The drop does not move focus by itself - the pointer went down
  /// inside the dragged lane, and that already focused it.
  Widget _dropTarget(BuildContext context, String laneId, Widget child) {
    return DragTarget<String>(
      key: ValueKey<String>('lane-drop-$laneId'),
      onWillAcceptWithDetails: (details) => details.data != laneId,
      onAcceptWithDetails: (details) => state._emitLayout(
        _layout.reordered(draggedLaneId: details.data, targetLaneId: laneId),
      ),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// "Let the program scroll, not the user."
///
/// Differs from [ClampingScrollPhysics] in exactly one gate: with
/// `shouldAcceptUserOffset` false the `Scrollable` never attaches a drag recognizer
/// and pointer-signal (wheel) handling returns early, while clamping, inertia and
/// `animateTo` are inherited unchanged.
class _ProgrammaticScrollPhysics extends ClampingScrollPhysics {
  const _ProgrammaticScrollPhysics({super.parent});

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => false;

  @override
  _ProgrammaticScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _ProgrammaticScrollPhysics(parent: buildParent(ancestor));
}
