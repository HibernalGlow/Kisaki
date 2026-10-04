import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/scan_presets.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// Saved scan configurations, from the reference's source-settings card.
///
/// The card owns its name field: a dialog or a card that takes a controller from its caller leaves a
/// disposed field behind the moment the caller disposes it while the widget is still on screen.
class ScanPresetCard extends StatefulWidget {
  const ScanPresetCard({required this.controller, super.key});

  final BoardController controller;

  @override
  State<ScanPresetCard> createState() => _ScanPresetCardState();
}

class _ScanPresetCardState extends State<ScanPresetCard> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final List<ScanPreset> presets = widget.controller.scanPresets;
        return SectionCard(
          title: Labels.of('preset-card-title'),
          children: <Widget>[
            BoardField(
              key: const Key('preset-name-field'),
              labelKey: 'preset-name-label',
              value: _name.text,
              onChanged: (String value) => setState(() => _name.text = value),
            ),
            const SizedBox(height: BoardTokens.gapSmall),
            Wrap(
              spacing: BoardTokens.gapSmall,
              runSpacing: BoardTokens.gapSmall,
              children: <Widget>[
                BoardAction(
                  key: const Key('preset-save'),
                  labelKey: 'preset-action-save',
                  icon: Icons.bookmark_add_outlined,
                  dense: true,
                  onPressed: () {
                    widget.controller.savePreset(_name.text);
                    _name.clear();
                    setState(() {});
                  },
                ),
                BoardAction(
                  key: const Key('preset-export'),
                  labelKey: 'preset-action-export',
                  icon: Icons.copy_all_outlined,
                  dense: true,
                  onPressed: presets.isEmpty
                      ? null
                      : widget.controller.copyPresetText,
                ),
                BoardAction(
                  key: const Key('preset-import'),
                  labelKey: 'preset-action-import',
                  icon: Icons.upload_file_outlined,
                  dense: true,
                  onPressed: () => _openImport(context),
                ),
              ],
            ),
            const SizedBox(height: BoardTokens.gap),
            if (presets.isEmpty)
              Text(
                Labels.of('preset-empty'),
                key: const Key('preset-empty'),
                style: palette.text.bodySmall?.copyWith(color: palette.fgFaint),
              )
            else
              for (final ScanPreset preset in presets)
                _PresetRow(
                  key: Key('preset-item-${preset.id}'),
                  controller: widget.controller,
                  preset: preset,
                ),
          ],
        );
      },
    );
  }

  Future<void> _openImport(BuildContext context) => showDialog<void>(
    context: context,
    builder: (BuildContext context) =>
        _ImportDialog(controller: widget.controller),
  );
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.controller, required this.preset, super.key});

  final BoardController controller;
  final ScanPreset preset;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: BoardTokens.gapSmall),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(preset.name, style: palette.text.bodySmall),
                Text(
                  Labels.of(
                    'preset-tool',
                    args: <String, Object>{'tool': preset.tool},
                  ),
                  style: palette.text.bodySmall?.copyWith(
                    color: palette.fgFaint,
                  ),
                ),
              ],
            ),
          ),
          BoardAction(
            key: Key('preset-apply-${preset.id}'),
            labelKey: 'preset-action-apply',
            dense: true,
            onPressed: () => controller.applyPreset(preset.id),
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          BoardAction(
            key: Key('preset-delete-${preset.id}'),
            labelKey: 'preset-action-delete',
            dense: true,
            onPressed: () => controller.deletePreset(preset.id),
          ),
        ],
      ),
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.controller});

  final BoardController controller;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _text = TextEditingController();
  bool _replace = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AlertDialog(
      key: const Key('preset-import-dialog'),
      title: Text(Labels.of('preset-action-import')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const Key('preset-import-field'),
              controller: _text,
              maxLines: 8,
              // The confirm button is gated on the text, so typing has to repaint the dialog.
              onChanged: (String _) => setState(() {}),
              style: palette.text.bodySmall,
              decoration: InputDecoration(
                hintText: Labels.of('preset-import-placeholder'),
              ),
            ),
            const SizedBox(height: BoardTokens.gapSmall),
            ToggleRow(
              key: const Key('preset-import-replace'),
              labelKey: 'preset-action-replace',
              value: _replace,
              onChanged: (bool value) => setState(() => _replace = value),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        BoardAction(
          key: const Key('preset-import-cancel'),
          labelKey: 'confirm-cancel',
          dense: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        BoardAction(
          key: const Key('preset-import-confirm'),
          labelKey: 'preset-action-import',
          dense: true,
          onPressed: _text.text.trim().isEmpty
              ? null
              : () {
                  final String text = _text.text;
                  final bool replace = _replace;
                  Navigator.of(context).pop();
                  widget.controller.importPresetText(text, replace: replace);
                },
        ),
      ],
    );
  }
}
