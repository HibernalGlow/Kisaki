part of 'board_controller.dart';

/// The distribution figures the analysis lane paints from the rows the board already holds.
extension BoardAnalysis on BoardController {
  /// The image scanner's hash size, because the same difference means a different level at 8 and 64.
  int get analysisHashSize {
    final FieldPayload payload = valueOf('img_hash_size').value;
    final int? parsed = switch (payload) {
      FieldPayloadChoice(value: final String text) => int.tryParse(text),
      FieldPayloadInteger(value: final int number) => number,
      _ => null,
    };
    return normalizeHashSize(parsed ?? 16);
  }

  /// The numeric sort key behind the difference column, or -1 when the tool has none.
  int get differenceIndex {
    final ToolSpec? spec = _tool;
    if (spec == null) {
      return -1;
    }
    return spec.columns.indexWhere(
      (ColumnDef column) => column.key == 'difference',
    );
  }

  bool get hasSimilarityStats => differenceIndex >= 0;

  /// The two scanners whose thresholds a reader has to reason about, whichever column they fill.
  bool get supportsSimilarityReference {
    final String? id = _tool?.id;
    return id == 'similar_images' || id == 'similar_videos';
  }

  List<FormatStat> get formatStats =>
      buildFormatStats(_rows, tool: _tool?.id ?? '');

  List<SimilarityStat> get similarityStats => buildSimilarityStats(
    _rows,
    hashSize: analysisHashSize,
    tool: _tool?.id ?? '',
    differenceIndex: differenceIndex,
  );
}
