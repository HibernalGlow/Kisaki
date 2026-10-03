import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';
import 'comparison_images.dart';
import 'widgets/primitives.dart';

/// Single-picture preview, from `nodes/shared/LocalImagePreviewDialog.tsx`.
///
/// The reference also prints an EXIF field grid under the picture; the scan result carries no
/// metadata, so the dialog shows what Kisaki actually knows: the name, the path and its position in
/// the rows on screen.
class PreviewView extends StatelessWidget {
  const PreviewView({required this.controller, super.key});

  final BoardController controller;

  static Future<void> open(
    BuildContext context,
    BoardController controller,
    String path,
  ) {
    controller.openPreview(path);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => PreviewView(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final String path = controller.previewPath;
        if (path.isEmpty) {
          return const SizedBox.shrink();
        }
        final List<String> paths = controller.previewPaths;
        final int index = paths.indexOf(path);
        final Size viewport = MediaQuery.sizeOf(context);
        final double side = (viewport.shortestSide * 0.6).clamp(240.0, 640.0);
        return Focus(
          autofocus: true,
          onKeyEvent: (FocusNode node, KeyEvent event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            return switch (event.logicalKey) {
              LogicalKeyboardKey.arrowLeft => _step(context, -1),
              LogicalKeyboardKey.arrowRight => _step(context, 1),
              _ => KeyEventResult.ignored,
            };
          },
          child: PopScope(
            onPopInvokedWithResult: (bool didPop, Object? result) {
              if (didPop) {
                controller.closePreview();
              }
            },
            child: AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(Labels.of('preview-title')),
                  const SizedBox(height: BoardTokens.gapSmall),
                  Text(
                    path,
                    style: palette.tableFigure(color: palette.fgMuted),
                  ),
                ],
              ),
              content: SizedBox(
                width: side,
                height: side,
                child: DiskImage(
                  key: Key('preview-image-$path'),
                  path: path,
                  fit: BoxFit.contain,
                  placeholder: Center(
                    child: Text(
                      Labels.of('preview-loading'),
                      style: palette.text.bodySmall,
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                BoardAction(
                  key: const Key('preview-prev'),
                  labelKey: 'preview-prev',
                  icon: Icons.arrow_back_rounded,
                  dense: true,
                  onPressed: index <= 0
                      ? null
                      : () => controller.stepPreview(-1),
                ),
                Text(
                  '${index + 1} / ${paths.length}',
                  key: const Key('preview-index'),
                  style: palette.tableFigure(color: palette.fgMuted),
                ),
                BoardAction(
                  key: const Key('preview-next'),
                  labelKey: 'preview-next',
                  icon: Icons.arrow_forward_rounded,
                  dense: true,
                  onPressed: index < 0 || index >= paths.length - 1
                      ? null
                      : () => controller.stepPreview(1),
                ),
                BoardAction(
                  key: const Key('preview-close'),
                  labelKey: 'action-close',
                  dense: true,
                  onPressed: () {
                    controller.closePreview();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  KeyEventResult _step(BuildContext context, int delta) {
    controller.stepPreview(delta);
    return KeyEventResult.handled;
  }
}
