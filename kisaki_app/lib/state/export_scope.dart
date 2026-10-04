import '../engine/models.dart';

/// The three row sets a result can be exported from, from `czkawka/cards`' export card.
enum ExportScope {
  selected('export-scope-selected'),
  visible('export-scope-visible'),
  all('export-scope-all');

  const ExportScope(this.labelKey);

  final String labelKey;
}

/// Which rows the reader means.
///
/// The reference scopes `selected` to the whole result, not to the rows the filters leave: a row the
/// reader picked and then filtered away is still meant to be exported. `visible` is the opposite
/// answer, the filtered and sorted set, and an empty selection stays empty instead of quietly
/// falling back to everything.
List<ScanRow> rowsForScope({
  required ExportScope scope,
  required List<ScanRow> all,
  required List<ScanRow> visible,
  required Set<String> selected,
}) {
  return switch (scope) {
    ExportScope.all => List<ScanRow>.unmodifiable(all),
    ExportScope.visible => List<ScanRow>.unmodifiable(visible),
    ExportScope.selected =>
      all.where((ScanRow row) => selected.contains(row.path)).toList(),
  };
}
