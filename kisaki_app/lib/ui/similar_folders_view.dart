import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/similar_folders.dart';
import '../theme/board_theme.dart';
import '../util/format.dart';
import 'comparison_images.dart';
import 'widgets/primitives.dart';

/// The image scanner's folder roll-up, from `czkawka/similar-folders-view.tsx`.
///
/// Copy, open and reveal are listed on every row the way the reference lists them: open and reveal
/// are disabled when the embedding host has no callback, so the reader sees the action and why it is
/// dark instead of never learning it exists.
class SimilarFoldersView extends StatelessWidget {
  const SimilarFoldersView({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final List<FolderStat> folders = controller.similarFolders;
        if (folders.isEmpty) {
          return Center(
            child: Text(
              Labels.of('folders-empty'),
              key: const Key('folders-empty'),
              style: palette.text.bodySmall,
            ),
          );
        }
        return ListView.separated(
          key: const Key('folders-list'),
          padding: EdgeInsets.zero,
          itemCount: folders.length,
          separatorBuilder: (BuildContext context, int index) =>
              const Hairline(),
          itemBuilder: (BuildContext context, int index) =>
              _FolderRow(controller: controller, stat: folders[index]),
        );
      },
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.controller, required this.stat});

  final BoardController controller;
  final FolderStat stat;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    // Height comes from the content, not a fixed 64: the badges wrap when the middle lane is narrow,
    // and a fixed box would push the second line out of view.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BoardTokens.pad,
        vertical: BoardTokens.gapSmall,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 48,
            height: 48,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: palette.border),
                color: palette.sunken,
              ),
              child: DiskImage(
                path: stat.previewPath ?? stat.path,
                fit: BoxFit.cover,
                placeholder: const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(width: BoardTokens.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  stat.path,
                  key: Key('folder-path-${stat.path}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: palette.text.bodyMedium,
                ),
                const SizedBox(height: BoardTokens.gapSmall),
                Wrap(
                  spacing: BoardTokens.gapSmall,
                  children: <Widget>[
                    _Badge(
                      text: Labels.of(
                        'folders-images',
                        args: <String, Object>{'count': stat.count},
                      ),
                      filled: true,
                    ),
                    _Badge(
                      text: Labels.of(
                        'folders-groups',
                        args: <String, Object>{'count': stat.groupCount},
                      ),
                    ),
                    _Badge(text: humanBytes(stat.bytes)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: BoardTokens.gap),
          BoardAction(
            key: Key('folder-copy-${stat.path}'),
            labelKey: 'action-copy-path',
            dense: true,
            onPressed: () => controller.copyText(stat.path),
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          BoardAction(
            key: Key('folder-open-${stat.path}'),
            labelKey: 'folders-open',
            labelArgs: <String, Object>{'path': stat.path},
            icon: Icons.open_in_new,
            iconOnly: true,
            onPressed: controller.canOpenFiles
                ? () => controller.openPath(stat.path)
                : null,
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          BoardAction(
            key: Key('folder-reveal-${stat.path}'),
            labelKey: 'folders-reveal',
            labelArgs: <String, Object>{'path': stat.path},
            icon: Icons.folder_open_outlined,
            iconOnly: true,
            onPressed: controller.canRevealFiles
                ? () => controller.revealPath(stat.path)
                : null,
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.filled = false});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BoardTokens.gapSmall,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: filled ? palette.selection : Colors.transparent,
        border: Border.all(color: palette.border),
      ),
      child: Text(
        text,
        style: palette.tableFigure(
          color: filled ? palette.fg : palette.fgMuted,
        ),
      ),
    );
  }
}

/// Images or folders, with the folder count in the tab so the roll-up is never a blind switch.
class FoldersViewSwitch extends StatelessWidget {
  const FoldersViewSwitch({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BoardTokens.pad,
            vertical: BoardTokens.gapSmall,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: BoardAction(
                  key: const Key('view-images'),
                  labelKey: 'views-images',
                  dense: true,
                  tone: controller.folderView ? null : palette.primary,
                  onPressed: () => controller.setFolderView(false),
                ),
              ),
              const SizedBox(width: BoardTokens.gapSmall),
              Expanded(
                child: BoardAction(
                  key: const Key('view-folders'),
                  labelKey: 'views-folders',
                  dense: true,
                  tone: controller.folderView ? palette.primary : null,
                  onPressed: () => controller.setFolderView(true),
                ),
              ),
              const SizedBox(width: BoardTokens.gapSmall),
              Text(
                '${controller.similarFolders.length}',
                key: const Key('folders-count'),
                style: palette.tableFigure(color: palette.fgMuted),
              ),
              const SizedBox(width: BoardTokens.gapSmall),
              Expanded(
                child: Text(
                  Labels.of('folders-summary'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: palette.text.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
