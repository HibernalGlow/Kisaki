part of 'board_controller.dart';

/// The analysis panel detached from its lane and floated over the board.
///
/// The rect is normalized on read, like the reference normalizes it when it publishes its data, so a
/// window that shrinks pulls the panel back inside without a listener firing during a build.
extension BoardFloatingPanel on BoardController {
  FloatingPanelState get floatingPanel =>
      normalizeFloatingPanel(_floating, _floatingViewport);

  FloatingViewport get floatingViewport => _floatingViewport;

  /// A board this narrow has no room for a panel on top of it, so the reference refuses the float
  /// and keeps the lane docked.
  bool get floatingAnalysisAvailable =>
      _floatingViewport.width >= _floatingMinWidth;

  bool get floatingAnalysisOpen => floatingAnalysisAvailable && _floating.open;

  /// The lane the floating panel took over stays hidden - two copies of the same numbers would read
  /// as two different results.
  bool get dockedAnalysisVisible => !floatingAnalysisOpen;

  /// Fed by the board's own layout, so no notification is raised here: the caller is already building.
  void reportFloatingViewport(double width, double height) {
    final FloatingViewport next = FloatingViewport.of(width, height);
    if (next.width == _floatingViewport.width &&
        next.height == _floatingViewport.height) {
      return;
    }
    _floatingViewport = next;
  }

  void toggleFloatingPanel() {
    if (!floatingAnalysisAvailable) {
      return;
    }
    _floating = normalizeFloatingPanel(
      _floating.copyWith(open: !_floating.open),
      _floatingViewport,
    );
    publish();
  }

  /// Stores a rect a drag or resize gesture already resolved from the one it started on.
  void placeFloatingPanel(FloatingRect rect) => _applyRect(rect);

  void moveFloatingPanel(double deltaX, double deltaY) {
    _applyRect(
      moveFloatingRect(floatingPanel.rect, deltaX, deltaY, _floatingViewport),
    );
  }

  void resizeFloatingPanel(ResizeEdge edge, double deltaX, double deltaY) {
    _applyRect(
      resizeFloatingRect(
        floatingPanel.rect,
        edge,
        deltaX,
        deltaY,
        _floatingViewport,
      ),
    );
  }

  void _applyRect(FloatingRect rect) {
    if (rect == _floating.rect) {
      return;
    }
    _floating = _floating.copyWith(rect: rect);
    publish();
  }
}

/// Below this board width the float is refused, the reference's compact cutoff.
const double _floatingMinWidth = 760;
