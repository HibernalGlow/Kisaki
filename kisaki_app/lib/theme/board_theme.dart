import 'package:flutter/material.dart';

/// Design tokens copied from `kisaki/ui/globals/theme.slint`.
///
/// Sizes are logical pixels; the Slint source uses `length` (px) 1:1.
class BoardTokens {
  const BoardTokens._();

  static const double rowHeight = 44;
  static const double gap = 8;
  static const double gapSmall = 4;
  static const double pad = 8;
  static const double radius = 6;
  static const double laneHeaderHeight = 32;
  static const double laneCollapsedWidth = 48;
  static const double headerHeight = 48;
  static const double colSelect = 42;
  static const double colGroup = 76;
  static const double colName = 236;

  static const double fsCaption = 10;
  static const double fsLabel = 11;
  static const double fsBody = 12;
  static const double fsTitle = 14;
  static const double fsMetric = 15;

  static const double minWindowWidth = 940;
  static const double minWindowHeight = 560;

  static const double sourceLaneDefault = 300;
  static const double sourceLaneMin = 220;
  static const double sourceLaneMax = 560;
  static const double resultsLaneDefault = 300;
  static const double resultsLaneMin = 210;
  static const double resultsLaneMax = 520;
}

/// Every surface colour derives from the single [dark] flag, so one toggle restyles the board.
class BoardPalette {
  const BoardPalette({required this.dark});

  final bool dark;

  Color get bg => _d(const Color(0xFF0E1013), const Color(0xFFF4F5F7));
  Color get card => _d(const Color(0xFF171A20), const Color(0xFFFFFFFF));
  Color get raised => _d(const Color(0xFF1D212A), const Color(0xFFEEF0F4));
  Color get sunken => _d(const Color(0xFF12151A), const Color(0xFFE8EBEF));
  Color get border => _d(const Color(0xFF262B34), const Color(0xFFD5D9E0));
  Color get borderSoft => _d(const Color(0xFF1E232A), const Color(0xFFE3E6EB));
  Color get hairline => _d(const Color(0xFF20252D), const Color(0xFFDDE1E7));

  Color get fg => _d(const Color(0xFFE6E9EF), const Color(0xFF17191C));
  Color get fgMuted => _d(const Color(0xFF99A3B2), const Color(0xFF5D6673));
  Color get fgFaint => _d(const Color(0xFF6A7382), const Color(0xFF8B95A3));
  Color get fgInverted => const Color(0xFFFFFFFF);

  Color get primary => _d(const Color(0xFF4F8CFF), const Color(0xFF2563EB));
  Color get primarySoft => _d(const Color(0xFF1B2B45), const Color(0xFFDBEAFE));
  Color get selection => _d(const Color(0xFF1D2F4D), const Color(0xFFDBEAFE));
  Color get hover => _d(const Color(0xFF222834), const Color(0xFFECEEF2));
  Color get pressed => _d(const Color(0xFF2A3140), const Color(0xFFE0E4EA));

  Color get danger => _d(const Color(0xFFF2555A), const Color(0xFFD92D2F));
  Color get dangerSoft => _d(const Color(0xFF2C181B), const Color(0xFFFDE8E8));
  Color get warn => _d(const Color(0xFFF0A92E), const Color(0xFFB45309));
  Color get ok => _d(const Color(0xFF3FB950), const Color(0xFF15803D));

  Color get scrim => Color(0x00000000).withValues(alpha: dark ? 0.6 : 0.4);

  /// Group identity is the `chart_*` cycle plus a printed group number, never colour alone.
  Color chartByIndex(int index) => const <Color>[
    Color(0xFF4F8CFF),
    Color(0xFF3FB950),
    Color(0xFFF0A92E),
    Color(0xFFA855F7),
    Color(0xFF06B6D4),
  ][index % 5];

  Color _d(Color darkColor, Color lightColor) => dark ? darkColor : lightColor;

  TextTheme get text => TextTheme(
    displaySmall: _style(BoardTokens.fsMetric, FontWeight.w600, fg),
    titleMedium: _style(BoardTokens.fsTitle, FontWeight.w600, fg),
    titleSmall: _style(BoardTokens.fsLabel, FontWeight.w600, fgMuted),
    bodyMedium: _style(BoardTokens.fsBody, FontWeight.w400, fg),
    bodySmall: _style(BoardTokens.fsLabel, FontWeight.w400, fgMuted),
    labelSmall: _style(BoardTokens.fsCaption, FontWeight.w600, fgMuted),
  );

  TextStyle _style(double size, FontWeight weight, Color color) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.25);
}

class BoardTheme extends InheritedWidget {
  const BoardTheme({required this.dark, required super.child, super.key});

  final bool dark;

  BoardPalette get palette => BoardPalette(dark: dark);

  static BoardPalette of(BuildContext context) {
    final BoardTheme? theme = context
        .dependOnInheritedWidgetOfExactType<BoardTheme>();
    return theme?.palette ?? BoardPalette(dark: true);
  }

  @override
  bool updateShouldNotify(BoardTheme oldWidget) => oldWidget.dark != dark;
}

/// Flat Material shell: hairlines and background steps carry separation, so elevation stays 0.
ThemeData boardThemeData(BoardPalette palette) {
  final TextTheme text = palette.text;
  return ThemeData(
    useMaterial3: true,
    brightness: palette.dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: palette.bg,
    canvasColor: palette.bg,
    textTheme: text,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.primary,
      brightness: palette.dark ? Brightness.dark : Brightness.light,
      surface: palette.card,
      error: palette.danger,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: palette.pressed,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.card,
      foregroundColor: palette.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleMedium,
    ),
    cardTheme: CardThemeData(
      color: palette.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: palette.hairline),
        borderRadius: BorderRadius.circular(BoardTokens.radius),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: palette.hairline,
      thickness: 1,
      space: 1,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.primary
            : palette.sunken,
      ),
      side: BorderSide(color: palette.border),
      shape: const RoundedRectangleBorder(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.fgInverted
            : palette.fgMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.primary
            : palette.sunken,
      ),
      trackOutlineColor: WidgetStatePropertyAll<Color>(palette.border),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.fg,
        backgroundColor: palette.raised,
        padding: const EdgeInsets.symmetric(horizontal: BoardTokens.gap),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: palette.border),
          borderRadius: BorderRadius.circular(BoardTokens.radius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.fg,
        side: BorderSide(color: palette.border),
        padding: const EdgeInsets.symmetric(horizontal: BoardTokens.gap),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: palette.sunken,
      hintStyle: text.bodySmall?.copyWith(color: palette.fgFaint),
      labelStyle: text.bodySmall,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: palette.border),
        borderRadius: BorderRadius.circular(BoardTokens.radius),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: palette.border),
        borderRadius: BorderRadius.circular(BoardTokens.radius),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: palette.primary),
        borderRadius: BorderRadius.circular(BoardTokens.radius),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: palette.fg,
      unselectedLabelColor: palette.fgMuted,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelStyle: text.titleSmall,
      unselectedLabelStyle: text.titleSmall,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.raised,
        border: Border.all(color: palette.border),
      ),
      textStyle: text.bodySmall,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.card,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: palette.border),
        borderRadius: BorderRadius.circular(BoardTokens.radius),
      ),
      textStyle: text.bodyMedium,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: palette.border),
        borderRadius: BorderRadius.circular(BoardTokens.radius),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: palette.primary),
  );
}
