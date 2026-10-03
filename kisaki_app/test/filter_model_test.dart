import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/filter_model.dart';

/// Mirrors `Xiranite/packages/nodes/czkawka/src/filters.test.ts` case for case, with the same
/// fixture values, so a divergence between the ported model and the reference shows up here rather
/// than in someone's saved preset.
void main() {
  const int mb = 1024 * 1024;
  // 2026-07-14T12:00:00Z, the reference fixture's timestamp.
  final int now = DateTime.utc(2026, 7, 14, 12).millisecondsSinceEpoch;
  const int day = 24 * 60 * 60 * 1000;

  ToolSpec mediaTool() => _tool('similar_images', <String>[
    'size',
    'modified',
    'similarity',
    'dimensions',
  ]);

  ToolSpec duplicateTool() =>
      _tool('duplicate_files', <String>['size', 'modified']);

  List<ScanRow> fixture() => <ScanRow>[
    row(
      path: 'D:/keep/a.jpg',
      size: 120 * mb,
      group: 0,
      modified: now - 2 * day,
      similarity: '98%',
      dimensions: '1920x1080',
    ),
    row(
      path: 'D:/drop/b.png',
      size: 2 * mb,
      group: 0,
      modified: now - 40 * day,
      similarity: '72%',
      dimensions: '800x600',
    ),
    row(
      path: 'D:/ref/c.jpg',
      size: 1 * mb,
      group: 0,
      modified: now - 400 * day,
      reference: true,
    ),
    row(path: 'D:/keep/d.mp3', size: 4 * mb, group: 1, modified: now),
    row(path: 'D:/keep/e.mp3', size: 5 * mb, group: 1, modified: now),
  ];

  List<String> pathsOf(FilterResult result) =>
      result.rows.map((ScanRow row) => row.path).toList();

  test(
    'combines group and entry filters with AND semantics and unit conversion',
    () {
      final FilterState state = FilterState.defaults();
      state.groupCount
        ..enabled = true
        ..min = 3
        ..max = 3;
      state.fileSize
        ..enabled = true
        ..min = 100
        ..max = 200
        ..unit = SizeUnit.mb;
      state.extensionEnabled = true;
      state.extensionMode = true;
      state.extensions = <String>['.JPG'];
      state.showAllInFilteredGroups = false;

      final FilterResult result = applyFilters(
        rows: fixture(),
        selected: <String>{},
        state: state,
        tool: duplicateTool(),
        now: now,
      );

      expect(pathsOf(result), <String>['D:/keep/a.jpg']);
      expect(result.stats.totalItems, 5);
      expect(result.stats.filteredItems, 1);
      expect(result.stats.totalGroups, 2);
      expect(result.stats.filteredGroups, 1);
      expect(result.stats.activeFilterCount, 3);
    },
  );

  test(
    'supports selection and group mark modes while protecting references',
    () {
      final FilterState state = FilterState.defaults();
      state.mark = MarkFilter.groupSomeSelected;
      expect(
        applyFilters(
          rows: fixture(),
          selected: <String>{'D:/keep/a.jpg'},
          state: state,
          now: now,
        ).rows.map((ScanRow row) => row.groupIndex).toSet(),
        <int>{0},
      );

      state.mark = MarkFilter.unselected;
      state.showAllInFilteredGroups = false;
      expect(
        pathsOf(
          applyFilters(
            rows: fixture(),
            selected: <String>{'D:/keep/a.jpg'},
            state: state,
            now: now,
          ),
        ),
        contains('D:/drop/b.png'),
      );
      expect(
        pathsOf(
          applyFilters(
            rows: fixture(),
            selected: <String>{'D:/keep/a.jpg'},
            state: state,
            now: now,
          ),
        ),
        isNot(contains('D:/ref/c.jpg')),
      );

      state.mark = MarkFilter.reference;
      expect(
        pathsOf(
          applyFilters(
            rows: fixture(),
            selected: <String>{},
            state: state,
            now: now,
          ),
        ),
        <String>['D:/ref/c.jpg'],
      );
    },
  );

  test('restores every entry in a group containing a filtered match', () {
    final FilterState state = FilterState.defaults();
    state.pathEnabled = true;
    state.pathMode = PathMatchMode.contains;
    state.pathPattern = '/drop/';
    state.showAllInFilteredGroups = true;

    final FilterResult result = applyFilters(
      rows: fixture(),
      selected: <String>{},
      state: state,
      now: now,
    );
    expect(
      result.rows.where((ScanRow row) => row.groupIndex == 0),
      hasLength(3),
    );
  });

  test('filters date, similarity, resolution and regex paths', () {
    final FilterState state = FilterState.defaults();
    state.dateEnabled = true;
    state.datePreset = DatePreset.last7Days;
    state.similarity
      ..enabled = true
      ..min = 95
      ..max = 100;
    state.resolutionEnabled = true;
    state.minWidth = 1900;
    state.minHeight = 1000;
    state.aspectRatio = AspectRatio.wide;
    state.pathEnabled = true;
    state.pathMode = PathMatchMode.regex;
    state.pathPattern = r'keep[/\\].+\.jpg$';
    state.showAllInFilteredGroups = false;

    expect(
      pathsOf(
        applyFilters(
          rows: fixture(),
          selected: <String>{},
          state: state,
          tool: mediaTool(),
          now: now,
        ),
      ),
      <String>['D:/keep/a.jpg'],
    );
  });

  test('reports invalid regex and live extension statistics', () {
    final FilterState state = FilterState.defaults();
    state.pathEnabled = true;
    state.pathMode = PathMatchMode.regex;
    state.pathPattern = '[';

    final FilterResult invalid = applyFilters(
      rows: fixture(),
      selected: <String>{},
      state: state,
      now: now,
    );
    expect(invalid.rows, isEmpty);
    expect(invalid.pathPatternError, isNotNull);

    state.pathEnabled = false;
    final FilterResult result = applyFilters(
      rows: fixture(),
      selected: <String>{},
      state: state,
      now: now,
    );
    final ExtensionStat jpg = result.stats.extensions.firstWhere(
      (ExtensionStat item) => item.extension == 'jpg',
    );
    expect(jpg.totalCount, 2);
    expect(jpg.filteredCount, 2);
    expect(jpg.totalBytes, 121 * mb);
  });

  test('supports every path match mode', () {
    const List<(PathMatchMode, String, bool, List<String>)> cases =
        <(PathMatchMode, String, bool, List<String>)>[
          (
            PathMatchMode.contains,
            'KEEP',
            false,
            <String>['D:/keep/a.jpg', 'D:/keep/d.mp3', 'D:/keep/e.mp3'],
          ),
          (
            PathMatchMode.notContains,
            '/keep/',
            false,
            <String>['D:/drop/b.png', 'D:/ref/c.jpg'],
          ),
          (PathMatchMode.startsWith, 'D:/ref', true, <String>['D:/ref/c.jpg']),
          (
            PathMatchMode.endsWith,
            '.mp3',
            true,
            <String>['D:/keep/d.mp3', 'D:/keep/e.mp3'],
          ),
          (
            PathMatchMode.regex,
            r'[ad]\.(jpg|mp3)$',
            false,
            <String>['D:/keep/a.jpg', 'D:/keep/d.mp3'],
          ),
        ];

    for (final (
          PathMatchMode mode,
          String pattern,
          bool caseSensitive,
          List<String> expected,
        )
        in cases) {
      final FilterState state = FilterState.defaults();
      state.pathEnabled = true;
      state.pathMode = mode;
      state.pathPattern = pattern;
      state.pathCaseSensitive = caseSensitive;
      state.showAllInFilteredGroups = false;

      expect(
        pathsOf(
          applyFilters(
            rows: fixture(),
            selected: <String>{},
            state: state,
            now: now,
          ),
        ),
        expected,
        reason: 'path mode ${mode.wire}',
      );
    }
  });

  test(
    'supports exclusion, text regex, case sensitivity, and no-extension tokens',
    () {
      final List<ScanRow> extended = <ScanRow>[
        ...fixture(),
        row(path: 'D:/README', size: 1, group: 2, modified: now - 400 * day),
      ];
      final FilterState state = FilterState.defaults();
      state.extensionEnabled = true;
      state.extensionMode = false;
      state.extensions = <String>['png', 'mp3'];
      state.textEnabled = true;
      state.textPattern = r'^(a|c|README)';
      state.textRegex = true;
      state.textCaseSensitive = true;
      state.textFields = <TextField>[TextField.name];
      state.showAllInFilteredGroups = false;

      expect(
        applyFilters(
          rows: extended,
          selected: <String>{},
          state: state,
          now: now,
        ).rows.map((ScanRow row) => row.name).toList(),
        <String>['a.jpg', 'c.jpg', 'README'],
      );

      state.extensionMode = true;
      state.extensions = <String>[kNoExtension];
      state.textEnabled = false;
      expect(
        pathsOf(
          applyFilters(
            rows: extended,
            selected: <String>{},
            state: state,
            now: now,
          ),
        ),
        <String>['D:/README'],
      );
    },
  );

  test('applies every date preset boundary', () {
    const List<(DatePreset, List<String>)> cases = <(DatePreset, List<String>)>[
      (DatePreset.today, <String>['D:/keep/d.mp3', 'D:/keep/e.mp3']),
      (
        DatePreset.last7Days,
        <String>['D:/keep/a.jpg', 'D:/keep/d.mp3', 'D:/keep/e.mp3'],
      ),
      (
        DatePreset.last30Days,
        <String>['D:/keep/a.jpg', 'D:/keep/d.mp3', 'D:/keep/e.mp3'],
      ),
      (
        DatePreset.lastYear,
        <String>[
          'D:/keep/a.jpg',
          'D:/drop/b.png',
          'D:/keep/d.mp3',
          'D:/keep/e.mp3',
        ],
      ),
    ];

    for (final (DatePreset preset, List<String> expected) in cases) {
      final FilterState state = FilterState.defaults();
      state.dateEnabled = true;
      state.datePreset = preset;
      state.showAllInFilteredGroups = false;

      expect(
        pathsOf(
          applyFilters(
            rows: fixture(),
            selected: <String>{},
            state: state,
            now: now,
          ),
        ),
        expected,
        reason: 'date preset ${preset.wire}',
      );
    }
  });

  test('counts active filters without counting group expansion', () {
    final FilterState state = FilterState.defaults();
    state.mark = MarkFilter.selected;
    state.fileSize.enabled = true;
    state.pathEnabled = true;
    state.pathMode = PathMatchMode.contains;
    state.pathPattern = 'keep';
    state.showAllInFilteredGroups = false;

    expect(
      applyFilters(
        rows: fixture(),
        selected: <String>{'D:/keep/a.jpg'},
        state: state,
        now: now,
      ).stats.activeFilterCount,
      3,
    );
  });

  test('filters format categories and recognizes the folder tool', () {
    final FilterState state = FilterState.defaults();
    state.extensionEnabled = true;
    state.excludedCategories = <FormatCategory>[FormatCategory.images];
    state.showAllInFilteredGroups = false;

    final FilterResult result = applyFilters(
      rows: fixture(),
      selected: <String>{},
      state: state,
      tool: duplicateTool(),
      now: now,
    );
    expect(pathsOf(result), <String>['D:/keep/d.mp3', 'D:/keep/e.mp3']);
    final CategoryStat images = result.stats.categories.firstWhere(
      (CategoryStat item) => item.category == FormatCategory.images,
    );
    expect(images.totalCount, 3);
    expect(images.filteredCount, 0);

    final FilterResult folders = applyFilters(
      rows: <ScanRow>[row(path: 'D:/empty', size: 0, group: 0, modified: now)],
      selected: <String>{},
      state: FilterState.defaults(),
      tool: _tool('empty_folders', <String>['name']),
      now: now,
    );
    expect(folders.stats.categories.single.category, FormatCategory.folders);
    expect(folders.stats.categories.single.totalCount, 1);
  });

  test('round-trips custom presets and applies every built-in preset', () {
    final FilterState state = FilterState.defaults();
    state.pathEnabled = true;
    state.pathMode = PathMatchMode.contains;
    state.pathPattern = 'archive';

    final String text = serializeFilterPresets(<FilterPreset>[
      FilterPreset(id: 'archive', name: 'Archive', state: state),
    ]);
    final FilterPreset restored = parseFilterPresets(text).single;
    expect(restored.id, 'archive');
    expect(restored.state.toJson(), state.toJson());

    expect(
      FilterState.fromPreset(
        BuiltinPreset.largeFiles,
        now: now,
      ).fileSize.enabled,
      isTrue,
    );
    expect(
      FilterState.fromPreset(BuiltinPreset.largeFiles, now: now).fileSize.min,
      100,
    );
    expect(
      FilterState.fromPreset(BuiltinPreset.smallFiles, now: now).fileSize.unit,
      SizeUnit.kb,
    );
    expect(
      FilterState.fromPreset(
        BuiltinPreset.recentlyModified,
        now: now,
      ).datePreset,
      DatePreset.last30Days,
    );
    expect(
      FilterState.fromPreset(BuiltinPreset.oldFiles, now: now).dateEnd,
      now - 365 * day,
    );
    expect(
      () => parseFilterPresets('{"version":2,"presets":[]}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('limits quick text matching to the selected field families', () {
    final ToolSpec tool = _tool('duplicate_files', <String>[
      'size',
      'modified',
      'title',
      'detail',
    ]);
    final List<ScanRow> searchable = <ScanRow>[
      row(
        path: 'D:/folder/plain.bin',
        size: 1,
        group: 0,
        modified: now,
        cells: <String>['Needle Title', 'Needle Detail'],
      ),
    ];

    FilterResult run(List<TextField> fields, String pattern) {
      final FilterState state = FilterState.defaults();
      state.textEnabled = true;
      state.textPattern = pattern;
      state.textFields = fields;
      state.showAllInFilteredGroups = false;
      return applyFilters(
        rows: searchable,
        selected: <String>{},
        state: state,
        tool: tool,
        now: now,
      );
    }

    expect(run(<TextField>[TextField.name], 'Needle').rows, isEmpty);
    expect(run(<TextField>[TextField.metadata], 'Needle').rows, hasLength(1));
    expect(run(<TextField>[TextField.detail], 'Needle').rows, hasLength(1));
    expect(run(<TextField>[TextField.path], 'D:/folder').rows, hasLength(1));
  });
}

ToolSpec _tool(String id, List<String> columnKeys) => ToolSpec(
  id: id,
  glyph: '',
  labelKey: 'tool-$id',
  grouped: true,
  supportsReference: false,
  columns: <ColumnDef>[
    for (final String key in columnKeys)
      ColumnDef(
        key: key,
        labelKey: 'column-$key',
        flex: 1,
        minWidth: 80,
        alignRight: key == 'size' || key == 'modified',
      ),
  ],
  fieldIds: const <String>[],
);

ScanRow row({
  required String path,
  required int size,
  required int group,
  required int modified,
  bool reference = false,
  String similarity = '',
  String dimensions = '',
  List<String> cells = const <String>[],
}) => ScanRow(
  path: path,
  name: path.split('/').last,
  directory: path.substring(0, path.lastIndexOf('/')),
  cells: <String>[
    if (size >= 0) '$size B',
    if (modified > 0) '$modified',
    ...cells,
    if (similarity.isNotEmpty) similarity,
    if (dimensions.isNotEmpty) dimensions,
  ],
  sizeBytes: size,
  modifiedTs: modified,
  groupIndex: group,
  groupSize: 0,
  isGroupStart: false,
  isReference: reference,
  sortKeys: <int>[size, modified ~/ 1000],
);
