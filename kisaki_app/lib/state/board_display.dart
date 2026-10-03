part of 'board_controller.dart';

/// How the table shows itself: click and box rules, the picture preview, and the
/// display toggles a reader sets from the results header.
extension BoardTableDisplay on BoardController {
  /// The rows a drag rectangle covered become the selection; Ctrl or Command adds, Alt subtracts.
  void applyBoxSelection(Iterable<String> paths, BoxMode mode) {
    final List<String> next = applyBoxPaths(
      _selected.toList(),
      paths.where((String path) => !isReferencePath(path)).toList(),
      mode,
    );
    _selected
      ..clear()
      ..addAll(next);
    _commitSelection();
    publish();
  }

  bool isReferencePath(String path) =>
      _rows.any((ScanRow row) => row.path == path && row.isReference);

  /// Port of the reference's click rules: plain picks one, Ctrl/Cmd adds, Shift extends the range
  /// from the last row clicked without a modifier.
  void clickSelect(
    ScanRow row, {
    required bool additive,
    required bool ranged,
  }) {
    final bool checked = !_selected.contains(row.path);
    final ClickMode mode = ranged
        ? ClickMode.range
        : additive
        ? ClickMode.toggle
        : ClickMode.replace;
    final List<String> next = applyResultSelection(
      current: _selected.toList(),
      visible: _visible,
      path: row.path,
      checked: checked,
      mode: mode,
      anchor: _selectionAnchor,
    );
    _selected
      ..clear()
      ..addAll(next);
    if (!ranged) {
      _selectionAnchor = row.path;
    }
    _commitSelection();
    publish();
  }

  /// Display toggles the reference exposes for the table body.
  bool get reversePath => _reversePath;
  bool get wrapText => _wrapText;

  void setReversePath(bool value) {
    _reversePath = value;
    publish();
  }

  void setWrapText(bool value) {
    _wrapText = value;
    publish();
  }

  String shownPath(ScanRow row) =>
      _reversePath ? formatReversePath(row.path) : row.path;

  void selectAllVisible() {
    for (final ScanRow row in _visible) {
      _selected.add(row.path);
    }
    _commitSelection();
    publish();
  }

  void clearSelection() {
    if (_selected.isEmpty) {
      return;
    }
    _selected.clear();
    _commitSelection();
    publish();
  }

  /// The assistant and the comparison dialog work on the groups the table shows, so a filtered-out
  /// row is never touched.
  List<List<ScanRow>> get boardGroups => groupsOf(_visible, _tool);

  /// The pictures the preview can step through: the rows on screen, in table order.
  List<String> get previewPaths =>
      _visible.map((ScanRow row) => row.path).where(isSimiuSetImage).toList();

  String get previewPath => _previewPath ?? '';

  bool get previewOpen => _previewPath != null;

  void openPreview(String path) {
    _previewPath = path;
    publish();
  }

  void closePreview() {
    if (_previewPath == null) {
      return;
    }
    _previewPath = null;
    publish();
  }

  /// The panel the reference keeps docked beside the table: same active picture, no dialog.
  bool get pinnedPreview => _pinnedPreview;

  bool get previewPanelOpen =>
      _pinnedPreview && previewPaths.contains(_previewPath);

  void togglePinnedPreview() {
    _pinnedPreview = !_pinnedPreview;
    if (_pinnedPreview && previewPaths.isNotEmpty) {
      _previewPath ??= previewPaths.first;
    }
    publish();
  }

  /// Steps through [previewPaths] and stops at the ends, like the reference's arrows.
  void stepPreview(int delta) {
    final String? current = _previewPath;
    if (current == null) {
      return;
    }
    final List<String> paths = previewPaths;
    final int index = paths.indexOf(current);
    if (index < 0) {
      return;
    }
    final int next = (index + delta).clamp(0, paths.length - 1);
    if (paths[next] == current) {
      return;
    }
    _previewPath = paths[next];
    publish();
  }

  /// Widths the reader dragged, keyed `tool:column`, so each scanner keeps its own layout.
  Map<String, double> get columnWidths => _columnWidths;

  /// The reference paints a picture per row when thumbnails are on. A row whose suffix cannot be
  /// decoded keeps the slot empty rather than asking an image codec for a text file.
  bool get showThumbnails => _showThumbnails;

  bool showsThumbnail(ScanRow row) =>
      _showThumbnails && isSimiuSetImage(row.path);

  void setShowThumbnails(bool value) {
    _showThumbnails = value;
    publish();
  }

  void setColumnWidth(String columnKey, double width, double minWidth) {
    final String toolId = _tool?.id ?? '';
    if (toolId.isEmpty) {
      return;
    }
    final double clamped = width < minWidth ? minWidth : width;
    final String key = '$toolId:$columnKey';
    if (_columnWidths[key] == clamped) {
      return;
    }
    _columnWidths[key] = clamped;
    publish();
  }

  /// Gives every column of the current scanner back to the flexed layout.
  void resetColumnWidths() {
    final String prefix = '${_tool?.id ?? ''}:';
    final List<String> owned = _columnWidths.keys
        .where((String key) => key.startsWith(prefix))
        .toList();
    if (owned.isEmpty) {
      return;
    }
    _columnWidths.removeWhere(
      (String key, double value) => owned.contains(key),
    );
    publish();
  }
}
