part of 'board_controller.dart';

/// The board's own history: what was asked of the engine and what came back.
///
/// The entries live in [BoardController] because the scan and the verbs write them from their own
/// methods; this half is the surface the activity panel reads and filters.
extension BoardActivityLog on BoardController {
  List<ActivityEntry> get activityLog =>
      List<ActivityEntry>.unmodifiable(_activity);

  List<ActivityEntry> get filteredActivity =>
      filterActivityLog(_activity, _activityQuery);

  String get activityQuery => _activityQuery;

  /// What the copy button puts on the clipboard: every entry, newest last.
  String get activityText => serializeActivityLog(_activity);

  void setActivityQuery(String value) {
    if (_activityQuery == value) {
      return;
    }
    _activityQuery = value;
    publish();
  }

  void clearActivityLog() {
    if (_activity.isEmpty) {
      return;
    }
    _activity.clear();
    publish();
  }

  /// Copies the whole history. The status line names the entry count instead of echoing every
  /// entry back through [copyText], whose path wording is built for a single line.
  Future<void> copyActivityLog() async {
    await Clipboard.setData(ClipboardData(text: activityText));
    _setStatus(
      'activity-copied',
      args: <String, Object>{'count': _activity.length},
    );
    publish();
  }

  /// Records one line of the board's own history; the tool comes from the row set it describes.
  void logActivity(
    ActivityKind kind,
    ActivityLevel level,
    String message, {
    int? progress,
    String? action,
    int? affectedCount,
    int? errorCount,
  }) {
    final List<ActivityEntry> next = appendActivityLog(
      _activity,
      ActivityDraft(
        tool: _tool?.id ?? '',
        kind: kind,
        level: level,
        message: message,
        progress: progress,
        action: action,
        affectedCount: affectedCount,
        errorCount: errorCount,
      ),
    );
    _activity
      ..clear()
      ..addAll(next);
    publish();
  }

  /// The reference appends every engine event. Kisaki's engine repeats the same stage with a new
  /// percentage, so only a stage change is recorded - the rail already shows the live percentage.
  void logProgress(ProgressUpdate update) {
    final String stage = Labels.of(update.stageLabelKey);
    if (stage == _lastProgressStage) {
      return;
    }
    _lastProgressStage = stage;
    logActivity(
      ActivityKind.progress,
      ActivityLevel.info,
      stage,
      progress: update.percent < 0 ? null : update.percent,
    );
  }
}
