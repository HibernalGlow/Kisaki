import 'dart:collection';
import 'dart:convert';

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
      directories: uniquePaths(
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

/// Insertion-ordered de-duplication, matching the `Set` the reference builds paths through.
List<String> uniquePaths(Iterable<String> values) =>
    LinkedHashSet<String>.of(values).toList();
