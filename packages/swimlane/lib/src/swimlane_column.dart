import 'package:flutter/material.dart';

import 'lane_header_fit.dart';
import 'lane_host.dart';
import 'swimlane_layout.dart';

/// One lane: a header (reorder handle, title, width badge, host actions, solo,
/// collapse, more) plus the content the host supplied, or the 44dp rail.
///
/// **The header belongs to the lane.** The contract Rossi inherits from neoview
/// says a lane header owns collapse, reorder, focus and width, which is why
/// reordering is a handle in the header instead of a separate drag area.
///
/// The header is also a right-click target. When it is narrow, buttons are
/// deliberately dropped (see [resolveLaneHeaderFit]), so "put the width back /
/// leave solo" needs another entrance: the host's menu, opened by right-clicking
/// the header or the rail.
class SwimlaneColumn extends StatelessWidget {
  const SwimlaneColumn({
    super.key,
    required this.lane,
    required this.onToggleCollapse,
    required this.onToggleSolo,
    this.onResetWidth,
    this.menuHost,
    this.headerStrip,
    this.headerActions = const <Widget>[],
    this.iconBuilder,
    this.titleBuilder,
    this.child,
  });

  final SwimlaneLaneInfo lane;

  /// Collapse, or focus when this lane is only a rail. The workspace already made
  /// that choice; see [SwimlaneMenuRequest.onToggleCollapse].
  final VoidCallback onToggleCollapse;
  final VoidCallback onToggleSolo;
  final VoidCallback? onResetWidth;

  final SwimlaneMenuHost? menuHost;

  /// The host's own strip mounted inside the header (Rossi: the panel tab strip).
  /// `null` means nothing is mounted, and then the header budget has no strip line
  /// at all - which is how a lane without tabs gets its buttons back.
  final SwimlaneHeaderStripHost? headerStrip;

  /// Extra header buttons, already built by the host. They must stay icon-button
  /// sized: see [SwimlaneHeaderActionsBuilder].
  final List<Widget> headerActions;

  final SwimlaneIconBuilder? iconBuilder;
  final SwimlaneTitleBuilder? titleBuilder;

  /// Lane content. The workspace wraps it in the "first click is eaten" absorber;
  /// this widget only draws.
  final Widget? child;

  IconData get _icon => iconBuilder?.call(lane) ?? defaultLaneIcon;

  String get _title => titleBuilder?.call(lane) ?? lane.config.title;

  SwimlaneMenuRequest _menuRequest() => SwimlaneMenuRequest(
    lane: lane,
    onToggleCollapse: onToggleCollapse,
    onToggleSolo: onToggleSolo,
    onResetWidth: onResetWidth,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The rail tier has no "more" button - 44px cannot hold one - so right-clicking
    // the rail is the only way to change the width or leave solo.
    if (lane.showsAsRail) {
      return _withContextMenu(context, _buildRail(context, theme));
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          // Three tiers: the interaction is here > it is about to come here > idle.
          // The armed tier uses the **same** primary colour at a lower alpha: a
          // different hue would read as a different state (a drag target already uses
          // solid primary), while all it means is "same thing, not quite yet".
          // Changing geometry here would re-run the header budget on every hover and
          // the header would look like it is breathing.
          color: lane.isActive
              ? theme.colorScheme.primary.withValues(alpha: 0.55)
              : lane.focusArmed
              ? theme.colorScheme.primary.withValues(alpha: 0.22)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: lane.isActive ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          _withContextMenu(
            context,
            _buildHeader(context, theme, lane.laidOutWidth),
          ),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, ThemeData theme, double laneWidth) {
    final strip = headerStrip;
    final stripNeed = strip == null ? 0.0 : strip.widthFor(lane);
    final fit = resolveLaneHeaderFit(
      laneWidth: laneWidth,
      isActive: lane.isActive,
      headerActionCount: headerActions.length,
      stripNeed: stripNeed,
    );

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: lane.isSolo
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          _buildReorderHandle(context, theme),
          const SizedBox(width: 4),

          // Title; double tap resets the width.
          //
          // The text is `Flexible`, so a squeezed header ellipsises it first and
          // needs no rule of its own. The width badge is **hard**: given zero width
          // it still demands its 78px and the row overflows, so [fit] decides
          // whether it is drawn.
          Expanded(
            child: Tooltip(
              message:
                  'Double click resets this lane width. '
                  'Right click opens its menu.',
              child: InkWell(
                onDoubleTap: onResetWidth,
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        _title,
                        key: ValueKey<String>('lane-title-${lane.laneId}'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (fit.showBadge) ...[
                      const SizedBox(width: 6),
                      // Fixed width on purpose. This badge used to size itself to
                      // the font, so a font change silently moved the number the
                      // header budget depends on and a 440px lane overflowed.
                      SizedBox(
                        width: LaneChrome.badgeInner,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${lane.laidOutWidth.round()}px',
                            key: ValueKey<String>('lane-badge-${lane.laneId}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          ...headerActions,

          // A host strip mounted in the header: Rossi's `titleMounted` tier, the one
          // that costs no extra row. It is laid out by this `Row`, so it gets **no**
          // positioning widget (those fill the constraints they are given and would
          // break the row) - only the width this budget can spare.
          if (strip != null && stripNeed > 0 && fit.stripMaxWidth > 0) ...[
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: fit.stripMaxWidth),
              child: strip.build(context, lane),
            ),
            const SizedBox(width: 4),
          ],

          // The order the buttons are dropped in is the reverse of the one they are
          // asked in; see [resolveLaneHeaderFit].
          if (fit.showSolo)
            IconButton(
              key: ValueKey<String>('lane-solo-${lane.laneId}'),
              icon: Icon(
                lane.isSolo
                    ? Icons.center_focus_strong_rounded
                    : Icons.center_focus_weak_rounded,
                size: 20,
                color: lane.isSolo
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              tooltip: lane.isSolo ? 'Exit solo' : 'Solo this lane',
              onPressed: onToggleSolo,
              visualDensity: VisualDensity.compact,
            ),
          if (fit.showCollapse)
            IconButton(
              key: ValueKey<String>('lane-collapse-${lane.laneId}'),
              icon: const Icon(Icons.vertical_align_center_rounded, size: 18),
              tooltip: 'Collapse to a compact rail',
              onPressed: onToggleCollapse,
              visualDensity: VisualDensity.compact,
            ),
          if (fit.showMore)
            menuHost?.buildButton(context, _menuRequest()) ??
                const SizedBox.shrink(),
        ],
      ),
    );
  }

  /// Right-click anywhere in the header: the host's menu, the same item set the
  /// button uses. Left-click entrances live closer to the pointer and win.
  Widget _withContextMenu(BuildContext context, Widget child) {
    final host = menuHost;
    if (host == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (details) =>
          host.showAtPointer(context, _menuRequest(), details.globalPosition),
      child: child,
    );
  }

  /// The lane icon **is** the reorder handle: press and hold to drag it onto another
  /// lane. A long press means reordering costs no extra width in an already tight
  /// header and cannot fire on an ordinary click.
  Widget _buildReorderHandle(BuildContext context, ThemeData theme) {
    final icon = Icon(_icon, size: 18, color: theme.colorScheme.primary);

    // A solo lane is not a drag source: reordering what the user cannot see is a way
    // to lose a layout, and Rossi draws a plain tooltip there instead.
    if (lane.isSolo) return Tooltip(message: _title, child: icon);

    return Tooltip(
      message: '$_title - press and hold to reorder lanes',
      waitDuration: const Duration(milliseconds: 500),
      child: LongPressDraggable<String>(
        key: ValueKey<String>('lane-drag-${lane.laneId}'),
        data: lane.laneId,
        delay: const Duration(milliseconds: 200),
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  _icon,
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  _title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        child: MouseRegion(cursor: SystemMouseCursors.grab, child: icon),
      ),
    );
  }

  // ── Rail ──────────────────────────────────────────────────────────────

  /// The 44dp compact rail: icon, rotated title, expand affordance.
  Widget _buildRail(BuildContext context, ThemeData theme) {
    return Container(
      key: ValueKey<String>('lane-rail-${lane.laneId}'),
      width: SwimlaneLayout.collapsedLaneWidth,
      height: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          IconButton(
            icon: Icon(_icon, size: 18, color: theme.colorScheme.primary),
            tooltip: '$_title - tap to hand the interaction to this lane',
            onPressed: onToggleCollapse,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 12),
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              _title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            key: ValueKey<String>('lane-expand-${lane.laneId}'),
            icon: const Icon(Icons.unfold_more_rounded, size: 16),
            tooltip: 'Expand lane',
            onPressed: onToggleCollapse,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
