import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/simiu_sets.dart';

import 'support/stub_engine.dart';

/// Mirrors `packages/nodes/czkawka/src/simiu-sets.test.ts` for the half that plans; the mutation and
/// the undo journal are the bridge's job and are tested in Rust.
void main() {
  ScanRow image(String path, int group) =>
      StubEngine.row(path, size: 10, group: group);

  SimiuOptions options({
    List<String> roots = const <String>['D:/library'],
    bool recursive = true,
    SimiuScanOrder scanOrder = SimiuScanOrder.smallestFirst,
    String namePrefix = 'simiu_set',
    int minimumGroupSize = 2,
  }) => SimiuOptions(
    roots: roots,
    recursive: recursive,
    scanOrder: scanOrder,
    namePrefix: namePrefix,
    minimumGroupSize: minimumGroupSize,
  );

  test('keeps groups directory-local and skips an all-in-one directory', () {
    final SimiuPlan plan = planSimiuSets(
      rows: <ScanRow>[
        image('D:/library/a.jpg', 0),
        image('D:/library/b.jpg', 0),
        image('D:/library/c.jpg', 1),
        image('D:/library/child/d.jpg', 0),
        image('D:/library/child/e.jpg', 0),
      ],
      options: options(namePrefix: 'sets'),
    );

    expect(plan.directoryCount, 2);
    expect(plan.imageCount, 5);
    expect(plan.groups, hasLength(1));
    expect(plan.groups.single.parentDirectory, 'D:/library');
    expect(plan.groups.single.name, 'sets__set_001');
    expect(plan.groups.single.files, <String>[
      'D:/library/a.jpg',
      'D:/library/b.jpg',
    ]);
    expect(
      plan.operations
          .map((SimiuOperation operation) => operation.target)
          .toList(),
      <String>[
        'D:/library/sets__set_001/a.jpg',
        'D:/library/sets__set_001/b.jpg',
      ],
      reason: 'the child folder is already one set, so it is left alone',
    );
  });

  test(
    'a directory whose name carries the marker or the prefix never plans',
    () {
      expect(
        shouldSkipSimiuSetDirectory('D:/library/.simiu-old', 'sets'),
        isTrue,
      );
      expect(
        shouldSkipSimiuSetDirectory('D:/library/sets__set_001', 'sets'),
        isTrue,
      );
      expect(shouldSkipSimiuSetDirectory('D:/library/SET_2024', 'set'), isTrue);
      expect(shouldSkipSimiuSetDirectory('D:/library/photos', 'set'), isFalse);
    },
  );

  test('an existing sibling folder claims the set name', () {
    final SimiuPlan plan = planSimiuSets(
      rows: <ScanRow>[
        image('D:/library/a.jpg', 0),
        image('D:/library/b.jpg', 0),
        image('D:/library/c.jpg', 1),
        image('D:/library/sets__set_001/held.jpg', 2),
      ],
      options: options(namePrefix: 'sets'),
    );

    expect(plan.groups.single.name, 'sets__set_001_01');
    expect(plan.operations.first.target, 'D:/library/sets__set_001_01/a.jpg');
  });

  test('a candidate below the minimum group size is dropped', () {
    final SimiuPlan plan = planSimiuSets(
      rows: <ScanRow>[
        image('D:/library/a.jpg', 0),
        image('D:/library/b.jpg', 0),
        image('D:/library/c.jpg', 1),
      ],
      options: options(namePrefix: 'sets', minimumGroupSize: 3),
    );

    expect(plan.operations, isEmpty);
    expect(plan.groups, isEmpty);
    expect(plan.directoryCount, 1, reason: 'the folder is still counted');
  });

  test('the scan order decides which directory is planned first', () {
    final List<ScanRow> rows = <ScanRow>[
      image('D:/lib/zeta/a1.jpg', 0),
      image('D:/lib/zeta/a2.jpg', 0),
      image('D:/lib/zeta/alone.jpg', 1),
      image('D:/lib/alpha/b1.jpg', 2),
      image('D:/lib/alpha/b2.jpg', 2),
      image('D:/lib/alpha/b3.jpg', 3),
      image('D:/lib/alpha/alone.jpg', 4),
    ];

    final SimiuPlan smallest = planSimiuSets(
      rows: rows,
      options: options(roots: const <String>['D:/lib'], namePrefix: 'sets'),
    );
    final SimiuPlan byPath = planSimiuSets(
      rows: rows,
      options: options(
        roots: const <String>['D:/lib'],
        namePrefix: 'sets',
        scanOrder: SimiuScanOrder.path,
      ),
    );

    expect(smallest.operations.first.source, 'D:/lib/zeta/a1.jpg');
    expect(byPath.operations.first.source, 'D:/lib/alpha/b1.jpg');
  });

  test('the deepest directory is planned first when asked', () {
    final SimiuPlan plan = planSimiuSets(
      rows: <ScanRow>[
        image('D:/lib/a1.jpg', 0),
        image('D:/lib/a2.jpg', 0),
        image('D:/lib/alone.jpg', 1),
        image('D:/lib/deep/e1.jpg', 2),
        image('D:/lib/deep/e2.jpg', 2),
        image('D:/lib/deep/e3.jpg', 3),
      ],
      options: options(
        roots: const <String>['D:/lib'],
        namePrefix: 'sets',
        scanOrder: SimiuScanOrder.deepestFirst,
      ),
    );

    expect(plan.operations.first.source, 'D:/lib/deep/e1.jpg');
  });

  test('non-images and paths outside the roots are never moved', () {
    final SimiuPlan plan = planSimiuSets(
      rows: <ScanRow>[
        image('D:/library/a.jpg', 0),
        image('D:/library/b.jpg', 0),
        image('D:/library/extra.jpg', 1),
        image('D:/library/notes.txt', 0),
        image('E:/other/c.jpg', 0),
        image('E:/other/d.jpg', 0),
      ],
      options: options(namePrefix: 'sets'),
    );

    expect(plan.imageCount, 3);
    expect(
      plan.operations.map((SimiuOperation operation) => operation.source),
      <String>['D:/library/a.jpg', 'D:/library/b.jpg'],
    );
  });

  test('without recursion only files in the root itself are planned', () {
    final SimiuPlan plan = planSimiuSets(
      rows: <ScanRow>[
        image('D:/library/a.jpg', 0),
        image('D:/library/b.jpg', 0),
        image('D:/library/child/c.jpg', 0),
        image('D:/library/child/d.jpg', 0),
        image('D:/library/alone.jpg', 1),
      ],
      options: options(namePrefix: 'sets', recursive: false),
    );

    expect(plan.directoryCount, 1);
    expect(plan.operations, hasLength(2));

    // Positive control: the same rows one level deeper are planned when recursion is allowed.
    final SimiuPlan walked = planSimiuSets(
      rows: <ScanRow>[
        image('D:/library/a.jpg', 0),
        image('D:/library/b.jpg', 0),
        image('D:/library/child/c.jpg', 1),
        image('D:/library/child/d.jpg', 1),
        image('D:/library/child/lonely.jpg', 3),
        image('D:/library/alone.jpg', 2),
      ],
      options: options(namePrefix: 'sets'),
    );
    expect(walked.directoryCount, 2);
    expect(walked.operations, hasLength(4));
  });

  test('the prefix and the minimum size are sanitized like the reference', () {
    expect(sanitizeSimiuPrefix('a<b>c'), 'a_b_c');
    expect(sanitizeSimiuPrefix('   '), simiuDefaultPrefix);
    final SimiuOptions small = options(minimumGroupSize: 1).normalized();
    final SimiuOptions huge = options(minimumGroupSize: 99999).normalized();
    expect(small.minimumGroupSize, simiuMinimumFloor);
    expect(huge.minimumGroupSize, simiuMaximumFloor);
    expect(
      options(roots: const <String>['D:/a', ' D:/a ', '']).normalized().roots,
      <String>['D:/a'],
    );
  });

  test('the wire names the reference uses round-trip', () {
    expect(
      SimiuScanOrder.fromWire('deepest-first'),
      SimiuScanOrder.deepestFirst,
    );
    expect(SimiuScanOrder.fromWire('path'), SimiuScanOrder.path);
    expect(SimiuScanOrder.fromWire('nonsense'), SimiuScanOrder.smallestFirst);
    expect(SimiuScanOrder.smallestFirst.wire, 'smallest-first');
  });
}
