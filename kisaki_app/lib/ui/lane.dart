import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// One board column: a numbered step header plus its content.
///
/// Collapsed lanes show a single letter - the product draws no icons and Slint has no
/// vertical text, so the Flutter port keeps the same rule instead of slicing a title.
///
/// The `step` marker is the board's answer to "which stage is in progress": the number is printed
/// whether or not the lane is live, and only the colour and the top rule say which one is.
class Lane extends StatelessWidget {
  const Lane({
    required this.titleKey,
    required this.letter,
    required this.collapsed,
    required this.onToggle,
    required this.child,
    this.width,
    this.actions = const <Widget>[],
    this.step,
    this.active = false,
    super.key,
  });

  final String titleKey;
  final String letter;
  final bool collapsed;
  final VoidCallback onToggle;
  final Widget child;
  final double? width;
  final List<Widget> actions;
  final String? step;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    if (collapsed) {
      return GestureDetector(
        key: Key('lane-$letter'),
        onTap: onToggle,
        child: Container(
          width: BoardTokens.laneCollapsedWidth,
          decoration: ShapeDecoration(
            color: palette.card,
            shape: palette.panelShape(palette.hairline),
          ),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: BoardTokens.gap),
          child: Text(
            letter,
            style: TextStyle(
              fontSize: BoardTokens.fsLabel,
              fontWeight: BoardTokens.weightEmphasis,
              color: palette.fgMuted,
            ),
          ),
        ),
      );
    }

    return Container(
      key: Key('lane-$letter'),
      width: width,
      decoration: ShapeDecoration(
        color: palette.card,
        shape: palette.panelShape(palette.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The rule and the title share one 44px strip, so marking the live step costs the board no
          // height at all - the strip reserves the rule inside itself.
          SizedBox(
            height: BoardTokens.laneHeaderHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: BoardTokens.stepRuleThickness,
                  child: ColoredBox(
                    key: Key('lane-rule-$letter'),
                    color: active ? palette.primary : palette.card,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BoardTokens.pad,
                    ),
                    child: Row(
                      children: <Widget>[
                        if (step != null)
                          Text(
                            step!,
                            key: Key('lane-step-$letter'),
                            style: palette.stepLabel(
                              color: active ? palette.primary : palette.fgMuted,
                            ),
                          ),
                        if (step != null)
                          const SizedBox(width: BoardTokens.gapSmall),
                        Expanded(child: KeyHeading(titleKey)),
                        ...actions,
                        IconButton(
                          icon: const Icon(Icons.remove_rounded, size: 16),
                          // The strip's height comes from the touch row, so its own control stays
                          // dense and the actions keep their place in a narrow lane.
                          style: IconButton.styleFrom(
                            fixedSize: const Size.square(
                              BoardTokens.laneHeaderHeight -
                                  BoardTokens.stepRuleThickness -
                                  BoardTokens.gap,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          tooltip: Labels.of(titleKey),
                          onPressed: onToggle,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
        onHorizontalDragUpdate: (DragUpdateDetails details) =>
            apply((read() + details.delta.dx).clamp(minWidth, maxWidth)),
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
