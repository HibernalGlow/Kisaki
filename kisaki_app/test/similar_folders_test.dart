import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/similar_folders.dart';

/// Mirrors `Xiranite/packages/nodes/czkawka/src/similar-folders.test.ts` case for case, plus the
/// two folder assertions from `core.test.ts`, so the derived statistics cannot drift.
void main() {
  List<List<ScanRow>> windowsGroups() => <List<ScanRow>>[
    <ScanRow>[
      folderRow(r'D:\photos\a.jpg', 10, reference: true),
      folderRow(r'D:\photos\b.jpg', 20),
      folderRow(r'D:\other\c.jpg', 5),
    ],
    <ScanRow>[
      folderRow(r'D:\photos\d.jpg', 30),
      folderRow(r'D:\other\e.jpg', 7),
    ],
  ];

  test('aggregates counts, bytes, groups, previews, and the threshold', () {
    expect(buildSimilarFolders(windowsGroups(), threshold: 3), <FolderStat>[
      const FolderStat(
        path: r'D:\photos',
        count: 3,
        bytes: 60,
        groupCount: 2,
        previewPath: r'D:\photos\b.jpg',
      ),
    ]);
  });

  test('prefers a non-reference entry for the preview', () {
    final FolderStat photos = buildSimilarFolders(
      windowsGroups(),
      threshold: 1,
    ).firstWhere((FolderStat stat) => stat.path == r'D:\photos');
    expect(photos.previewPath, r'D:\photos\b.jpg');
  });

  test('sorts by count then bytes, and keeps posix separators', () {
    final List<List<ScanRow>> groups = <List<ScanRow>>[
      <ScanRow>[
        folderRow('/a/one.png', 1),
        folderRow('/b/two.png', 8),
        folderRow('/a/three.png', 2),
        folderRow('/b/four.png', 4),
      ],
    ];
    expect(
      buildSimilarFolders(groups).map((FolderStat stat) => stat.path),
      <String>['/b', '/a'],
    );
    expect(buildSimilarFolders(groups), hasLength(2));
  });

  test('a threshold below one still reports every folder', () {
    expect(
      buildSimilarFolders(
        windowsGroups(),
        threshold: 0,
      ).map((FolderStat stat) => stat.count),
      <int>[3, 2],
    );
  });

  test('a path with no parent directory is not a folder', () {
    expect(
      buildSimilarFolders(<List<ScanRow>>[
        <ScanRow>[folderRow('a.jpg', 1), folderRow('b.jpg', 2)],
      ]),
      isEmpty,
    );
  });
}

ScanRow folderRow(String path, int size, {bool reference = false}) => ScanRow(
  path: path,
  name: path.split(RegExp(r'[\\/]')).last,
  directory: '',
  cells: const <String>[],
  sizeBytes: size,
  modifiedTs: 0,
  groupIndex: 0,
  groupSize: 0,
  isGroupStart: false,
  isReference: reference,
  sortKeys: <int>[size],
);
