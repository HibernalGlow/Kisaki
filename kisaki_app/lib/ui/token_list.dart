import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// How a path list asks the platform for entries; the app supplies the picker.
enum PathRequest { directory, file, manual }

typedef PathPicker = Future<List<String>> Function(
  BuildContext context,
  PathRequest request,
);

/// One editable string list: existing entries carry a remove control, the field at the
/// bottom appends, and the header actions cover bulk paste and clear.
class TokenListEditor extends StatefulWidget {
  const TokenListEditor({
    required this.entries,
    required this.onAdd,
    required this.onRemoveAt,
    required this.onClear,
    required this.placeholder,
    this.onManualEntry,
    this.label,
    super.key,
  });

  final List<String> entries;
  final ValueChanged<String> onAdd;
  final ValueChanged<int> onRemoveAt;
  final VoidCallback onClear;
  final String placeholder;
  final VoidCallback? onManualEntry;
  final String? label;

  @override
  State<TokenListEditor> createState() => _TokenListEditorState();
}

class _TokenListEditorState extends State<TokenListEditor> {
  final TextEditingController _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _draft.text.trim();
    if (value.isEmpty) {
      return;
    }
    widget.onAdd(value);
    _draft.clear();
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: BoardTokens.gapSmall),
            child: MicroHeading(widget.label!),
          ),
        if (widget.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: BoardTokens.gapSmall),
            child: Text(
              Labels.of('empty-paths'),
              style: TextStyle(
                fontSize: BoardTokens.fsLabel,
                color: palette.fgFaint,
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: ListView.builder(
              shrinkWrap: true,
              itemExtent: 24,
              itemCount: widget.entries.length,
              itemBuilder: (BuildContext context, int index) {
                final String entry = widget.entries[index];
                return Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        entry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: BoardTokens.fsLabel,
                          color: palette.fg,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 13),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 22,
                        height: 22,
                      ),
                      onPressed: () => widget.onRemoveAt(index),
                    ),
                  ],
                );
              },
            ),
          ),
        const SizedBox(height: BoardTokens.gapSmall),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: Key('token-field-${widget.label ?? widget.placeholder}'),
                controller: _draft,
                onSubmitted: (_) => _submit(),
                style: TextStyle(
                  fontSize: BoardTokens.fsBody,
                  color: palette.fg,
                ),
                decoration: InputDecoration(hintText: widget.placeholder),
              ),
            ),
            const SizedBox(width: BoardTokens.gapSmall),
            BoardAction(
              key: Key('token-add-${widget.label ?? widget.placeholder}'),
              labelKey: 'action-add-manual',
              dense: true,
              onPressed: _submit,
            ),
            if (widget.onManualEntry != null) ...<Widget>[
              const SizedBox(width: BoardTokens.gapSmall),
              BoardAction(
                labelKey: 'action-clear',
                dense: true,
                onPressed: widget.onClear,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Multi-line paste sheet - the path entry route that needs no platform picker.
Future<List<String>?> showManualPathSheet(
  BuildContext context, {
  String? title,
}) async {
  final BoardPalette palette = BoardTheme.of(context);
  final TextEditingController controller = TextEditingController();
  final List<String>? result = await showDialog<List<String>>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(
        title ?? Labels.of('action-add-manual'),
        style: TextStyle(fontSize: BoardTokens.fsTitle, color: palette.fg),
      ),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('manual-path-field'),
          controller: controller,
          maxLines: 8,
          style: TextStyle(fontSize: BoardTokens.fsBody, color: palette.fg),
          decoration: InputDecoration(
            hintText: Labels.of('placeholder-manual'),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(<String>[]),
          child: Text(Labels.of('confirm-cancel')),
        ),
        FilledButton(
          key: const Key('manual-path-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(
            controller.text
                .split('\n')
                .map((String line) => line.trim())
                .where((String line) => line.isNotEmpty)
                .toList(),
          ),
          child: Text(Labels.of('confirm-ok')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
