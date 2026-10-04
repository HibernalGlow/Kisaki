import 'dart:math' as math;

import 'lane_config.dart';

/// The lane model: an ordered set of lanes, each with its own width, collapse
/// flag, and an optional solo lane.
///
/// Every mutation returns a **new** layout; the host owns the state and decides
/// what to do with it. This mirrors Rossi, where the same operations live as
/// `WorkspaceCubit` methods that `emit` a copied `WorkspaceLayoutConfig`
/// (`rossi/lib/workspace/cubit/workspace_cubit.dart`). The clamps and the
/// arithmetic here are copied from those methods, not reinvented.
///
/// Pure Dart on purpose, like the rest of the model layer.
class SwimlaneLayout {
  /// Width of a collapsed lane - the compact rail.
  ///
  /// Rossi `workspace_layout_config.dart`: `collapsedLaneWidth = 44.0`, itself
  /// neoview's `COLLAPSED_WIDTH`. It is used both as the rail width and as the
  /// floor for a solo lane that has been squeezed by rails.
  static const double collapsedLaneWidth = 44.0;

  /// Lane ids in strip order. Left to right.
  ///
  /// A plain list of ids, so a host can add a lane without changing the model
  /// (Rossi calls this the "generic order").
  final List<String> laneOrder;

  /// Per-lane configuration, keyed by id.
  final Map<String, LaneConfig> lanes;

  /// The lane the host wants to be alone in the viewport, or `null`.
  ///
  /// Rossi keeps solo in the persisted layout because it is a property of the
  /// lane, not transient workspace state.
  final String? soloLaneId;

  const SwimlaneLayout({
    required this.laneOrder,
    required this.lanes,
    this.soloLaneId,
  });

  LaneConfig? lane(String laneId) => lanes[laneId];

  /// Lanes that have a config and are therefore laid out.
  ///
  /// An id in [laneOrder] with no entry in [lanes] is skipped by the strip
  /// builder (Rossi: `if (lane == null) continue`), which is what lets a host
  /// remove a lane without rewriting the order.
  List<String> get laidOutLanes => <String>[
    for (final String id in laneOrder)
      if (lanes.containsKey(id)) id,
  ];

  double laneWidth(String laneId, double viewportWidth) =>
      lanes[laneId]?.resolveWidth(viewportWidth) ?? 0.0;

  bool isCollapsed(String laneId) => lanes[laneId]?.collapsed ?? false;

  // ── Mutations ──────────────────────────────────────────────────────────

  SwimlaneLayout copyWith({
    List<String>? laneOrder,
    Map<String, LaneConfig>? lanes,
    String? Function()? soloLaneId,
  }) {
    return SwimlaneLayout(
      laneOrder: laneOrder ?? this.laneOrder,
      lanes: lanes ?? this.lanes,
      soloLaneId: soloLaneId != null ? soloLaneId() : this.soloLaneId,
    );
  }

  LaneConfig? _requireLane(String laneId) => lanes[laneId];

  Map<String, LaneConfig> _replaceLane(String laneId, LaneConfig next) {
    final updated = Map<String, LaneConfig>.from(lanes);
    updated[laneId] = next;
    return updated;
  }

  /// Swap lane order so [draggedLaneId] lands on [targetLaneId]'s slot.
  ///
  /// Copied from Rossi's `reorderLane`: remove the dragged id, then insert it at
  /// the target's index. Reordering touches **only** the order - no width, no
  /// collapse, no solo (Rossi: "reorder only changes who is on the left").
  /// Dropping a lane on itself is a no-op that returns the same instance, so a
  /// host can tell nothing changed.
  SwimlaneLayout reordered({
    required String draggedLaneId,
    required String targetLaneId,
  }) {
    if (draggedLaneId == targetLaneId) return this;
    final order = List<String>.from(laneOrder);
    final from = order.indexOf(draggedLaneId);
    final to = order.indexOf(targetLaneId);
    if (from < 0 || to < 0) return this;
    order.removeAt(from);
    order.insert(to, draggedLaneId);
    return copyWith(laneOrder: order);
  }

  /// Move [laneId] to the absolute slot [targetIndex].
  ///
  /// The index counts the order **without** the dragged lane, which is what a
  /// `ReorderableListView`/`ReorderableDragStartListener` hand-back means by
  /// `newIndex`. Clamped into range instead of throwing, so a drag that ends
  /// past the end lands on the last slot.
  SwimlaneLayout movedLaneTo(String laneId, int targetIndex) {
    final order = List<String>.from(laneOrder);
    final from = order.indexOf(laneId);
    if (from < 0) return this;
    order.removeAt(from);
    final to = targetIndex.clamp(0, order.length);
    order.insert(to, laneId);
    return copyWith(laneOrder: order);
  }

  /// Collapse / expand a lane.
  SwimlaneLayout setCollapsed(String laneId, {required bool collapsed}) {
    final lane = _requireLane(laneId);
    if (lane == null || lane.collapsed == collapsed) return this;
    return copyWith(
      lanes: _replaceLane(laneId, lane.copyWith(collapsed: collapsed)),
    );
  }

  SwimlaneLayout toggledCollapsed(String laneId) {
    final lane = _requireLane(laneId);
    if (lane == null) return this;
    return setCollapsed(laneId, collapsed: !lane.collapsed);
  }

  /// Set the solo lane (`null` clears it).
  SwimlaneLayout withSolo(String? laneId) {
    if (laneId != null && !lanes.containsKey(laneId)) return this;
    if (laneId == soloLaneId) return this;
    return copyWith(soloLaneId: () => laneId);
  }

  /// Toggle solo, the header button's action.
  ///
  /// Entering or leaving solo **never rewrites the lane's stored width**, so a
  /// reader lane returns to the ratio it had before (Rossi `toggleSoloLane`).
  SwimlaneLayout toggledSolo(String laneId) =>
      withSolo(soloLaneId == laneId ? null : laneId);

  /// Drag the handle between two lanes by [delta] pixels.
  ///
  /// The clamp is Rossi's `dragLanePair`, copied exactly: the pair moves
  /// together, so the grow side is capped by **both** its own `maxWidth` and the
  /// neighbour's remaining room above its `minWidth`. Net effect: the strip width
  /// stays constant and neither lane can be dragged past its band.
  /// [applied] == 0 (already pinned) returns the same instance.
  SwimlaneLayout draggedPair({
    required String leftLaneId,
    required String rightLaneId,
    required double delta,
    required double viewportWidth,
  }) {
    final left = _requireLane(leftLaneId);
    final right = _requireLane(rightLaneId);
    if (left == null || right == null) return this;

    final leftWidth = left.resolveWidth(viewportWidth);
    final rightWidth = right.resolveWidth(viewportWidth);

    final maxGrow = math.min(
      left.maxWidth - leftWidth,
      rightWidth - right.minWidth,
    );
    final maxShrink = -math.min(
      leftWidth - left.minWidth,
      right.maxWidth - rightWidth,
    );

    final applied = delta.clamp(maxShrink, maxGrow).toDouble();
    if (applied == 0) return this;

    return copyWith(
      lanes:
          _replaceLane(
              leftLaneId,
              left.withStoredWidth(
                px: leftWidth + applied,
                viewportWidth: viewportWidth,
              ),
            )
            ..[rightLaneId] = right.withStoredWidth(
              px: rightWidth - applied,
              viewportWidth: viewportWidth,
            ),
    );
  }

  /// Write an absolute width for one lane only (the host's width field).
  ///
  /// Clamped to the lane's **own** band, not the neighbour's - unlike
  /// [draggedPair]. The result may push the strip into horizontal scrolling, and
  /// that is the point: panel lanes are not clamped to the current window width.
  /// Rossi `setLaneWidth`.
  SwimlaneLayout withLaneWidth(String laneId, double px, double viewportWidth) {
    final lane = _requireLane(laneId);
    if (lane == null) return this;
    final width = px.clamp(lane.minWidth, lane.maxWidth).toDouble();
    return copyWith(
      lanes: _replaceLane(
        laneId,
        lane.withStoredWidth(px: width, viewportWidth: viewportWidth),
      ),
    );
  }

  /// Restore one lane's recommended width (double tap on a lane title).
  SwimlaneLayout withResetWidth(String laneId) {
    final lane = _requireLane(laneId);
    if (lane == null) return this;
    final reset = lane.copyWith(
      width: lane.recommendedWidth,
      widthRatio: () => lane.recommendedWidthRatio,
    );
    // Already at the recommendation: hand back the same instance so the caller can
    // tell "nothing to do" without diffing.
    if (reset == lane) return this;
    return copyWith(lanes: _replaceLane(laneId, reset));
  }

  /// Restore both lanes around a handle (double tap on the handle itself).
  ///
  /// A handle straddles two lanes; resetting one side would leave the other
  /// dragged crooked. Rossi `resetLanePair`.
  SwimlaneLayout withResetPair(String firstLaneId, String secondLaneId) {
    var next = this;
    for (final String laneId in <String>[firstLaneId, secondLaneId]) {
      next = next.withResetWidth(laneId);
    }
    return next;
  }

  /// The solo lane that actually takes the viewport width.
  ///
  /// Rossi's rule (`WorkspaceState.effectiveSoloLaneId`) is deliberately
  /// asymmetric, and both halves are kept:
  ///
  /// - a [LaneKind.reader] lane stays solo **no matter which lane is active**.
  ///   Activating a neighbour must not collapse its width, because a width change
  ///   makes the host re-lay-out expensive content. "Show one lane" is supposed
  ///   to be done by moving the strip, not by re-laying out.
  /// - a [LaneKind.panel] lane is only solo while it is also active. Without that
  ///   precondition, "solo a panel lane + work elsewhere" pushes the other lanes
  ///   out of the viewport with no way back.
  String? effectiveSoloLaneId({String? activeLaneId}) {
    final solo = soloLaneId;
    if (solo == null) return null;
    if (lanes[solo]?.kind == LaneKind.reader) return solo;
    return solo == activeLaneId ? solo : null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'laneOrder': laneOrder,
    'lanes': <String, Object?>{
      for (final MapEntry<String, LaneConfig> entry in lanes.entries)
        entry.key: entry.value.toJson(),
    },
    'soloLaneId': soloLaneId,
  };

  /// Restore a layout from JSON against [defaults].
  ///
  /// Two normalizations copied from Rossi's `WorkspaceLayoutConfig.fromJson`:
  /// 1. unknown ids in `laneOrder` are dropped, ids missing from it are appended
  ///    in default order - so a host can add or retire a lane without a
  ///    migration and without a phantom empty slot;
  /// 2. a missing or malformed lane block falls back to that lane's default
  ///    instead of discarding the whole layout;
  /// 3. a solo id pointing at a lane that no longer exists is dropped.
  factory SwimlaneLayout.fromJson(
    Map<String, Object?> json, {
    required SwimlaneLayout defaults,
  }) {
    final rawOrder = json['laneOrder'];
    final persisted = <String>[
      if (rawOrder is List)
        for (final Object? value in rawOrder)
          if (value is String) value,
    ];
    final order = <String>[
      for (final String id in persisted)
        if (defaults.lanes.containsKey(id)) id,
      for (final String id in defaults.laneOrder)
        if (!persisted.contains(id)) id,
    ];

    final rawLanes = json['lanes'];
    final lanes = <String, LaneConfig>{};
    for (final MapEntry<String, LaneConfig> entry in defaults.lanes.entries) {
      final Object? raw = rawLanes is Map ? rawLanes[entry.key] : null;
      lanes[entry.key] = raw is Map
          ? LaneConfig.fromJson(
              raw.cast<String, Object?>(),
              fallback: entry.value,
            )
          : entry.value;
    }

    final rawSolo = json['soloLaneId'];
    final solo = rawSolo is String && lanes.containsKey(rawSolo)
        ? rawSolo
        : null;

    return SwimlaneLayout(laneOrder: order, lanes: lanes, soloLaneId: solo);
  }

  @override
  String toString() =>
      'SwimlaneLayout(order: $laneOrder, solo: $soloLaneId, '
      'lanes: ${lanes.length})';
}
