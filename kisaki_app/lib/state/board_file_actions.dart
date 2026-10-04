part of 'board_controller.dart';

/// The row actions that reach outside the board: open a file with its default app, reveal it in the
/// file manager, and put the file object itself on the system clipboard.
///
/// All three belong to the host, so a build without one lists them disabled rather than leaving the
/// reader to discover it by clicking, and a failing host reports through the status line instead of
/// throwing into a gesture callback.
extension BoardFileActions on BoardController {
  FileHost get fileHost => _fileHost;

  bool get canOpenFiles => _fileHost.canOpen;

  bool get canRevealFiles => _fileHost.canReveal;

  bool get canCopyFiles => _fileHost.canCopyFiles;

  Future<void> openPath(String path) async {
    final Future<void> Function(String path)? open = _fileHost.open;
    if (open == null) {
      return;
    }
    await _fileAction(
      () => open(path),
      doneKey: 'status_opened',
      failedKey: 'status_open_failed',
      subject: path,
    );
  }

  Future<void> revealPath(String path) async {
    final Future<void> Function(String path)? reveal = _fileHost.reveal;
    if (reveal == null) {
      return;
    }
    await _fileAction(
      () => reveal(path),
      doneKey: 'status_revealed',
      failedKey: 'status_reveal_failed',
      subject: path,
    );
  }

  /// `paths` is one row or a whole selection; the reference copies the row under the pointer.
  Future<void> copyFilesToClipboard(List<String> paths) async {
    final Future<void> Function(List<String> paths)? copyFiles =
        _fileHost.copyFiles;
    if (copyFiles == null || paths.isEmpty) {
      return;
    }
    await _fileAction(
      () => copyFiles(paths),
      doneKey: 'status_copied_files',
      failedKey: 'status_copy_files_failed',
      subject: paths.length == 1 ? paths.single : '${paths.length} files',
    );
  }

  Future<void> _fileAction(
    Future<void> Function() action, {
    required String doneKey,
    required String failedKey,
    required String subject,
  }) async {
    try {
      await action();
      _setStatus(doneKey, args: <String, Object>{'path': subject});
    } on FileHostException catch (error) {
      _setStatus(
        failedKey,
        args: <String, Object>{'path': error.path, 'error': error.message},
      );
      logActivity(
        ActivityKind.operation,
        ActivityLevel.error,
        error.toString(),
      );
    }
    publish();
  }
}
