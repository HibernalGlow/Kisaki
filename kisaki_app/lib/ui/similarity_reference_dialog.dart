import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../state/analysis_stats.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// The similarity cheat sheet from `czkawka/similarity-reference-dialog.tsx`.
///
/// It answers the question the hash-size field poses: the same difference means a different level at
/// 8 and at 64, so the limits are printed next to each other instead of hidden in a tooltip.
class SimilarityReferenceDialog extends StatelessWidget {
  const SimilarityReferenceDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (BuildContext context) => const SimilarityReferenceDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final List<SimilarityReferenceRow> rows = buildSimilarityReference();
    return AlertDialog(
      key: const Key('similarity-reference-dialog'),
      title: Text(Labels.of('similarity-reference-title')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              Labels.of('similarity-reference-description'),
              style: palette.text.bodySmall?.copyWith(color: palette.fgMuted),
            ),
            const SizedBox(height: BoardTokens.gap),
            _HeadRow(palette: palette),
            const Hairline(),
            for (final SimilarityReferenceRow row in rows)
              _ReferenceRow(row: row, palette: palette),
          ],
        ),
      ),
      actions: <Widget>[
        BoardAction(
          key: const Key('similarity-reference-close'),
          labelKey: 'action-close',
          dense: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _HeadRow extends StatelessWidget {
  const _HeadRow({required this.palette});

  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BoardTokens.gapSmall),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 108,
            child: Text(
              Labels.of('similarity-reference-level'),
              style: palette.text.bodySmall?.copyWith(color: palette.fgFaint),
            ),
          ),
          for (final int hashSize in similarityHashSizes)
            Expanded(
              child: Text(
                Labels.of(
                  'similarity-reference-hash',
                  args: <String, Object>{'size': hashSize},
                ),
                textAlign: TextAlign.end,
                style: palette.tableFigure(color: palette.fgMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({required this.row, required this.palette});

  final SimilarityReferenceRow row;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('similarity-reference-${row.level.wire}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 108,
            child: Text(
              Labels.of(row.level.labelKey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: palette.text.bodySmall,
            ),
          ),
          for (final int hashSize in similarityHashSizes)
            Expanded(
              child: Text(
                row.ranges[hashSize]!,
                textAlign: TextAlign.end,
                style: palette.tableFigure(),
              ),
            ),
        ],
      ),
    );
  }
}
