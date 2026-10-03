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
            style: TextStyle(
              fontSize: BoardTokens.fsCaption,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: color ?? palette.fgMuted,
            ),
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
      decoration: BoxDecoration(
        color: filled ? palette.sunken : palette.card,
        borderRadius: BorderRadius.circular(BoardTokens.radius),
        border: Border.all(color: palette.hairline),
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
    super.key,
  });

  final String labelKey;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final bool enabled = onPressed != null;
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: BoardTokens.gap,
          vertical: dense ? BoardTokens.gapSmall : 6,
        ),
        decoration: BoxDecoration(
          color: enabled ? palette.raised : palette.sunken,
          borderRadius: BorderRadius.circular(BoardTokens.radius),
          border: Border.all(
            color: enabled && tone != null ? tone! : palette.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 14,
                color: enabled ? (tone ?? palette.fg) : palette.fgFaint,
              ),
              const SizedBox(width: BoardTokens.gapSmall),
            ],
            Text(
              Labels.of(labelKey),
              style: TextStyle(
                fontSize: BoardTokens.fsLabel,
                fontWeight: FontWeight.w600,
                color: enabled ? (tone ?? palette.fg) : palette.fgFaint,
              ),
            ),
          ],
        ),
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
