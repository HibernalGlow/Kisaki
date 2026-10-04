import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'lane_config.dart';

/// Everything the package hands a host builder about one lane at one moment.
///
/// The package knows geometry and lane bookkeeping; the host knows what a lane
/// *means*. This type is the whole seam between them: it carries the numbers only
/// the strip layer can know, so the host never has to guess a width or a state.
@immutable
class SwimlaneLaneInfo {
  const SwimlaneLaneInfo({
    required this.laneId,
    required this.config,
    required this.index,
    required this.laidOutWidth,
    required this.viewportWidth,
    required this.isActive,
    required this.isSolo,
    required this.isRail,
    required this.focusArmed,
  });

  final String laneId;
  final LaneConfig config;

  /// Position in the strip order, after reordering.
  final int index;

  /// The width this lane **actually occupies right now** - not
  /// `config.resolveWidth`: a rail is 44, a solo lane is the whole available
  /// width, and the elastic lane ate the spare. Rossi passes the same distinction
  /// as `SwimlaneColumn.resolvedWidth`.
  final double laidOutWidth;

  /// Viewport width the strip is laid out in. A ratio lane and any host
  /// "normal width" field need it; only the `LayoutBuilder` one level up knows it
  /// (Rossi `SwimlaneColumn.viewportWidth`).
  final double viewportWidth;

  /// The lane the workspace handed the interaction to.
  final bool isActive;

  /// The lane currently taking the viewport.
  final bool isSolo;

  /// Drawn as the compact rail: either collapsed by the user or squeezed into a
  /// rail by the solo navigator.
  ///
  /// It is wider than `config.collapsed` on purpose. Content must not be laid out
  /// for a rail's 44px when the flag says "not collapsed" - that is stripes, not
  /// a navigator.
  final bool isRail;

  /// The pointer settled here but the interaction has not been handed over yet.
  ///
  /// Border colour only, never geometry: if the armed state changed width, the
  /// header budget would recompute every hover and the header would appear to
  /// breathe.
  final bool focusArmed;

  /// Whether this lane is drawn as a rail **right now**, whether or not the user
  /// collapsed it.
  ///
  /// A host label must describe what is painted: a rail that the solo navigator
  /// squeezed is not collapsed, and its collapse button does something else
  /// entirely (it focuses). Rossi `SwimlaneColumn._showsAsRail`.
  bool get showsAsRail => (config.collapsed || isRail) && !isSolo;

  @override
  String toString() =>
      'SwimlaneLaneInfo($laneId, width: $laidOutWidth, rail: $isRail, '
      'active: $isActive, solo: $isSolo, armed: $focusArmed)';
}

/// A lane's per-lane chrome builder: the host returns widgets, the package draws
/// them in fixed slots.
typedef SwimlaneWidgetBuilder = Widget Function(
  BuildContext context,
  SwimlaneLaneInfo lane,
);

/// Extra buttons at the right end of a lane header.
///
/// Keep them **narrow**: the header's give-way budget counts one
/// `IconButton(visualDensity: compact)` per entry (40px, see `LaneChrome`). A wide
/// widget in here makes that budget lie, which is how a lane ends up overflowing
/// its own header (Rossi `SwimlaneColumn.headerActions`).
typedef SwimlaneHeaderActionsBuilder = List<Widget> Function(
  BuildContext context,
  SwimlaneLaneInfo lane,
);

/// Lane label. `null` falls back to `LaneConfig.title`.
///
/// Rossi needs this because his reader lane shows the book title instead of
/// "Reader" while a book is open (`laneTitleOverride`). The host decides; the
/// package just asks.
typedef SwimlaneTitleBuilder = String? Function(SwimlaneLaneInfo lane);

/// Lane icon. `null` falls back to [defaultLaneIcon].
typedef SwimlaneIconBuilder = IconData? Function(SwimlaneLaneInfo lane);

/// The icon Rossi's fallback branch draws for an unknown lane.
const IconData defaultLaneIcon = Icons.view_column_rounded;

/// Everything a host needs to build one lane's "more" menu.
///
/// Rossi's `LaneMenu` is a value object rather than a widget because the same menu
/// has **two entrances**: the button in the header, and right-clicking anywhere on
/// the header. The second one exists precisely for the case where the first was
/// squeezed out of a narrow header, so both must be one item set and one
/// dispatcher - that is why this is handed to the host as data.
@immutable
class SwimlaneMenuRequest {
  const SwimlaneMenuRequest({
    required this.lane,
    required this.onToggleCollapse,
    required this.onToggleSolo,
    required this.onResetWidth,
  });

  final SwimlaneLaneInfo lane;

  /// Collapse or focus - already routed. On a rail the package swaps it for
  /// "hand the interaction to this lane" (see [SwimlaneLaneInfo.showsAsRail]).
  /// Toggling collapse on a rail the navigator produced would turn "show the lane
  /// navigator" into "collapse this lane forever", the opposite of the tap.
  final VoidCallback onToggleCollapse;

  /// Toggle solo for this lane.
  final VoidCallback onToggleSolo;

  /// Restore this lane's recommended width. `null` when the host has nothing to
  /// reset.
  final VoidCallback? onResetWidth;

  String get laneId => lane.laneId;
  double get viewportWidth => lane.viewportWidth;

  /// What the collapse entry should say: the painted shape, not the flag.
  bool get showsAsRail => lane.showsAsRail;
  bool get isSolo => lane.isSolo;
}

/// Injection point for the per-lane "more" menu.
///
/// The package deliberately owns **none** of its content: what a lane can do is
/// application knowledge. Two entry points, because Rossi has two:
/// [buildButton] for the header slot, [showAtPointer] for right-clicking the
/// header when the button itself gave way to a narrow lane.
abstract class SwimlaneMenuHost {
  const SwimlaneMenuHost();

  /// The header button. Return `null` to draw nothing (a rail has no room for it).
  Widget? buildButton(BuildContext context, SwimlaneMenuRequest request);

  /// Open the same menu at [globalPosition] (the right-click path).
  void showAtPointer(
    BuildContext context,
    SwimlaneMenuRequest request,
    Offset globalPosition,
  );
}

/// Injection point for a strip the host wants mounted **inside** a lane header
/// (Rossi's panel tab strip). The package owns none of its content, but the
/// header's give-way budget needs two things from it:
///
/// - [widthFor]: how wide the strip really is. Rossi must know it as a **hard
///   number**, because "the icons have to stay whole" outranks every button in the
///   row; a strip measured from the font would silently change the budget (Rossi
///   recorded exactly that: a font swap lost 5px and a 440px lane overflowed).
/// - [build]: the strip, drawn with the width the budget can spare.
abstract class SwimlaneHeaderStripHost {
  const SwimlaneHeaderStripHost();

  /// Width this strip needs for [lane]. `0` means "nothing mounted".
  double widthFor(SwimlaneLaneInfo lane);

  /// Draw it. The workspace caps it with a [ConstrainedBox] at the width the
  /// header budget can spare, so a strip that sizes itself to its content takes
  /// only what it needs - and when the cap is **below** [widthFor] the row's
  /// non-flexible items sum to exactly the available width, and the flexible part
  /// gets 0 rather than a negative number.
  Widget build(BuildContext context, SwimlaneLaneInfo lane);
}

/// Where the pointer came from, which decides what can trigger at all.
///
/// Copied from Rossi's `workspace_pointer_mode.dart`, including why the test is
/// [TargetPlatform] and not `Platform`: a Windows laptop with a touchscreen still
/// **has** a pointer and should take the hover branch, while on a phone
/// `MouseRegion.onEnter/onHover` and wheel events **never** fire, so anything with
/// only those entrances simply does not exist there. Overridable in tests with
/// `debugDefaultTargetPlatformOverride`.
enum SwimlanePointerMode {
  /// A pointer exists: hover dwell and right-click menus both work.
  hover,

  /// Touch only: none of the above can fire, so every capability needs an
  /// equivalent entrance or it is missing.
  touchOnly;

  static SwimlanePointerMode forTargetPlatform(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => SwimlanePointerMode.hover,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => SwimlanePointerMode.touchOnly,
    };
  }

  /// Hover-capable platform, using the same rule Rossi's `hasHoverPointer` uses.
  static bool get hasHoverPointer =>
      forTargetPlatform(defaultTargetPlatform) == SwimlanePointerMode.hover;
}
