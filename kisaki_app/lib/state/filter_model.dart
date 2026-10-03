import 'dart:convert';

import '../engine/models.dart';

/// A port of the engine-agnostic filter model in
/// `Xiranite/packages/nodes/czkawka/src/filters.ts`.
///
/// The wire names below are the reference's, on purpose: a Kisaki filter preset must be
/// interchangeable with one exported from the reference node, so a renamed value is a data break
/// rather than a refactor.
enum SizeUnit {
  b('B', 1),
  kb('KB', 1024),
  mb('MB', 1024 * 1024),
  gb('GB', 1024 * 1024 * 1024),
  tb('TB', 1024 * 1024 * 1024 * 1024);

  const SizeUnit(this.wire, this.multiplier);
  final String wire;
  final int multiplier;

  static SizeUnit? fromWire(String? value) {
    for (final SizeUnit unit in SizeUnit.values) {
      if (unit.wire == value) {
        return unit;
      }
    }
    return null;
  }
}

enum MarkFilter {
  all('all'),
  selected('selected'),
  unselected('unselected'),
  groupSomeSelected('group-some-selected'),
  groupAllSelected('group-all-selected'),
  groupNoneSelected('group-none-selected'),
  reference('reference');

  const MarkFilter(this.wire);
  final String wire;

  static MarkFilter fromWire(String? value) => MarkFilter.values.firstWhere(
    (MarkFilter mark) => mark.wire == value,
    orElse: () => MarkFilter.all,
  );
}

enum PathMatchMode {
  contains('contains'),
  notContains('not-contains'),
  startsWith('starts-with'),
  endsWith('ends-with'),
  regex('regex');

  const PathMatchMode(this.wire);
  final String wire;
}

enum DatePreset {
  today('today'),
  last7Days('last-7-days'),
  last30Days('last-30-days'),
  lastYear('last-year'),
  custom('custom');

  const DatePreset(this.wire);
  final String wire;
}

enum AspectRatio {
  any('any'),
  wide('16:9'),
  classic('4:3'),
  square('1:1');

  const AspectRatio(this.wire);
  final String wire;
}

enum FormatCategory {
  images('images'),
  videos('videos'),
  audio('audio'),
  documents('documents'),
  archives('archives'),
  folders('folders'),
  other('other');

  const FormatCategory(this.wire);
  final String wire;
}

enum TextField {
  name('name'),
  path('path'),
  metadata('metadata'),
  detail('detail');

  const TextField(this.wire);
  final String wire;
}

enum BuiltinPreset {
  none('none'),
  largeFiles('large-files'),
  smallFiles('small-files'),
  recentlyModified('recently-modified'),
  oldFiles('old-files');

  const BuiltinPreset(this.wire);
  final String wire;
}

/// Rows with no suffix at all are a real bucket in the reference's chips.
const String kNoExtension = '__no_extension__';

class RangeFilter {
  RangeFilter({this.enabled = false, this.min, this.max, this.unit});

  bool enabled;
  int? min;
  int? max;
  SizeUnit? unit;

  RangeFilter copy() =>
      RangeFilter(enabled: enabled, min: min, max: max, unit: unit);
}

class FilterState {
  FilterState({
    this.textEnabled = false,
    this.textPattern = '',
    this.textRegex = false,
    this.textCaseSensitive = false,
    List<TextField>? textFields,
    this.mark = MarkFilter.all,
    RangeFilter? groupCount,
    RangeFilter? groupSize,
    RangeFilter? fileSize,
    this.extensionMode = true,
    List<String>? extensions,
    List<FormatCategory>? excludedCategories,
    this.extensionEnabled = false,
    this.dateEnabled = false,
    this.datePreset = DatePreset.custom,
    this.dateStart,
    this.dateEnd,
    this.pathEnabled = false,
    this.pathMode = PathMatchMode.contains,
    this.pathPattern = '',
    this.pathCaseSensitive = false,
    RangeFilter? similarity,
    this.resolutionEnabled = false,
    this.minWidth,
    this.minHeight,
    this.maxWidth,
    this.maxHeight,
    this.aspectRatio = AspectRatio.any,
    this.showAllInFilteredGroups = true,
  }) : textFields = textFields ?? TextField.values.toList(),
       groupCount = groupCount ?? RangeFilter(min: 2, max: 100),
       groupSize =
           groupSize ?? RangeFilter(min: 0, max: 100, unit: SizeUnit.gb),
       fileSize = fileSize ?? RangeFilter(min: 0, max: 100, unit: SizeUnit.gb),
       extensions = extensions ?? <String>[],
       excludedCategories = excludedCategories ?? <FormatCategory>[],
       similarity = similarity ?? RangeFilter(min: 0, max: 100);

  bool textEnabled;
  String textPattern;
  bool textRegex;
  bool textCaseSensitive;
  List<TextField> textFields;

  MarkFilter mark;
  RangeFilter groupCount;
  RangeFilter groupSize;
  RangeFilter fileSize;

  bool extensionEnabled;

  /// `true` keeps the listed extensions, `false` drops them.
  bool extensionMode;
  List<String> extensions;
  List<FormatCategory> excludedCategories;

  bool dateEnabled;
  DatePreset datePreset;
  int? dateStart;
  int? dateEnd;

  bool pathEnabled;
  PathMatchMode pathMode;
  String pathPattern;
  bool pathCaseSensitive;

  RangeFilter similarity;

  bool resolutionEnabled;
  int? minWidth;
  int? minHeight;
  int? maxWidth;
  int? maxHeight;
  AspectRatio aspectRatio;

  bool showAllInFilteredGroups;

  static FilterState defaults() => FilterState();

  /// The document shape is the reference's, key for key.
  Map<String, Object?> toJson() => <String, Object?>{
    'text': <String, Object?>{
      'enabled': textEnabled,
      'pattern': textPattern,
      'regex': textRegex,
      'caseSensitive': textCaseSensitive,
      'fields': textFields
          .map((TextField field) => field.wire)
          .toList(growable: false),
    },
    'mark': mark.wire,
    'groupCount': _range(groupCount),
    'groupSize': _range(groupSize),
    'fileSize': _range(fileSize),
    'extension': <String, Object?>{
      'enabled': extensionEnabled,
      'mode': extensionMode ? 'include' : 'exclude',
      'extensions': extensions,
      'excludedCategories': excludedCategories
          .map((FormatCategory category) => category.wire)
          .toList(growable: false),
    },
    'modifiedDate': <String, Object?>{
      'enabled': dateEnabled,
      'preset': datePreset.wire,
      if (dateStart != null) 'start': dateStart,
      if (dateEnd != null) 'end': dateEnd,
    },
    'path': <String, Object?>{
      'enabled': pathEnabled,
      'mode': pathMode.wire,
      'pattern': pathPattern,
      'caseSensitive': pathCaseSensitive,
    },
    'similarity': _range(similarity),
    'resolution': <String, Object?>{
      'enabled': resolutionEnabled,
      if (minWidth != null) 'minWidth': minWidth,
      if (minHeight != null) 'minHeight': minHeight,
      if (maxWidth != null) 'maxWidth': maxWidth,
      if (maxHeight != null) 'maxHeight': maxHeight,
      'aspectRatio': aspectRatio.wire,
    },
    'showAllInFilteredGroups': showAllInFilteredGroups,
  };

  static Map<String, Object?> _range(RangeFilter range) => <String, Object?>{
    'enabled': range.enabled,
    if (range.min != null) 'min': range.min,
    if (range.max != null) 'max': range.max,
    if (range.unit != null) 'unit': range.unit!.wire,
  };

  /// Anything the document leaves out falls back to the default, like the reference's normalizer.
  factory FilterState.fromJson(Map<String, Object?> json) {
    final FilterState state = FilterState();
    final Map<String, Object?>? text = _section(json, 'text');
    if (text != null) {
      state.textEnabled = text['enabled'] == true;
      state.textPattern = text['pattern'] as String? ?? '';
      state.textRegex = text['regex'] == true;
      state.textCaseSensitive = text['caseSensitive'] == true;
      final List<String>? fields = (text['fields'] as List<Object?>?)
          ?.map((Object? value) => '$value')
          .toList();
      if (fields != null && fields.isNotEmpty) {
        state.textFields = fields
            .map(
              (String wire) => TextField.values.firstWhere(
                (TextField field) => field.wire == wire,
                orElse: () => TextField.name,
              ),
            )
            .toList();
      }
    }
    state.mark = MarkFilter.fromWire(json['mark'] as String?);
    state.groupCount = _rangeOf(json['groupCount'], state.groupCount);
    state.groupSize = _rangeOf(json['groupSize'], state.groupSize);
    state.fileSize = _rangeOf(json['fileSize'], state.fileSize);
    final Map<String, Object?>? extension = _section(json, 'extension');
    if (extension != null) {
      state.extensionEnabled = extension['enabled'] == true;
      state.extensionMode = extension['mode'] != 'exclude';
      state.extensions =
          (extension['extensions'] as List<Object?>? ?? <Object?>[])
              .map((Object? value) => '$value')
              .toList();
      state.excludedCategories =
          (extension['excludedCategories'] as List<Object?>? ?? <Object?>[])
              .map(
                (Object? value) => FormatCategory.values.firstWhere(
                  (FormatCategory category) => category.wire == '$value',
                  orElse: () => FormatCategory.other,
                ),
              )
              .toList();
    }
    final Map<String, Object?>? date = _section(json, 'modifiedDate');
    if (date != null) {
      state.dateEnabled = date['enabled'] == true;
      state.datePreset = DatePreset.values.firstWhere(
        (DatePreset preset) => preset.wire == date['preset'],
        orElse: () => DatePreset.custom,
      );
      state.dateStart = (date['start'] as num?)?.toInt();
      state.dateEnd = (date['end'] as num?)?.toInt();
    }
    final Map<String, Object?>? path = _section(json, 'path');
    if (path != null) {
      state.pathEnabled = path['enabled'] == true;
      state.pathMode = PathMatchMode.values.firstWhere(
        (PathMatchMode mode) => mode.wire == path['mode'],
        orElse: () => PathMatchMode.contains,
      );
      state.pathPattern = path['pattern'] as String? ?? '';
      state.pathCaseSensitive = path['caseSensitive'] == true;
    }
    state.similarity = _rangeOf(json['similarity'], state.similarity);
    final Map<String, Object?>? resolution = _section(json, 'resolution');
    if (resolution != null) {
      state.resolutionEnabled = resolution['enabled'] == true;
      state.minWidth = (resolution['minWidth'] as num?)?.toInt();
      state.minHeight = (resolution['minHeight'] as num?)?.toInt();
      state.maxWidth = (resolution['maxWidth'] as num?)?.toInt();
      state.maxHeight = (resolution['maxHeight'] as num?)?.toInt();
      state.aspectRatio = AspectRatio.values.firstWhere(
        (AspectRatio ratio) => ratio.wire == resolution['aspectRatio'],
        orElse: () => AspectRatio.any,
      );
    }
    if (json['showAllInFilteredGroups'] is bool) {
      state.showAllInFilteredGroups = json['showAllInFilteredGroups']! as bool;
    }
    return state;
  }

  static Map<String, Object?>? _section(
    Map<String, Object?> json,
    String key,
  ) => json[key] is Map<String, Object?>
      ? json[key]! as Map<String, Object?>
      : null;

  static RangeFilter _rangeOf(Object? raw, RangeFilter fallback) {
    if (raw is! Map<String, Object?>) {
      return fallback;
    }
    return RangeFilter(
      enabled: raw['enabled'] == true,
      min: (raw['min'] as num?)?.toInt(),
      max: (raw['max'] as num?)?.toInt(),
      unit: SizeUnit.fromWire(raw['unit'] as String?),
    );
  }

  /// Mirrors `applyCzkawkaBuiltinFilterPreset`, including its boundary numbers.
  static FilterState fromPreset(BuiltinPreset preset, {int? now}) {
    final FilterState state = FilterState();
    switch (preset) {
      case BuiltinPreset.largeFiles:
        state.fileSize
          ..enabled = true
          ..min = 100
          ..max = 102400
          ..unit = SizeUnit.mb;
      case BuiltinPreset.smallFiles:
        state.fileSize
          ..enabled = true
          ..min = 0
          ..max = 1024
          ..unit = SizeUnit.kb;
      case BuiltinPreset.recentlyModified:
        state.dateEnabled = true;
        state.datePreset = DatePreset.last30Days;
      case BuiltinPreset.oldFiles:
        state.dateEnabled = true;
        state.datePreset = DatePreset.custom;
        state.dateStart = 0;
        state.dateEnd = (now ?? _nowMs()) - 365 * 24 * 60 * 60 * 1000;
      case BuiltinPreset.none:
        break;
    }
    return state;
  }

  FilterState copy() => FilterState(
    textEnabled: textEnabled,
    textPattern: textPattern,
    textRegex: textRegex,
    textCaseSensitive: textCaseSensitive,
    textFields: List<TextField>.of(textFields),
    mark: mark,
    groupCount: groupCount.copy(),
    groupSize: groupSize.copy(),
    fileSize: fileSize.copy(),
    extensionEnabled: extensionEnabled,
    extensionMode: extensionMode,
    extensions: List<String>.of(extensions),
    excludedCategories: List<FormatCategory>.of(excludedCategories),
    dateEnabled: dateEnabled,
    datePreset: datePreset,
    dateStart: dateStart,
    dateEnd: dateEnd,
    pathEnabled: pathEnabled,
    pathMode: pathMode,
    pathPattern: pathPattern,
    pathCaseSensitive: pathCaseSensitive,
    similarity: similarity.copy(),
    resolutionEnabled: resolutionEnabled,
    minWidth: minWidth,
    minHeight: minHeight,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    aspectRatio: aspectRatio,
    showAllInFilteredGroups: showAllInFilteredGroups,
  );

  int get activeCount =>
      _on(textEnabled && textPattern.isNotEmpty) +
      _on(mark != MarkFilter.all) +
      _on(groupCount.enabled) +
      _on(groupSize.enabled) +
      _on(fileSize.enabled) +
      _on(
        extensionEnabled &&
            (extensions.isNotEmpty || excludedCategories.isNotEmpty),
      ) +
      _on(dateEnabled) +
      _on(pathEnabled && pathPattern.isNotEmpty) +
      _on(similarity.enabled) +
      _on(resolutionEnabled);

  static int _on(bool value) => value ? 1 : 0;
}

class ExtensionStat {
  ExtensionStat(this.extension)
    : totalCount = 0,
      filteredCount = 0,
      totalBytes = 0,
      filteredBytes = 0;
  final String extension;
  int totalCount;
  int filteredCount;
  int totalBytes;
  int filteredBytes;
}

class CategoryStat {
  CategoryStat(this.category) : totalCount = 0, filteredCount = 0;
  final FormatCategory category;
  int totalCount;
  int filteredCount;
}

class FilterStats {
  FilterStats({
    required this.totalItems,
    required this.filteredItems,
    required this.totalGroups,
    required this.filteredGroups,
    required this.selectedItems,
    required this.activeFilterCount,
    required this.extensions,
    required this.categories,
  });

  final int totalItems;
  final int filteredItems;
  final int totalGroups;
  final int filteredGroups;
  final int selectedItems;
  final int activeFilterCount;
  final List<ExtensionStat> extensions;
  final List<CategoryStat> categories;
}

class FilterResult {
  FilterResult({
    required this.rows,
    required this.stats,
    this.pathPatternError,
    this.textPatternError,
  });

  final List<ScanRow> rows;
  final FilterStats stats;
  final String? pathPatternError;
  final String? textPatternError;
}

/// Columns that carry metadata rather than a detail line, mirroring the reference's split of
/// `metadata` and `detail` fields.
const Set<String> _metadataKeys = <String>{
  'size',
  'modified',
  'similarity',
  'dimensions',
  'fps',
  'codec',
  'bitrate',
  'length',
  'title',
  'artist',
  'year',
};

bool supportsSimilarityFilter(ToolSpec? tool) => _isMedia(tool);
bool supportsResolutionFilter(ToolSpec? tool) => _isMedia(tool);

bool _isMedia(ToolSpec? tool) =>
    tool != null &&
    (tool.id == 'similar_images' || tool.id == 'similar_videos');

FilterResult applyFilters({
  required List<ScanRow> rows,
  required Set<String> selected,
  required FilterState state,
  ToolSpec? tool,
  int? now,
}) {
  final int stamp = now ?? _nowMs();
  final ({bool Function(String) match, String? error}) text = _textMatcher(
    state.textPattern,
    state.textCaseSensitive,
    state.textRegex,
  );
  final ({bool Function(String) match, String? error}) path = _pathMatcher(
    state.pathPattern,
    state.pathCaseSensitive,
    state.pathMode,
  );

  final List<ScanRow> kept = <ScanRow>[];
  for (final List<ScanRow> group in _groupsOf(rows, tool)) {
    if (!_matchesGroupRanges(group, state) ||
        !_matchesGroupMark(group, selected, state.mark)) {
      continue;
    }
    final List<ScanRow> matched = group
        .where(
          (ScanRow row) => _matchesEntry(
            row,
            group,
            selected,
            state,
            tool,
            stamp,
            text.match,
            path.match,
          ),
        )
        .toList();
    if (matched.isEmpty) {
      continue;
    }
    final bool entryFilter = _hasEntryFilter(state);
    kept.addAll(state.showAllInFilteredGroups && entryFilter ? group : matched);
  }

  return FilterResult(
    rows: kept,
    stats: _stats(rows, kept, selected, state, tool),
    pathPatternError: path.error,
    textPatternError: text.error,
  );
}

/// Groups rows the way the engine grouped them: `groupSize` is what the scanner reported, so a
/// single-member result never merges with an unrelated neighbour just because the selected tool
/// happens to be a grouped one. Group ids may repeat per tool, so rows travel in scan order.
List<List<ScanRow>> _groupsOf(List<ScanRow> rows, ToolSpec? tool) {
  final Map<Object, List<ScanRow>> blocks = <Object, List<ScanRow>>{};
  for (final ScanRow row in rows) {
    final Object key = row.groupSize > 1
        ? 'group-${row.groupIndex}'
        : 'row-${row.path}';
    blocks.putIfAbsent(key, () => <ScanRow>[]).add(row);
  }
  return blocks.values.toList();
}

bool _matchesGroupRanges(List<ScanRow> group, FilterState state) {
  final int bytes = group.fold<int>(
    0,
    (int sum, ScanRow row) => sum + row.sizeBytes,
  );
  if (state.groupCount.enabled &&
      !_inRange(group.length, state.groupCount.min, state.groupCount.max)) {
    return false;
  }
  if (state.groupSize.enabled &&
      !_inRange(
        bytes,
        _boundary(state.groupSize.min, state.groupSize.unit),
        _boundary(state.groupSize.max, state.groupSize.unit),
      )) {
    return false;
  }
  return true;
}

bool _matchesGroupMark(
  List<ScanRow> group,
  Set<String> selected,
  MarkFilter mark,
) {
  if (mark == MarkFilter.all ||
      mark == MarkFilter.selected ||
      mark == MarkFilter.unselected ||
      mark == MarkFilter.reference) {
    return true;
  }
  final List<ScanRow> selectable = group
      .where((ScanRow row) => !row.isReference)
      .toList();
  final int hits = selectable
      .where((ScanRow row) => selected.contains(row.path))
      .length;
  return switch (mark) {
    MarkFilter.groupSomeSelected => hits > 0 && hits < selectable.length,
    MarkFilter.groupAllSelected =>
      selectable.isNotEmpty && hits == selectable.length,
    _ => hits == 0,
  };
}

bool _matchesEntry(
  ScanRow row,
  List<ScanRow> group,
  Set<String> selected,
  FilterState state,
  ToolSpec? tool,
  int now,
  bool Function(String) textMatch,
  bool Function(String) pathMatch,
) {
  if (state.mark == MarkFilter.selected && !selected.contains(row.path)) {
    return false;
  }
  if (state.mark == MarkFilter.unselected &&
      (row.isReference || selected.contains(row.path))) {
    return false;
  }
  if (state.mark == MarkFilter.reference && !row.isReference) {
    return false;
  }
  if (state.textEnabled &&
      state.textPattern.isNotEmpty &&
      !textMatch(_searchText(row, tool, state.textFields))) {
    return false;
  }
  if (state.fileSize.enabled &&
      !_inRange(
        row.sizeBytes,
        _boundary(state.fileSize.min, state.fileSize.unit),
        _boundary(state.fileSize.max, state.fileSize.unit),
      )) {
    return false;
  }
  if (state.extensionEnabled) {
    if (state.excludedCategories.contains(_categoryOf(row, tool))) {
      return false;
    }
    if (state.extensions.isNotEmpty) {
      final Set<String> listed = state.extensions
          .map(_normalizeExtension)
          .toSet();
      final bool included = listed.contains(_extensionOf(row.path));
      if (state.extensionMode == !included) {
        return false;
      }
    }
  }
  if (state.dateEnabled && !_matchesDate(row.modifiedTs, state, now)) {
    return false;
  }
  if (state.pathEnabled &&
      state.pathPattern.isNotEmpty &&
      !pathMatch(row.path)) {
    return false;
  }
  if (state.similarity.enabled) {
    final double? value = _numberCell(row, tool, 'similarity');
    if (value == null ||
        value < 0 ||
        !_inRange(value, state.similarity.min, state.similarity.max)) {
      return false;
    }
  }
  if (state.resolutionEnabled && !_matchesResolution(row, tool, state)) {
    return false;
  }
  return true;
}

bool _hasEntryFilter(FilterState state) =>
    state.textEnabled ||
    state.mark == MarkFilter.selected ||
    state.mark == MarkFilter.unselected ||
    state.mark == MarkFilter.reference ||
    state.fileSize.enabled ||
    state.extensionEnabled ||
    state.dateEnabled ||
    state.pathEnabled ||
    state.similarity.enabled ||
    state.resolutionEnabled;

FilterStats _stats(
  List<ScanRow> all,
  List<ScanRow> kept,
  Set<String> selected,
  FilterState state,
  ToolSpec? tool,
) {
  final Map<String, ExtensionStat> extensions = <String, ExtensionStat>{};
  final Map<FormatCategory, CategoryStat> categories =
      <FormatCategory, CategoryStat>{};

  void tally(Iterable<ScanRow> rows, {required bool filtered}) {
    for (final ScanRow row in rows) {
      final String extension = _extensionOf(row.path);
      final String key = extension.isEmpty ? kNoExtension : extension;
      final ExtensionStat bucket = extensions.putIfAbsent(
        key,
        () => ExtensionStat(key),
      );
      if (!filtered) {
        bucket.totalCount++;
        bucket.totalBytes += row.sizeBytes;
      } else {
        bucket.filteredCount++;
        bucket.filteredBytes += row.sizeBytes;
      }
      final FormatCategory category = _categoryOf(row, tool);
      final CategoryStat categoryBucket = categories.putIfAbsent(
        category,
        () => CategoryStat(category),
      );
      if (filtered) {
        categoryBucket.filteredCount++;
      } else {
        categoryBucket.totalCount++;
      }
    }
  }

  tally(all, filtered: false);
  tally(kept, filtered: true);

  final List<ExtensionStat> byExtension = extensions.values.toList()
    ..sort(
      (ExtensionStat a, ExtensionStat b) =>
          b.filteredCount - a.filteredCount != 0
          ? b.filteredCount - a.filteredCount
          : b.totalCount - a.totalCount != 0
          ? b.totalCount - a.totalCount
          : a.extension.compareTo(b.extension),
    );
  final List<CategoryStat> byCategory = categories.values.toList()
    ..sort(
      (CategoryStat a, CategoryStat b) =>
          _categoryOrder.indexOf(a.category) -
          _categoryOrder.indexOf(b.category),
    );

  return FilterStats(
    totalItems: all.length,
    filteredItems: kept.length,
    totalGroups: _groupsOf(all, tool).length,
    filteredGroups: _groupsOf(kept, tool).length,
    selectedItems: all
        .where((ScanRow row) => selected.contains(row.path))
        .length,
    activeFilterCount: state.activeCount,
    extensions: byExtension,
    categories: byCategory,
  );
}

bool _matchesDate(int value, FilterState state, int now) {
  final int timestamp = value > 0 && value < 10000000000 ? value * 1000 : value;
  const int day = 24 * 60 * 60 * 1000;
  int start = state.dateStart ?? 0;
  int end = state.dateEnd ?? 1 << 62;
  switch (state.datePreset) {
    case DatePreset.today:
      // Local midnight, like the reference's setHours(0, 0, 0, 0).
      final DateTime day = DateTime.fromMillisecondsSinceEpoch(now);
      start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
      end = now;
    case DatePreset.last7Days:
      start = now - 7 * day;
      end = now;
    case DatePreset.last30Days:
      start = now - 30 * day;
      end = now;
    case DatePreset.lastYear:
      start = now - 365 * day;
      end = now;
    case DatePreset.custom:
      break;
  }
  return timestamp >= start && timestamp <= end;
}

bool _matchesResolution(ScanRow row, ToolSpec? tool, FilterState state) {
  final (int, int)? size = _dimensions(row, tool);
  if (size == null) {
    return false;
  }
  if (!_inRange(size.$1, state.minWidth, state.maxWidth) ||
      !_inRange(size.$2, state.minHeight, state.maxHeight)) {
    return false;
  }
  if (state.aspectRatio == AspectRatio.any) {
    return true;
  }
  final List<String> parts = state.aspectRatio.wire.split(':');
  final double expected = double.parse(parts.first) / double.parse(parts.last);
  return (size.$1 / size.$2 - expected).abs() <= 0.02;
}

double? _numberCell(ScanRow row, ToolSpec? tool, String key) {
  final int index = _columnIndex(tool, key);
  if (index < 0 || index >= row.cells.length) {
    return null;
  }
  final RegExp leading = RegExp(r'-?\d+(\.\d+)?');
  final Match? found = leading.firstMatch(row.cells[index]);
  return found == null ? null : double.parse(found.group(0)!);
}

(int, int)? _dimensions(ScanRow row, ToolSpec? tool) {
  final int index = _columnIndex(tool, 'dimensions');
  if (index < 0 || index >= row.cells.length) {
    return null;
  }
  final RegExp pattern = RegExp(r'(\d+)\s*[x×]\s*(\d+)');
  final Match? found = pattern.firstMatch(row.cells[index]);
  if (found == null) {
    return null;
  }
  return (int.parse(found.group(1)!), int.parse(found.group(2)!));
}

int _columnIndex(ToolSpec? tool, String key) {
  if (tool == null) {
    return -1;
  }
  for (int index = 0; index < tool.columns.length; index++) {
    if (tool.columns[index].key == key) {
      return index;
    }
  }
  return -1;
}

String _searchText(ScanRow row, ToolSpec? tool, List<TextField> fields) {
  final List<String> parts = <String>[];
  if (fields.contains(TextField.name)) {
    parts.add(row.name);
  }
  if (fields.contains(TextField.path)) {
    parts.add(row.path);
  }
  if (fields.contains(TextField.metadata)) {
    parts.add(_cellsWhere(tool, row, _metadataKeys.contains));
  }
  if (fields.contains(TextField.detail)) {
    parts.add(
      _cellsWhere(tool, row, (String key) => !_metadataKeys.contains(key)),
    );
  }
  return parts.where((String part) => part.isNotEmpty).join('\n');
}

String _cellsWhere(
  ToolSpec? tool,
  ScanRow row,
  bool Function(String key) accept,
) {
  if (tool == null) {
    return row.cells.join('\n');
  }
  final List<String> hits = <String>[];
  for (int index = 0; index < tool.columns.length; index++) {
    if (index < row.cells.length && accept(tool.columns[index].key)) {
      hits.add(row.cells[index]);
    }
  }
  return hits.join('\n');
}

({bool Function(String) match, String? error}) _textMatcher(
  String pattern,
  bool caseSensitive,
  bool regex,
) {
  if (regex) {
    return _regexMatcher(pattern, caseSensitive);
  }
  return (
    match: (String value) =>
        _fold(caseSensitive, value).contains(_fold(caseSensitive, pattern)),
    error: null,
  );
}

({bool Function(String) match, String? error}) _pathMatcher(
  String pattern,
  bool caseSensitive,
  PathMatchMode mode,
) {
  if (mode == PathMatchMode.regex) {
    return _regexMatcher(pattern, caseSensitive);
  }
  return (
    match: (String value) {
      final String needle = _fold(caseSensitive, pattern);
      final String candidate = _fold(caseSensitive, value);
      return switch (mode) {
        PathMatchMode.contains => candidate.contains(needle),
        PathMatchMode.notContains => !candidate.contains(needle),
        PathMatchMode.startsWith => candidate.startsWith(needle),
        PathMatchMode.endsWith => candidate.endsWith(needle),
        PathMatchMode.regex => false,
      };
    },
    error: null,
  );
}

({bool Function(String) match, String? error}) _regexMatcher(
  String pattern,
  bool caseSensitive,
) {
  try {
    final RegExp expression = RegExp(pattern, caseSensitive: caseSensitive);
    return (match: (String value) => expression.hasMatch(value), error: null);
  } on FormatException catch (error) {
    return (match: (String value) => false, error: error.message);
  }
}

String _fold(bool caseSensitive, String value) =>
    caseSensitive ? value : value.toLowerCase();

bool _inRange(num value, num? min, num? max) =>
    (min == null || value >= min) && (max == null || value <= max);

int? _boundary(int? value, SizeUnit? unit) =>
    value == null ? null : value * (unit ?? SizeUnit.b).multiplier;

String _extensionOf(String path) {
  final String name = path
      .split('/')
      .where((String part) => part.isNotEmpty)
      .last;
  final int dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
}

String _normalizeExtension(String value) {
  final String trimmed = value
      .trim()
      .replaceFirst(RegExp(r'^\.'), '')
      .toLowerCase();
  return trimmed == kNoExtension ? '' : trimmed;
}

FormatCategory _categoryOf(ScanRow row, ToolSpec? tool) {
  if (tool != null && tool.id == 'empty_folders') {
    return FormatCategory.folders;
  }
  final String extension = _extensionOf(row.path);
  for (final MapEntry<String, Set<String>> entry
      in _categoryExtensions.entries) {
    if (entry.value.contains(extension)) {
      return FormatCategory.values.firstWhere(
        (FormatCategory category) => category.wire == entry.key,
      );
    }
  }
  return FormatCategory.other;
}

/// Chip order in the reference's statistics line.
const List<FormatCategory> _categoryOrder = <FormatCategory>[
  FormatCategory.images,
  FormatCategory.videos,
  FormatCategory.audio,
  FormatCategory.documents,
  FormatCategory.archives,
  FormatCategory.folders,
  FormatCategory.other,
];

const Map<String, Set<String>> _categoryExtensions = <String, Set<String>>{
  'images': <String>{
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'tif',
    'tiff',
    'avif',
    'heic',
    'jxl',
    'svg',
    'raw',
    'cr2',
    'nef',
    'arw',
  },
  'videos': <String>{
    'mp4',
    'mkv',
    'avi',
    'mov',
    'webm',
    'wmv',
    'flv',
    'm4v',
    'mpeg',
    'mpg',
    'ts',
  },
  'audio': <String>{
    'mp3',
    'flac',
    'wav',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'wma',
    'ape',
  },
  'documents': <String>{
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'md',
    'rtf',
    'epub',
  },
  'archives': <String>{
    'zip',
    '7z',
    'rar',
    'tar',
    'gz',
    'bz2',
    'xz',
    'zst',
    'cab',
    'iso',
  },
};

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

/// A saved filter, identical in shape to the reference node's preset document so the two can be
/// exchanged as files.
class FilterPreset {
  const FilterPreset({
    required this.id,
    required this.name,
    required this.state,
  });

  final String id;
  final String name;
  final FilterState state;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'state': state.toJson(),
  };
}

/// Mirrors `parseCzkawkaFilterPresets`, including its refusal to accept another document version.
List<FilterPreset> parseFilterPresets(String text) {
  final Object? parsed = jsonDecode(text);
  if (parsed is! Map<String, Object?> ||
      parsed['version'] != 1 ||
      parsed['presets'] is! List<Object?>) {
    throw const FormatException('Unsupported Kisaki filter preset document.');
  }
  final List<Object?> raw = parsed['presets']! as List<Object?>;
  return <FilterPreset>[
    for (int index = 0; index < raw.length; index++)
      () {
        final Object? item = raw[index];
        if (item is! Map<String, Object?> ||
            item['id'] is! String ||
            (item['id'] as String).isEmpty ||
            item['name'] is! String ||
            (item['name'] as String).isEmpty ||
            item['state'] is! Map<String, Object?>) {
          throw FormatException('Invalid preset at index $index.');
        }
        return FilterPreset(
          id: item['id']! as String,
          name: item['name']! as String,
          state: FilterState.fromJson(item['state']! as Map<String, Object?>),
        );
      }(),
  ];
}

String serializeFilterPresets(List<FilterPreset> presets) =>
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': 1,
      'presets': presets.map((FilterPreset preset) => preset.toJson()).toList(),
    });
