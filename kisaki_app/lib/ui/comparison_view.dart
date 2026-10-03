import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/image_comparison.dart';
import '../theme/board_theme.dart';
import 'comparison_images.dart';
import 'widgets/primitives.dart';

export 'comparison_images.dart'
    show comparisonImageLoader, imageDestRect, loadFileImage;

/// The image comparison dialog from `czkawka/image-comparison-dialog.tsx`.
///
/// Previews come off the file system rather than the bridge, so the dialog only needs the two paths
/// the group already gives it.
class ComparisonView extends StatelessWidget {
  const ComparisonView({required this.controller, super.key});

  final BoardController controller;

  static Future<void> open(
    BuildContext context,
    BoardController controller,
    ScanRow row,
  ) {
    controller.openComparison(row);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => ComparisonView(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final ComparisonState state = controller.comparison;
        final ComparisonEntries entries = controller.comparisonSelection;
        final ScanRow? active = entries.active;
        final Size viewport = MediaQuery.sizeOf(context);
        return PopScope(
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (didPop) {
              controller.closeComparison();
            }
          },
          child: AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(Labels.of('comparison-title')),
                const SizedBox(height: BoardTokens.gapSmall),
                Text(
                  active?.path ?? '',
                  style: palette.tableFigure(color: palette.fgMuted),
                ),
              ],
            ),
            content: SizedBox(
              width: (viewport.width * 0.96).clamp(360.0, 1240.0),
              height: (viewport.height * 0.9).clamp(320.0, 880.0),
              child: active == null
                  ? const ComparisonMissingImage(path: null)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _Toolbar(
                                state: state,
                                canCompare: entries.canCompare,
                                controller: controller,
                              ),
                            ),
                            BoardAction(
                              key: const Key('comparison-close'),
                              labelKey: 'comparison-close',
                              dense: true,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: BoardTokens.gap),
                        if (entries.group.length > 1)
                          _TargetStrip(
                            entries: entries,
                            controller: controller,
                          ),
                        const SizedBox(height: BoardTokens.gap),
                        Expanded(
                          child: _Stage(
                            state: state,
                            entries: entries,
                            controller: controller,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.canCompare,
    required this.controller,
  });

  final ComparisonState state;
  final bool canCompare;
  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Wrap(
      spacing: BoardTokens.gapSmall,
      runSpacing: BoardTokens.gapSmall,
      children: <Widget>[
        for (final ComparisonMode mode in ComparisonMode.values)
          BoardAction(
            key: Key('comparison-mode-${mode.wire}'),
            labelKey: 'comparison-${mode.wire}',
            dense: true,
            tone: state.mode == mode ? palette.primary : null,
            onPressed: mode == ComparisonMode.single || canCompare
                ? () => controller.setComparisonMode(mode)
                : null,
          ),
        BoardAction(
          key: const Key('comparison-color-coding'),
          labelKey: 'comparison-color-coding',
          dense: true,
          tone: state.colorCoding ? palette.primary : null,
          onPressed: canCompare ? controller.toggleComparisonColorCoding : null,
        ),
      ],
    );
  }
}

class _TargetStrip extends StatelessWidget {
  const _TargetStrip({required this.entries, required this.controller});

  final ComparisonEntries entries;
  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final List<ScanRow> others = entries.group
        .where((ScanRow row) => row.path != entries.active?.path)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MicroHeading(Labels.of('comparison-targets')),
        const SizedBox(height: BoardTokens.gapSmall),
        Wrap(
          spacing: BoardTokens.gapSmall,
          runSpacing: BoardTokens.gapSmall,
          children: <Widget>[
            for (final ScanRow row in others)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: Key('comparison-target-${row.path}'),
                  onTap: () => controller.setComparisonTarget(row.path),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: row.path == entries.target?.path
                            ? palette.primary
                            : palette.border,
                        width: row.path == entries.target?.path ? 2 : 1,
                      ),
                      color: palette.sunken,
                    ),
                    child: ComparisonFileImage(
                      path: row.path,
                      fit: BoxFit.cover,
                      placeholder: const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.state,
    required this.entries,
    required this.controller,
  });

  final ComparisonState state;
  final ComparisonEntries entries;
  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final ScanRow active = entries.active!;
    final ScanRow? target = entries.target;
    if (target == null || state.mode == ComparisonMode.single) {
      return ComparisonImagePane(entry: active, labelKey: 'comparison-source');
    }
    if (state.mode == ComparisonMode.sideBySide) {
      return Row(
        children: <Widget>[
          Expanded(
            child: ComparisonImagePane(
              entry: active,
              labelKey: 'comparison-source',
            ),
          ),
          const SizedBox(width: BoardTokens.gap),
          Expanded(
            child: ComparisonImagePane(
              entry: target,
              labelKey: 'comparison-target',
            ),
          ),
        ],
      );
    }
    if (state.mode == ComparisonMode.swipe) {
      return _SwipeStage(
        state: state,
        active: active,
        target: target,
        controller: controller,
      );
    }
    return _OnionStage(
      state: state,
      active: active,
      target: target,
      controller: controller,
    );
  }
}

class _SwipeStage extends StatelessWidget {
  const _SwipeStage({
    required this.state,
    required this.active,
    required this.target,
    required this.controller,
  });

  final ComparisonState state;
  final ScanRow active;
  final ScanRow target;
  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final double fraction = state.swipePercent / 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              return GestureDetector(
                key: const Key('comparison-swipe-stage'),
                onTapDown: (TapDownDetails details) => controller
                    .setComparisonSwipe(details.localPosition.dx / width * 100),
                onHorizontalDragUpdate: (DragUpdateDetails details) =>
                    controller.setComparisonSwipe(
                      details.localPosition.dx / width * 100,
                    ),
                child: ColoredBox(
                  color: palette.sunken,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ComparisonLayer(
                        path: target.path,
                        fraction: 1,
                        colorCoding: false,
                      ),
                      ComparisonLayer(
                        path: active.path,
                        fraction: fraction,
                        colorCoding: state.colorCoding,
                      ),
                      Positioned(
                        left: (width * fraction - 1).clamp(0.0, width),
                        top: 0,
                        bottom: 0,
                        child: ColoredBox(
                          color: palette.primary,
                          child: const SizedBox(width: 2),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: BoardTokens.gap),
        _Ruler(
          labelKey: 'comparison-swipe-position',
          value: state.swipePercent,
          onChanged: controller.setComparisonSwipe,
        ),
      ],
    );
  }
}

class _OnionStage extends StatelessWidget {
  const _OnionStage({
    required this.state,
    required this.active,
    required this.target,
    required this.controller,
  });

  final ComparisonState state;
  final ScanRow active;
  final ScanRow target;
  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ColoredBox(
            color: palette.sunken,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ComparisonLayer(
                  path: target.path,
                  fraction: 1,
                  colorCoding: false,
                ),
                ComparisonLayer(
                  path: active.path,
                  fraction: 1,
                  colorCoding: state.colorCoding,
                  opacity: state.onionOpacity / 100,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: BoardTokens.gap),
        _Ruler(
          labelKey: 'comparison-onion-opacity',
          value: state.onionOpacity,
          onChanged: controller.setComparisonOpacity,
        ),
      ],
    );
  }
}

class _Ruler extends StatelessWidget {
  const _Ruler({
    required this.labelKey,
    required this.value,
    required this.onChanged,
  });

  final String labelKey;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Row(
      children: <Widget>[
        SizedBox(
          width: BoardTokens.fieldWidth,
          child: MicroHeading(Labels.of(labelKey)),
        ),
        Expanded(
          child: Slider(
            key: Key('$labelKey-slider'),
            value: value,
            max: 100,
            min: 0,
            divisions: 100,
            label: '${value.round()}%',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '${value.round()}%',
            textAlign: TextAlign.right,
            style: palette.tableFigure(),
          ),
        ),
      ],
    );
  }
}
