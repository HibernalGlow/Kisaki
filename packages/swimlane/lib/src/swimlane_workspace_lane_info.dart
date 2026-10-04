part of 'swimlane_workspace.dart';

/// What the host is handed about a lane, and the cache of the widgets it builds from
/// it.
///
/// Split out of the state file by responsibility: the widget keeps the props, the
/// lifecycle and the tree, and this is the seam to the host. It is an `extension`
/// rather than a mixin because a mixin would put these members on the public type;
/// being in the same library, `part` files reach the state's private fields anyway.
extension _WorkspaceLaneInfo on _SwimlaneWorkspaceState {
  /// Rebuild the host content instances only when something **other than** who is
  /// active changed. Rossi `_syncLaneContent`.
  void _syncLaneContent(BuildContext context, SwimlaneStripMetrics metrics) {
    final signature = _signatureOf(metrics);
    if (_contentSignature == signature) return;
    _contentSignature = signature;
    _laneContent.clear();
    for (final SwimlaneStripSlot slot in metrics.slots) {
      final laneId = slot.laneId;
      if (laneId == null) continue;
      _laneContent[laneId] = widget.laneBuilder(
        context,
        _laneInfo(
          laneId: laneId,
          slotWidth: slot.width,
          isActive: widget.activeLaneId == laneId,
          isRail: slot.collapsed,
        ),
      );
    }
  }

  /// Everything the host's builder may see, **minus** the transient focus state.
  ///
  /// Slot widths and rail flags are folded in as a string because a record holding
  /// `List`s compares by identity and would invalidate the cache every frame. A rail
  /// flip changes a width, so that string catches it: the point of the cache is that
  /// "the interaction moved" costs nothing below the shell, not that content sits at a
  /// width it was never laid out for.
  Object _signatureOf(SwimlaneStripMetrics metrics) {
    final buffer = StringBuffer();
    for (final SwimlaneStripSlot slot in metrics.slots) {
      buffer.write('${slot.laneId ?? "-"}:${slot.width}:${slot.collapsed};');
    }
    return (
      widget.layout,
      widget.interaction,
      widget.laneBuilder,
      widget.headerActionsBuilder,
      widget.menuHost,
      widget.headerStrip,
      widget.iconBuilder,
      widget.titleBuilder,
      buffer.toString(),
    );
  }

  SwimlaneLaneInfo _laneInfo({
    required String laneId,
    required double slotWidth,
    required bool isActive,
    required bool isRail,
  }) {
    final soloLaneId = widget.layout.effectiveSoloLaneId(
      activeLaneId: widget.activeLaneId,
    );
    return SwimlaneLaneInfo(
      laneId: laneId,
      // Rossi's fallback for a lane id whose config went missing: 380px, named by id.
      config:
          widget.layout.lane(laneId) ?? LaneConfig(width: 380, title: laneId),
      index: widget.layout.laidOutLanes.indexOf(laneId),
      laidOutWidth: slotWidth,
      viewportWidth: _viewportWidth,
      isActive: isActive,
      isSolo: soloLaneId == laneId,
      isRail: isRail,
      focusArmed: _armedHoverLaneId == laneId,
    );
  }
}
