import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import '../engine/models.dart';

/// Dart port of `packages/nodes/czkawka/src/selection-assistant.ts`.
///
/// The wire names are the reference's on purpose, so a Kisaki assistant document stays readable by
/// the same format.
enum SelectionApplyMode {
  replace('replace'),
  add('add'),
  remove('remove'),
  intersect('intersect');

  const SelectionApplyMode(this.wire);
  final String wire;

  static SelectionApplyMode fromWire(String? value) =>
      SelectionApplyMode.values.firstWhere(
        (SelectionApplyMode mode) => mode.wire == value,
        orElse: () => SelectionApplyMode.replace,
      );
}

enum GroupSelectionMode {
  allExceptOne('all-except-one'),
  selectOne('select-one'),
  allExceptOnePerFolder('all-except-one-per-folder'),
  allExceptOneMatchingSet('all-except-one-matching-set');

  const GroupSelectionMode(this.wire);
  final String wire;

  static GroupSelectionMode fromWire(String? value) =>
      GroupSelectionMode.values.firstWhere(
        (GroupSelectionMode mode) => mode.wire == value,
        orElse: () => GroupSelectionMode.allExceptOne,
      );
}

/// `creationDate`, `resolution`, `hash` and `hardLinks` have no value on a Kisaki row yet, so they
/// rank as empty until the bridge publishes them.
enum SelectionSortField {
  folderPath('folderPath'),
  fileName('fileName'),
  fileSize('fileSize'),
  creationDate('creationDate'),
  modifiedDate('modifiedDate'),
  resolution('resolution'),
  disk('disk'),
  fileType('fileType'),
  hash('hash'),
  hardLinks('hardLinks');

  const SelectionSortField(this.wire);
  final String wire;

  static SelectionSortField fromWire(String? value) =>
      SelectionSortField.values.firstWhere(
        (SelectionSortField field) => field.wire == value,
        orElse: () => SelectionSortField.modifiedDate,
      );
}

enum MatchCondition {
  none('none'),
  contains('contains'),
  notContains('not-contains'),
  startsWith('starts-with'),
  endsWith('ends-with'),
  equals('equals');

  const MatchCondition(this.wire);
  final String wire;

  static MatchCondition fromWire(String? value) =>
      MatchCondition.values.firstWhere(
        (MatchCondition condition) => condition.wire == value,
        orElse: () => MatchCondition.none,
      );
}

enum SelectionTextColumn {
  fullPath('fullPath'),
  fileName('fileName'),
  folderPath('folderPath');

  const SelectionTextColumn(this.wire);
  final String wire;

  static SelectionTextColumn fromWire(String? value) =>
      SelectionTextColumn.values.firstWhere(
        (SelectionTextColumn column) => column.wire == value,
        orElse: () => SelectionTextColumn.fullPath,
      );
}

enum DirectorySelectionMode {
  keepOnePerDirectory('keep-one-per-directory'),
  selectAllInDirectory('select-all-in-directory'),
  excludeDirectory('exclude-directory');

  const DirectorySelectionMode(this.wire);
  final String wire;

  static DirectorySelectionMode fromWire(String? value) =>
      DirectorySelectionMode.values.firstWhere(
        (DirectorySelectionMode mode) => mode.wire == value,
        orElse: () => DirectorySelectionMode.keepOnePerDirectory,
      );
}

enum SortDirection {
  asc('asc'),
  desc('desc');

  const SortDirection(this.wire);
  final String wire;

  static SortDirection fromWire(String? value) =>
      SortDirection.values.firstWhere(
        (SortDirection direction) => direction.wire == value,
        orElse: () => SortDirection.desc,
      );
}

/// Which of the assistant's three rule tabs an apply came from.
enum AssistantRuleKind {
  group('group'),
  text('text'),
  directory('directory');

  const AssistantRuleKind(this.wire);
  final String wire;
}

class SelectionSortCriterion {
  const SelectionSortCriterion({
    required this.id,
    required this.field,
    required this.direction,
    this.preferEmpty = false,
    this.enabled = true,
    this.filterCondition = MatchCondition.none,
    this.filterValue = '',
  });

  final String id;
  final SelectionSortField field;
  final SortDirection direction;
  final bool preferEmpty;
  final bool enabled;
  final MatchCondition filterCondition;
  final String filterValue;

  SelectionSortCriterion copyWith({
    SelectionSortField? field,
    SortDirection? direction,
    bool? preferEmpty,
    bool? enabled,
    MatchCondition? filterCondition,
    String? filterValue,
  }) => SelectionSortCriterion(
    id: id,
    field: field ?? this.field,
    direction: direction ?? this.direction,
    preferEmpty: preferEmpty ?? this.preferEmpty,
    enabled: enabled ?? this.enabled,
    filterCondition: filterCondition ?? this.filterCondition,
    filterValue: filterValue ?? this.filterValue,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'field': field.wire,
    'direction': direction.wire,
    'preferEmpty': preferEmpty,
    'enabled': enabled,
    'filterCondition': filterCondition.wire,
    'filterValue': filterValue,
  };

  static SelectionSortCriterion fromJson(
    Map<String, Object?> json,
    int index,
  ) => SelectionSortCriterion(
    id: _asString(json['id']) ?? 'criterion-$index',
    field: SelectionSortField.fromWire(_asString(json['field'])),
    direction: SortDirection.fromWire(_asString(json['direction'])),
    preferEmpty: _asBool(json['preferEmpty']) ?? false,
    enabled: _asBool(json['enabled']) ?? true,
    filterCondition: MatchCondition.fromWire(
      _asString(json['filterCondition']),
    ),
    filterValue: _asString(json['filterValue']) ?? '',
  );
}

class GroupRule {
  GroupRule({required this.mode, required this.sortCriteria});

  final GroupSelectionMode mode;
  final List<SelectionSortCriterion> sortCriteria;

  GroupRule copyWith({
    GroupSelectionMode? mode,
    List<SelectionSortCriterion>? sortCriteria,
  }) => GroupRule(
    mode: mode ?? this.mode,
    sortCriteria:
        sortCriteria ?? List<SelectionSortCriterion>.of(this.sortCriteria),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.wire,
    'sortCriteria': sortCriteria
        .map((SelectionSortCriterion item) => item.toJson())
        .toList(),
  };
}

class TextRule {
  TextRule({
    required this.column,
    required this.condition,
    required this.pattern,
    this.useRegex = false,
    this.caseSensitive = false,
    this.matchWholeColumn = false,
  });

  final SelectionTextColumn column;
  final MatchCondition condition;
  final String pattern;
  final bool useRegex;
  final bool caseSensitive;
  final bool matchWholeColumn;

  TextRule copyWith({
    SelectionTextColumn? column,
    MatchCondition? condition,
    String? pattern,
    bool? useRegex,
    bool? caseSensitive,
    bool? matchWholeColumn,
  }) => TextRule(
    column: column ?? this.column,
    condition: condition ?? this.condition,
    pattern: pattern ?? this.pattern,
    useRegex: useRegex ?? this.useRegex,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    matchWholeColumn: matchWholeColumn ?? this.matchWholeColumn,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'column': column.wire,
    'condition': condition.wire,
    'pattern': pattern,
    'useRegex': useRegex,
    'caseSensitive': caseSensitive,
    'matchWholeColumn': matchWholeColumn,
  };
}

class DirectoryRule {
  DirectoryRule({required this.mode, required this.directories});

  final DirectorySelectionMode mode;
  final List<String> directories;

  DirectoryRule copyWith({
    DirectorySelectionMode? mode,
    List<String>? directories,
  }) => DirectoryRule(
    mode: mode ?? this.mode,
    directories: directories ?? List<String>.of(this.directories),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.wire,
    'directories': directories,
  };
}

class SelectionConfig {
  SelectionConfig({
    required this.applyMode,
    required this.group,
    required this.text,
    required this.directory,
  });

  final SelectionApplyMode applyMode;
  final GroupRule group;
  final TextRule text;
  final DirectoryRule directory;

  factory SelectionConfig.defaults() => SelectionConfig(
    applyMode: SelectionApplyMode.replace,
    group: GroupRule(
      mode: GroupSelectionMode.allExceptOne,
      sortCriteria: const <SelectionSortCriterion>[
        SelectionSortCriterion(
          id: 'modified',
          field: SelectionSortField.modifiedDate,
          direction: SortDirection.desc,
        ),
      ],
    ),
    text: TextRule(
      column: SelectionTextColumn.fullPath,
      condition: MatchCondition.contains,
      pattern: '',
    ),
    directory: DirectoryRule(
      mode: DirectorySelectionMode.keepOnePerDirectory,
      directories: const <String>[],
    ),
  );

  SelectionConfig copyWith({
    SelectionApplyMode? applyMode,
    GroupRule? group,
    TextRule? text,
    DirectoryRule? directory,
  }) => SelectionConfig(
    applyMode: applyMode ?? this.applyMode,
    group: group ?? this.group,
    text: text ?? this.text,
    directory: directory ?? this.directory,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'applyMode': applyMode.wire,
    'group': group.toJson(),
    'text': text.toJson(),
    'directory': directory.toJson(),
  };
}

class SelectionResult {
  const SelectionResult({
    required this.paths,
    required this.matchedPaths,
    required this.affectedCount,
    this.error,
    this.directoryRequired = false,
  });

  final List<String> paths;
  final List<String> matchedPaths;
  final int affectedCount;
  final String? error;
  final bool directoryRequired;
}

class SelectionStats {
  const SelectionStats({
    required this.selectedCount,
    required this.selectedBytes,
    required this.reclaimableBytes,
  });

  final int selectedCount;
  final int selectedBytes;
  final int reclaimableBytes;

  @override
  bool operator ==(Object other) =>
      other is SelectionStats &&
      other.selectedCount == selectedCount &&
      other.selectedBytes == selectedBytes &&
      other.reclaimableBytes == reclaimableBytes;

  @override
  int get hashCode =>
      Object.hash(selectedCount, selectedBytes, reclaimableBytes);
}

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
      paths: _unique(current),
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
      paths: _unique(current),
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
  present: _unique(initial),
  future: const <List<String>>[],
  limit: limit,
);

SelectionHistory pushSelectionHistory(
  SelectionHistory history,
  Iterable<String> paths,
) {
  final List<String> next = _unique(paths);
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

String serializeSelectionConfig(SelectionConfig config) =>
    jsonEncode(<String, Object?>{'version': 1, 'config': config.toJson()});

SelectionConfig parseSelectionConfig(String document) {
  final Object? decoded = jsonDecode(document);
  final Map<String, Object?> root = _asMap(decoded);
  if (root.isEmpty ||
      root['version'] != 1 ||
      _asMap(root['config']).isEmpty ||
      root['config'] is! Map) {
    throw const FormatException(
      'Unsupported Kisaki selection assistant document.',
    );
  }
  final Map<String, Object?> value = _asMap(root['config']);
  final Map<String, Object?> group = _asMap(value['group']);
  final Map<String, Object?> text = _asMap(value['text']);
  final Map<String, Object?> directory = _asMap(value['directory']);
  final List<Object?> criteria = group['sortCriteria'] is List
      ? group['sortCriteria'] as List<Object?>
      : const <Object?>[];
  final SelectionConfig defaults = SelectionConfig.defaults();
  return SelectionConfig(
    applyMode: SelectionApplyMode.fromWire(_asString(value['applyMode'])),
    group: GroupRule(
      mode: GroupSelectionMode.fromWire(_asString(group['mode'])),
      sortCriteria: criteria
          .asMap()
          .entries
          .map(
            (MapEntry<int, Object?> entry) =>
                SelectionSortCriterion.fromJson(_asMap(entry.value), entry.key),
          )
          .toList(),
    ),
    text: TextRule(
      column: SelectionTextColumn.fromWire(_asString(text['column'])),
      condition: MatchCondition.fromWire(_asString(text['condition'])),
      pattern: _asString(text['pattern']) ?? defaults.text.pattern,
      useRegex: _asBool(text['useRegex']) ?? defaults.text.useRegex,
      caseSensitive:
          _asBool(text['caseSensitive']) ?? defaults.text.caseSensitive,
      matchWholeColumn:
          _asBool(text['matchWholeColumn']) ?? defaults.text.matchWholeColumn,
    ),
    directory: DirectoryRule(
      mode: DirectorySelectionMode.fromWire(_asString(directory['mode'])),
      directories: _unique(
        (directory['directories'] is List
                ? directory['directories'] as List<Object?>
                : const <Object?>[])
            .map((Object? item) => _asString(item) ?? '')
            .where((String item) => item.isNotEmpty),
      ),
    ),
  );
}

Map<String, Object?> _asMap(Object? value) => value is Map
    ? value.map(
        (Object? key, Object? item) => MapEntry<String, Object?>('$key', item),
      )
    : const <String, Object?>{};

String? _asString(Object? value) => value is String ? value : null;

bool? _asBool(Object? value) => value is bool ? value : null;

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
    return _naturalCompare(left.path, right.path);
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
      : _naturalCompare('$left', '$right');
  return criterion.direction == SortDirection.desc ? -compared : compared;
}

SelectionResult _selectionResult(
  Iterable<String> current,
  Set<String> matched,
  SelectionApplyMode mode,
) {
  final List<String> before = _unique(current);
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
/// `file10`; a plain code-unit compare would put it after.
int _naturalCompare(String left, String right) {
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

List<String> _unique(Iterable<String> values) =>
    LinkedHashSet<String>.of(values).toList();

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
