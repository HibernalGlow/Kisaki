import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';
import 'analysis_panel.dart';
import 'filter_panel.dart';
import 'header_bar.dart';
import 'lane.dart';
import 'overlays.dart';
import 'results_panel.dart';
import 'source_panel.dart';
import 'token_list.dart' show PathPicker;

/// Application shell: Swiss flat palette plus the board, driven only by [controller].
class KisakiBoardApp extends StatefulWidget {
  const KisakiBoardApp({required this.controller, this.picker, super.key});

  final BoardController controller;
  final PathPicker? picker;

  @override
  State<KisakiBoardApp> createState() => _KisakiBoardAppState();
}

class _KisakiBoardAppState extends State<KisakiBoardApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(KisakiBoardApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardPalette(dark: widget.controller.dark);
    return BoardTheme(
      key: ValueKey<bool>(palette.dark),
      dark: palette.dark,
      child: MaterialApp(
        title: Labels.of('app-title'),
        debugShowCheckedModeBanner: false,
        theme: boardThemeData(palette),
        home: KisakiBoard(controller: widget.controller, picker: widget.picker),
      ),
    );
  }
}

class KisakiBoard extends StatefulWidget {
  const KisakiBoard({required this.controller, this.picker, super.key});

  final BoardController controller;
  final PathPicker? picker;

  @override
  State<KisakiBoard> createState() => _KisakiBoardState();
}

class _KisakiBoardState extends State<KisakiBoard> {
  bool _confirmOpen = false;

  /// The board takes the keyboard on purpose: a shortcut that only worked after the first click
  /// would leave the app mouse-only on launch.
  final FocusNode _keys = FocusNode(debugLabel: 'kisaki-keys');

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (widget.controller.confirm != null && !_confirmOpen) {
      _confirmOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) async {
        if (!mounted) {
          return;
        }
        await KisakiOverlays.showConfirm(context, widget.controller);
        if (mounted) {
          _confirmOpen = false;
        }
      });
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(KisakiBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _keys.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final bool modifier =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (modifier && event.logicalKey == LogicalKeyboardKey.keyF) {
      FilterPanel.open(context, widget.controller);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        widget.controller.filters.activeCount > 0) {
      widget.controller.resetFilters();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final BoardController controller = widget.controller;
    final BoardPalette palette = BoardTheme.of(context);
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: palette.bg,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            HeaderBar(controller: controller),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(BoardTokens.gap),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) =>
                      _Lanes(
                        controller: controller,
                        picker: widget.picker,
                        available: constraints.maxWidth.isFinite
                            ? constraints.maxWidth
                            : BoardTokens.minWindowWidth,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Source and results lanes keep their own width; analysis takes whatever is left.
class _Lanes extends StatelessWidget {
  const _Lanes({
    required this.controller,
    required this.picker,
    required this.available,
  });

  final BoardController controller;
  final PathPicker? picker;
  final double available;

  static const double _handleWidth = BoardTokens.gap;

  @override
  Widget build(BuildContext context) {
    final LaneLayout layout = controller.layout;
    final double sourceWidth = layout.sourceCollapsed
        ? BoardTokens.laneCollapsedWidth
        : layout.sourceWidth.clamp(
            BoardTokens.sourceLaneMin,
            BoardTokens.sourceLaneMax,
          );
    final double resultsWidth = layout.resultsCollapsed
        ? BoardTokens.laneCollapsedWidth
        : layout.resultsWidth.clamp(
            BoardTokens.resultsLaneMin,
            BoardTokens.resultsLaneMax,
          );
    final double reserved =
        sourceWidth + resultsWidth + _handleWidth * 2 + BoardTokens.gap * 2;
    final bool fits = reserved + 220 <= available;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Lane(
          titleKey: 'lane-source',
          letter: 'S',
          collapsed: layout.sourceCollapsed,
          onToggle: () => controller.toggleLane('source'),
          width: fits ? sourceWidth : BoardTokens.sourceLaneMin,
          child: SourcePanel(controller: controller, picker: picker),
        ),
        if (!layout.sourceCollapsed) ...<Widget>[
          const SizedBox(width: _handleWidth),
          LaneDragHandle(
            read: () => controller.layout.sourceWidth,
            apply: controller.setSourceWidth,
            resetTo: LaneLayout.sourceDefault,
            minWidth: BoardTokens.sourceLaneMin,
            maxWidth: BoardTokens.sourceLaneMax,
          ),
          const SizedBox(width: _handleWidth),
        ],
        Lane(
          titleKey: 'lane-results',
          letter: 'R',
          collapsed: layout.resultsCollapsed,
          onToggle: () => controller.toggleLane('results'),
          width: fits ? resultsWidth : BoardTokens.resultsLaneMin,
          child: ResultsPanel(controller: controller),
        ),
        if (!layout.resultsCollapsed) ...<Widget>[
          const SizedBox(width: _handleWidth),
          LaneDragHandle(
            read: () => controller.layout.resultsWidth,
            apply: controller.setResultsWidth,
            resetTo: LaneLayout.resultsDefault,
            minWidth: BoardTokens.resultsLaneMin,
            maxWidth: BoardTokens.resultsLaneMax,
          ),
          const SizedBox(width: _handleWidth),
        ],
        Expanded(
          child: Lane(
            titleKey: 'lane-analysis',
            letter: 'A',
            collapsed: layout.analysisCollapsed,
            onToggle: () => controller.toggleLane('analysis'),
            child: AnalysisPanel(controller: controller),
          ),
        ),
      ],
    );
  }
}
