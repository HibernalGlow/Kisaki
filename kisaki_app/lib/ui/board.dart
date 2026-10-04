import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/board_step.dart';
import '../state/card_layout.dart';
import '../theme/board_theme.dart';
import 'board_blocks.dart';
import 'card_stack.dart';
import 'filter_panel.dart';
import 'header_bar.dart';
import 'lane.dart';
import 'overlays.dart';
import 'results_panel.dart';
import 'token_list.dart' show PathPicker;
import 'widgets/primitives.dart';

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
    if (modifier && event.logicalKey == LogicalKeyboardKey.keyR) {
      widget.controller.refreshScan();
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
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double width = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : BoardTokens.minWindowWidth;
                    return _Lanes(
                      controller: widget.controller,
                      picker: widget.picker,
                      available: width,
                    );
                  },
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

    final String? solo = layout.soloLane;

    // Derived per build: exactly one lane carries the accent rule, and which one it is comes from
    // the scan state rather than from anything the layout stores.
    final BoardStep step = currentBoardStep(controller);

    // Every lane header carries the reference's two lane controls: how its blocks are arranged, and
    // whether the lane takes the whole board.
    List<Widget> laneActions(String id, {CardPanel? panel}) => <Widget>[
      if (panel != null)
        CardDisplayToggle(controller: controller, panel: panel),
      if (panel == CardPanel.analysis)
        BoardAction(
          key: const Key('cards-manage'),
          labelKey: 'cards-manage',
          icon: Icons.view_day_outlined,
          dense: true,
          iconOnly: true,
          onPressed: () => CardManagerDialog.open(context, controller),
        ),
      BoardAction(
        key: Key('lane-solo-$id'),
        labelKey: solo == id ? 'lane-unsolo' : 'lane-solo',
        icon: solo == id
            ? Icons.filter_alt_off_rounded
            : Icons.filter_alt_rounded,
        dense: true,
        iconOnly: true,
        onPressed: () => controller.toggleSoloLane(id),
      ),
    ];

    Lane sourceLane({double? width}) => Lane(
      titleKey: 'lane-source',
      letter: 'S',
      step: BoardStep.source.number,
      active: step == BoardStep.source,
      collapsed: layout.sourceCollapsed,
      onToggle: () => controller.toggleLane('source'),
      actions: laneActions('source', panel: CardPanel.source),
      width: width,
      child: CardStack(
        controller: controller,
        panel: CardPanel.source,
        renderCard: (BuildContext context, CardId id) =>
            boardCard(controller: controller, id: id, picker: picker),
      ),
    );

    Lane resultsLane({double? width}) => Lane(
      titleKey: 'lane-results',
      letter: 'R',
      step: BoardStep.results.number,
      active: step == BoardStep.results,
      collapsed: layout.resultsCollapsed,
      onToggle: () => controller.toggleLane('results'),
      actions: laneActions('results'),
      width: width,
      child: ResultsPanel(controller: controller),
    );

    Lane analysisLane({double? width}) => Lane(
      titleKey: 'lane-analysis',
      letter: 'A',
      step: BoardStep.analysis.number,
      active: step == BoardStep.analysis,
      collapsed: layout.analysisCollapsed,
      onToggle: () => controller.toggleLane('analysis'),
      actions: laneActions('analysis', panel: CardPanel.analysis),
      width: width,
      child: CardStack(
        controller: controller,
        panel: CardPanel.analysis,
        renderCard: (BuildContext context, CardId id) =>
            boardCard(controller: controller, id: id, picker: picker),
      ),
    );

    // The last lane in the reader's order takes whatever is left; the two before it keep their own
    // width, with a handle between a lane and the next.
    final List<String> order = normalizeLaneOrder(layout.laneOrder);
    final double analysisLaneWidth = layout.analysisCollapsed
        ? BoardTokens.laneCollapsedWidth
        : layout.analysisWidth.clamp(
            BoardTokens.resultsLaneMin,
            BoardTokens.resultsLaneMax,
          );

    Widget slotAt(int index, {required bool flexed}) {
      final String id = order[index];
      final double? width = flexed
          ? null
          : switch (id) {
              // A board too narrow for the reader's widths holds every fixed lane at its minimum, so
              // the flexed lane is never asked to absorb a negative remainder.
              'source' => fits ? sourceWidth : BoardTokens.sourceLaneMin,
              'results' => fits ? resultsWidth : BoardTokens.resultsLaneMin,
              _ => fits ? analysisLaneWidth : BoardTokens.resultsLaneMin,
            };
      return switch (id) {
        'source' => sourceLane(width: width),
        'results' => resultsLane(width: width),
        _ => analysisLane(width: width),
      };
    }

    List<Widget> handleAfter(int index) {
      final String id = order[index];
      final bool collapsed = switch (id) {
        'source' => layout.sourceCollapsed,
        'results' => layout.resultsCollapsed,
        _ => layout.analysisCollapsed,
      };
      if (collapsed) {
        return const <Widget>[];
      }
      final Widget handle = switch (id) {
        'source' => LaneDragHandle(
          read: () => controller.layout.sourceWidth,
          apply: controller.setSourceWidth,
          resetTo: LaneLayout.sourceDefault,
          minWidth: BoardTokens.sourceLaneMin,
          maxWidth: BoardTokens.sourceLaneMax,
        ),
        'results' => LaneDragHandle(
          read: () => controller.layout.resultsWidth,
          apply: controller.setResultsWidth,
          resetTo: LaneLayout.resultsDefault,
          minWidth: BoardTokens.resultsLaneMin,
          maxWidth: BoardTokens.resultsLaneMax,
        ),
        _ => LaneDragHandle(
          read: () => controller.layout.analysisWidth,
          apply: controller.setAnalysisWidth,
          resetTo: LaneLayout.analysisDefault,
          minWidth: BoardTokens.resultsLaneMin,
          maxWidth: BoardTokens.resultsLaneMax,
        ),
      };
      return <Widget>[
        const SizedBox(width: _handleWidth),
        handle,
        const SizedBox(width: _handleWidth),
      ];
    }

    if (solo != null) {
      // One lane holds the whole board, and the other two leave it entirely.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: slotAt(order.indexOf(solo), flexed: true)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        slotAt(0, flexed: false),
        ...handleAfter(0),
        slotAt(1, flexed: false),
        ...handleAfter(1),
        Expanded(child: slotAt(2, flexed: true)),
      ],
    );
  }
}
