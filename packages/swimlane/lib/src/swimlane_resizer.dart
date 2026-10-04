import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'strip_metrics.dart';

/// The horizontal drag handle between two lanes.
class SwimlaneResizer extends StatefulWidget {
  /// The handle's **occupied** width.
  ///
  /// The strip assembly must count this into its total: if "the width that was
  /// computed" and "the width actually laid out" differ by one handle, the `Row`
  /// overflows and Flutter paints the yellow-and-black stripes over the interface.
  /// It therefore references [SwimlaneStripMetrics.defaultResizerWidth]: the
  /// allocation is a pure function that cannot load this widget, so only **one
  /// and the same constant** can guarantee that the computed and the painted
  /// thing are the same thing. Rossi `LaneResizer.width`.
  static const double width = SwimlaneStripMetrics.defaultResizerWidth;

  /// Horizontal drag delta in logical pixels, already pointed at the lane pair
  /// this handle sits between (the host clamps it - see
  /// `SwimlaneLayout.draggedPair`).
  final ValueChanged<double> onDragDelta;

  /// Double tap: the host restores both neighbouring lanes. Rossi
  /// `resetLanePair` - a handle straddles two lanes, so resetting one side would
  /// leave the other one still dragged crooked.
  final VoidCallback? onDoubleTapReset;

  const SwimlaneResizer({
    super.key,
    required this.onDragDelta,
    this.onDoubleTapReset,
  });

  @override
  State<SwimlaneResizer> createState() => _SwimlaneResizerState();
}

class _SwimlaneResizerState extends State<SwimlaneResizer> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _isHovered || _isDragging;

    final barColor = active
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.4);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        // Opaque: the visible bar is 1.5px wide inside a 10px slot, and the gap
        // has to take the hit or the handle is nearly impossible to grab.
        behavior: HitTestBehavior.opaque,
        // Measure from the press, not from the first move event: with the default
        // `DragStartBehavior.start` the distance between pointer-down and the frame
        // where the drag wins the arena is silently discarded, so the lane never quite
        // reaches where the cursor is. Rossi leaves the default; a resize handle is the
        // one control where "the edge is under the pointer" is the whole point
        // (deviation 11 in `README.md`).
        dragStartBehavior: DragStartBehavior.down,
        onDoubleTap: widget.onDoubleTapReset,
        onHorizontalDragStart: (_) => setState(() => _isDragging = true),
        onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
        onHorizontalDragCancel: () => setState(() => _isDragging = false),
        onHorizontalDragUpdate: (details) =>
            widget.onDragDelta(details.delta.dx),
        child: SizedBox(
          width: SwimlaneResizer.width,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: active ? 3.0 : 1.5,
              height: double.infinity,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.3,
                          ),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
