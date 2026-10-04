part of 'board_controller.dart';

/// The two row actions that reach outside the board: open a file with its default app, or reveal it in
/// the file manager.
///
/// Both belong to the host, so a build without one has no such menu item, and a failing host reports
/// through the status line rather than throwing into a gesture callback.
extension BoardFileActions on BoardController {
  FileHost get fileHost => _fileHost;

  bool get canOpenFiles => _fileHost.canOpen;

  bool get canRevealFiles => _fileHost.canReveal;

  Future<void> openPath(String path) async {
    final Future<void> Function(String path)? open = _fileHost.open;
    if (open == null) {
      return;
    }
    await _fileAction(open, path, 'status_opened', 'status_open_failed');
  }

  Future<void> revealPath(String path) async {
    final Future<void> Function(String path)? reveal = _fileHost.reveal;
    if (reveal == null) {
      return;
    }
    await _fileAction(reveal, path, 'status_revealed', 'status_reveal_failed');
  }

  Future<void> _fileAction(
    Future<void> Function(String path) action,
    String path,
    String doneKey,
    String failedKey,
  ) async {
    try {
      await action(path);
      _setStatus(doneKey, args: <String, Object>{'path': path});
    } on FileHostException catch (error) {
      _setStatus(failedKey, args: <String, Object>{
        'path': error.path,
        'error': error.message,
      });
      logActivity(
        ActivityKind.operation,
        ActivityLevel.error,
        error.toString(),
      );
    }
    publish();
  }
}
