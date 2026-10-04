import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/export_scope.dart';

import 'support/stub_engine.dart';

/// StreamController delivers on a microtask, so the board only sees an event after a drain.
Future<void> drain() => Future<void>.delayed(Duration.zero);

void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  test('the first scanner and its defaults load without any scan', () async {
    expect(controller.tool?.id, 'duplicate_files');
    expect(controller.fields.map((FieldDef def) => def.id), <String>[
      'dup_use_prehash',
      'dup_hash_type',
      'dup_prehash_cache_size',
    ]);
    expect(
      controller.valueOf('dup_prehash_cache_size').value,
      const FieldPayloadInteger(256),
    );
    expect(controller.phase, ScanPhase.idle);
    expect(engine.requests, isEmpty);
  });

  test(
    'scan refuses an empty path list and never reaches the engine',
    () async {
      expect(controller.startScan(), isFalse);
      expect(engine.requests, isEmpty);
      expect(
        controller.statusText,
        'Add at least one included directory before scanning',
      );
    },
  );

  test(
    'request carries paths, shared filters and the current option values',
    () async {
      controller
        ..addIncluded(<String>['/data', '/data'])
        ..addReference(<String>['/ref'])
        ..addExcludedItem(<String>['*/.git/*'])
        ..addAllowedExtension(<String>['jpg'])
        ..setMinSize('10')
        ..setMaxSize('4096')
        ..setUseCache(false)
        ..setFieldValue(
          'dup_hash_type',
          const FieldPayloadChoice('option_check_method_name'),
        )
        ..setFieldValue(
          'dup_prehash_cache_size',
          const FieldPayloadInteger(512),
        );

      expect(controller.startScan(), isTrue);
      final ScanRequest request = engine.requests.single;
      expect(request.included, <String>['/data']);
      expect(request.reference, <String>['/ref']);
      expect(request.excludedItems, <String>['*/.git/*']);
      expect(request.allowedExtensions, <String>['jpg']);
      expect(request.minSizeKib, '10');
      expect(request.useCache, isFalse);
      expect(
        request.fields.map((FieldValue value) => value.value).toList(),
        <FieldPayload>[
          const FieldPayloadFlag(true),
          const FieldPayloadChoice('option_check_method_name'),
          const FieldPayloadInteger(512),
        ],
      );
    },
  );

  test(
    'progress ticks then a completion result feed the metrics and status',
    () async {
      controller.addIncluded(<String>['/data']);
      controller.startScan();
      engine.emit(
        const ScanEventProgress(
          ProgressUpdate(
            stageLabelKey: 'status_scanning',
            current: 40,
            total: 100,
            percent: 40,
            detail: 'hashing',
          ),
        ),
      );
      await drain();
      expect(controller.progressValue, 0.4);

      engine.emit(
        ScanEventCompleted(
          StubEngine.outcome('duplicate_files', <ScanRow>[
            StubEngine.row('/data/a', group: 0, start: true),
            StubEngine.row('/data/b', group: 0),
          ]),
        ),
      );
      await drain();

      expect(controller.phase, ScanPhase.finished);
      expect(controller.progressValue, isNull);
      expect(controller.rows.length, 2);
      expect(controller.visibleRows.length, 2);
      expect(controller.fileCount, 2);
      expect(controller.groupCount, 1);
      expect(controller.reclaimableBytes, 2048);
      expect(controller.statusText, 'Found 2 files in 1 groups (2.0 KiB)');
      expect(controller.messages, contains('skipped 1 unreadable path'));
    },
  );

  test('an unmeasurable stage leaves the rail indeterminate', () async {
    controller.addIncluded(<String>['/data']);
    controller.startScan();
    engine.emit(
      const ScanEventProgress(
        ProgressUpdate(
          stageLabelKey: 'status_scanning',
          current: 0,
          total: 0,
          percent: -1,
          detail: '',
        ),
      ),
    );
    await drain();
    expect(controller.progressValue, isNull);
  });

  test(
    'stop asks the engine and keeps whatever the scan already found',
    () async {
      controller.addIncluded(<String>['/data']);
      controller.startScan();
      controller.stopScan();
      expect(engine.stopRequests, 1);
      expect(controller.phase, ScanPhase.stopping);
      expect(controller.statusText, 'Requesting stop...');

      engine.emit(
        ScanEventCompleted(
          StubEngine.outcome('duplicate_files', <ScanRow>[
            StubEngine.row('/data/a', group: 0, start: true),
          ], stopped: true),
        ),
      );
      await drain();
      expect(controller.phase, ScanPhase.finished);
      expect(controller.rows.length, 1);
      expect(
        controller.statusText,
        'Scan stopped - results found so far are kept',
      );
    },
  );

  test('a failed scan surfaces the engine error as critical text', () async {
    controller.addIncluded(<String>['/data']);
    controller.startScan();
    engine.emit(const ScanEventFailed('No included or reference paths'));
    await drain();
    expect(controller.phase, ScanPhase.failed);
    expect(controller.critical, 'No included or reference paths');
    expect(controller.statusText, 'The scan failed, please retry.');
  });

  test(
    'a stream that closes without a terminal event is reported, not swallowed',
    () async {
      controller.addIncluded(<String>['/data']);
      controller.startScan();
      engine.emit(
        const ScanEventProgress(
          ProgressUpdate(
            stageLabelKey: 'status_scanning',
            current: 1,
            total: 2,
            percent: 50,
            detail: '',
          ),
        ),
      );
      await drain();
      await engine.closeLast();
      await drain();
      expect(controller.phase, ScanPhase.failed);
      expect(controller.critical, isNotNull);
    },
  );

  test(
    'late events from a superseded scan cannot overwrite the current one',
    () async {
      controller.addIncluded(<String>['/data']);
      controller.startScan();
      final StreamController<ScanEvent> first = engine.lastStream;

      controller.selectTool('big_files');
      controller.startScan();
      expect(engine.requests.length, 2);
      engine.emit(
        ScanEventCompleted(
          StubEngine.outcome('big_files', <ScanRow>[
            StubEngine.row('/current/a'),
          ]),
        ),
      );
      await drain();
      expect(controller.rows.single.path, '/current/a');

      engine.emitTo(
        first,
        ScanEventCompleted(
          StubEngine.outcome('duplicate_files', <ScanRow>[
            StubEngine.row('/stale/a', group: 0, start: true),
            StubEngine.row('/stale/b', group: 0),
          ]),
        ),
      );
      await drain();
      expect(controller.rows.single.path, '/current/a');
      expect(controller.selectedCount, 0);
    },
  );

  test('selecting a scanner clears the previous result set', () async {
    controller.addIncluded(<String>['/data']);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row('/data/a', group: 0, start: true),
        ]),
      ),
    );
    await drain();
    controller.toggleSelected(controller.rows.first);
    expect(controller.selectedCount, 1);

    controller.selectTool('big_files');
    expect(controller.tool?.id, 'big_files');
    expect(controller.rows, isEmpty);
    expect(controller.selectedCount, 0);
    expect(controller.phase, ScanPhase.idle);
  });

  test(
    'selection is keyed by path, so re-sorting keeps it and sizes add up',
    () async {
      controller
        ..addIncluded(<String>['/data'])
        ..selectTool('big_files');
      controller.startScan();
      engine.emit(
        ScanEventCompleted(
          StubEngine.outcome('big_files', <ScanRow>[
            StubEngine.row('/data/small', size: 10),
            StubEngine.row('/data/large', size: 5000),
          ]),
        ),
      );
      await drain();

      controller.toggleSelected(controller.rows.last);
      controller.toggleSort(0);
      expect(controller.visibleRows.map((ScanRow row) => row.path), <String>[
        '/data/small',
        '/data/large',
      ]);
      expect(controller.isSelected(controller.visibleRows.last), isTrue);
      expect(controller.selectedCount, 1);
      expect(controller.selectedBytes, 5000);

      controller.toggleSort(0);
      expect(controller.visibleRows.first.path, '/data/large');
      expect(controller.isSelected(controller.visibleRows.first), isTrue);

      controller.toggleSort(0);
      expect(controller.sortColumn, -1);
      expect(controller.visibleRows.first.path, '/data/small');
    },
  );

  test('group toggles move from none to all and back', () async {
    controller.addIncluded(<String>['/data']);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row('/data/a', group: 0, start: true),
          StubEngine.row('/data/b', group: 0),
          StubEngine.row('/data/c', group: 1, start: true),
          StubEngine.row('/data/d', group: 1),
        ]),
      ),
    );
    await drain();

    expect(controller.groupSelection(0), GroupSelection.none);
    controller.toggleSelected(controller.rows[1]);
    expect(controller.groupSelection(0), GroupSelection.partial);
    controller.toggleGroup(0);
    expect(controller.groupSelection(0), GroupSelection.all);
    expect(controller.selectedCount, 2);
    controller.toggleGroup(0);
    expect(controller.groupSelection(0), GroupSelection.none);
    expect(controller.selectedCount, 0);
  });

  test(
    'filter narrows the visible rows without touching the canonical ones',
    () async {
      controller
        ..addIncluded(<String>['/data'])
        ..selectTool('big_files');
      controller.startScan();
      engine.emit(
        ScanEventCompleted(
          StubEngine.outcome('big_files', <ScanRow>[
            StubEngine.row('/data/keep.txt'),
            StubEngine.row('/photos/skip.png'),
          ]),
        ),
      );
      await drain();
      controller.setFilter('keep');
      expect(controller.visibleRows.single.path, '/data/keep.txt');
      expect(controller.rows.length, 2);
      controller.setFilter('');
      expect(controller.visibleRows.length, 2);
    },
  );

  test(
    'delete is dry run by default and asks for confirmation first',
    () async {
      controller
        ..addIncluded(<String>['/data'])
        ..selectTool('big_files');
      controller.requestDelete();
      expect(controller.confirm, isNull);
      expect(controller.statusText, 'Select at least one result first');

      controller.startScan();
      engine.emit(
        ScanEventCompleted(
          StubEngine.outcome('big_files', <ScanRow>[
            StubEngine.row('/data/a', size: 100),
            StubEngine.row('/data/b', size: 200),
          ]),
        ),
      );
      await drain();
      controller.toggleSelected(controller.rows.first);
      controller.requestDelete();

      final ConfirmRequest confirm = controller.confirm!;
      expect(confirm.dryRun, isTrue);
      expect(confirm.titleKey, 'label-dry-run');
      expect(confirm.args['count'], 1);
      expect(engine.deletes, isEmpty);
    },
  );

  test('accepting a dry run plans without removing rows', () async {
    controller
      ..addIncluded(<String>['/data'])
      ..selectTool('big_files');
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('big_files', <ScanRow>[
          StubEngine.row('/data/a', size: 100),
          StubEngine.row('/data/b', size: 200),
        ]),
      ),
    );
    await drain();
    controller.toggleSelected(controller.rows.first);
    controller.requestDelete();
    await controller.acceptConfirm();

    expect(engine.deletes.single.dryRun, isTrue);
    expect(engine.deletes.single.deleteToTrash, isTrue);
    expect(controller.rows.length, 2);
    expect(controller.confirm, isNull);
    expect(controller.statusText, 'Dry run only - no files were changed');
  });

  test('a delete that reports failures keeps every row in the table', () async {
    engine.deleteOutcome = const DeleteOutcome(
      affected: 1,
      errors: 1,
      reclaimedBytes: 100,
      messages: 'one path was locked',
      log: <String>['/data/a'],
    );
    controller
      ..addIncluded(<String>['/data'])
      ..selectTool('big_files')
      ..setDryRun(false)
      ..setMoveToTrash(false);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('big_files', <ScanRow>[
          StubEngine.row('/data/a', size: 100),
          StubEngine.row('/data/b', size: 200),
        ]),
      ),
    );
    await drain();
    controller.selectAllVisible();
    controller.requestDelete();
    await controller.acceptConfirm();

    expect(engine.deletes.single.deleteToTrash, isFalse);
    expect(controller.rows.map((ScanRow row) => row.path).toList(), <String>[
      '/data/a',
      '/data/b',
    ]);
    expect(controller.selectedCount, 0);
    expect(
      controller.messages,
      'one path was locked\n/data/a',
      reason: 'the engine summary comes first, then the per-file log',
    );
    expect(controller.statusText, 'Removed 1 paths, 1 failed');
  });

  test('a clean delete drops exactly the selected rows', () async {
    engine.deleteOutcome = const DeleteOutcome(
      affected: 2,
      errors: 0,
      reclaimedBytes: 300,
      messages: '',
      log: <String>[],
    );
    controller
      ..addIncluded(<String>['/data'])
      ..selectTool('big_files')
      ..setDryRun(false);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('big_files', <ScanRow>[
          StubEngine.row('/data/a', size: 100),
          StubEngine.row('/data/b', size: 200),
          StubEngine.row('/data/c', size: 300),
        ]),
      ),
    );
    await drain();
    controller.toggleSelected(controller.rows.first);
    controller.toggleSelected(controller.rows[1]);
    controller.requestDelete();
    await controller.acceptConfirm();

    expect(controller.rows.map((ScanRow row) => row.path).toList(), <String>[
      '/data/c',
    ]);
    expect(controller.visibleRows.single.path, '/data/c');
    expect(controller.selectedCount, 0);
    expect(controller.statusText, 'Removed 2 paths');
  });

  test('the per-file delete log reaches the messages view', () async {
    engine.deleteOutcome = const DeleteOutcome(
      affected: 1,
      errors: 0,
      reclaimedBytes: 100,
      messages: '1 file handled',
      log: <String>['/data/a -> trash', '/data/b -> refused'],
    );
    controller
      ..addIncluded(<String>['/data'])
      ..selectTool('big_files')
      ..setDryRun(false);
    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('big_files', <ScanRow>[
          StubEngine.row('/data/a', size: 100),
          StubEngine.row('/data/b', size: 200),
        ]),
      ),
    );
    await drain();
    controller.toggleSelected(controller.rows.first);
    controller.requestDelete();
    await controller.acceptConfirm();

    expect(controller.messages, contains('/data/a -> trash'));
    expect(controller.messages, contains('/data/b -> refused'));
    expect(controller.messages, contains('1 file handled'));
  });

  test(
    'a failing delete keeps the result set intact and records the error',
    () async {
      engine.deleteFailure = Exception('trash helper died');
      controller
        ..addIncluded(<String>['/data'])
        ..selectTool('big_files')
        ..setDryRun(false);
      controller.startScan();
      engine.emit(
        ScanEventCompleted(
          StubEngine.outcome('big_files', <ScanRow>[
            StubEngine.row('/data/a', size: 100),
          ]),
        ),
      );
      await drain();
      controller.toggleSelected(controller.rows.first);
      controller.requestDelete();
      await controller.acceptConfirm();

      expect(controller.rows.length, 1);
      expect(controller.critical, contains('trash helper died'));
      expect(controller.actionRunning, isFalse);
    },
  );

  test('export answers the scope it was given and reports the folder the engine wrote', () async {
    controller.addIncluded(<String>['/data']);
    await controller.exportResults('/tmp/out');
    expect(engine.exports, isEmpty);
    expect(controller.statusText, 'There are no results to export');

    controller.startScan();
    engine.emit(
      ScanEventCompleted(
        StubEngine.outcome('duplicate_files', <ScanRow>[
          StubEngine.row('/data/keep.bin', group: 0, start: true),
          StubEngine.row('/data/other.bin', group: 1, start: true),
        ]),
      ),
    );
    await drain();

    // The reference opens on the selection, so nothing picked is nothing to write - and the
    // export must not quietly fall back to dumping the whole result.
    expect(controller.exportScope, ExportScope.selected);
    await controller.exportResults('/tmp/out');
    expect(engine.exports, isEmpty);
    expect(controller.statusText, 'There are no results to export');

    controller.toggleSelected(controller.rows[1]);
    await controller.exportResults('/tmp/out', format: 'csv');

    final ExportRequest request = engine.exports.single;
    expect(
      request.rows.map((ScanRow row) => row.path),
      <String>['/data/other.bin'],
    );
    expect(request.format, 'csv');
    expect(request.grouped, isTrue);
    expect(request.tool, 'duplicate_files');
    expect(controller.statusText, 'Results written to /tmp/kisaki');

    // The three scopes answer differently, and the reference keeps `selected` independent of the
    // filter: a row the reader picked still exports after a filter hides it.
    controller.setFilter('keep');
    expect(controller.visibleRows, hasLength(1));
    controller.setExportScope(ExportScope.visible);
    expect(controller.exportScopeRows.map((ScanRow row) => row.path), <String>[
      '/data/keep.bin',
    ]);
    controller.setExportScope(ExportScope.selected);
    expect(controller.exportScopeRows.map((ScanRow row) => row.path), <String>[
      '/data/other.bin',
    ]);
    controller.setExportScope(ExportScope.all);
    expect(controller.exportScopeRows, hasLength(2));
    await controller.exportResults('/tmp/all');
    expect(engine.exports.last.rows.map((ScanRow row) => row.path), <String>[
      '/data/keep.bin',
      '/data/other.bin',
    ]);
  });

  test(
    'lane widths, collapse and reset round-trip through the layout',
    () async {
      controller.setSourceWidth(480);
      controller.setResultsWidth(300);
      controller.toggleLane('source');
      expect(controller.layout.sourceWidth, 480);
      expect(controller.layout.sourceCollapsed, isTrue);

      controller.toggleLane('results');
      expect(controller.layout.resultsCollapsed, isTrue);
      controller.toggleLane('analysis');
      expect(controller.layout.analysisCollapsed, isTrue);

      controller.resetLayout();
      expect(controller.layout.sourceCollapsed, isFalse);
      expect(controller.layout.resultsCollapsed, isFalse);
      expect(controller.layout.analysisCollapsed, isFalse);
      expect(controller.layout.sourceWidth, LaneLayout.sourceDefault);
    },
  );

  test(
    'theme toggle flips the single flag every colour derives from',
    () async {
      expect(controller.dark, isTrue);
      controller.toggleTheme();
      expect(controller.dark, isFalse);
      controller.toggleTheme();
      expect(controller.dark, isTrue);
    },
  );
}
