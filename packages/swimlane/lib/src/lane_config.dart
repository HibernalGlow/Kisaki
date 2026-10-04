import 'dart:math' as math;

/// What a lane measures its width in.
///
/// Rossi keeps this distinction implicit in the lane **id** (`LaneId.reader` is
/// the elastic lane and the only one carrying a `widthRatio`):
/// `rossi/lib/workspace/model/workspace_strip_metrics.dart` reads
/// `widths[LaneId.reader]`, and `workspace_cubit.dart`'s `_withWidth` writes the
/// ratio back for any lane that has one. A package cannot hard-code an
/// application's id string, so the property moves onto the lane itself.
/// Numbers and clamps are unchanged.
enum LaneKind {
  /// Absolute pixels, never clamped to the window width. When the strip does not
  /// fit, the whole strip scrolls sideways instead of squeezing a panel lane.
  panel,

  /// A fraction of the viewport (`viewportWidth * widthRatio`), which is what
  /// keeps a rotating / resizing window from making the lane wider than the
  /// workspace. This is also the **elastic** lane: spare strip width goes to it.
  reader,
}

/// Geometry of a single lane: stored width, its min/max band, collapse flag.
///
/// The two measuring units are the point of this class
/// (Rossi `workspace_layout_config.dart`, `LaneConfig`):
/// - a [LaneKind.panel] lane is **absolute pixels** and is **not** clamped to the
///   current window width - a narrow window scrolls the strip;
/// - a [LaneKind.reader] lane stores a **viewport ratio**, so resizing the window
///   keeps the lane proportional instead of overflowing it.
///
/// Pure Dart on purpose (no Flutter import): this is the layer the geometry
/// assertions talk to, exactly like Rossi's rule that his model files must load
/// in a bare Dart VM.
class LaneConfig {
  /// Absolute pixel width. For a [LaneKind.reader] lane it is only a nominal
  /// value kept in sync with [widthRatio] (Rossi writes both in `_withWidth`).
  final double width;

  /// Viewport ratio; `null` for panel lanes.
  final double? widthRatio;

  /// Default band copied from Rossi's `LaneConfig` (220 / 750).
  final double minWidth;
  final double maxWidth;

  /// Collapsed into the 44dp compact rail.
  final bool collapsed;

  /// Lane label. The host owns it (i18n lives outside this package).
  final String title;

  final LaneKind kind;

  /// The width a double tap resets **to**.
  ///
  /// Rossi reads it from a global table (`WorkspaceLayoutConfig.defaults()`),
  /// which a reusable package cannot have: it would have to know the host's lane
  /// ids. So each lane carries its own recommendation, defaulting to the width it
  /// was constructed with.
  final double recommendedWidth;
  final double? recommendedWidthRatio;

  LaneConfig({
    required this.width,
    this.widthRatio,
    this.minWidth = 220.0,
    this.maxWidth = 750.0,
    this.collapsed = false,
    this.title = '',
    this.kind = LaneKind.panel,
    double? recommendedWidth,
    double? recommendedWidthRatio,
  }) : recommendedWidth = recommendedWidth ?? width,
       recommendedWidthRatio = recommendedWidthRatio ?? widthRatio;

  /// Width this lane occupies for a viewport of [viewportWidth].
  double resolveWidth(double viewportWidth) {
    final ratio = widthRatio;
    final raw = ratio != null && viewportWidth > 0
        ? viewportWidth * ratio
        : width;
    return raw.clamp(minWidth, maxWidth).toDouble();
  }

  /// Write [px] back into the lane's own measuring unit.
  ///
  /// A panel lane stores pixels; a reader lane stores the ratio too, so that a
  /// later window resize still honours "the user wanted this fraction" instead of
  /// the pixel count it happened to be dragged to. Rossi: `workspace_cubit.dart`
  /// `_withWidth` (a reader lane dragged to 900px in a 1600px viewport stores
  /// `widthRatio = 900 / 1600`).
  ///
  /// Deviation: the ratio is floored at 0.05. Rossi floors nothing because his
  /// only caller (`dragLanePair`, `setLaneWidth`) has already clamped `px` into
  /// the lane's own band; a host calling this directly with `px = 0` would
  /// persist a ratio that makes the lane invisible forever, since every later
  /// width is derived from it.
  LaneConfig withStoredWidth({
    required double px,
    required double viewportWidth,
  }) {
    if (widthRatio == null || viewportWidth <= 0) return copyWith(width: px);
    return copyWith(
      width: px,
      widthRatio: () => math.max(px / viewportWidth, 0.05),
    );
  }

  LaneConfig copyWith({
    double? width,
    // A getter, so that "leave it alone" and "clear it to null" stay distinct -
    // the same trick Rossi uses in `LaneConfig.copyWith`.
    double? Function()? widthRatio,
    double? minWidth,
    double? maxWidth,
    bool? collapsed,
    String? title,
    LaneKind? kind,
    double? recommendedWidth,
    double? Function()? recommendedWidthRatio,
  }) {
    return LaneConfig(
      width: width ?? this.width,
      widthRatio: widthRatio != null ? widthRatio() : this.widthRatio,
      minWidth: minWidth ?? this.minWidth,
      maxWidth: maxWidth ?? this.maxWidth,
      collapsed: collapsed ?? this.collapsed,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      recommendedWidth: recommendedWidth ?? this.recommendedWidth,
      recommendedWidthRatio: recommendedWidthRatio != null
          ? recommendedWidthRatio()
          : this.recommendedWidthRatio,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'width': width,
    'minWidth': minWidth,
    'maxWidth': maxWidth,
    'collapsed': collapsed,
    'title': title,
    'kind': kind.name,
    'recommendedWidth': recommendedWidth,
    if (widthRatio != null) 'widthRatio': widthRatio,
    if (recommendedWidthRatio != null)
      'recommendedWidthRatio': recommendedWidthRatio,
  };

  /// Restore a lane from JSON.
  ///
  /// Every field falls back to [fallback] **on its own**: a hand-edited config
  /// with one bad number must not send the whole layout back to defaults
  /// (Rossi `workspace_layout_config.dart`, `LaneConfig.fromJson`).
  factory LaneConfig.fromJson(
    Map<String, Object?> json, {
    required LaneConfig fallback,
  }) {
    double num_(String key, double value) =>
        json[key] is num ? (json[key]! as num).toDouble() : value;
    double? optionalRatio(String key, double? value) =>
        json[key] is num ? (json[key]! as num).toDouble() : value;
    return LaneConfig(
      width: num_('width', fallback.width),
      widthRatio: optionalRatio('widthRatio', fallback.widthRatio),
      minWidth: num_('minWidth', fallback.minWidth),
      maxWidth: num_('maxWidth', fallback.maxWidth),
      collapsed: json['collapsed'] is bool
          ? json['collapsed']! as bool
          : fallback.collapsed,
      title: json['title'] is String
          ? json['title']! as String
          : fallback.title,
      kind: LaneKind.values.firstWhere(
        (LaneKind value) => value.name == json['kind'],
        orElse: () => fallback.kind,
      ),
      recommendedWidth: num_('recommendedWidth', fallback.recommendedWidth),
      recommendedWidthRatio: optionalRatio(
        'recommendedWidthRatio',
        fallback.recommendedWidthRatio,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LaneConfig &&
      other.width == width &&
      other.widthRatio == widthRatio &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.collapsed == collapsed &&
      other.title == title &&
      other.kind == kind &&
      other.recommendedWidth == recommendedWidth &&
      other.recommendedWidthRatio == recommendedWidthRatio;

  @override
  int get hashCode => Object.hash(
    width,
    widthRatio,
    minWidth,
    maxWidth,
    collapsed,
    title,
    kind,
    recommendedWidth,
    recommendedWidthRatio,
  );

  @override
  String toString() =>
      'LaneConfig(${kind.name}, width: $width, ratio: $widthRatio, '
      'band: $minWidth-$maxWidth, collapsed: $collapsed, title: $title)';
}
