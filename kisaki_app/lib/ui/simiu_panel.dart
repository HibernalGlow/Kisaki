import 'package:flutter/material.dart';

import '../engine/models.dart' show SimiuMode, SimiuOperation;
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/simiu_model.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// The image scanner's second mode, from `czkawka/views/CzkawkaPanelsView.tsx`.
///
/// The reference puts the mode selector above the algorithm options and only shows the set fields
/// while the mode is on, which is what this does.
class SimiuFields extends StatelessWidget {
  const SimiuFields({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final SimiuModel simiu = controller.simiu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BoardDropdown<bool>(
          key: const Key('simiu-mode'),
          labelKey: 'simiu-mode-label',
          values: const <bool>[false, true],
          current: simiu.enabled,
          label: (bool value) =>
              Labels.of(value ? 'simiu-mode-sets' : 'simiu-mode-scanner'),
          onChanged: controller.setSimiuEnabled,
        ),
        if (simiu.enabled) ...<Widget>[
          const SizedBox(height: BoardTokens.gap),
          BoardField(
            key: const Key('simiu-prefix'),
            labelKey: 'simiu-prefix-label',
            value: simiu.options.namePrefix,
            onChanged: controller.setSimiuPrefix,
          ),
          const SizedBox(height: BoardTokens.gap),
          BoardField(
            key: const Key('simiu-min-group'),
            labelKey: 'simiu-min-group-label',
            value: '${simiu.options.minimumGroupSize}',
            onChanged: (String text) {
              final int? parsed = int.tryParse(text.trim());
              if (parsed != null) {
                controller.setSimiuMinimumGroupSize(parsed);
              }
            },
          ),
          const SizedBox(height: BoardTokens.gap),
          BoardDropdown<SimiuScanOrder>(
            key: const Key('simiu-scan-order'),
            labelKey: 'simiu-scan-order-label',
            values: SimiuScanOrder.values,
            current: simiu.options.scanOrder,
            label: (SimiuScanOrder value) => Labels.of(switch (value) {
              SimiuScanOrder.path => 'simiu-order-path',
              SimiuScanOrder.smallestFirst => 'simiu-order-smallest',
              SimiuScanOrder.deepestFirst => 'simiu-order-deepest',
            }),
            onChanged: controller.setSimiuScanOrder,
          ),
        ],
      ],
    );
  }
}

/// The set plan and its two verbs, from `czkawka/views/CzkawkaCardsView.tsx`.
///
/// The reference shows the first twelve planned moves in the confirm dialog; Kisaki keeps the same
/// preview in the lane, because the plan changes while the fields are typed in and a dialog would
/// hide that feedback.
class SimiuSetCard extends StatelessWidget {
  const SimiuSetCard({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final SimiuModel simiu = controller.simiu;
    final SimiuPlan plan = controller.simiuPlan;
    final List<SimiuOperation> operations = plan.operations;
    final List<SimiuOperation> preview = operations.take(12).toList();

    return SectionCard(
      title: Labels.of('simiu-card-title'),
      children: <Widget>[
        Text(Labels.of('simiu-card-hint'), style: palette.text.bodySmall),
        const SizedBox(height: BoardTokens.gap),
        BoardDropdown<SimiuMode>(
          key: const Key('simiu-operation-mode'),
          labelKey: 'simiu-operation-mode-label',
          values: SimiuMode.values,
          current: simiu.mode,
          label: (SimiuMode value) => Labels.of(switch (value) {
            SimiuMode.move => 'simiu-operation-move',
            SimiuMode.copy => 'simiu-operation-copy',
            SimiuMode.link => 'simiu-operation-link',
          }),
          onChanged: controller.setSimiuMode,
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        ToggleRow(
          key: const Key('simiu-clean-empty'),
          labelKey: 'simiu-clean-empty-label',
          value: simiu.cleanEmptyDirectories,
          onChanged: controller.setSimiuCleanEmptyDirectories,
        ),
        const SizedBox(height: BoardTokens.gap),
        Text(
          Labels.of(
            'simiu-plan-count',
            args: <String, Object>{
              'count': operations.length,
              'folders': plan.groups.length,
            },
          ),
          key: const Key('simiu-plan-count'),
          style: palette.tableFigure(color: palette.fgMuted),
        ),
        if (preview.isNotEmpty) ...<Widget>[
          const SizedBox(height: BoardTokens.gapSmall),
          _Preview(operations: preview),
        ],
        const SizedBox(height: BoardTokens.gap),
        BoardAction(
          key: const Key('simiu-apply'),
          labelKey: 'simiu-action-apply',
          icon: Icons.drive_folder_upload_outlined,
          tone: operations.isEmpty ? null : palette.primary,
          onPressed: operations.isEmpty || controller.actionRunning
              ? null
              : controller.requestSimiuApply,
        ),
        if (simiu.journal.isNotEmpty) ...<Widget>[
          const SizedBox(height: BoardTokens.gapSmall),
          BoardAction(
            key: const Key('simiu-undo'),
            labelKey: 'simiu-action-undo',
            icon: Icons.undo_rounded,
            dense: true,
            onPressed: controller.actionRunning
                ? null
                : controller.requestSimiuUndo,
          ),
        ],
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.operations});

  final List<SimiuOperation> operations;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 168),
      child: ListView(
        key: const Key('simiu-preview'),
        padding: const EdgeInsets.symmetric(
          horizontal: BoardTokens.gapSmall,
          vertical: BoardTokens.gapSmall,
        ),
        shrinkWrap: true,
        children: <Widget>[
          for (final SimiuOperation operation in operations)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Path(text: operation.source, style: palette.text.bodySmall),
                  _Path(
                    text: '\u2192 ${operation.target}',
                    style: palette.text.bodySmall?.copyWith(
                      color: palette.fgFaint,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Path extends StatelessWidget {
  const _Path({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
