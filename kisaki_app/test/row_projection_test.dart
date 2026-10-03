import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/row_projection.dart';

ColumnDef _column(
  String key, {
  double flex = 1,
  double minWidth = 80,
  bool alignRight = false,
}) => ColumnDef(
  key: key,
  labelKey: key,
  flex: flex,
  minWidth: minWidth,
  alignRight: alignRight,
);

final ToolSpec _flat = ToolSpec(
  id: 'big_files',
  glyph: 'B',
  labelKey: 'tool_big_files',
  grouped: false,
  supportsReference: false,
  columns: <ColumnDef>[
    _column('col_size', alignRight: true),
    _column('col_modified'),
  ],
  fieldIds: const <String>[],
);

final ToolSpec _grouped = ToolSpec(
  id: 'duplicate_files',
  glyph: 'D',
  labelKey: 'tool_duplicate_files',
  grouped: true,
  supportsReference: true,
  columns: <ColumnDef>[
    _column('col_size', alignRight: true),
    _column('col_modified'),
  ],
  fieldIds: const <String>[],
);

ScanRow _row(
  String path, {
  int size = 0,
  int modified = 0,
  int group = -1,
  bool start = false,
}) => ScanRow(
  path: path,
  name: path.substring(path.lastIndexOf('/') + 1),
  directory: path.substring(0, path.lastIndexOf('/')),
  cells: const <String>[],
  sizeBytes: size,
  modifiedTs: modified,
  groupIndex: group,
  groupSize: 0,
  isGroupStart: start,
  isReference: false,
  sortKeys: <int>[size, modified],
);

void main() {
  final List<ScanRow> rows = <ScanRow>[
    _row('/data/a.txt', size: 300, modified: 5),
    _row('/data/b.txt', size: 100, modified: 9),
    _row('/photos/c.png', size: 700, modified: 1),
  ];

  test('flat sort by the size column honours direction and ties', () {
    final List<ScanRow> ascending = projectRows(
      rows: rows,
      tool: _flat,
      filter: '',
      sortColumn: 0,
      sortAscending: true,
    );
    expect(ascending.map((ScanRow row) => row.path).toList(), <String>[
      '/data/b.txt',
      '/data/a.txt',
      '/photos/c.png',
    ]);

    final List<ScanRow> descending = projectRows(
      rows: rows,
      tool: _flat,
      filter: '',
      sortColumn: 0,
      sortAscending: false,
    );
    expect(descending.first.path, '/photos/c.png');
  });

  test(
    'the modified column is read as a timestamp, not a sort key of the size',
    () {
      final List<ScanRow> sorted = projectRows(
        rows: rows,
        tool: _flat,
        filter: '',
        sortColumn: 1,
        sortAscending: true,
      );
      expect(sorted.map((ScanRow row) => row.modifiedTs).toList(), <int>[
        1,
        5,
        9,
      ]);
    },
  );

  test('filter matches path, name and cells', () {
    expect(
      projectRows(
        rows: rows,
        tool: _flat,
        filter: 'photos',
        sortColumn: -1,
        sortAscending: true,
      ).length,
      1,
    );
    expect(
      projectRows(
        rows: rows,
        tool: _flat,
        filter: 'c.png',
        sortColumn: -1,
        sortAscending: true,
      ).single.path,
      '/photos/c.png',
    );
    expect(
      projectRows(
        rows: rows,
        tool: _flat,
        filter: 'nomatch',
        sortColumn: -1,
        sortAscending: true,
      ),
      isEmpty,
    );
  });

  test('grouped scanners keep each block contiguous when sorting', () {
    final List<ScanRow> grouped = <ScanRow>[
      _row('/g1/x', size: 10, group: 0, start: true),
      _row('/g1/y', size: 90, group: 0),
      _row('/g2/z', size: 50, group: 1, start: true),
      _row('/g2/w', size: 80, group: 1),
    ];
    final List<ScanRow> sorted = projectRows(
      rows: grouped,
      tool: _grouped,
      filter: '',
      sortColumn: 0,
      sortAscending: true,
    );
    expect(sorted.map((ScanRow row) => row.groupIndex).toList(), <int>[
      0,
      0,
      1,
      1,
    ]);
    expect(sorted.map((ScanRow row) => row.sizeBytes).toList(), <int>[
      10,
      90,
      50,
      80,
    ]);
  });

  test('group selection reports none, partial and all', () {
    final List<ScanRow> members = <ScanRow>[
      _row('/g/x', group: 0),
      _row('/g/y', group: 0),
    ];
    expect(groupSelectionOf(members, <String>{}), GroupSelection.none);
    expect(groupSelectionOf(members, <String>{'/g/x'}), GroupSelection.partial);
    expect(
      groupSelectionOf(members, <String>{'/g/x', '/g/y'}),
      GroupSelection.all,
    );
    expect(
      groupSelectionOf(<ScanRow>[], <String>{'/g/x'}),
      GroupSelection.none,
    );
  });
}
