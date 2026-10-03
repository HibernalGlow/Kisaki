import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/group_organize.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// Sorting similar groups into per-source folders, from `czkawka/views/CzkawkaCardsView.tsx`.
///
/// The reference shows the plan only inside its confirm dialog; Kisaki paints it in the lane because
/// the template field changes it while it is typed.
class OrganizeCard extends StatelessWidget {
  const OrganizeCard({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final OrganizePlan plan = controller.organizePlan;
    final List<OrganizeItem> preview = plan.items.take(8).toList();

    return SectionCard(
      title: Labels.of('organize-card-title'),
      children: <Widget>[
        Text(Labels.of('organize-card-hint'), style: palette.text.bodySmall),
        const SizedBox(height: BoardTokens.gap),
        BoardField(
          key: const Key('organize-template'),
          labelKey: 'organize-template-label',
          value: controller.organize.subfolderTemplate,
          onChanged: (String text) => controller.updateOrganize(
            (OrganizeOptions options) =>
                options.copyWith(subfolderTemplate: text),
          ),
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        ToggleRow(
          key: const Key('organize-skip-single'),
          labelKey: 'organize-skip-single-label',
          value: controller.organize.skipSingleFileFolders,
          onChanged: (bool value) => controller.updateOrganize(
            (OrganizeOptions options) =>
                options.copyWith(skipSingleFileFolders: value),
          ),
        ),
        const SizedBox(height: BoardTokens.gap),
        Text(
          Labels.of(
            'organize-plan',
            args: <String, Object>{
              'count': plan.items.length,
              'groups': plan.selectedGroupCount,
              'folders': plan.targetFolderCount,
            },
          ),
          key: const Key('organize-plan'),
          style: palette.tableFigure(color: palette.fgMuted),
        ),
        if (preview.isNotEmpty) ...<Widget>[
          const SizedBox(height: BoardTokens.gapSmall),
          for (final OrganizeItem item in preview)
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
                    '\u2192 ${item.destination}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: palette.text.bodySmall?.copyWith(
                      color: palette.fgFaint,
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: BoardTokens.gap),
        BoardAction(
          key: const Key('organize-action'),
          labelKey: 'organize-action',
          icon: Icons.folder_special_outlined,
          tone: plan.items.isEmpty ? null : palette.primary,
          onPressed: plan.items.isEmpty || controller.actionRunning
              ? null
              : controller.requestOrganize,
        ),
      ],
    );
  }
}
