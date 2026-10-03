import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// One board column: header strip with a micro-heading plus a collapse control.
///
/// Collapsed lanes show a single letter - the product draws no icons and Slint has no
/// vertical text, so the Flutter port keeps the same rule instead of slicing a title.
class Lane extends StatelessWidget {
  const Lane({
    required this.titleKey,
    required this.letter,
    required this.collapsed,
    required this.onToggle,
    required this.child,
    this.width,
    this.actions = const <Widget>[],
    super.key,
  });

  final String titleKey;
  final String letter;
  final bool collapsed;
  final VoidCallback onToggle;
  final Widget child;
  final double? width;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    if (collapsed) {
      return GestureDetector(
        key: Key('lane-$letter'),
        onTap: onToggle,
        child: Container(
          width: BoardTokens.laneCollapsedWidth,
          decoration: BoxDecoration(
            color: palette.card,
            border: Border.all(color: palette.hairline),
            borderRadius: BorderRadius.circular(BoardTokens.radius),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: BoardTokens.gap),
          child: Text(
            letter,
            style: TextStyle(
              fontSize: BoardTokens.fsTitle,
              fontWeight: FontWeight.w700,
              color: palette.fgMuted,
            ),
          ),
        ),
      );
    }

    return Container(
      key: Key('lane-$letter'),
      width: width,
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.hairline),
        borderRadius: BorderRadius.circular(BoardTokens.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: BoardTokens.laneHeaderHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: BoardTokens.pad),
              child: Row(
                children: <Widget>[
                  Expanded(child: KeyHeading(titleKey)),
                  ...actions,
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    tooltip: Labels.of(titleKey),
                    onPressed: onToggle,
                  ),
                ],
              ),
            ),
          ),
          const Hairline(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Horizontal drag handle between two lanes; double tap restores the default width.
class LaneDragHandle extends StatelessWidget {
  const LaneDragHandle({
    required this.read,
    required this.apply,
    required this.resetTo,
    required this.minWidth,
    required this.maxWidth,
    super.key,
  });

  final double Function() read;
  final ValueChanged<double> apply;
  final double resetTo;
  final double minWidth;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const Key('lane-drag-handle'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (DragUpdateDetails details) => apply((read() + details.delta.dx).clamp(minWidth, maxWidth)),
        onDoubleTap: () => apply(resetTo),
        child: Container(
          width: BoardTokens.gap,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Container(width: 1, height: 24, color: palette.border),
        ),
      ),
    );
  }
}
