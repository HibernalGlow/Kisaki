import 'package:flutter/widgets.dart';

import 'board_theme.dart';

/// A 12-column Swiss grid.
///
/// Content declares how many columns it spans; the column width and the 16px gutter come from the
/// token scale, so panels align without anyone negotiating pixel widths. Use [SwissCell] children
/// and keep the spans summing to 12 per row - the grid wraps whenever a row would overflow.
class SwissGrid extends StatelessWidget {
  const SwissGrid({
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    super.key,
  });

  final List<SwissCell> children;
  final CrossAxisAlignment crossAxisAlignment;

  static const int columns = BoardTokens.gridColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double slot =
            (constraints.maxWidth - BoardTokens.gutter * (columns - 1)) /
            columns;
        final List<Widget> rows = <Widget>[];
        final List<Widget> current = <Widget>[];
        int used = 0;

        void flush() {
          if (current.isEmpty) {
            return;
          }
          rows.add(
            Row(
              crossAxisAlignment: crossAxisAlignment,
              children: List<Widget>.of(current),
            ),
          );
          current.clear();
          used = 0;
        }

        for (final SwissCell cell in children) {
          final int span = cell.span.clamp(1, columns);
          if (used > 0 && used + span > columns) {
            flush();
          }
          if (used > 0) {
            current.add(const SizedBox(width: BoardTokens.gutter));
          }
          current.add(
            SizedBox(
              width: slot * span + BoardTokens.gutter * (span - 1),
              child: cell,
            ),
          );
          used += span;
        }
        flush();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final Widget row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: BoardTokens.gap),
                child: row,
              ),
          ],
        );
      },
    );
  }
}

/// One cell of a [SwissGrid]; [span] is a column count, not a pixel width.
class SwissCell extends StatelessWidget {
  const SwissCell({required this.child, this.span = 3, this.label, super.key});

  final Widget child;
  final int span;

  /// An optional micro-heading above the content, so the grid itself carries the label rhythm.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    if (label == null) {
      return child;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label!.toUpperCase(), style: palette.text.labelSmall),
        const SizedBox(height: BoardTokens.gapSmall),
        child,
      ],
    );
  }
}
