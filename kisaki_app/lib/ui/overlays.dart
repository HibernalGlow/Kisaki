import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/export_scope.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// Window-level overlays of the layout contract: tool menu, confirm dialog, scan messages.
class KisakiOverlays {
  const KisakiOverlays._();

  static Future<void> openToolMenu(
    BuildContext context,
    BoardController controller,
  ) => showDialog<void>(
    context: context,
    barrierLabel: Labels.of('tool-selector'),
    barrierColor: BoardTheme.of(context).scrim,
    // The tool menu hangs from the header, so it is anchored top-right instead of centred.
    builder: (BuildContext dialogContext) => Material(
      type: MaterialType.transparency,
      child: _ToolMenu(
        controller: controller,
        onSelect: (String id) {
          controller.selectTool(id);
          Navigator.of(dialogContext).pop();
        },
      ),
    ),
  );

  static Future<void> showConfirm(
    BuildContext context,
    BoardController controller,
  ) async {
    final ConfirmRequest? request = controller.confirm;
    if (request == null) {
      return;
    }
    final BoardPalette palette = BoardTheme.of(context);
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('confirm-dialog'),
        title: Text(
          Labels.of(request.titleKey),
          style: TextStyle(
            fontSize: BoardTokens.fsTitle,
            fontWeight: FontWeight.w700,
            color: palette.fg,
          ),
        ),
        content: Text(
          Labels.of(request.bodyKey, args: request.args),
          style: TextStyle(
            fontSize: BoardTokens.fsBody,
            color: palette.fgMuted,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(Labels.of('confirm-cancel')),
          ),
          FilledButton(
            key: const Key('confirm-accept'),
            style: FilledButton.styleFrom(
              backgroundColor: request.dryRun
                  ? palette.primary
                  : palette.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(Labels.of('confirm-ok')),
          ),
        ],
      ),
    );
    if (accepted ?? false) {
      await controller.acceptConfirm();
    } else {
      controller.dismissConfirm();
    }
  }

  static Future<void> openMessages(
    BuildContext context,
    BoardController controller,
  ) => showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      key: const Key('messages-dialog'),
      title: Text(
        Labels.of('label-errors'),
        style: TextStyle(
          fontSize: BoardTokens.fsTitle,
          fontWeight: FontWeight.w700,
          color: BoardTheme.of(context).fg,
        ),
      ),
      content: SizedBox(
        width: 520,
        height: 320,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (controller.critical != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: BoardTokens.gap),
                  child: Text(
                    controller.critical!,
                    style: TextStyle(
                      fontSize: BoardTokens.fsBody,
                      color: BoardTheme.of(context).danger,
                    ),
                  ),
                ),
              SelectableText(
                controller.messages.isEmpty
                    ? Labels.of('status-ready')
                    : controller.messages,
                style: TextStyle(
                  fontSize: BoardTokens.fsLabel,
                  color: BoardTheme.of(context).fg,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(Labels.of('action-close')),
        ),
      ],
    ),
  );

  static Future<void> openExportSheet(
    BuildContext context,
    BoardController controller,
  ) async {
    final ({String path, String format})? choice =
        await showDialog<({String path, String format})>(
          context: context,
          builder: (BuildContext context) =>
              _ExportDialog(controller: controller),
        );
    if (choice != null) {
      await controller.exportResults(choice.path, format: choice.format);
    }
  }
}

/// The export sheet. It owns its text field on purpose: the route is still animating away after a
/// pop, and a field disposed by the caller is then read by a widget that no longer exists.
class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.controller});

  final BoardController controller;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  static const List<String> _formats = <String>['json', 'csv'];

  final TextEditingController _path = TextEditingController();
  String _format = 'json';

  @override
  void initState() {
    super.initState();
    _path.addListener(_onPathChanged);
  }

  void _onPathChanged() => setState(() {});

  @override
  void dispose() {
    _path.removeListener(_onPathChanged);
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final int scopeRows = widget.controller.exportScopeRows.length;
        return AlertDialog(
          key: const Key('export-dialog'),
          title: Text(
            Labels.of('action-export'),
            style: TextStyle(
              fontSize: BoardTokens.fsTitle,
              fontWeight: FontWeight.w700,
              color: palette.fg,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                MicroHeading(Labels.of('export-scope-title')),
                const SizedBox(height: BoardTokens.gapSmall),
                BoardDropdown<ExportScope>(
                  key: const Key('export-scope'),
                  labelKey: 'export-scope-title',
                  values: ExportScope.values,
                  current: widget.controller.exportScope,
                  label: (ExportScope scope) => Labels.of(scope.labelKey),
                  onChanged: widget.controller.setExportScope,
                ),
                const SizedBox(height: BoardTokens.gapSmall),
                // The count is the readback: the reader sees which rows the choice resolves to
                // before anything reaches the engine.
                Text(
                  Labels.of(
                    'export-scope-count',
                    args: <String, Object>{'count': scopeRows},
                  ),
                  key: const Key('export-scope-count'),
                  style: palette.text.bodySmall?.copyWith(
                    color: palette.fgMuted,
                  ),
                ),
                const SizedBox(height: BoardTokens.gap),
                MicroHeading(Labels.of('export-path-title')),
                const SizedBox(height: BoardTokens.gapSmall),
                TextField(
                  key: const Key('export-path'),
                  controller: _path,
                  style: TextStyle(
                    fontSize: BoardTokens.fsBody,
                    color: palette.fg,
                  ),
                  decoration: const InputDecoration(
                    hintText: '/tmp/kisaki-results',
                  ),
                ),
                const SizedBox(height: BoardTokens.gap),
                MicroHeading(Labels.of('export-format-title')),
                const SizedBox(height: BoardTokens.gapSmall),
                Wrap(
                  spacing: BoardTokens.gapSmall,
                  children: _formats.map((String option) {
                    final bool active = option == _format;
                    return GestureDetector(
                      key: Key('export-format-$option'),
                      onTap: () => setState(() => _format = option),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: BoardTokens.gap,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: active ? palette.primary : palette.raised,
                          borderRadius: BorderRadius.circular(
                            BoardTokens.radius,
                          ),
                          border: Border.all(
                            color: active ? palette.primary : palette.border,
                          ),
                        ),
                        child: Text(
                          option.toUpperCase(),
                          style: TextStyle(
                            fontSize: BoardTokens.fsCaption,
                            fontWeight: FontWeight.w700,
                            color: active
                                ? palette.fgInverted
                                : palette.fgMuted,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(Labels.of('confirm-cancel')),
            ),
            FilledButton(
              key: const Key('export-confirm'),
              // Like the reference: no path or an empty scope leaves nothing to save.
              onPressed: _path.text.trim().isEmpty || scopeRows == 0
                  ? null
                  : () =>
                        Navigator.of(context)
                            .pop((path: _path.text.trim(), format: _format)),
              child: Text(Labels.of('confirm-ok')),
            ),
          ],
        );
      },
    );
  }
}

class _ToolMenu extends StatelessWidget {
  const _ToolMenu({required this.controller, required this.onSelect});

  final BoardController controller;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final List<ToolSpec> tools = controller.tools;
    return Padding(
      padding: const EdgeInsets.only(top: BoardTokens.headerHeight, right: 12),
      child: Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: 300,
          child: Material(
            key: const Key('tool-menu'),
            color: palette.card,
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: palette.border),
              borderRadius: BorderRadius.circular(BoardTokens.radius),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: ListView.builder(
                padding: const EdgeInsets.all(BoardTokens.gapSmall),
                itemCount: tools.length,
                itemBuilder: (BuildContext context, int index) {
                  final ToolSpec tool = tools[index];
                  final bool active = tool.id == controller.tool?.id;
                  return ListTile(
                    key: Key('tool-${tool.id}'),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: GlyphTile(glyph: tool.glyph, active: active),
                    title: Text(
                      Labels.of(tool.labelKey),
                      style: TextStyle(
                        fontSize: BoardTokens.fsBody,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? palette.primary : palette.fg,
                      ),
                    ),
                    trailing: active
                        ? Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: palette.primary,
                          )
                        : null,
                    onTap: () => onSelect(tool.id),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
