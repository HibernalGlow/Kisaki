import 'dart:io';

/// Opening a file in its default app, and revealing it in the file manager.
///
/// This is a host seam because the reference only offers those two row actions when the embedding host
/// supplies them: with no host the menu leaves them out rather than showing a dead item. Tests inject a
/// recorder, so no widget test can launch a real application.
class FileHost {
  const FileHost({this.open, this.reveal});

  /// A null opener means this build cannot open files, and the menu drops the item.
  final Future<void> Function(String path)? open;
  final Future<void> Function(String path)? reveal;

  static const FileHost unsupported = FileHost();

  bool get canOpen => open != null;

  bool get canReveal => reveal != null;
}

/// Why a file action failed. The path travels with the message, because a bare "Permission denied" from
/// the process layer is impossible to trace back to a row.
class FileHostException implements Exception {
  const FileHostException({
    required this.executable,
    required this.path,
    required this.message,
  });

  final String executable;
  final String path;
  final String message;

  @override
  String toString() => '$executable could not handle $path: $message';
}

/// The host a desktop build ships with. Linux has no portable "reveal this file" command, so that
/// capability stays absent there instead of guessing at a desktop environment's helper.
FileHost desktopFileHost() {
  if (Platform.isMacOS) {
    return FileHost(
      open: (String path) => _run('open', const <String>[], path),
      reveal: (String path) => _run('open', const <String>['-R'], path),
    );
  }
  if (Platform.isLinux) {
    return FileHost(open: (String path) => _run('xdg-open', const <String>[], path));
  }
  if (Platform.isWindows) {
    return FileHost(
      open: (String path) => _run('explorer.exe', const <String>[], path),
      reveal: (String path) => _run('explorer.exe', const <String>['/select,'], path),
    );
  }
  return FileHost.unsupported;
}

Future<void> _run(String executable, List<String> before, String path) async {
  final List<String> arguments = <String>[...before, path];
  ProcessResult result;
  try {
    result = await Process.run(executable, arguments, runInShell: false);
  } on ProcessException catch (error) {
    throw FileHostException(
      executable: executable,
      path: path,
      message: error.message,
    );
  }
  if (result.exitCode != 0) {
    final String detail = (result.stderr as String).trim();
    throw FileHostException(
      executable: executable,
      path: path,
      message: detail.isEmpty ? 'exit code ${result.exitCode}' : detail,
    );
  }
}
