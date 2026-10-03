/// Dart port of `packages/nodes/czkawka/src/activity-log.ts`.
///
/// The log is the board's own record of what it asked the engine to do, so it survives a scan that
/// was stopped and an operation that failed; only the newest `limit` entries are kept.
enum ActivityKind {
  scan('scan'),
  progress('progress'),
  operation('operation'),
  system('system');

  const ActivityKind(this.wire);

  final String wire;
}

enum ActivityLevel {
  info('info', '\u00b7'),
  success('success', '\u2713'),
  warning('warning', '!'),
  error('error', '\u00d7');

  const ActivityLevel(this.wire, this.marker);

  final String wire;

  /// The marker is part of the text, so a copied log reads the same as the painted one.
  final String marker;

  static ActivityLevel fromWire(String value) =>
      ActivityLevel.values.firstWhere(
        (ActivityLevel level) => level.wire == value,
        orElse: () => ActivityLevel.info,
      );
}

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.timestamp,
    required this.tool,
    required this.kind,
    required this.level,
    required this.message,
    this.progress,
    this.action,
    this.affectedCount,
    this.errorCount,
  });

  final String id;
  final int timestamp;
  final String tool;
  final ActivityKind kind;
  final ActivityLevel level;
  final String message;
  final int? progress;
  final String? action;
  final int? affectedCount;
  final int? errorCount;
}

/// A entry without an id and a timestamp, which is what the caller knows.
class ActivityDraft {
  const ActivityDraft({
    required this.tool,
    required this.kind,
    required this.level,
    required this.message,
    this.progress,
    this.action,
    this.affectedCount,
    this.errorCount,
  });

  final String tool;
  final ActivityKind kind;
  final ActivityLevel level;
  final String message;
  final int? progress;
  final String? action;
  final int? affectedCount;
  final int? errorCount;
}

List<ActivityEntry> appendActivityLog(
  List<ActivityEntry> entries,
  ActivityDraft draft, {
  int limit = 200,
  int? now,
}) {
  final int timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
  final ActivityEntry entry = ActivityEntry(
    id: '$timestamp-${entries.length}-${draft.kind.wire}',
    timestamp: timestamp,
    tool: draft.tool,
    kind: draft.kind,
    level: draft.level,
    message: draft.message,
    progress: draft.progress,
    action: draft.action,
    affectedCount: draft.affectedCount,
    errorCount: draft.errorCount,
  );
  final int kept = limit < 1 ? 1 : limit;
  final List<ActivityEntry> next = <ActivityEntry>[...entries, entry];
  return next.length <= kept ? next : next.sublist(next.length - kept);
}

/// Matches the tool, kind, level, action or message, like the reference's filter.
List<ActivityEntry> filterActivityLog(
  List<ActivityEntry> entries,
  String query,
) {
  final String needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return entries;
  }
  return entries
      .where(
        (ActivityEntry entry) => <String?>[
          entry.tool,
          entry.kind.wire,
          entry.level.wire,
          entry.action,
          entry.message,
        ].any((String? value) => (value ?? '').toLowerCase().contains(needle)),
      )
      .toList();
}

String formatActivityMessage(
  ActivityLevel level,
  String message, {
  int? progress,
}) {
  final String percentage = progress == null ? '' : ' [$progress%]';
  return '${level.marker}$percentage $message';
}

String formatActivityEntry(ActivityEntry entry) {
  final String time = DateTime.fromMillisecondsSinceEpoch(
    entry.timestamp,
    isUtc: true,
  ).toIso8601String();
  final String result = entry.affectedCount == null
      ? ''
      : ' \u00b7 ${entry.affectedCount} affected / ${entry.errorCount ?? 0} errors';
  return '$time \u00b7 ${entry.tool} \u00b7 ${entry.kind.wire} \u00b7 '
      '${formatActivityMessage(entry.level, entry.message, progress: entry.progress)}$result';
}

String serializeActivityLog(List<ActivityEntry> entries) =>
    entries.map(formatActivityEntry).join('\n');
