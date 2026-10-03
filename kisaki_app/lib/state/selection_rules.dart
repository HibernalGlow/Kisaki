import 'dart:math' as math;

import '../engine/models.dart';
import 'selection_model.dart';

/// The rule half of the ported assistant: it turns a saved configuration into a path selection
/// and keeps the undo and redo stack, exactly like `selection-assistant.ts`.
SelectionResult applyGroupSelection({
  required List<List<ScanRow>> groups,
  required Iterable<String> current,
  required GroupRule rule,
  SelectionApplyMode mode = SelectionApplyMode.replace,
}) {
  final Set<String> matched = <String>{};
  for (final List<ScanRow> group in groups) {
    matched.addAll(_groupCandidates(group, rule));
  }
  return _selectionResult(current, matched, mode);
}

SelectionResult applyTextSelection({
  required List<List<ScanRow>> groups,
  required Iterable<String> current,
  required TextRule rule,
  SelectionApplyMode mode = SelectionApplyMode.replace,
}) {
  final _Matcher matcher = _createMatcher(
    rule.pattern,
    rule.caseSensitive,
    rule.useRegex,
    rule.matchWholeColumn ? MatchCondition.equals : rule.condition,
  );
  if (matcher.error != null) {
    return SelectionResult(
      paths: uniquePaths(current),
      matchedPaths: const <String>[],
      affectedCount: 0,
      error: matcher.error,
    );
  }
  final Set<String> matched = <String>{};
  for (final ScanRow row in _selectableRows(groups)) {
    if (matcher.matches(_textColumn(row.path, rule.column))) {
      matched.add(row.path);
    }
  }
  return _selectionResult(current, matched, mode);
}

SelectionResult applyDirectorySelection({
  required List<List<ScanRow>> groups,
  required Iterable<String> current,
  required DirectoryRule rule,
  SelectionApplyMode mode = SelectionApplyMode.replace,
}) {
  if (rule.mode != DirectorySelectionMode.keepOnePerDirectory &&
      rule.directories.isEmpty) {
    return SelectionResult(
      paths: uniquePaths(current),
      matchedPaths: const <String>[],
      affectedCount: 0,
      error: 'At least one directory is required.',
      directoryRequired: true,
    );
  }
  final Set<String> matched = <String>{};
  if (rule.mode == DirectorySelectionMode.keepOnePerDirectory) {
    for (final List<ScanRow> group in groups) {
      final Map<String, List<ScanRow>> byDirectory = <String, List<ScanRow>>{};
      for (final ScanRow row in group) {
        if (row.isReference) {
          continue;
        }
        byDirectory.putIfAbsent(_dirName(row.path), () => <ScanRow>[]).add(row);
      }
      for (final List<ScanRow> rows in byDirectory.values) {
        matched.addAll(rows.skip(1).map((ScanRow row) => row.path));
      }
    }
  } else {
    for (final ScanRow row in _selectableRows(groups)) {
      if (rule.directories.any(
        (String directory) => _isInDirectory(row.path, directory),
      )) {
        matched.add(row.path);
      }
    }
  }
  return _selectionResult(current, matched, mode);
}

List<String> applySelectionMode({
  required Iterable<String> current,
  required Iterable<String> matched,
  required SelectionApplyMode mode,
}) {
  final Set<String> before = current.toSet();
  final Set<String> candidates = matched.toSet();
  switch (mode) {
    case SelectionApplyMode.replace:
      return candidates.toList();
    case SelectionApplyMode.add:
      return <String>{...before, ...candidates}.toList();
    case SelectionApplyMode.remove:
      return before.where((String path) => !candidates.contains(path)).toList();
    case SelectionApplyMode.intersect:
      return before.where(candidates.contains).toList();
  }
}

List<String> invertSelection(
  List<List<ScanRow>> groups,
  Iterable<String> current,
) {
  final Set<String> selected = current.toSet();
  return _selectableRows(groups)
      .where((ScanRow row) => !selected.contains(row.path))
      .map((ScanRow row) => row.path)
      .toList();
}

List<String> selectAllEntries(List<List<ScanRow>> groups) =>
    _selectableRows(groups).map((ScanRow row) => row.path).toList();

SelectionStats selectionStats(
  List<List<ScanRow>> groups,
  Iterable<String> selectedPaths,
) {
  final Set<String> selected = selectedPaths.toSet();
  int selectedCount = 0;
  int selectedBytes = 0;
  int reclaimableBytes = 0;
  for (final List<ScanRow> group in groups) {
    final List<ScanRow> picked = group
        .where((ScanRow row) => !row.isReference && selected.contains(row.path))
        .toList();
    final int pickedBytes = _sumSizes(picked);
    selectedCount += picked.length;
    selectedBytes += pickedBytes;
    reclaimableBytes += math.min(_groupReclaimable(group), pickedBytes);
  }
  return SelectionStats(
    selectedCount: selectedCount,
    selectedBytes: selectedBytes,
    reclaimableBytes: reclaimableBytes,
  );
}

class SelectionHistory {
  const SelectionHistory({
    required this.past,
    required this.present,
    required this.future,
    this.limit = 50,
  });

  final List<List<String>> past;
  final List<String> present;
  final List<List<String>> future;
  final int limit;

  bool get canUndo => past.isNotEmpty;
  bool get canRedo => future.isNotEmpty;
}

SelectionHistory createSelectionHistory(
  Iterable<String> initial, {
  int limit = 50,
}) => SelectionHistory(
  past: const <List<String>>[],
  present: uniquePaths(initial),
  future: const <List<String>>[],
  limit: limit,
);

SelectionHistory pushSelectionHistory(
  SelectionHistory history,
  Iterable<String> paths,
) {
  final List<String> next = uniquePaths(paths);
  if (_samePaths(history.present, next)) {
    return history;
  }
  return SelectionHistory(
    past: _bounded(<List<String>>[
      ...history.past,
      history.present,
    ], history.limit),
    present: next,
    future: const <List<String>>[],
    limit: history.limit,
  );
}

SelectionHistory undoSelectionHistory(SelectionHistory history) {
  if (history.past.isEmpty) {
    return history;
  }
  return SelectionHistory(
    past: history.past.sublist(0, history.past.length - 1),
    present: history.past.last,
    future: <List<String>>[
      history.present,
      ...history.future,
    ].take(history.limit).toList(),
    limit: history.limit,
  );
}

SelectionHistory redoSelectionHistory(SelectionHistory history) {
  if (history.future.isEmpty) {
    return history;
  }
  return SelectionHistory(
    past: _bounded(<List<String>>[
      ...history.past,
      history.present,
    ], history.limit),
    present: history.future.first,
    future: history.future.sublist(1),
    limit: history.limit,
  );
}

List<String> _groupCandidates(List<ScanRow> group, GroupRule rule) {
  final List<ScanRow> entries = _sortRows(
    group.where((ScanRow row) => !row.isReference).toList(),
    rule.sortCriteria,
  );
  switch (rule.mode) {
    case GroupSelectionMode.selectOne:
      return entries.isEmpty ? const <String>[] : <String>[entries.first.path];
    case GroupSelectionMode.allExceptOne:
      return entries.skip(1).map((ScanRow row) => row.path).toList();
    case GroupSelectionMode.allExceptOnePerFolder:
      final Map<String, List<ScanRow>> byFolder = <String, List<ScanRow>>{};
      for (final ScanRow row in entries) {
        byFolder.putIfAbsent(_dirName(row.path), () => <ScanRow>[]).add(row);
      }
      return byFolder.values
          .expand(
            (List<ScanRow> rows) => rows.skip(1).map((ScanRow row) => row.path),
          )
          .toList();
    case GroupSelectionMode.allExceptOneMatchingSet:
      final SelectionSortCriterion? criterion = _firstWhere(
        rule.sortCriteria,
        (SelectionSortCriterion item) => item.enabled,
      );
      if (criterion == null) {
        return entries.skip(1).map((ScanRow row) => row.path).toList();
      }
      final Map<String, List<ScanRow>> sets = <String, List<ScanRow>>{};
      for (final ScanRow row in entries) {
        final Object? value = _fieldValue(row, criterion.field);
        sets
            .putIfAbsent(
              value == null ? '__empty__' : '$value',
              () => <ScanRow>[],
            )
            .add(row);
      }
      return sets.values
          .skip(1)
          .expand((List<ScanRow> rows) => rows.map((ScanRow row) => row.path))
          .toList();
  }
}

List<ScanRow> _sortRows(
  List<ScanRow> entries,
  List<SelectionSortCriterion> criteria,
) {
  final List<SelectionSortCriterion> enabled = criteria
      .where((SelectionSortCriterion criterion) => criterion.enabled)
      .toList();
  final List<SelectionSortCriterion> filtering = enabled
      .where(
        (SelectionSortCriterion criterion) =>
            criterion.filterCondition != MatchCondition.none &&
            criterion.filterValue.isNotEmpty,
      )
      .toList();
  final List<ScanRow> rows = filtering.isEmpty
      ? <ScanRow>[...entries]
      : entries
            .where(
              (ScanRow row) => filtering.every(
                (SelectionSortCriterion criterion) => _createMatcher(
                  criterion.filterValue,
                  false,
                  false,
                  criterion.filterCondition,
                ).matches('${_fieldValue(row, criterion.field) ?? ''}'),
              ),
            )
            .toList();
  rows.sort((ScanRow left, ScanRow right) {
    for (final SelectionSortCriterion criterion in enabled) {
      final int compared = _compareValues(
        _fieldValue(left, criterion.field),
        _fieldValue(right, criterion.field),
        criterion,
      );
      if (compared != 0) {
        return compared;
      }
    }
    return naturalCompare(left.path, right.path);
  });
  return rows;
}

Object? _fieldValue(ScanRow row, SelectionSortField field) {
  switch (field) {
    case SelectionSortField.folderPath:
      return _dirName(row.path);
    case SelectionSortField.fileName:
      return row.name;
    case SelectionSortField.fileSize:
      return row.sizeBytes;
    case SelectionSortField.modifiedDate:
      return row.modifiedTs;
    case SelectionSortField.disk:
      if (_drivePattern.hasMatch(row.path)) {
        return row.path.substring(0, 2).toUpperCase();
      }
      final List<String> parts = _normalize(row.path)
          .split('/')
          .where((String part) => part.isNotEmpty)
          .toList();
      return '/${parts.isEmpty ? '' : parts.first}';
    case SelectionSortField.fileType:
      return _extensionOf(row.name);
    case SelectionSortField.creationDate:
    case SelectionSortField.resolution:
    case SelectionSortField.hash:
    case SelectionSortField.hardLinks:
      return null;
  }
}

int _compareValues(
  Object? left,
  Object? right,
  SelectionSortCriterion criterion,
) {
  final bool leftEmpty = left == null || left == '';
  final bool rightEmpty = right == null || right == '';
  if (leftEmpty != rightEmpty) {
    final bool first = criterion.preferEmpty ? leftEmpty : !leftEmpty;
    return first ? -1 : 1;
  }
  final int compared = left is num && right is num
      ? left.compareTo(right)
      : naturalCompare('$left', '$right');
  return criterion.direction == SortDirection.desc ? -compared : compared;
}

SelectionResult _selectionResult(
  Iterable<String> current,
  Set<String> matched,
  SelectionApplyMode mode,
) {
  final List<String> before = uniquePaths(current);
  final List<String> paths = applySelectionMode(
    current: before,
    matched: matched,
    mode: mode,
  );
  return SelectionResult(
    paths: paths,
    matchedPaths: matched.toList(),
    affectedCount: _symmetricDifference(before, paths),
  );
}

class _Matcher {
  _Matcher(this._test, [this.error]);

  final bool Function(String value) _test;
  final String? error;

  bool matches(String value) => _test(value);
}

_Matcher _createMatcher(
  String pattern,
  bool caseSensitive,
  bool regex,
  MatchCondition condition,
) {
  if (pattern.isEmpty) {
    return _Matcher((String value) => false);
  }
  if (regex) {
    try {
      final RegExp expression = RegExp(pattern, caseSensitive: caseSensitive);
      return _Matcher(expression.hasMatch);
    } on FormatException catch (error) {
      return _Matcher((String value) => false, error.message);
    }
  }
  final String needle = caseSensitive ? pattern : pattern.toLowerCase();
  return _Matcher((String value) {
    final String candidate = caseSensitive ? value : value.toLowerCase();
    switch (condition) {
      case MatchCondition.contains:
        return candidate.contains(needle);
      case MatchCondition.notContains:
        return !candidate.contains(needle);
      case MatchCondition.startsWith:
        return candidate.startsWith(needle);
      case MatchCondition.endsWith:
        return candidate.endsWith(needle);
      case MatchCondition.equals:
        return candidate == needle;
      case MatchCondition.none:
        return true;
    }
  });
}

List<ScanRow> _selectableRows(List<List<ScanRow>> groups) => groups
    .expand(
      (List<ScanRow> group) => group.where((ScanRow row) => !row.isReference),
    )
    .toList();

String _textColumn(String path, SelectionTextColumn column) {
  switch (column) {
    case SelectionTextColumn.fullPath:
      return path;
    case SelectionTextColumn.fileName:
      final List<String> parts = _normalize(path).split('/');
      return parts.last.isEmpty ? path : parts.last;
    case SelectionTextColumn.folderPath:
      return _dirName(path);
  }
}

String _normalize(String path) => path.replaceAll(r'\', '/');

String _dirName(String path) {
  final String normalized = _normalize(path);
  final int index = normalized.lastIndexOf('/');
  return index > 0 ? normalized.substring(0, index) : '';
}

bool _isInDirectory(String path, String directory) {
  final String normalizedPath = _normalize(path).toLowerCase();
  final String normalizedDirectory = _normalize(directory)
      .replaceAll(RegExp(r'/$'), '')
      .toLowerCase();
  return normalizedPath == normalizedDirectory ||
      normalizedPath.startsWith('$normalizedDirectory/');
}

String _extensionOf(String name) {
  final int index = name.lastIndexOf('.');
  return index > 0 ? name.substring(index + 1).toLowerCase() : '';
}

/// The reference compares paths with `localeCompare(..., {numeric: true})`, so `file2` sorts before
/// `file10`; a plain code-unit compare would put it after. Shared with the folder ranking.
int naturalCompare(String left, String right) {
  int i = 0;
  int j = 0;
  while (i < left.length && j < right.length) {
    final int leftCode = left.codeUnitAt(i);
    final int rightCode = right.codeUnitAt(j);
    final bool leftDigit = _isDigit(leftCode);
    final bool rightDigit = _isDigit(rightCode);
    if (leftDigit && rightDigit) {
      final int startLeft = i;
      final int startRight = j;
      while (i < left.length && _isDigit(left.codeUnitAt(i))) {
        i++;
      }
      while (j < right.length && _isDigit(right.codeUnitAt(j))) {
        j++;
      }
      final String leftRun = _trimZeros(left.substring(startLeft, i));
      final String rightRun = _trimZeros(right.substring(startRight, j));
      if (leftRun.length != rightRun.length) {
        return leftRun.length - rightRun.length;
      }
      final int compared = leftRun.compareTo(rightRun);
      if (compared != 0) {
        return compared;
      }
      continue;
    }
    if (leftCode != rightCode) {
      return leftCode - rightCode;
    }
    i++;
    j++;
  }
  return (left.length - i) - (right.length - j);
}

bool _isDigit(int code) => code >= 48 && code <= 57;

final RegExp _drivePattern = RegExp(r'^[A-Za-z]:');

T? _firstWhere<T>(List<T> items, bool Function(T item) test) {
  for (final T item in items) {
    if (test(item)) {
      return item;
    }
  }
  return null;
}

String _trimZeros(String run) {
  int index = 0;
  while (index < run.length && run[index] == '0') {
    index++;
  }
  return run.substring(index);
}

int _sumSizes(List<ScanRow> rows) =>
    rows.fold<int>(0, (int sum, ScanRow row) => sum + row.sizeBytes);

/// `core.ts:565-569`: a group only reclaims bytes when it has several entries, references make
/// every other entry reclaimable, and otherwise one copy (the largest) stays.
int _groupReclaimable(List<ScanRow> group) {
  if (group.length <= 1) {
    return 0;
  }
  final bool hasReference = group.any((ScanRow row) => row.isReference);
  if (hasReference) {
    return _sumSizes(group.where((ScanRow row) => !row.isReference).toList());
  }
  return _sumSizes(group) -
      group.map((ScanRow row) => row.sizeBytes).reduce(math.max);
}

List<List<String>> _bounded(List<List<String>> states, int limit) =>
    states.length > limit ? states.sublist(states.length - limit) : states;

int _symmetricDifference(List<String> left, List<String> right) {
  final Set<String> before = left.toSet();
  final Set<String> after = right.toSet();
  return left.where((String path) => !after.contains(path)).length +
      right.where((String path) => !before.contains(path)).length;
}

bool _samePaths(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
