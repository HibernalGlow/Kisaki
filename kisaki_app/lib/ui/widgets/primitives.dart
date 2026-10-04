import 'package:flutter/material.dart';

import '../../l10n/labels.dart';
import '../../theme/board_theme.dart';

/// Uppercase micro-heading: Swiss hierarchy is carried by type, not decoration.
class MicroHeading extends StatelessWidget {
  const MicroHeading(this.text, {this.color, this.trailing, super.key});

  final String text;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            text.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: palette.microLabel(color: color ?? palette.fgMuted),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class KeyHeading extends StatelessWidget {
  const KeyHeading(this.labelKey, {this.trailing, super.key});

  final String labelKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) =>
      MicroHeading(Labels.of(labelKey), trailing: trailing);

  /// Path lists and extension lists are edited as one token line per entry.
}

class Hairline extends StatelessWidget {
  const Hairline({this.vertical = false, super.key});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final Color color = BoardTheme.of(context).hairline;
    return Container(
      width: vertical ? 1 : double.infinity,
      height: vertical ? double.infinity : 1,
      color: color,
    );
  }
}

/// Flat 1px-bordered surface used for every card in the board.
class FlatCard extends StatelessWidget {
  const FlatCard({
    required this.child,
    this.padding,
    this.filled = false,
    super.key,
  });

  final Widget child;
  final EdgeInsets? padding;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Container(
      decoration: ShapeDecoration(
        color: filled ? palette.sunken : palette.card,
        shape: BoardShape.panel(palette.hairline),
      ),
      padding: padding ?? const EdgeInsets.all(BoardTokens.pad),
      child: child,
    );
  }
}

/// Typographic marker tile - Kisaki has no icon assets by design.
class GlyphTile extends StatelessWidget {
  const GlyphTile({
    required this.glyph,
    this.active = false,
    this.size = 22,
    super.key,
  });

  final String glyph;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? palette.primary : palette.raised,
        borderRadius: BorderRadius.circular(BoardTokens.radius),
        border: Border.all(color: active ? palette.primary : palette.border),
      ),
      child: Text(
        glyph,
        style: TextStyle(
          fontSize: BoardTokens.fsLabel,
          fontWeight: FontWeight.w700,
          color: active ? palette.fgInverted : palette.fg,
        ),
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.labelKey,
    required this.value,
    this.accent,
    super.key,
  });

  final String labelKey;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MicroHeading(Labels.of(labelKey)),
        const SizedBox(height: BoardTokens.gapSmall),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: palette.metricFigure(color: accent ?? palette.fg),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.labelKey, this.detail, super.key});

  final String labelKey;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(BoardTokens.gap * 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            Labels.of(labelKey),
            style: TextStyle(fontSize: BoardTokens.fsBody, color: palette.fg),
          ),
          if (detail != null) ...<Widget>[
            const SizedBox(height: BoardTokens.gapSmall),
            Text(
              detail!,
              style: TextStyle(
                fontSize: BoardTokens.fsLabel,
                color: palette.fgFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small text-only action, sized for lane headers and tool strips.
class BoardAction extends StatelessWidget {
  const BoardAction({
    required this.labelKey,
    required this.onPressed,
    this.icon,
    this.tone,
    this.dense = false,
    this.iconOnly = false,
    this.labelArgs = const <String, Object>{},
    super.key,
  });

  final String labelKey;
  final Map<String, Object> labelArgs;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? tone;
  final bool dense;

  /// The reference's strip buttons carry an icon and an aria-label only, so a tight header keeps
  /// its affordances instead of losing them to an ellipsis.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final bool enabled = onPressed != null;
    final String label = Labels.of(labelKey, args: labelArgs);
    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(
            icon,
            size: 14,
            color: enabled ? (tone ?? palette.fg) : palette.fgFaint,
          ),
          if (!iconOnly) const SizedBox(width: BoardTokens.gapSmall),
        ],
        if (!iconOnly)
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: BoardTokens.fsLabel,
                fontWeight: FontWeight.w700,
                color: enabled ? (tone ?? palette.fg) : palette.fgFaint,
              ),
            ),
          ),
      ],
    );
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Container(
        padding: iconOnly
            ? const EdgeInsets.all(BoardTokens.gapSmall)
            // A dense strip cannot carry a full gutter on both sides and still fit its siblings, so
            // it keeps one step of horizontal padding.
            : EdgeInsets.symmetric(
                horizontal: dense ? BoardTokens.gapSmall : BoardTokens.gap,
                vertical: dense ? BoardTokens.gapSmall : 6,
              ),
        decoration: BoxDecoration(
          color: enabled ? palette.raised : palette.sunken,
          borderRadius: BorderRadius.circular(BoardTokens.radius),
          border: Border.all(
            color: enabled && tone != null ? tone! : palette.border,
          ),
        ),
        child: iconOnly ? Tooltip(message: label, child: content) : content,
      ),
    );
  }
}

class ToggleRow extends StatelessWidget {
  const ToggleRow({
    required this.labelKey,
    required this.value,
    required this.onChanged,
    this.hint,
    super.key,
  });

  final String labelKey;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: MicroHeading(Labels.of(labelKey))),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
        if (hint != null)
          Text(
            hint!,
            style: TextStyle(
              fontSize: BoardTokens.fsCaption,
              color: palette.fgFaint,
            ),
          ),
      ],
    );
  }
}

/// Text input that owns its controller, so a rebuild during typing cannot reset the caret.
class BoardField extends StatefulWidget {
  const BoardField({
    required this.labelKey,
    required this.value,
    required this.onChanged,
    this.multiline = false,
    this.enabled = true,
    super.key,
  });

  final String labelKey;
  final String value;
  final ValueChanged<String> onChanged;
  final bool multiline;
  final bool enabled;

  @override
  State<BoardField> createState() => _BoardFieldState();
}

class _BoardFieldState extends State<BoardField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(BoardField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      maxLines: widget.multiline ? 4 : 1,
      style: BoardTheme.of(context).text.bodyMedium,
      decoration: InputDecoration(hintText: Labels.of(widget.labelKey)),
      onChanged: widget.onChanged,
    );
  }
}

/// Square, hairline select. `labelKey` names the field for assistive tech because the section
/// heading, not a per-field label, is what a sighted reader sees.
class BoardDropdown<T> extends StatelessWidget {
  const BoardDropdown({
    required this.labelKey,
    required this.values,
    required this.current,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final String labelKey;
  final List<T> values;
  final T current;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: Labels.of(labelKey),
      child: DropdownButtonFormField<T>(
        initialValue: current,
        // Without this the menu keeps its intrinsic width and overflows narrow slots.
        isExpanded: true,
        items: <DropdownMenuItem<T>>[
          for (final T value in values)
            DropdownMenuItem<T>(
              key: Key('$labelKey-option-${_optionId(value)}'),
              value: value,
              child: Text(label(value)),
            ),
        ],
        onChanged: (T? value) {
          if (value != null) {
            onChanged(value);
          }
        },
      ),
    );
  }
}

/// One option's stable id: an enum's name rather than `MoveConflictPolicy.rename`, so a key stays
/// readable and a test can aim at an option instead of its painted label.
String _optionId(Object? value) =>
    value is Enum ? value.name : value.toString();

/// Outlined section with a micro-heading: the Swiss card, hairline and no elevation.
class SectionCard extends StatelessWidget {
  const SectionCard({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BoardTokens.gap),
      child: FlatCard(
        child: Padding(
          padding: const EdgeInsets.all(BoardTokens.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MicroHeading(title),
              const SizedBox(height: BoardTokens.gapSmall),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
