import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/floating_panel.dart';
import '../theme/board_theme.dart';
import 'card_stack.dart';
import 'widgets/primitives.dart';

/// The analysis lane lifted off the board so the numbers stay readable while the lanes use the width.
///
/// Dragging is anchored on the rect the gesture started from, like the reference, so a panel pushed
/// against the board edge can be pulled back instead of sticking there.
class FloatingAnalysisPanel extends StatefulWidget {
  const FloatingAnalysisPanel({
    required this.controller,
    required this.body,
    super.key,
  });

  final BoardController controller;
  final Widget body;

  @override
  State<FloatingAnalysisPanel> createState() => _FloatingAnalysisPanelState();
}

class _FloatingAnalysisPanelState extends State<FloatingAnalysisPanel> {
  /// Straight edges are grabbable across a band and the corners over a square of the same size, so a
  /// pointer only has to land near the frame and the header keeps its own buttons.
  static const double _pad = BoardTokens.gap;

  final FocusNode _headerKeys = FocusNode(
    debugLabel: 'floating-analysis-header',
  );

  FloatingRect? _base;
  Offset? _origin;
  bool _grabbed = false;

  @override
  void dispose() {
    _headerKeys.dispose();
    super.dispose();
  }

  void _start(Offset global) {
    _base = widget.controller.floatingPanel.rect;
    _origin = global;
    setState(() => _grabbed = true);
  }

  void _drag(ResizeEdge? edge, DragUpdateDetails details) {
    final FloatingRect? base = _base;
    final Offset? origin = _origin;
    if (base == null || origin == null) {
      return;
    }
    final FloatingViewport viewport = widget.controller.floatingViewport;
    widget.controller.placeFloatingPanel(
      edge == null
          ? moveFloatingRect(
              base,
              details.globalPosition.dx - origin.dx,
              details.globalPosition.dy - origin.dy,
              viewport,
            )
          : resizeFloatingRect(
              base,
              edge,
              details.globalPosition.dx - origin.dx,
              details.globalPosition.dy - origin.dy,
              viewport,
            ),
    );
  }

  void _finish() {
    _base = null;
    _origin = null;
    if (_grabbed) {
      setState(() => _grabbed = false);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final double step = HardwareKeyboard.instance.isShiftPressed ? 32 : 12;
    double dx = 0;
    double dy = 0;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      dx = -step;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      dx = step;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      dy = -step;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      dy = step;
    } else {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      widget.controller.resizeFloatingPanel(ResizeEdge.southEast, dx, dy);
    } else {
      widget.controller.moveFloatingPanel(dx, dy);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Container(
            key: const Key('floating-analysis'),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(BoardTokens.radius),
              border: Border.all(color: palette.border),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Header(
                  palette: palette,
                  grabbed: _grabbed,
                  focusNode: _headerKeys,
                  onKey: _onKey,
                  onPanStart: (DragStartDetails d) => _start(d.globalPosition),
                  onPanUpdate: (DragUpdateDetails d) => _drag(null, d),
                  onPanEnd: (DragEndDetails _) => _finish(),
                  onClose: () => widget.controller.toggleFloatingPanel(),
                  onManage: () =>
                      CardManagerDialog.open(context, widget.controller),
                ),
                const Hairline(),
                Expanded(child: widget.body),
              ],
            ),
          ),
        ),
        for (final _Handle handle in _handles)
          Positioned(
            left: handle.left,
            top: handle.top,
            right: handle.right,
            bottom: handle.bottom,
            child: _ResizeHandle(
              handle: handle,
              edge: handle.edge,
              onPanStart: (DragStartDetails d) => _start(d.globalPosition),
              onPanUpdate: (DragUpdateDetails d) => _drag(handle.edge, d),
              onPanEnd: (DragEndDetails _) => _finish(),
            ),
          ),
      ],
    );
  }

  /// The eight pads the reference offers: four bands inset past the corners, four corner squares.
  List<_Handle> get _handles => const <_Handle>[
    _Handle(edge: ResizeEdge.north, top: 0, left: _pad, right: _pad),
    _Handle(edge: ResizeEdge.south, bottom: 0, left: _pad, right: _pad),
    _Handle(edge: ResizeEdge.east, right: 0, top: _pad, bottom: _pad),
    _Handle(edge: ResizeEdge.west, left: 0, top: _pad, bottom: _pad),
    _Handle(edge: ResizeEdge.northWest, top: 0, left: 0),
    _Handle(edge: ResizeEdge.northEast, top: 0, right: 0),
    _Handle(edge: ResizeEdge.southWest, bottom: 0, left: 0),
    _Handle(edge: ResizeEdge.southEast, bottom: 0, right: 0),
  ];
}

class _Handle {
  const _Handle({
    required this.edge,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });

  final ResizeEdge edge;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;

  MouseCursor get cursor => switch (edge) {
    ResizeEdge.north => SystemMouseCursors.resizeUp,
    ResizeEdge.south => SystemMouseCursors.resizeDown,
    ResizeEdge.east => SystemMouseCursors.resizeRight,
    ResizeEdge.west => SystemMouseCursors.resizeLeft,
    ResizeEdge.northWest => SystemMouseCursors.resizeUpLeft,
    ResizeEdge.northEast => SystemMouseCursors.resizeUpRight,
    ResizeEdge.southWest => SystemMouseCursors.resizeDownLeft,
    ResizeEdge.southEast => SystemMouseCursors.resizeDownRight,
  };
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.handle,
    required this.edge,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final _Handle handle;
  final ResizeEdge edge;
  final void Function(DragStartDetails details) onPanStart;
  final void Function(DragUpdateDetails details) onPanUpdate;
  final void Function(DragEndDetails details) onPanEnd;

  @override
  Widget build(BuildContext context) {
    const double pad = _FloatingAnalysisPanelState._pad;
    // The side the handle spans is fixed by the positioning; the other one carries the grab band.
    final bool stretchWidth = handle.left != null && handle.right != null;
    final bool stretchHeight = handle.top != null && handle.bottom != null;
    return Semantics(
      label: Labels.of(
        'floating-resize',
        args: <String, Object>{'edge': edge.name},
      ),
      child: MouseRegion(
        cursor: handle.cursor,
        child: GestureDetector(
          key: Key('floating-resize-${edge.name}'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: onPanStart,
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
          child: SizedBox(
            width: stretchWidth ? null : pad,
            height: stretchHeight ? null : pad,
          ),
        ),
      ),
    );
  }
}

/// The header carries the drag surface and the keyboard focus, so the panel moves without a mouse.
class _Header extends StatelessWidget {
  const _Header({
    required this.palette,
    required this.grabbed,
    required this.focusNode,
    required this.onKey,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onClose,
    required this.onManage,
  });

  final BoardPalette palette;
  final bool grabbed;
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode node, KeyEvent event) onKey;
  final void Function(DragStartDetails details) onPanStart;
  final void Function(DragUpdateDetails details) onPanUpdate;
  final void Function(DragEndDetails details) onPanEnd;
  final VoidCallback onClose;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: Labels.of('floating-move'),
      container: true,
      child: Focus(
        focusNode: focusNode,
        onKeyEvent: onKey,
        child: MouseRegion(
          cursor: grabbed
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab,
          child: GestureDetector(
            key: const Key('floating-header'),
            behavior: HitTestBehavior.opaque,
            // The panel has to follow the pointer from the press, not from the point the pan slop
            // cleared.
            dragStartBehavior: DragStartBehavior.down,
            // A click on the header hands it the keyboard, so the arrows work without a second step.
            onTap: () => focusNode.requestFocus(),
            onPanStart: onPanStart,
            onPanUpdate: onPanUpdate,
            onPanEnd: onPanEnd,
            child: ColoredBox(
              color: grabbed ? palette.raised : palette.card,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BoardTokens.gap,
                  vertical: BoardTokens.gapSmall,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.drag_indicator_rounded,
                      size: 14,
                      color: palette.fgMuted,
                    ),
                    const SizedBox(width: BoardTokens.gapSmall),
                    Expanded(
                      child: Text(
                        Labels.of('floating-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: BoardTokens.fsLabel,
                          fontWeight: FontWeight.w700,
                          color: palette.fg,
                        ),
                      ),
                    ),
                    BoardAction(
                      key: const Key('cards-manage'),
                      labelKey: 'cards-manage',
                      icon: Icons.view_day_outlined,
                      dense: true,
                      iconOnly: true,
                      onPressed: onManage,
                    ),
                    const SizedBox(width: BoardTokens.gapSmall),
                    BoardAction(
                      key: const Key('floating-close'),
                      labelKey: 'floating-close',
                      icon: Icons.close_rounded,
                      dense: true,
                      iconOnly: true,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
