import 'dart:math' as math;

/// The lane header's "who is still in this row, who has to give way" budget.
///
/// Pure arithmetic on purpose, so the yield order can be asserted directly.
/// Every number here is copied from Rossi's `_LaneChrome`
/// (`rossi/lib/workspace/widgets/swimlane/swimlane_column.dart`), where they were
/// measured on a 400px lane. Touching the header's layout means re-checking them.
class LaneChrome {
  const LaneChrome._();

  /// Lane border plus the header's own 10 + 10 horizontal padding.
  ///
  /// The border depends on whether this is the active lane:
  /// `Border.all(width: isActive ? 1.5 : 1)`, so the active lane has 1px less.
  /// Under-counting that one pixel is exactly the "440px lane overflows by 1px"
  /// bug - which in an assertion is a failure and on screen is stripes.
  static double borderAndPadding({required bool isActive}) =>
      20 + (isActive ? 3 : 2);

  /// The lane icon (which is also the reorder handle) plus the 4 after it.
  static const double handle = 18 + 4;

  /// The 4 on each side of a header-mounted strip.
  static const double stripGaps = 4 + 4;

  /// One `IconButton(visualDensity: VisualDensity.compact)`.
  static const double iconButton = 40;

  static const double soloButton = iconButton;
  static const double collapseButton = iconButton;

  /// The "more" button: 4 + 4 padding around a 16 icon.
  static const double moreButton = 24;

  /// The width badge is **fixed width**, which is what makes this budget a hard
  /// number: Rossi first recorded a measured 62.5, then a font change silently
  /// lost 5px and a 440px lane overflowed. Fixed at 72, plus the 6 between it and
  /// the title.
  static const double badgeInner = 72;
  static const double badge = badgeInner + 6;
}

/// Result of [resolveLaneHeaderFit]: which items still fit in the header row.
class LaneHeaderFit {
  const LaneHeaderFit({
    required this.stripMaxWidth,
    required this.showBadge,
    required this.showSolo,
    required this.showCollapse,
    required this.showMore,
  });

  /// Upper bound for a host strip mounted in the header. The strip sizes itself
  /// to its content, so this is a **cap**, not a reservation. When it is below
  /// what the strip needs (the last-resort tier) the sum of the non-flexible
  /// items equals the row's width exactly, so the flexible part gets 0 rather
  /// than a negative number - a negative one is stripes.
  final double stripMaxWidth;

  final bool showBadge;
  final bool showSolo;
  final bool showCollapse;
  final bool showMore;
}

/// Decide what the header can still show at [laneWidth].
///
/// The yield order is Rossi's, kept verbatim (user rule of 2026-09-20): **the
/// host's mounted strip must stay whole**, so it takes what it actually needs
/// first; then whatever is left is handed out in the order
/// "more -> collapse -> solo -> width badge -> title text", last one to be dropped
/// is the one asked first. The title is `Flexible`, so it absorbs pressure as an
/// ellipsis and needs no rule; the badge is hard, so it does.
///
/// Dropping a button does not drop the function: everything those buttons do
/// also lives in the host's own lane menu, reachable by right-clicking the header.
///
/// Only when even "handle + strip" does not fit does the strip get told to scroll
/// itself - that is the last tier, not the default one. Rossi's earlier version
/// did the opposite (reserving 75 for the title and capping the strip with the
/// rest), which left 158 on a 389px lane when five icons need around 210, and cut
/// the last icon off.
LaneHeaderFit resolveLaneHeaderFit({
  required double laneWidth,
  required bool isActive,
  int headerActionCount = 0,
  double stripNeed = 0,
}) {
  var rest =
      laneWidth -
      LaneChrome.borderAndPadding(isActive: isActive) -
      LaneChrome.handle -
      LaneChrome.iconButton * headerActionCount;

  if (stripNeed > 0) rest -= LaneChrome.stripGaps + stripNeed;

  // Whoever gives way last asks for space first, so "more" is served first.
  final showMore = rest >= LaneChrome.moreButton;
  if (showMore) rest -= LaneChrome.moreButton;
  final showCollapse = rest >= LaneChrome.collapseButton;
  if (showCollapse) rest -= LaneChrome.collapseButton;
  final showSolo = rest >= LaneChrome.soloButton;
  if (showSolo) rest -= LaneChrome.soloButton;

  final showBadge = rest >= LaneChrome.badge;
  if (showBadge) rest -= LaneChrome.badge;

  return LaneHeaderFit(
    stripMaxWidth: (stripNeed + math.min(rest, 0)).clamp(0.0, double.infinity),
    showBadge: showBadge,
    showSolo: showSolo,
    showCollapse: showCollapse,
    showMore: showMore,
  );
}
