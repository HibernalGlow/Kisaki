import '../engine/models.dart';
import '../util/format.dart';

enum GroupSelection { none, partial, all }

/// The text the table shows for one cell. The engine formats its date column in UTC, so a date
/// column is rebuilt from the row's epoch and shown in the reader's own zone instead.
String displayCell(ColumnDef column, ScanRow row, int index) {
  if (column.key == 'modified' && row.modifiedTs > 0) {
    return humanDate(row.modifiedTs);
  }
  return index < row.cells.length ? row.cells[index] : '';
}

GroupSelection groupSelectionOf(List<ScanRow> members, Set<String> selected) {
  if (members.isEmpty) {
    return GroupSelection.none;
  }
  final int hits = members
      .where((ScanRow row) => selected.contains(row.path))
      .length;
  if (hits == 0) {
    return GroupSelection.none;
  }
  return hits == members.length ? GroupSelection.all : GroupSelection.partial;
}

/// Turns the canonical scan result into what the table shows: filter first, then sort.
///
/// Grouped scanners sort inside each block so a group never splits across the table.
List<ScanRow> projectRows({
  required List<ScanRow> rows,
  required ToolSpec? tool,
  required String filter,
  required int sortColumn,
  required bool sortAscending,
}) {
  final String query = filter.trim().toLowerCase();
  final List<ScanRow> result = query.isEmpty
      ? List<ScanRow>.of(rows)
      : rows
            .where(
              (ScanRow row) =>
                  row.path.toLowerCase().contains(query) ||
                  row.name.toLowerCase().contains(query) ||
                  row.cells.any(
                    (String cell) => cell.toLowerCase().contains(query),
                  ),
            )
            .toList();
  if (sortColumn < 0) {
    return result;
  }

  final int direction = sortAscending ? 1 : -1;
  int keyOf(ScanRow row) {
    final List<ColumnDef>? columns = tool?.columns;
    if (columns != null && sortColumn < columns.length) {
      final String key = columns[sortColumn].key;
      if (key == 'size') {
        return row.sizeBytes;
      }
      if (key == 'modified') {
        return row.modifiedTs;
      }
    }
    return sortColumn < row.sortKeys.length ? row.sortKeys[sortColumn] : 0;
  }

  if (tool != null && tool.grouped) {
    final Map<int, List<ScanRow>> blocks = <int, List<ScanRow>>{};
    for (final ScanRow row in result) {
      blocks.putIfAbsent(row.groupIndex, () => <ScanRow>[]).add(row);
    }
    final List<int> order = blocks.keys.toList()..sort();
    return order.expand((int group) {
      final List<ScanRow> block = blocks[group]!
        ..sort(
          (ScanRow a, ScanRow b) => direction * keyOf(a).compareTo(keyOf(b)),
        );
      return block;
    }).toList();
  }

  result.sort((ScanRow a, ScanRow b) {
    final int byKey = direction * keyOf(a).compareTo(keyOf(b));
    return byKey != 0 ? byKey : a.path.compareTo(b.path);
  });
  return result;
}

/// Port of `formatReversePath`: the leaf comes first, so a long shared prefix stops hiding the part
/// that actually differs. A path with nothing to reverse is shown as it is.
String formatReversePath(String path) {
  final String normalized = path.replaceAll(r'\', '/');
  final String prefix = normalized.startsWith('//') ? '//' : '';
  final List<String> parts = normalized
      .substring(prefix.length)
      .split('/')
      .where((String part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) {
    return path;
  }
  return parts.reversed.join(' \u2039 ');
}
