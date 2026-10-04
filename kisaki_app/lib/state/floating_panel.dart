import 'dart:math' as math;

/// Geometry of the analysis panel when it floats over the board, a port of the reference's
/// floating panel rules.
///
/// The panel is placed and sized in board coordinates and every change goes through [clampFloatingRect],
/// so a drag or a shrunk window can never leave it partly unreachable.

/// The area the floating panel may live in - the board body, not the whole window.
class FloatingViewport {
  const FloatingViewport({required this.width, required this.height});

  final double width;
  final double height;

  /// The reference floors the viewport so a collapsed or still-measuring host cannot size the panel
  /// down to nothing.
  factory FloatingViewport.of(double width, double height) => FloatingViewport(
    width: math.max(_minViewportWidth, _orFallback(width, _fallbackWidth)),
    height: math.max(_minViewportHeight, _orFallback(height, _fallbackHeight)),
  );

  static const double _minViewportWidth = 320;
  static const double _minViewportHeight = 240;
  static const double _fallbackWidth = 1200;
  static const double _fallbackHeight = 760;

  static double _orFallback(double value, double fallback) =>
      value <= 0 ? fallback : value;
}

class FloatingRect {
  const FloatingRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  FloatingRect copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) => FloatingRect(
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
  );

  @override
  bool operator ==(Object other) =>
      other is FloatingRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() =>
      'FloatingRect(x: $x, y: $y, width: $width, height: $height)';
}

class FloatingPanelState {
  const FloatingPanelState({required this.open, required this.rect});

  final bool open;
  final FloatingRect rect;

  FloatingPanelState copyWith({bool? open, FloatingRect? rect}) =>
      FloatingPanelState(open: open ?? this.open, rect: rect ?? this.rect);
}

/// Which edges a resize gesture pulls. The eight corners and sides of the reference's handles.
enum ResizeEdge {
  north,
  northEast,
  east,
  southEast,
  south,
  southWest,
  west,
  northWest;

  bool get dragsNorth =>
      this == ResizeEdge.north ||
      this == ResizeEdge.northEast ||
      this == ResizeEdge.northWest;
  bool get dragsSouth =>
      this == ResizeEdge.south ||
      this == ResizeEdge.southEast ||
      this == ResizeEdge.southWest;
  bool get dragsEast =>
      this == ResizeEdge.east ||
      this == ResizeEdge.northEast ||
      this == ResizeEdge.southEast;
  bool get dragsWest =>
      this == ResizeEdge.west ||
      this == ResizeEdge.northWest ||
      this == ResizeEdge.southWest;
}

const double kFloatingMargin = 8;
const double kFloatingMinWidth = 260;
const double kFloatingMinHeight = 220;
const double kFloatingMaxWidth = 900;
const double kFloatingMaxHeight = 900;
const double kFloatingDefaultWidth = 380;
const double kFloatingDefaultHeight = 560;

/// The first panel sits in the top-right of the board, away from the results the reader compares
/// against the numbers.
FloatingPanelState createDefaultFloatingPanel(FloatingViewport viewport) {
  final double width = math.min(
    kFloatingDefaultWidth,
    math.max(0, viewport.width - kFloatingMargin * 2),
  );
  final double height = math.min(
    kFloatingDefaultHeight,
    math.max(0, viewport.height - kFloatingMargin * 2),
  );
  return FloatingPanelState(
    open: false,
    rect: clampFloatingRect(
      FloatingRect(
        x: viewport.width - width - 24,
        y: 64,
        width: width,
        height: height,
      ),
      viewport,
    ),
  );
}

FloatingPanelState normalizeFloatingPanel(
  FloatingPanelState state,
  FloatingViewport viewport,
) => state.copyWith(rect: clampFloatingRect(state.rect, viewport));

FloatingRect clampFloatingRect(FloatingRect rect, FloatingViewport viewport) {
  final double availableWidth = math.max(
    0,
    viewport.width - kFloatingMargin * 2,
  );
  final double availableHeight = math.max(
    0,
    viewport.height - kFloatingMargin * 2,
  );
  final double width = _clamp(
    rect.width,
    math.min(kFloatingMinWidth, availableWidth),
    math.min(kFloatingMaxWidth, availableWidth),
  );
  final double height = _clamp(
    rect.height,
    math.min(kFloatingMinHeight, availableHeight),
    math.min(kFloatingMaxHeight, availableHeight),
  );
  return FloatingRect(
    x: _clamp(
      rect.x,
      kFloatingMargin,
      math.max(kFloatingMargin, viewport.width - width - kFloatingMargin),
    ),
    y: _clamp(
      rect.y,
      kFloatingMargin,
      math.max(kFloatingMargin, viewport.height - height - kFloatingMargin),
    ),
    width: width,
    height: height,
  );
}

FloatingRect moveFloatingRect(
  FloatingRect rect,
  double deltaX,
  double deltaY,
  FloatingViewport viewport,
) => clampFloatingRect(
  rect.copyWith(x: rect.x + deltaX, y: rect.y + deltaY),
  viewport,
);

/// Pulling a west or north edge moves that edge and keeps the opposite one, so the anchored side is
/// corrected after the clamp - otherwise a shrunk panel would slide away from the pointer.
FloatingRect resizeFloatingRect(
  FloatingRect rect,
  ResizeEdge edge,
  double deltaX,
  double deltaY,
  FloatingViewport viewport,
) {
  FloatingRect next = rect;
  if (edge.dragsEast) {
    next = next.copyWith(width: rect.width + deltaX);
  }
  if (edge.dragsSouth) {
    next = next.copyWith(height: rect.height + deltaY);
  }
  if (edge.dragsWest) {
    next = next.copyWith(x: rect.x + deltaX, width: rect.width - deltaX);
  }
  if (edge.dragsNorth) {
    next = next.copyWith(y: rect.y + deltaY, height: rect.height - deltaY);
  }
  FloatingRect clamped = clampFloatingRect(next, viewport);
  if (edge.dragsWest) {
    clamped = clamped.copyWith(
      x: math.min(
        rect.x + rect.width - clamped.width,
        viewport.width - clamped.width - kFloatingMargin,
      ),
    );
  }
  if (edge.dragsNorth) {
    clamped = clamped.copyWith(
      y: math.min(
        rect.y + rect.height - clamped.height,
        viewport.height - clamped.height - kFloatingMargin,
      ),
    );
  }
  return clampFloatingRect(clamped, viewport);
}

double _clamp(double value, double min, double max) {
  if (!value.isFinite) {
    return min;
  }
  return math.min(math.max(min, value), math.max(min, max));
}
