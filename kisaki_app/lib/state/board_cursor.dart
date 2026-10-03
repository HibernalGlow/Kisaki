part of 'board_controller.dart';

/// The keyboard cursor: one row the arrows work on, so a reader can select and open without a mouse.
///
/// The reference table is pointer-only - a web page reaches its rows with Tab through the sort
/// buttons, not through the rows. Kisaki promises mouse *and* keyboard, so the cursor is the board's
/// own addition, and every action it takes goes through the same selection and preview rules a click
/// uses.
extension BoardRowCursor on BoardController {
  int get cursorIndex => _cursor;

  ScanRow? get cursorRow {
    if (_cursor < 0 || _cursor >= _visible.length) {
      return null;
    }
    return _visible[_cursor];
  }

  bool isCursor(ScanRow row) =>
      _cursor >= 0 &&
      _cursor < _visible.length &&
      _visible[_cursor].path == row.path;

  /// Moves by [delta] rows and stops at both ends. From no cursor, either direction lands on the
  /// nearest end, which is what a reader expects from the first arrow press.
  void moveCursor(int delta) {
    if (_visible.isEmpty) {
      return;
    }
    if (_cursor < 0) {
      _cursor = delta < 0 ? _visible.length - 1 : 0;
    } else {
      final int next = _cursor + delta;
      _cursor = next < 0
          ? 0
          : (next >= _visible.length ? _visible.length - 1 : next);
    }
    publish();
  }

  void setCursor(int index) {
    if (_visible.isEmpty) {
      return;
    }
    _cursor = index < 0
        ? 0
        : (index >= _visible.length ? _visible.length - 1 : index);
    publish();
  }

  /// A click and an arrow agree on where the cursor is, so the rule a reader sees matches the row
  /// they just picked.
  void placeCursor(String path) {
    final int index = _visible.indexWhere((ScanRow row) => row.path == path);
    if (index < 0 || index == _cursor) {
      return;
    }
    _cursor = index;
    publish();
  }

  /// Space: the same checkbox a click would change.
  void toggleCursorSelection() {
    final ScanRow? row = cursorRow;
    if (row == null || row.isReference) {
      return;
    }
    clickSelect(row, additive: true, ranged: false);
  }

  /// Shift plus an arrow: extend from the last plain click, as a dragged box would.
  void extendCursorSelection() {
    final ScanRow? row = cursorRow;
    if (row == null || row.isReference) {
      return;
    }
    clickSelect(row, additive: false, ranged: true);
  }
}
