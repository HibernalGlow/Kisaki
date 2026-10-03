import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';
import '../theme/swiss_grid.dart';
import '../util/format.dart';
import 'exif_card.dart';
import 'overlays.dart';
import 'simiu_panel.dart';
import 'widgets/primitives.dart';

/// Right lane: result metrics, the destructive toggles, a plan preview, and actions.
class AnalysisPanel extends StatelessWidget {
  const AnalysisPanel({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final String tool = controller.tool?.id ?? '';
    final bool canRename = tool == 'bad_names' || tool == 'bad_extensions';
    return ListView(
      padding: const EdgeInsets.all(BoardTokens.section),
      children: <Widget>[
        SwissGrid(
          children: <SwissCell>[
            SwissCell(
              span: 6,
              child: MetricTile(
                labelKey: 'metric-files',
                value: '${controller.fileCount}',
              ),
            ),
            SwissCell(
              span: 6,
              child: MetricTile(
                labelKey: 'metric-groups',
                value: '${controller.groupCount}',
              ),
            ),
            SwissCell(
              span: 6,
              child: MetricTile(
                labelKey: 'metric-total',
                value: humanBytes(controller.totalBytes),
              ),
            ),
            SwissCell(
              span: 6,
              child: MetricTile(
                labelKey: 'metric-reclaimable',
                value: humanBytes(controller.reclaimableBytes),
                accent: palette.ok,
              ),
            ),
            SwissCell(
              span: 6,
              child: MetricTile(
                labelKey: 'metric-selected',
                value: '${controller.selectedCount}',
                accent: controller.selectedCount > 0 ? palette.primary : null,
              ),
            ),
            SwissCell(
              span: 6,
              child: MetricTile(
                labelKey: 'metric-selected-size',
                value: controller.selectedSizeText,
              ),
            ),
          ],
        ),
        const SizedBox(height: BoardTokens.section),
        if (controller.supportsSimiuSets &&
            controller.simiu.enabled) ...<Widget>[
          SimiuSetCard(controller: controller),
          const SizedBox(height: BoardTokens.gap * 2),
        ],
        if (controller.supportsExifClean) ...<Widget>[
          ExifCard(controller: controller, key: const Key('exif-card')),
          const SizedBox(height: BoardTokens.gap * 2),
        ],
        const Hairline(),
        const SizedBox(height: BoardTokens.gap),
        ToggleRow(
          labelKey: 'label-dry-run',
          value: controller.dryRun,
          onChanged: controller.setDryRun,
          hint: Labels.of('hint-dry-run'),
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        ToggleRow(
          labelKey: 'label-trash',
          value: controller.moveToTrash,
          onChanged: controller.setMoveToTrash,
        ),
        const SizedBox(height: BoardTokens.gap * 2),
        if (controller.selectedCount > 0) ...<Widget>[
          FlatCard(filled: true, child: _PlanBlock(controller: controller)),
          const SizedBox(height: BoardTokens.gap * 2),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: BoardAction(
                key: const Key('delete-selected'),
                labelKey: 'action-delete',
                icon: Icons.delete_outline_rounded,
                tone: controller.selectedCount == 0 ? null : palette.danger,
                onPressed:
                    controller.selectedCount == 0 || controller.actionRunning
                    ? null
                    : controller.requestDelete,
              ),
            ),
            const SizedBox(width: BoardTokens.gap),
            Expanded(
              child: BoardAction(
                key: const Key('export-results'),
                labelKey: 'action-export',
                icon: Icons.download_outlined,
                onPressed: controller.rows.isEmpty || controller.actionRunning
                    ? null
                    : () => KisakiOverlays.openExportSheet(context, controller),
              ),
            ),
          ],
        ),
        const SizedBox(height: BoardTokens.gap),
        Row(
          children: <Widget>[
            Expanded(
              child: BoardAction(
                key: const Key('fix-names'),
                labelKey: 'action-fix-names',
                icon: Icons.drive_file_rename_outline_rounded,
                onPressed:
                    canRename &&
                        controller.selectedCount > 0 &&
                        !controller.actionRunning
                    ? controller.requestRename
                    : null,
              ),
            ),
            const SizedBox(width: BoardTokens.gap),
            Expanded(
              child: BoardAction(
                key: const Key('move-selection'),
                labelKey: 'action-move',
                icon: Icons.drive_folder_upload_outlined,
                onPressed:
                    controller.selectedCount == 0 || controller.actionRunning
                    ? null
                    : () => showMoveSheet(context, controller),
              ),
            ),
          ],
        ),

        const SizedBox(height: BoardTokens.gap * 2),
        if (controller.messages.isNotEmpty ||
            controller.critical != null) ...<Widget>[
          const Hairline(),
          const SizedBox(height: BoardTokens.gap),
          BoardAction(
            key: const Key('open-messages'),
            labelKey: 'label-errors',
            icon: Icons.list_alt_rounded,
            tone: controller.critical != null ? palette.warn : null,
            onPressed: () => KisakiOverlays.openMessages(context, controller),
          ),
        ],
      ],
    );
  }
}

/// Dry run is the default, so the plan is shown before anything is confirmed.
class _PlanBlock extends StatelessWidget {
  const _PlanBlock({required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final List<ScanRow> targets = controller.selectedRows;
    final int bytes = targets.fold<int>(
      0,
      (int sum, ScanRow row) => sum + row.sizeBytes,
    );
    final String verb = Labels.of(
      controller.dryRun
          ? 'label-dry-run'
          : (controller.moveToTrash
                ? 'plan_files_to_trash'
                : 'plan_files_to_delete'),
    );
    final List<String> preview = targets
        .take(8)
        .map((ScanRow row) => row.path)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          Labels.of(
            'plan_header',
            args: <String, Object>{
              'count': targets.length,
              'size': humanBytes(bytes),
              'verb': verb,
            },
          ),
          style: TextStyle(
            fontSize: BoardTokens.fsLabel,
            fontWeight: FontWeight.w700,
            color: controller.dryRun ? palette.fgMuted : palette.danger,
          ),
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        for (final String path in preview)
          Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: BoardTokens.fsCaption,
              color: palette.fg,
            ),
          ),
        if (targets.length > preview.length)
          Text(
            Labels.of(
              'plan_more',
              args: <String, Object>{'count': targets.length - preview.length},
            ),
            style: TextStyle(
              fontSize: BoardTokens.fsCaption,
              color: palette.fgFaint,
            ),
          ),
      ],
    );
  }
}

/// The reference asks for a destination and whether to move or copy, then confirms through the same
/// dry-run gate as deletion.
Future<void> showMoveSheet(BuildContext context, BoardController controller) =>
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => _MoveSheet(controller: controller),
    );

class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.controller});

  final BoardController controller;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  String _destination = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Labels.of('move-sheet-title')),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MicroHeading(Labels.of('move-destination')),
            const SizedBox(height: BoardTokens.gapSmall),
            BoardField(
              key: const Key('move-destination-field'),
              labelKey: 'move-destination',
              value: _destination,
              onChanged: (String value) => setState(() => _destination = value),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        BoardAction(
          key: const Key('move-sheet-cancel'),
          labelKey: 'confirm-cancel',
          dense: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        BoardAction(
          key: const Key('move-sheet-move'),
          labelKey: 'action-move-move',
          dense: true,
          onPressed: () {
            final String destination = _destination;
            Navigator.of(context).pop();
            widget.controller.requestMove(destination, MoveAction.move);
          },
        ),
        BoardAction(
          key: const Key('move-sheet-copy'),
          labelKey: 'action-move-copy',
          dense: true,
          onPressed: () {
            final String destination = _destination;
            Navigator.of(context).pop();
            widget.controller.requestMove(destination, MoveAction.copy);
          },
        ),
      ],
    );
  }
}
