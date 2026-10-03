import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';
import 'comparison_images.dart';
import 'widgets/primitives.dart';

/// The docked preview beside the table, from `nodes/shared/LocalMediaPreviewPanel.tsx`.
///
/// The reference also plays video and audio in this slot. Kisaki has no media player and the project
/// rule keeps non-Rust dependencies out, so the panel previews pictures and says so for the rest.
class PreviewPanel extends StatelessWidget {
  const PreviewPanel({required this.controller, super.key});

  final BoardController controller;

  static const double width = 288;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final String path = controller.previewPath;
        final List<String> paths = controller.previewPaths;
        if (!controller.previewPanelOpen || !paths.contains(path)) {
          return const SizedBox.shrink();
        }
        final int index = paths.indexOf(path);
        return Container(
          key: const Key('preview-panel'),
          width: width,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: palette.hairline)),
          ),
          padding: const EdgeInsets.all(BoardTokens.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          Labels.of(
                            'preview-panel-title',
                            args: <String, Object>{'name': _nameOf(path)},
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: BoardTokens.fsLabel,
                            fontWeight: FontWeight.w700,
                            color: palette.fg,
                          ),
                        ),
                        Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: palette.text.bodySmall?.copyWith(
                            color: palette.fgFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BoardAction(
                    key: const Key('preview-panel-close'),
                    labelKey: 'preview-panel-unpin',
                    dense: true,
                    onPressed: controller.togglePinnedPreview,
                  ),
                ],
              ),
              const SizedBox(height: BoardTokens.gap),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: palette.border),
                    color: palette.sunken,
                  ),
                  child: DiskImage(
                    key: Key('preview-panel-image-$path'),
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
              ),
              const SizedBox(height: BoardTokens.gapSmall),
              Row(
                children: <Widget>[
                  Expanded(
                    child: BoardAction(
                      key: const Key('preview-panel-prev'),
                      labelKey: 'preview-prev',
                      dense: true,
                      onPressed: index <= 0
                          ? null
                          : () => controller.stepPreview(-1),
                    ),
                  ),
                  const SizedBox(width: BoardTokens.gapSmall),
                  Expanded(
                    child: BoardAction(
                      key: const Key('preview-panel-next'),
                      labelKey: 'preview-next',
                      dense: true,
                      onPressed: index >= paths.length - 1
                          ? null
                          : () => controller.stepPreview(1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BoardTokens.gapSmall),
              Text(
                Labels.of(
                  'preview-position',
                  args: <String, Object>{
                    'index': index + 1,
                    'total': paths.length,
                  },
                ),
                key: const Key('preview-panel-position'),
                style: palette.tableFigure(color: palette.fgMuted),
              ),
            ],
          ),
        );
      },
    );
  }

  String _nameOf(String path) {
    final int slash = path.replaceAll(r'\', '/').lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
