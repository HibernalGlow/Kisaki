import 'package:flutter/material.dart';

import '../engine/models.dart' show ExifItem, ExifStatus;
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// EXIF cleanup for the remover tool, from `czkawka/views/CzkawkaCardsView.tsx`.
///
/// The reference counts the tags of every selected file while it builds the plan; Kisaki asks the
/// engine, which reads the metadata itself and answers with a per-file count, so the preview here
/// lists the files and the counts appear in the result once the run reported them.
class ExifCard extends StatelessWidget {
  const ExifCard({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final int selected = controller.selectedCount;
    final List<ExifItem> items = controller.exifOutcome?.items ?? const [];
    return SectionCard(
      title: Labels.of('exif-card-title'),
      children: <Widget>[
        Text(Labels.of('exif-card-hint'), style: palette.text.bodySmall),
        const SizedBox(height: BoardTokens.gap),
        ToggleRow(
          key: const Key('exif-override'),
          labelKey: 'exif-override-label',
          value: controller.exifOverrideFile,
          onChanged: controller.setExifOverrideFile,
          hint: Labels.of('exif-override-hint'),
        ),
        const SizedBox(height: BoardTokens.gap),
        Row(
          children: <Widget>[
            Expanded(
              child: BoardAction(
                key: const Key('exif-clean'),
                labelKey: 'exif-action-clean',
                icon: Icons.layers_clear_outlined,
                tone: selected == 0 ? null : palette.primary,
                onPressed: selected == 0 || controller.actionRunning
                    ? null
                    : controller.requestCleanExif,
              ),
            ),
            const SizedBox(width: BoardTokens.gapSmall),
            Text(
              '$selected',
              key: const Key('exif-selected-count'),
              style: palette.tableFigure(color: palette.fgMuted),
            ),
          ],
        ),
        if (items.isNotEmpty) ...<Widget>[
          const SizedBox(height: BoardTokens.gap),
          for (final ExifItem item in items.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: palette.text.bodySmall,
                  ),
                  Text(
                    _outcomeText(item),
                    style: palette.text.bodySmall?.copyWith(
                      color: item.status == ExifStatus.failed
                          ? palette.danger
                          : palette.fgFaint,
                    ),
                  ),
                ],
              ),
            ),
          if (controller.exifOutcome != null)
            Text(
              Labels.of(
                'exif-summary',
                args: <String, Object>{
                  'stripped': controller.exifOutcome!.stripped,
                  'candidates': controller.exifOutcome!.candidates,
                  'skipped': controller.exifOutcome!.skipped,
                  'planned': controller.exifOutcome!.planned,
                },
              ),
              key: const Key('exif-summary'),
              style: palette.tableFigure(),
            ),
        ],
      ],
    );
  }

  String _outcomeText(ExifItem item) {
    if (item.status == ExifStatus.failed) {
      return '${Labels.of('exif-result-failed')} ${item.detail}';
    }
    if (item.tagsRemoved == 0 && item.status != ExifStatus.planned) {
      return Labels.of('exif-result-skipped');
    }
    final String state = switch (item.status) {
      ExifStatus.stripped => 'exif-result-stripped',
      ExifStatus.candidate => 'exif-result-candidate',
      ExifStatus.planned => 'exif-result-planned',
      ExifStatus.skipped => 'exif-result-skipped',
      ExifStatus.failed => 'exif-result-failed',
    };
    return '${Labels.of(state)} - '
        '${Labels.of('exif-result-count', args: <String, Object>{'count': item.tagsRemoved})}';
  }
}
