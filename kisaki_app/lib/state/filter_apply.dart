import '../engine/models.dart';
import 'filter_model.dart';
import 'row_projection.dart';

/// The filtering half of the ported model: it turns a `FilterState` into the rows and the
/// statistics the board paints.
///
/// Group and entry conditions combine with AND, exactly like `filters.ts`.
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
  final int stamp = now ?? nowMillis();
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
  for (final List<ScanRow> group in groupsOf(rows, tool)) {
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
List<List<ScanRow>> groupsOf(List<ScanRow> rows, ToolSpec? tool) {
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
    totalGroups: groupsOf(all, tool).length,
    filteredGroups: groupsOf(kept, tool).length,
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
  if (state.aspectRatio == FilterAspectRatio.any) {
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

String _searchText(ScanRow row, ToolSpec? tool, List<TextFilterField> fields) {
  final List<String> parts = <String>[];
  if (fields.contains(TextFilterField.name)) {
    parts.add(row.name);
  }
  if (fields.contains(TextFilterField.path)) {
    parts.add(row.path);
  }
  if (fields.contains(TextFilterField.metadata)) {
    parts.add(_cellsWhere(tool, row, _metadataKeys.contains));
  }
  if (fields.contains(TextFilterField.detail)) {
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
      // Searching the painted text, so a query that is on screen always finds its row.
      hits.add(displayCell(tool.columns[index], row, index));
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
  // Engine rows carry the host separator, and a directory may contain a dot of its own, so the
  // extension is read off the last segment only.
  final List<String> parts = path
      .replaceAll(r'\', '/')
      .split('/')
      .where((String part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return '';
  }
  final int dot = parts.last.lastIndexOf('.');
  return dot > 0 ? parts.last.substring(dot + 1).toLowerCase() : '';
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

int nowMillis() => DateTime.now().millisecondsSinceEpoch;
