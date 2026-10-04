import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';
import 'overlays.dart';
import 'widgets/primitives.dart';

class HeaderBar extends StatelessWidget {
  const HeaderBar({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Container(
      height: BoardTokens.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: BoardTokens.pad),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            Labels.of('app-title'),
            style: TextStyle(
              fontSize: BoardTokens.fsTitle,
              fontWeight: FontWeight.w700,
              color: palette.fg,
            ),
          ),
          const SizedBox(width: BoardTokens.gap * 2),
          Flexible(child: _ScannerPicker(controller: controller)),
          const SizedBox(width: BoardTokens.gap),
          Flexible(child: _ScanControl(controller: controller)),
          const SizedBox(width: BoardTokens.gap * 2),
          Expanded(child: _ProgressRail(controller: controller)),
          const SizedBox(width: BoardTokens.gap),
          Flexible(
            child: BoardAction(
              labelKey: 'action-theme',
              icon: controller.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              dense: true,
              onPressed: controller.toggleTheme,
            ),
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          Flexible(
            child: BoardAction(
              key: const Key('floating-analysis-toggle'),
              labelKey: controller.floatingAnalysisOpen
                  ? 'action-float-analysis-close'
                  : 'action-float-analysis-open',
              icon: Icons.style_outlined,
              dense: true,
              iconOnly: true,
              onPressed: controller.floatingAnalysisAvailable
                  ? controller.toggleFloatingPanel
                  : null,
            ),
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          Flexible(
            child: BoardAction(
              labelKey: 'action-reset-layout',
              icon: Icons.restart_alt_rounded,
              dense: true,
              onPressed: controller.resetLayout,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerPicker extends StatelessWidget {
  const _ScannerPicker({required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final String label = controller.tool == null
        ? Labels.of('tool-selector')
        : Labels.of(controller.tool!.labelKey);
    return GestureDetector(
      key: const Key('scanner-picker'),
      onTap: () => KisakiOverlays.openToolMenu(context, controller),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BoardTokens.gap,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(BoardTokens.radius),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (controller.tool != null)
              GlyphTile(glyph: controller.tool!.glyph, size: 18),
            const SizedBox(width: BoardTokens.gapSmall),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: BoardTokens.fsLabel,
                  fontWeight: FontWeight.w600,
                  color: palette.fg,
                ),
              ),
            ),
            const SizedBox(width: BoardTokens.gapSmall),
            Icon(Icons.expand_more_rounded, size: 14, color: palette.fgMuted),
          ],
        ),
      ),
    );
  }
}

class _ScanControl extends StatelessWidget {
  const _ScanControl({required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final bool running = controller.scanning;
    return GestureDetector(
      key: const Key('scan-control'),
      onTap: running ? controller.stopScan : () => controller.startScan(),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BoardTokens.gap * 1.5,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: running ? palette.dangerSoft : palette.primary,
          borderRadius: BorderRadius.circular(BoardTokens.radius),
          border: Border.all(color: running ? palette.danger : palette.primary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                Labels.of(running ? 'action-stop' : 'action-scan'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: BoardTokens.fsLabel,
                  fontWeight: FontWeight.w700,
                  color: running ? palette.danger : palette.fgInverted,
                ),
              ),
            ),
            if (running) ...<Widget>[
              const SizedBox(width: BoardTokens.gapSmall),
              Icon(Icons.stop_rounded, size: 13, color: palette.danger),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressRail extends StatelessWidget {
  const _ProgressRail({required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final double? value = controller.progressValue;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          controller.statusText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: BoardTokens.fsLabel,
            color: palette.fgMuted,
          ),
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        SizedBox(
          height: 4,
          child: value == null && !controller.scanning
              ? ColoredBox(color: palette.hairline)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(BoardTokens.radius),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    backgroundColor: palette.hairline,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      controller.phase == ScanPhase.failed
                          ? palette.danger
                          : palette.primary,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
