import 'strip_metrics.dart';

/// Interaction delays and switches for the lane system, kept separate from the
/// geometry.
///
/// The three dwell delays are **independent** on purpose (Rossi
/// `workspace_interaction_settings.dart`, and the neoview contract it cites):
/// sharing one number makes whoever tunes the fastest feel ruin the others. Only
/// the dwell that lives inside this package is here - hover-to-focus - because
/// Rossi's edge-reveal delays belong to the reveal zones, which stayed with the
/// host (see the README).
class SwimlaneInteraction {
  /// Whether parking the pointer inside an inactive **reader** lane focuses it.
  final bool hoverFocusEnabled;

  /// Whether panel lanes also take hover focus.
  ///
  /// A separate switch because the contract only defines dwell-to-focus on the
  /// reader lane ("a dwell inside an inactive **Reader** lane activates it"):
  /// moving the pointer over a panel to check something should not steal focus.
  /// Rossi defaults it to on, and the way back is this switch rather than
  /// turning the reader side off.
  final bool panelHoverFocusEnabled;

  /// Dwell delay in milliseconds, **after the pointer has stopped**.
  ///
  /// Not "after it entered": whether the pointer has stopped is decided by
  /// `SwimlaneDwell.settleMs` (60ms, an internal constant, deliberately not a
  /// knob). That is why this number dropped from Rossi's original 420 to 150 -
  /// the felt total is around 210ms, and pass-bys are blocked by the settle
  /// window instead of by stretching the delay.
  final int hoverFocusDelayMs;

  /// The sliver the reader lane keeps in the viewport when focus moves elsewhere
  /// while it is solo, so a single click on that sliver returns to solo.
  /// Rossi `readerPeekWidth = 56`.
  final double readerPeekWidth;

  /// Whether focusing the reader lane also makes it solo.
  ///
  /// Off by default, the same asymmetry Rossi chose against neoview's default:
  /// "click the reader" should not silently push the other lanes out of the
  /// viewport.
  final bool autoSoloOnFocus;

  /// Whether the other lanes stay in the strip as compact rails while a lane is
  /// solo - the rails are then the lane navigator.
  ///
  /// The widget forces this on when there is no hover pointer: on touch the rails
  /// are the only handle back, because edge dwell needs `PointerHoverEvent`
  /// (which never fires there) and swiping the strip collides with the host's own
  /// horizontal gestures. The stored preference is left alone.
  final bool showLaneNavigatorInSolo;

  /// Whether the user may drag the strip sideways at all.
  ///
  /// Off still lets the strip move on focus; it only refuses "the user reached in
  /// and pulled", which is exactly the semantics Rossi documents for
  /// `ScrollPhysics.shouldAcceptUserOffset`.
  final bool manualScrollEnabled;

  /// Strip padding. Also the difference between the viewport width and the
  /// available width, so the two must never be interchanged.
  final double stripPadding;

  /// Width of the drag handle between two lanes.
  final double resizerWidth;

  /// How long the strip takes to slide to a focused lane.
  /// Rossi `SwimlaneWorkspace._scrollDuration`.
  final Duration scrollDuration;

  const SwimlaneInteraction({
    this.hoverFocusEnabled = true,
    this.panelHoverFocusEnabled = true,
    this.hoverFocusDelayMs = 150,
    this.readerPeekWidth = 56.0,
    this.autoSoloOnFocus = false,
    this.showLaneNavigatorInSolo = false,
    this.manualScrollEnabled = true,
    this.stripPadding = SwimlaneStripMetrics.defaultPadding,
    this.resizerWidth = SwimlaneStripMetrics.defaultResizerWidth,
    this.scrollDuration = const Duration(milliseconds: 220),
  });

  SwimlaneInteraction copyWith({
    bool? hoverFocusEnabled,
    bool? panelHoverFocusEnabled,
    int? hoverFocusDelayMs,
    double? readerPeekWidth,
    bool? autoSoloOnFocus,
    bool? showLaneNavigatorInSolo,
    bool? manualScrollEnabled,
    double? stripPadding,
    double? resizerWidth,
    Duration? scrollDuration,
  }) {
    return SwimlaneInteraction(
      hoverFocusEnabled: hoverFocusEnabled ?? this.hoverFocusEnabled,
      panelHoverFocusEnabled:
          panelHoverFocusEnabled ?? this.panelHoverFocusEnabled,
      hoverFocusDelayMs: hoverFocusDelayMs ?? this.hoverFocusDelayMs,
      readerPeekWidth: readerPeekWidth ?? this.readerPeekWidth,
      autoSoloOnFocus: autoSoloOnFocus ?? this.autoSoloOnFocus,
      showLaneNavigatorInSolo:
          showLaneNavigatorInSolo ?? this.showLaneNavigatorInSolo,
      manualScrollEnabled: manualScrollEnabled ?? this.manualScrollEnabled,
      stripPadding: stripPadding ?? this.stripPadding,
      resizerWidth: resizerWidth ?? this.resizerWidth,
      scrollDuration: scrollDuration ?? this.scrollDuration,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'hoverFocusEnabled': hoverFocusEnabled,
    'panelHoverFocusEnabled': panelHoverFocusEnabled,
    'hoverFocusDelayMs': hoverFocusDelayMs,
    'readerPeekWidth': readerPeekWidth,
    'autoSoloOnFocus': autoSoloOnFocus,
    'showLaneNavigatorInSolo': showLaneNavigatorInSolo,
    'manualScrollEnabled': manualScrollEnabled,
    'stripPadding': stripPadding,
    'resizerWidth': resizerWidth,
    'scrollDurationMs': scrollDuration.inMilliseconds,
  };

  /// One bad number falls back on its own, like the rest of the model layer.
  factory SwimlaneInteraction.fromJson(Map<String, Object?> json) {
    const base = SwimlaneInteraction();
    double num_(String key, double value) =>
        json[key] is num ? (json[key]! as num).toDouble() : value;
    int int_(String key, int value) =>
        json[key] is int ? json[key]! as int : value;
    bool bool_(String key, bool value) =>
        json[key] is bool ? json[key]! as bool : value;
    return SwimlaneInteraction(
      hoverFocusEnabled: bool_('hoverFocusEnabled', base.hoverFocusEnabled),
      panelHoverFocusEnabled: bool_(
        'panelHoverFocusEnabled',
        base.panelHoverFocusEnabled,
      ),
      hoverFocusDelayMs: int_('hoverFocusDelayMs', base.hoverFocusDelayMs),
      readerPeekWidth: num_('readerPeekWidth', base.readerPeekWidth),
      autoSoloOnFocus: bool_('autoSoloOnFocus', base.autoSoloOnFocus),
      showLaneNavigatorInSolo: bool_(
        'showLaneNavigatorInSolo',
        base.showLaneNavigatorInSolo,
      ),
      manualScrollEnabled: bool_(
        'manualScrollEnabled',
        base.manualScrollEnabled,
      ),
      stripPadding: num_('stripPadding', base.stripPadding),
      resizerWidth: num_('resizerWidth', base.resizerWidth),
      scrollDuration: Duration(
        milliseconds: int_(
          'scrollDurationMs',
          base.scrollDuration.inMilliseconds,
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SwimlaneInteraction &&
      other.hoverFocusEnabled == hoverFocusEnabled &&
      other.panelHoverFocusEnabled == panelHoverFocusEnabled &&
      other.hoverFocusDelayMs == hoverFocusDelayMs &&
      other.readerPeekWidth == readerPeekWidth &&
      other.autoSoloOnFocus == autoSoloOnFocus &&
      other.showLaneNavigatorInSolo == showLaneNavigatorInSolo &&
      other.manualScrollEnabled == manualScrollEnabled &&
      other.stripPadding == stripPadding &&
      other.resizerWidth == resizerWidth &&
      other.scrollDuration == scrollDuration;

  @override
  int get hashCode => Object.hash(
    hoverFocusEnabled,
    panelHoverFocusEnabled,
    hoverFocusDelayMs,
    readerPeekWidth,
    autoSoloOnFocus,
    showLaneNavigatorInSolo,
    manualScrollEnabled,
    stripPadding,
    resizerWidth,
    scrollDuration,
  );
}
