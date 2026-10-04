import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n/labels.dart';
import '../state/analysis_stats.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';
import '../util/format.dart';
import 'similarity_reference_dialog.dart';
import 'widgets/primitives.dart';

/// Format and similarity distributions from `czkawka/analysis-panel.tsx`.
///
/// The reference draws the format share as a conic-gradient donut. Kisaki keeps the same figures in
/// one stacked rule, because a Swiss board separates series by a printed label and a cycle index,
/// not by a fifth hue a reader has to match against a ring.
class AnalysisStatsCard extends StatelessWidget {
  const AnalysisStatsCard({required this.controller, super.key});

  final BoardController controller;

  static const double _barWeight = 4;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final List<FormatStat> formats = controller.formatStats
            .take(8)
            .toList();
        final List<SimilarityStat> similarities = controller.similarityStats;
        final CodecInfo? codec = controller.codec;
        final EngineInfo? info = controller.info;
        return SectionCard(
          title: Labels.of('analysis-title'),
          children: <Widget>[
            MicroHeading(Labels.of('analysis-format-share')),
            const SizedBox(height: BoardTokens.gapSmall),
            if (formats.isEmpty)
              _Empty(text: Labels.of('analysis-no-format'))
            else ...<Widget>[
              _ShareBar(
                formats: formats,
                palette: palette,
                key: const Key('format-share-bar'),
              ),
              const SizedBox(height: BoardTokens.gapSmall),
              for (final (int index, FormatStat item) in formats.indexed)
                _Legend(
                  swatch: palette.chartByIndex(index),
                  name: '.${item.format}',
                  trailing: '${item.bytesPercent.toStringAsFixed(1)}%',
                  entryKey: Key('format-legend-${item.format}'),
                  palette: palette,
                ),
            ],
            const SizedBox(height: BoardTokens.gap),
            MicroHeading(Labels.of('analysis-format-bytes')),
            const SizedBox(height: BoardTokens.gapSmall),
            for (final (int index, FormatStat item) in formats.indexed)
              _Meter(
                entryKey: Key('format-bytes-${item.format}'),
                leading: '.${item.format} \u00b7 ${item.count}',
                trailing: humanBytes(item.bytes),
                percent: item.bytesPercent,
                color: palette.chartByIndex(index),
                palette: palette,
                barWeight: _barWeight,
              ),
            const SizedBox(height: BoardTokens.gap),
            MicroHeading(
              Labels.of('analysis-similarity'),
              trailing: controller.supportsSimilarityReference
                  ? BoardAction(
                      key: const Key('similarity-reference-open'),
                      labelKey: 'similarity-reference-open',
                      icon: Icons.info_outline_rounded,
                      dense: true,
                      onPressed: () => SimilarityReferenceDialog.show(context),
                    )
                  : null,
            ),
            const SizedBox(height: BoardTokens.gapSmall),
            if (similarities.isEmpty)
              _Empty(text: Labels.of('analysis-no-similarity'))
            else
              for (final SimilarityStat item in similarities)
                _Meter(
                  entryKey: Key('similarity-${item.level.wire}'),
                  leading: Labels.of(item.level.labelKey),
                  trailing: '${item.count} \u00b7 ${item.range}',
                  percent: item.percent,
                  color: palette.primary,
                  palette: palette,
                  barWeight: _barWeight,
                ),
            const SizedBox(height: BoardTokens.gap),
            const Hairline(),
            const SizedBox(height: BoardTokens.gapSmall),
            MicroHeading(Labels.of('build-decoders')),
            const SizedBox(height: BoardTokens.gapSmall),
            Text(
              codec?.caption ?? '-',
              key: const Key('codec-caption'),
              style: TextStyle(
                fontSize: BoardTokens.fsBody,
                fontWeight: FontWeight.w700,
                color: codec != null && !codec.heif
                    ? palette.warn
                    : palette.fg,
              ),
            ),
            Text(
              Labels.of('build-decoders-note'),
              style: TextStyle(
                fontSize: BoardTokens.fsCaption,
                color: palette.fgMuted,
              ),
            ),
            Text(
              '${info?.coreVersion ?? '-'} | ${info?.os ?? '-'} | '
              '${info?.threadLimit ?? 0} | ${codec?.diagnostic ?? '-'}',
              key: const Key('build-runtime-line'),
              style: TextStyle(
                fontSize: BoardTokens.fsCaption,
                color: palette.fgFaint,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One horizontal rule whose segments carry the byte share of each format.
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.formats, required this.palette, super.key});

  final List<FormatStat> formats;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AnalysisStatsCard._barWeight,
      child: Row(
        children: <Widget>[
          for (final (int index, FormatStat item) in formats.indexed)
            Expanded(
              flex: _flexOf(item),
              child: ColoredBox(color: palette.chartByIndex(index)),
            ),
        ],
      ),
    );
  }

  /// Expanded takes a positive integer share, and a format with no bytes still owns a row.
  int _flexOf(FormatStat item) {
    final int flex = (item.bytesPercent * 100).round();
    return flex < 1 ? 1 : flex;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.swatch,
    required this.name,
    required this.trailing,
    required this.entryKey,
    required this.palette,
  });

  final Color swatch;
  final String name;
  final String trailing;
  final Key entryKey;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: entryKey,
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          Container(
            width: AnalysisStatsCard._barWeight,
            height: AnalysisStatsCard._barWeight,
            color: swatch,
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: palette.text.bodySmall,
            ),
          ),
          Flexible(
            child: Text(
              trailing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: palette.tableFigure(color: palette.fgMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label and value on one line, their share of the column on the rule below it.
class _Meter extends StatelessWidget {
  const _Meter({
    required this.entryKey,
    required this.leading,
    required this.trailing,
    required this.percent,
    required this.color,
    required this.palette,
    required this.barWeight,
  });

  final Key entryKey;
  final String leading;
  final String trailing;
  final double percent;
  final Color color;
  final BoardPalette palette;
  final double barWeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: entryKey,
      padding: const EdgeInsets.only(bottom: BoardTokens.gapSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  leading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: palette.text.bodySmall,
                ),
              ),
              Flexible(
                child: Text(
                  trailing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: palette.tableFigure(color: palette.fgMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: barWeight,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(color: palette.hairline),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (percent / 100).clamp(0.0, 1.0),
                  child: ColoredBox(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: BoardTheme.of(context).text.bodySmall
          ?.copyWith(color: BoardTheme.of(context).fgFaint),
    );
  }
}
