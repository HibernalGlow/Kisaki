import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/state/activity_log.dart';

/// Ported rules from `packages/nodes/czkawka/src/activity-log.ts`: one bounded history, one filter
/// over the searchable fields, and one formatter shared by the panel, the tooltip and the clipboard.
void main() {
  ActivityDraft draft({
    String tool = 'duplicate-files',
    ActivityKind kind = ActivityKind.scan,
    ActivityLevel level = ActivityLevel.info,
    String message = 'start',
    int? progress,
    String? action,
    int? affectedCount,
    int? errorCount,
  }) => ActivityDraft(
    tool: tool,
    kind: kind,
    level: level,
    message: message,
    progress: progress,
    action: action,
    affectedCount: affectedCount,
    errorCount: errorCount,
  );

  test('appends a bounded history without touching the caller list', () {
    final List<ActivityEntry> source = <ActivityEntry>[];
    final List<ActivityEntry> first = appendActivityLog(
      source,
      draft(message: 'start'),
      limit: 2,
      now: 100,
    );
    final List<ActivityEntry> second = appendActivityLog(
      first,
      draft(kind: ActivityKind.progress, message: 'hash', progress: 50),
      limit: 2,
      now: 200,
    );
    final List<ActivityEntry> third = appendActivityLog(
      second,
      draft(level: ActivityLevel.success, message: 'done'),
      limit: 2,
      now: 300,
    );

    expect(source, isEmpty, reason: 'the appended list is left alone');
    expect(first, hasLength(1));
    expect(third.map((ActivityEntry entry) => entry.message), <String>[
      'hash',
      'done',
    ]);
  });

  test(
    'ids carry the timestamp, the length before the append and the kind',
    () {
      final List<ActivityEntry> appended = appendActivityLog(
        <ActivityEntry>[
          ActivityEntry(
            id: '100-0-scan',
            timestamp: 100,
            tool: 'duplicate-files',
            kind: ActivityKind.scan,
            level: ActivityLevel.info,
            message: 'start',
          ),
        ],
        draft(kind: ActivityKind.operation, action: 'delete'),
        now: 200,
      );

      expect(appended.last.id, '200-1-operation');
    },
  );

  test('a limit below one still keeps the newest entry', () {
    final List<ActivityEntry> appended = appendActivityLog(
      <ActivityEntry>[
        ActivityEntry(
          id: 'a',
          timestamp: 1,
          tool: 'big-files',
          kind: ActivityKind.scan,
          level: ActivityLevel.info,
          message: 'older',
        ),
      ],
      draft(message: 'newest'),
      limit: 0,
      now: 2,
    );

    expect(appended.map((ActivityEntry entry) => entry.message), <String>[
      'newest',
    ]);
  });

  test('filters every searchable field and ignores case', () {
    final List<ActivityEntry> entries = <ActivityEntry>[
      appendActivityLog(
        <ActivityEntry>[],
        draft(
          tool: 'similar-images',
          kind: ActivityKind.progress,
          message: 'hashing',
        ),
        now: 1,
      ).single,
      appendActivityLog(
        <ActivityEntry>[],
        draft(
          tool: 'empty-files',
          kind: ActivityKind.operation,
          level: ActivityLevel.error,
          action: 'delete',
          message: 'failed',
        ),
        now: 2,
      ).single,
    ];

    expect(filterActivityLog(entries, 'hash'), hasLength(1));
    expect(filterActivityLog(entries, 'delete'), hasLength(1));
    expect(filterActivityLog(entries, '  EMPTY  '), hasLength(1));
    expect(filterActivityLog(entries, 'progress'), hasLength(1));
    expect(filterActivityLog(entries, 'error'), hasLength(1));
    expect(filterActivityLog(entries, 'nothing-matches'), isEmpty);
    expect(
      filterActivityLog(entries, ''),
      same(entries),
      reason: 'an empty query is the list itself, like the reference',
    );
  });

  test('one formatter serves the panel, the tooltip and the clipboard', () {
    final ActivityEntry entry = appendActivityLog(
      <ActivityEntry>[],
      draft(
        tool: 'big-files',
        kind: ActivityKind.operation,
        level: ActivityLevel.warning,
        action: 'move',
        message: 'partial',
        affectedCount: 3,
        errorCount: 1,
      ),
      now: 0,
    ).single;

    expect(
      formatActivityMessage(ActivityLevel.info, 'scan', progress: 42),
      '\u00b7 [42%] scan',
    );
    expect(
      formatActivityMessage(ActivityLevel.info, 'scan'),
      '\u00b7 scan',
      reason: 'an unmeasurable stage shows no percentage',
    );
    expect(
      formatActivityEntry(entry),
      contains('! partial \u00b7 3 affected / 1 errors'),
    );
    expect(
      serializeActivityLog(<ActivityEntry>[entry]),
      contains('big-files \u00b7 operation'),
    );
  });

  test('serialize puts one entry per line, oldest first', () {
    final List<ActivityEntry> entries = appendActivityLog(
      appendActivityLog(<ActivityEntry>[], draft(message: 'first'), now: 1),
      draft(message: 'second'),
      now: 2,
    );

    expect(serializeActivityLog(entries).split('\n'), hasLength(2));
    expect(
      serializeActivityLog(entries).indexOf('first'),
      lessThan(serializeActivityLog(entries).indexOf('second')),
    );
    expect(serializeActivityLog(<ActivityEntry>[]), isEmpty);
  });

  test('levels round trip over their wire names and markers', () {
    for (final ActivityLevel level in ActivityLevel.values) {
      expect(ActivityLevel.fromWire(level.wire), level);
    }
    expect(ActivityLevel.fromWire('fatal'), ActivityLevel.info);
    expect(
      ActivityLevel.values.map((ActivityLevel level) => level.marker).join(),
      '\u00b7\u2713!\u00d7',
    );
  });

  test('kinds keep the wire names the reference filters on', () {
    expect(
      ActivityKind.values.map((ActivityKind kind) => kind.wire).toList(),
      <String>['scan', 'progress', 'operation', 'system'],
    );
  });
}
