import '../engine/models.dart';

/// Dart port of `packages/nodes/czkawka/src/analysis.ts`.
///
/// The level boundaries are Czkawka core's own `SIMILAR_VALUES`, so a bucket here always agrees with
/// the level word the engine printed in the difference column.
enum SimilarityLevel {
  original('original'),
  veryHigh('very-high'),
  high('high'),
  medium('medium'),
  small('small'),
  verySmall('very-small'),
  minimal('minimal');

  const SimilarityLevel(this.wire);

  final String wire;

  String get labelKey => 'analysis-level-$wire';
}

const List<SimilarityLevel> similarityLevels = SimilarityLevel.values;

/// The hash sizes the image scanner accepts, and the difference limits each level may reach.
const List<int> similarityHashSizes = <int>[8, 16, 32, 64];

const Map<int, List<double>> similarityThresholds = <int, List<double>>{
  8: <double>[1, 2, 5, 7, 14, 40],
  16: <double>[2, 5, 15, 30, 40, 40],
  32: <double>[4, 10, 20, 40, 40, 40],
  64: <double>[6, 20, 40, 40, 40, 40],
};

/// Video matching compares audio fingerprints, so its differences are seconds, not bits.
const List<double> videoSimilarityThresholds = <double>[2.5, 5, 10, 20, 30, 40];

class FormatStat {
  const FormatStat({
    required this.format,
    required this.count,
    required this.bytes,
    required this.countPercent,
    required this.bytesPercent,
  });

  final String format;
  final int count;
  final int bytes;
  final double countPercent;
  final double bytesPercent;
}

class SimilarityStat {
  const SimilarityStat({
    required this.level,
    required this.range,
    required this.count,
    required this.percent,
  });

  final SimilarityLevel level;
  final String range;
  final int count;
  final double percent;
}

/// Groups the result rows by file extension, heaviest first.
List<FormatStat> buildFormatStats(List<ScanRow> rows, {String tool = ''}) {
  final Map<String, _FormatTotals> totals = <String, _FormatTotals>{};
  int totalBytes = 0;
  for (final ScanRow row in rows) {
    final String format = tool == 'empty_folders'
        ? 'folder'
        : extensionOf(row.path);
    final _FormatTotals current = totals[format] ?? _FormatTotals();
    current.count += 1;
    current.bytes += row.sizeBytes;
    totals[format] = current;
    totalBytes += row.sizeBytes;
  }
  final List<String> keys = totals.keys.toList()
    ..sort(
      (String left, String right) =>
          _compareFormats(totals[left]!, totals[right]!, left, right),
    );
  return keys
      .map(
        (String format) => FormatStat(
          format: format,
          count: totals[format]!.count,
          bytes: totals[format]!.bytes,
          countPercent: rows.isEmpty
              ? 0
              : totals[format]!.count / rows.length * 100,
          bytesPercent: totalBytes == 0
              ? 0
              : totals[format]!.bytes / totalBytes * 100,
        ),
      )
      .toList();
}

/// Counts the result rows in the engine's own similarity levels, emptiest level last.
///
/// Kisaki reads the difference from the bridge's numeric sort key rather than parsing the printed
/// level word, so a translated cell cannot silently drop a row from the histogram.
List<SimilarityStat> buildSimilarityStats(
  List<ScanRow> rows, {
  int hashSize = 16,
  String tool = '',
  int differenceIndex = -1,
}) {
  if (differenceIndex < 0) {
    return const <SimilarityStat>[];
  }
  final List<double> thresholds = tool == 'similar_videos'
      ? videoSimilarityThresholds
      : (similarityThresholds[normalizeHashSize(hashSize)] ??
            similarityThresholds[16]!);
  final Map<SimilarityLevel, int> counts = <SimilarityLevel, int>{};
  int total = 0;
  for (final ScanRow row in rows) {
    if (row.isReference || differenceIndex >= row.sortKeys.length) {
      continue;
    }
    final SimilarityLevel level = similarityLevel(
      row.sortKeys[differenceIndex].toDouble(),
      thresholds,
    );
    counts[level] = (counts[level] ?? 0) + 1;
    total += 1;
  }
  return <SimilarityStat>[
    for (final (int index, SimilarityLevel level) in similarityLevels.indexed)
      if ((counts[level] ?? 0) > 0)
        SimilarityStat(
          level: level,
          range: similarityRange(level, index, thresholds),
          count: counts[level]!,
          percent: total == 0 ? 0 : counts[level]! / total * 100,
        ),
  ];
}

/// The difference limits each level accepts at every hash size, for the reader who has to choose one.
List<SimilarityReferenceRow> buildSimilarityReference() =>
    <SimilarityReferenceRow>[
      for (final (int index, SimilarityLevel level) in similarityLevels.indexed)
        SimilarityReferenceRow(
          level: level,
          ranges: <int, String>{
            for (final int hashSize in similarityHashSizes)
              hashSize: similarityRange(
                level,
                index,
                similarityThresholds[hashSize]!,
              ),
          },
        ),
    ];

class SimilarityReferenceRow {
  const SimilarityReferenceRow({required this.level, required this.ranges});

  final SimilarityLevel level;
  final Map<int, String> ranges;
}

int normalizeHashSize(int hashSize) =>
    similarityHashSizes.contains(hashSize) ? hashSize : 16;

SimilarityLevel similarityLevel(double value, List<double> thresholds) {
  if (value == 0) {
    return SimilarityLevel.original;
  }
  final int index = thresholds.indexWhere(
    (double threshold) => value <= threshold,
  );
  if (index < 0) {
    return SimilarityLevel.minimal;
  }
  return index + 1 < similarityLevels.length
      ? similarityLevels[index + 1]
      : SimilarityLevel.minimal;
}

String similarityRange(
  SimilarityLevel level,
  int index,
  List<double> thresholds,
) {
  if (level == SimilarityLevel.original) {
    return '= 0';
  }
  final int cut = index - 1 < 0 ? 0 : index - 1;
  final double? threshold = cut < thresholds.length ? thresholds[cut] : null;
  return '\u2264 ${formatThreshold(threshold ?? thresholds.last)}';
}

/// Prints 2.5 as `2.5` and 5.0 as `5`, so a whole threshold does not gain a false decimal.
String formatThreshold(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

/// The lower-case extension, or `unknown` for a path that has none.
String extensionOf(String path) {
  final String name = path.replaceAll(r'\', '/').split('/').last;
  final int index = name.lastIndexOf('.');
  if (index > 0 && index < name.length - 1) {
    return name.substring(index + 1).toLowerCase();
  }
  return 'unknown';
}

int _compareFormats(
  _FormatTotals left,
  _FormatTotals right,
  String leftName,
  String rightName,
) {
  if (left.bytes != right.bytes) {
    return right.bytes - left.bytes;
  }
  if (left.count != right.count) {
    return right.count - left.count;
  }
  return leftName.compareTo(rightName);
}

class _FormatTotals {
  int count = 0;
  int bytes = 0;
}
