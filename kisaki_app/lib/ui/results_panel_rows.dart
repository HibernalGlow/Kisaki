part of 'results_panel.dart';

class _Rows extends StatefulWidget {
  const _Rows({required this.controller, required this.widths});

  final BoardController controller;
  final List<double> widths;

  @override
  State<_Rows> createState() => _RowsState();
}

class _RowsState extends State<_Rows> {
  /// A drag shorter than this is a click that missed a target, not a selection box.
  static const double _boxThreshold = 8;

  final FocusNode _keys = FocusNode(debugLabel: 'kisaki-results-keys');

  Offset? _origin;
  Rect? _box;
  int? _pointer;
  bool _shiftHeld = false;

  @override
  void initState() {
    super.initState();
    // A box drag and a scroll drag are the same gesture, so the box belongs to the modifier that
    // stops the list from scrolling: Shift draws, Ctrl or Command draws and keeps what was picked.
    HardwareKeyboard.instance.addHandler(_onKey);
    _shiftHeld = HardwareKeyboard.instance.isShiftPressed;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _keys.dispose();
    super.dispose();
  }

  /// Arrows walk the rows, Space checks one, Enter opens the picture under the cursor. Every action
  /// goes through the same rules a click uses, so a keyboard selection and a mouse selection agree.
  KeyEventResult _onResultKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final bool extend = HardwareKeyboard.instance.isShiftPressed;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, extend);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, extend);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _move(10, extend);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _move(-10, extend);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _jump(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _jump(widget.controller.visibleRows.length - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      widget.controller.toggleCursorSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return _openCursor();
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta, bool extend) {
    widget.controller.moveCursor(delta);
    if (extend) {
      widget.controller.extendCursorSelection();
    }
  }

  void _jump(int index) {
    widget.controller.setCursor(index);
  }

  KeyEventResult _openCursor() {
    final ScanRow? row = widget.controller.cursorRow;
    if (row == null || !widget.controller.previewPaths.contains(row.path)) {
      return KeyEventResult.ignored;
    }
    PreviewView.open(context, widget.controller, row.path);
    return KeyEventResult.handled;
  }

  bool _onKey(KeyEvent event) {
    final bool pressed = event is KeyDownEvent || event is KeyRepeatEvent;
    final bool isShift =
        event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight;
    if (!isShift || _shiftHeld == pressed) {
      return false;
    }
    setState(() => _shiftHeld = pressed);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final List<ScanRow> visible = widget.controller.visibleRows;
    if (visible.isEmpty) {
      return _EmptyRegion(controller: widget.controller);
    }
    final bool grouped = widget.controller.tool?.grouped ?? false;
    final BoardPalette palette = BoardTheme.of(context);
    return Focus(
      focusNode: _keys,
      onKeyEvent: _onResultKey,
      child: Stack(
        children: <Widget>[
          Listener(
            key: const Key('results-box-area'),
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: (_) => _clear(),
            child: ListView.builder(
              key: const Key('results-list'),
              padding: EdgeInsets.zero,
              physics: _shiftHeld ? const NeverScrollableScrollPhysics() : null,
              itemCount: visible.length,
              itemBuilder: (BuildContext context, int index) {
                final ScanRow row = visible[index];
                final bool cursor = widget.controller.isCursor(row);
                return Column(
                  children: <Widget>[
                    if (grouped && row.isGroupStart)
                      _GroupStrip(
                        controller: widget.controller,
                        row: row,
                        widths: widget.widths,
                      ),
                    _ResultRow(
                      controller: widget.controller,
                      row: row,
                      widths: widget.widths,
                      focused: cursor && _keys.hasFocus,
                    ),
                  ],
                );
              },
            ),
          ),
          if (_box != null)
            Positioned.fromRect(
              rect: _toLocal(_box!),
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('selection-box'),
                  decoration: BoxDecoration(
                    color: palette.selection,
                    border: Border.all(color: palette.selectionInk),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Rect _toLocal(Rect global) {
    final RenderBox anchor = context.findRenderObject()! as RenderBox;
    return Rect.fromLTWH(
      anchor.globalToLocal(global.topLeft).dx,
      anchor.globalToLocal(global.topLeft).dy,
      global.width,
      global.height,
    );
  }

  void _onDown(PointerDownEvent event) {
    // Raw pointer events are used instead of a gesture because a pan would lose the arena to the
    // list's own scroll drag, and because only a mouse drag is meant to draw a box.
    if (!_shiftHeld || event.kind != PointerDeviceKind.mouse) {
      _pointer = null;
      return;
    }
    _pointer = event.pointer;
    _origin = event.position;
    if (_box != null) {
      setState(() => _box = null);
    }
  }

  void _onMove(PointerMoveEvent event) {
    final Offset? origin = _origin;
    if (origin == null || event.pointer != _pointer) {
      return;
    }
    if ((event.position - origin).distance < _boxThreshold) {
      return;
    }
    setState(() {
      _box = Rect.fromPoints(origin, event.position);
    });
  }

  void _onUp(PointerUpEvent event) {
    final Rect? box = _box;
    setState(() {
      _box = null;
      _origin = null;
      _pointer = null;
    });
    if (box == null) {
      return;
    }
    final List<String> paths = <String>[];
    // visitChildElements only walks one level, so the descent has to recurse until it finds a row.
    void collect(Element element) {
      final Widget rowWidget = element.widget;
      if (rowWidget is _ResultRow) {
        final RenderObject? renderObject = element.renderObject;
        if (renderObject is RenderBox) {
          final Rect rect =
              renderObject.localToGlobal(Offset.zero) & renderObject.size;
          if (rect.overlaps(box)) {
            paths.add(rowWidget.row.path);
          }
        }
        return;
      }
      element.visitChildren(collect);
    }

    (context as Element).visitChildren(collect);
    final HardwareKeyboard keys = HardwareKeyboard.instance;
    final BoxMode mode = keys.isAltPressed
        ? BoxMode.remove
        : keys.isControlPressed || keys.isMetaPressed
        ? BoxMode.add
        : BoxMode.replace;
    widget.controller.applyBoxSelection(paths, mode);
  }

  void _clear() {
    setState(() {
      _box = null;
      _origin = null;
      _pointer = null;
    });
  }
}

class _GroupStrip extends StatelessWidget {
  const _GroupStrip({
    required this.controller,
    required this.row,
    required this.widths,
  });

  final BoardController controller;
  final ScanRow row;
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final bool allSelected =
        controller.groupSelection(row.groupIndex) == GroupSelection.all;
    return Container(
      color: palette.sunken,
      padding: const EdgeInsets.symmetric(
        horizontal: BoardTokens.gapSmall,
        vertical: 4,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 12,
            color: palette.chartByIndex(row.groupIndex),
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          // Colour is never the only signal, so the group number is printed.
          Text(
            '${Labels.of('col-group')} ${row.groupIndex + 1}',
            style: palette.microLabel(),
          ),
          const SizedBox(width: BoardTokens.gap),
          Text(
            '${row.groupSize}',
            style: TextStyle(
              fontSize: BoardTokens.fsCaption,
              height: BoardTokens.lhCaption / BoardTokens.fsCaption,
              color: palette.fgFaint,
            ),
          ),
          BoardAction(
            key: Key('group-toggle-${row.groupIndex}'),
            labelKey: 'action-select-group',
            dense: true,
            tone: allSelected ? palette.selectionInk : null,
            onPressed: () => controller.toggleGroup(row.groupIndex),
          ),
        ],
      ),
    );
  }
}

/// The step a result row occupies, widened with the reader's own text scale.
double _rowHeight(BuildContext context, {required bool wrap}) {
  final double base = wrap ? BoardTokens.rowHeight + 16 : BoardTokens.rowHeight;
  final double scale = MediaQuery.textScalerOf(context).scale(1);
  return base * (scale < 1 ? 1 : scale);
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.controller,
    required this.row,
    required this.widths,
    required this.focused,
  });

  final BoardController controller;
  final ScanRow row;
  final List<double> widths;

  /// The keyboard is on this row and the table holds focus, so the rule is drawn in the accent
  /// rather than a faint grey.
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final ToolSpec? tool = controller.tool;
    final List<ColumnDef> columns = tool?.columns ?? const <ColumnDef>[];
    final bool selected = controller.isSelected(row);
    final bool wrap = controller.wrapText;
    int offset = 0;

    final List<Widget> cells = <Widget>[
      SizedBox(
        width: widths[offset++],
        child: Checkbox(
          key: Key('row-select-${row.path}'),
          value: selected,
          // A reference row is the copy a fix must keep, so it cannot be picked, like the reference.
          onChanged: row.isReference ? null : (_) => _click(context),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    ];
    if (tool != null && tool.grouped) {
      cells.add(
        SizedBox(
          width: widths[offset++],
          child: Center(
            child: Text(
              '${row.groupIndex + 1}',
              style: TextStyle(
                fontSize: BoardTokens.fsLabel,
                height: BoardTokens.lhLabel / BoardTokens.fsLabel,
                color: palette.fgFaint,
              ),
            ),
          ),
        ),
      );
    }
    cells.add(
      SizedBox(
        width: widths[offset++],
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BoardTokens.gapSmall,
            vertical: 6,
          ),
          child: Row(
            children: <Widget>[
              if (controller.showsThumbnail(row)) ...<Widget>[
                _ThumbSlot(controller: controller, path: row.path),
                const SizedBox(width: BoardTokens.gapSmall),
              ],
              Expanded(
                child: controller.reversePath
                    ? Tooltip(
                        message: row.path,
                        child: Text(
                          controller.shownPath(row),
                          maxLines: wrap ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: BoardTokens.fsBody,
                            height: BoardTokens.lhBody / BoardTokens.fsBody,
                            fontWeight: FontWeight.w700,
                            color: selected ? palette.selectionInk : palette.fg,
                          ),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Tooltip(
                                  message: row.path,
                                  child: Text(
                                    row.name,
                                    maxLines: wrap ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: BoardTokens.fsBody,
                                      height:
                                          BoardTokens.lhBody /
                                          BoardTokens.fsBody,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? palette.selectionInk
                                          : palette.fg,
                                    ),
                                  ),
                                ),
                              ),
                              if (row.isReference) ...<Widget>[
                                const SizedBox(width: BoardTokens.gapSmall),
                                _RefBadge(),
                              ],
                            ],
                          ),
                          Text(
                            row.directory,
                            maxLines: wrap ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: BoardTokens.fsCaption,
                              height:
                                  BoardTokens.lhCaption / BoardTokens.fsCaption,
                              color: palette.fgFaint,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    for (int column = 0; column < columns.length; column++) {
      final ColumnDef definition = columns[column];
      final String text = displayCell(definition, row, column);
      cells.add(
        SizedBox(
          width: widths[offset++],
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BoardTokens.gapSmall,
            ),
            child: Align(
              alignment: definition.alignRight
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Right-aligned columns are the numeric ones, and they are set in tabular figures.
                style: definition.alignRight
                    ? palette.tableFigure()
                    : TextStyle(
                        fontSize: BoardTokens.fsLabel,
                        height: BoardTokens.lhLabel / BoardTokens.fsLabel,
                        color: palette.fg,
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      key: Key('result-row-${row.path}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _click(context),
      onSecondaryTapDown: (TapDownDetails details) => showRowMenu(
        context: context,
        controller: controller,
        row: row,
        position: details.globalPosition,
      ),
      child: Container(
        // Wrapping is a two-line row, so the row grows by a fixed step instead of jittering, and the
        // step follows the reader's text scale: the height has to stay tight or the stretched cells
        // collapse, but a fixed 44 clips the directory line when the system text is enlarged.
        height: _rowHeight(context, wrap: wrap),
        decoration: BoxDecoration(
          color: selected ? palette.selection : Colors.transparent,
          border: Border(bottom: BorderSide(color: palette.hairline)),
        ),
        child: _CursorAnchor(
          active: controller.isCursor(row),
          child: Stack(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
              // The cursor rule is an overlay, not a border: a border would take two pixels from the
              // columns and the row would report an overflow.
              if (controller.isCursor(row))
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      key: const Key('cursor-rule'),
                      width: 2,
                      color: focused ? palette.primary : palette.fgFaint,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Plain click picks one row, Ctrl or Command adds, Shift extends from the last plain click. A
  /// reference row is not a target, so neither the checkbox nor the row reacts to it.
  void _click(BuildContext context) {
    if (row.isReference) {
      return;
    }
    final HardwareKeyboard keys = HardwareKeyboard.instance;
    // Clicking the table is also how a reader gets to the arrows, so the pointer hands focus over.
    Focus.of(context).requestFocus();
    controller.placeCursor(row.path);
    controller.clickSelect(
      row,
      additive: keys.isControlPressed || keys.isMetaPressed,
      ranged: keys.isShiftPressed,
    );
  }
}

/// Scrolls the row into view when the keyboard cursor lands on it.
///
/// A GlobalKey would be the shorter way, but one key moving between the rows of a lazily built list
/// trips the semantics owner, which insists each traversal parent is unique.
class _CursorAnchor extends StatefulWidget {
  const _CursorAnchor({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_CursorAnchor> createState() => _CursorAnchorState();
}

class _CursorAnchorState extends State<_CursorAnchor> {
  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(covariant _CursorAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _reveal();
    }
  }

  void _reveal() {
    if (!widget.active) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // Holding Shift keeps the list still so a drag can draw a box, and asking a scroll view that
      // refuses to scroll for a move leaves the request pending forever. The cursor still ranges; the
      // lane's own counts say what it reached.
      final ScrollableState? view = Scrollable.maybeOf(context);
      if (view == null || view.widget.physics is NeverScrollableScrollPhysics) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        alignment: 0.05,
        duration: const Duration(milliseconds: 120),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RefBadge extends StatelessWidget {
  const _RefBadge();
  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: palette.warn),
        borderRadius: BorderRadius.circular(BoardTokens.radius),
      ),
      child: Text(
        Labels.of('badge-reference'),
        style: TextStyle(
          fontSize: BoardTokens.fsCaption,
          height: BoardTokens.lhCaption / BoardTokens.fsCaption,
          fontWeight: FontWeight.w700,
          color: palette.warn,
        ),
      ),
    );
  }
}

class _ThumbSlot extends StatelessWidget {
  const _ThumbSlot({required this.controller, required this.path});

  final BoardController controller;
  final String path;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    // The picture opens the preview instead of toggling the row, which is what the reference does.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => PreviewView.open(context, controller, path),
      child: Container(
        key: Key('row-thumb-$path'),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          color: palette.sunken,
        ),
        child: DiskImage(
          path: path,
          fit: BoxFit.cover,
          placeholder: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _EmptyRegion extends StatelessWidget {
  const _EmptyRegion({required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.rows.isNotEmpty) {
      return const EmptyState(labelKey: 'empty-filtered');
    }
    return switch (controller.phase) {
      ScanPhase.running ||
      ScanPhase.stopping => const EmptyState(labelKey: 'empty-running'),
      ScanPhase.failed => EmptyState(
        labelKey: 'empty-error',
        detail: controller.critical,
      ),
      ScanPhase.finished => const EmptyState(labelKey: 'empty-done'),
      ScanPhase.idle => EmptyState(
        labelKey: 'empty-idle',
        detail: controller.included.isEmpty ? Labels.of('empty-paths') : null,
      ),
    };
  }
}
