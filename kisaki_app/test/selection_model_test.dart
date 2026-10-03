import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/selection_model.dart';
import 'package:kisaki_app/state/selection_rules.dart';

/// Mirrors `Xiranite/packages/nodes/czkawka/src/selection-assistant.test.ts` case for case, with the
/// same fixture paths, sizes and timestamps, so a divergence shows up here instead of in a board.
void main() {
  List<List<ScanRow>> fixture() => <List<ScanRow>>[
    <ScanRow>[
      srow('D:/a/small.jpg', 10, 1),
      srow('D:/a/large.jpg', 30, 3),
      srow('D:/b/mid.png', 20, 2),
      srow('D:/ref/original.jpg', 40, 4, reference: true),
    ],
    <ScanRow>[srow('E:/c/old.mp3', 5, 1), srow('E:/c/new.mp3', 15, 5)],
  ];

  GroupRule groupRule(
    GroupSelectionMode mode,
    List<SelectionSortCriterion> criteria,
  ) => GroupRule(mode: mode, sortCriteria: criteria);

  test('implements replace, add, remove, and intersection modes', () {
    expect(
      applySelectionMode(
        current: <String>['a', 'b'],
        matched: <String>['b', 'c'],
        mode: SelectionApplyMode.replace,
      ),
      <String>['b', 'c'],
    );
    expect(
      applySelectionMode(
        current: <String>['a', 'b'],
        matched: <String>['b', 'c'],
        mode: SelectionApplyMode.add,
      ),
      <String>['a', 'b', 'c'],
    );
    expect(
      applySelectionMode(
        current: <String>['a', 'b'],
        matched: <String>['b', 'c'],
        mode: SelectionApplyMode.remove,
      ),
      <String>['a'],
    );
    expect(
      applySelectionMode(
        current: <String>['a', 'b'],
        matched: <String>['b', 'c'],
        mode: SelectionApplyMode.intersect,
      ),
      <String>['b'],
    );
  });

  test('supports all four group modes and multi-level sorting', () {
    final List<List<ScanRow>> groups = fixture();
    final List<SelectionSortCriterion> criteria = <SelectionSortCriterion>[
      const SelectionSortCriterion(
        id: 'folder',
        field: SelectionSortField.folderPath,
        direction: SortDirection.asc,
      ),
      const SelectionSortCriterion(
        id: 'size',
        field: SelectionSortField.fileSize,
        direction: SortDirection.desc,
      ),
    ];

    expect(
      applyGroupSelection(
        groups: groups,
        current: const <String>[],
        rule: groupRule(GroupSelectionMode.allExceptOne, criteria),
      ).paths,
      <String>['D:/a/small.jpg', 'D:/b/mid.png', 'E:/c/old.mp3'],
    );
    expect(
      applyGroupSelection(
        groups: groups,
        current: const <String>[],
        rule: groupRule(GroupSelectionMode.selectOne, criteria),
      ).paths,
      <String>['D:/a/large.jpg', 'E:/c/new.mp3'],
    );
    expect(
      applyGroupSelection(
        groups: groups,
        current: const <String>[],
        rule: groupRule(GroupSelectionMode.allExceptOnePerFolder, criteria),
      ).paths,
      <String>['D:/a/small.jpg', 'E:/c/old.mp3'],
    );
    expect(
      applyGroupSelection(
        groups: groups,
        current: const <String>[],
        rule: groupRule(GroupSelectionMode.allExceptOneMatchingSet, criteria),
      ).paths,
      <String>['D:/b/mid.png'],
    );
  });

  test('applies criterion filters and never selects references', () {
    final SelectionResult result = applyGroupSelection(
      groups: fixture(),
      current: const <String>[],
      rule: groupRule(GroupSelectionMode.selectOne, <SelectionSortCriterion>[
        const SelectionSortCriterion(
          id: 'jpg',
          field: SelectionSortField.fileType,
          direction: SortDirection.asc,
          filterCondition: MatchCondition.equals,
          filterValue: 'jpg',
        ),
      ]),
    );
    expect(result.paths, <String>['D:/a/large.jpg']);
    expect(result.paths, isNot(contains('D:/ref/original.jpg')));
  });

  test(
    'matches text columns, conditions, regex, and reports invalid expressions',
    () {
      final List<List<ScanRow>> groups = fixture();
      TextRule rule() => SelectionConfig.defaults().text;

      TextRule starts = rule().copyWith(
        column: SelectionTextColumn.fileName,
        pattern: 'new',
        condition: MatchCondition.startsWith,
      );
      expect(
        applyTextSelection(
          groups: groups,
          current: const <String>[],
          rule: starts,
        ).paths,
        <String>['E:/c/new.mp3'],
      );

      starts = starts.copyWith(useRegex: true, pattern: r'^(large|mid)\.');
      expect(
        applyTextSelection(
          groups: groups,
          current: const <String>[],
          rule: starts,
        ).paths,
        <String>['D:/a/large.jpg', 'D:/b/mid.png'],
      );

      starts = starts.copyWith(pattern: '[');
      expect(
        applyTextSelection(
          groups: groups,
          current: const <String>[],
          rule: starts,
        ).error,
        isNotNull,
      );
    },
  );

  test('supports directory include, exclude, and keep-one rules', () {
    final List<List<ScanRow>> groups = fixture();
    SelectionResult run(
      DirectoryRule rule, {
      List<String> current = const <String>[],
      SelectionApplyMode mode = SelectionApplyMode.replace,
    }) => applyDirectorySelection(
      groups: groups,
      current: current,
      rule: rule,
      mode: mode,
    );

    expect(
      run(
        DirectoryRule(
          mode: DirectorySelectionMode.selectAllInDirectory,
          directories: const <String>[],
        ),
      ).directoryRequired,
      isTrue,
    );
    expect(
      run(
        DirectoryRule(
          mode: DirectorySelectionMode.selectAllInDirectory,
          directories: const <String>['D:/a'],
        ),
      ).paths,
      <String>['D:/a/small.jpg', 'D:/a/large.jpg'],
    );
    expect(
      run(
        DirectoryRule(
          mode: DirectorySelectionMode.excludeDirectory,
          directories: const <String>['D:/a'],
        ),
        current: <String>['D:/a/small.jpg', 'D:/b/mid.png'],
        mode: SelectionApplyMode.remove,
      ).paths,
      <String>['D:/b/mid.png'],
    );
    expect(
      run(
        DirectoryRule(
          mode: DirectorySelectionMode.keepOnePerDirectory,
          directories: const <String>[],
        ),
      ).paths,
      <String>['D:/a/large.jpg', 'E:/c/new.mp3'],
    );
  });

  test('tracks undo/redo, invert, statistics, and config round trips', () {
    SelectionHistory history = createSelectionHistory(<String>['a']);
    history = pushSelectionHistory(history, <String>['a', 'b']);
    expect(undoSelectionHistory(history).present, <String>['a']);
    expect(
      redoSelectionHistory(undoSelectionHistory(history)).present,
      <String>['a', 'b'],
    );

    final List<List<ScanRow>> groups = fixture();
    expect(invertSelection(groups, <String>['D:/a/small.jpg']), hasLength(4));
    final SelectionStats stats = selectionStats(groups, <String>[
      'D:/a/large.jpg',
      'D:/b/mid.png',
    ]);
    expect(
      stats,
      const SelectionStats(
        selectedCount: 2,
        selectedBytes: 50,
        reclaimableBytes: 50,
      ),
    );

    final SelectionConfig config = SelectionConfig.defaults();
    expect(
      parseSelectionConfig(serializeSelectionConfig(config)).toJson(),
      config.toJson(),
    );
  });

  test('counts a group without references as keeping its largest copy', () {
    // core.ts:565-569 is the rule the engine reports, not the reference test's fixture shortcut.
    final SelectionStats stats = selectionStats(
      <List<ScanRow>>[
        <ScanRow>[srow('E:/c/old.mp3', 5, 1), srow('E:/c/new.mp3', 15, 5)],
      ],
      <String>['E:/c/old.mp3', 'E:/c/new.mp3'],
    );
    expect(stats.selectedBytes, 20);
    expect(stats.reclaimableBytes, 5);
  });

  test('ranks file2 before file10 the way the reference sorts names', () {
    final List<List<ScanRow>> groups = <List<ScanRow>>[
      <ScanRow>[srow('D:/x/file10.jpg', 1, 1), srow('D:/x/file2.jpg', 1, 1)],
    ];
    expect(
      applyGroupSelection(
        groups: groups,
        current: const <String>[],
        rule: groupRule(GroupSelectionMode.selectOne, <SelectionSortCriterion>[
          const SelectionSortCriterion(
            id: 'name',
            field: SelectionSortField.fileName,
            direction: SortDirection.asc,
          ),
        ]),
      ).paths,
      <String>['D:/x/file2.jpg'],
    );
  });

  test('keeps one entry per directory inside every group', () {
    final SelectionResult result = applyGroupSelection(
      groups: <List<ScanRow>>[
        <ScanRow>[
          srow('D:/one/a.jpg', 1, 1),
          srow('D:/one/b.jpg', 2, 2),
          srow('D:/two/c.jpg', 3, 3),
        ],
      ],
      current: const <String>[],
      rule: groupRule(
        GroupSelectionMode.allExceptOnePerFolder,
        SelectionConfig.defaults().group.sortCriteria,
      ),
    );
    expect(result.paths, <String>['D:/one/a.jpg']);
  });

  test('rejects a document whose version is not the one it writes', () {
    expect(
      () => parseSelectionConfig('{"version":2,"config":{}}'),
      throwsA(isA<FormatException>()),
    );
  });
}

ScanRow srow(String path, int size, int modified, {bool reference = false}) =>
    ScanRow(
      path: path,
      name: path.split('/').last,
      directory: path.substring(0, path.lastIndexOf('/')),
      cells: const <String>[],
      sizeBytes: size,
      modifiedTs: modified,
      groupIndex: 0,
      groupSize: 0,
      isGroupStart: false,
      isReference: reference,
      sortKeys: <int>[size, modified],
    );
