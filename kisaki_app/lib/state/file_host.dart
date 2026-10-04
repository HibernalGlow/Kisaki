import 'dart:io';

/// Opening a file in its default app, revealing it in the file manager, and putting the file itself on
/// the system clipboard.
///
/// This is a host seam because the reference gates those row actions on the callbacks its host passes:
/// without one the item is shown disabled and says so, rather than pretending to work. Tests inject a
/// recorder, so no widget test can launch a real application or touch the clipboard.
class FileHost {
  const FileHost({this.open, this.reveal, this.copyFiles});

  /// A null opener means this build cannot open files, and the menu item is shown but disabled.
  final Future<void> Function(String path)? open;
  final Future<void> Function(String path)? reveal;

  /// The file object on the clipboard, not its name - what a paste into a folder needs.
  final Future<void> Function(List<String> paths)? copyFiles;

  static const FileHost unsupported = FileHost();

  bool get canOpen => open != null;

  bool get canReveal => reveal != null;

  bool get canCopyFiles => copyFiles != null;
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

/// The host a desktop build ships with. Linux has no portable "reveal this file" command, and copying
/// a file object needs a file manager that owns the clipboard, so both stay absent there rather than
/// guessing at a desktop environment's helper.
FileHost desktopFileHost() {
  if (Platform.isMacOS) {
    return FileHost(
      open: (String path) => _run('open', const <String>[], path),
      reveal: (String path) => _run('open', const <String>['-R'], path),
      copyFiles: (List<String> paths) =>
          _runList('osascript', <String>[..._copyFilesScript, ...paths], paths),
    );
  }
  if (Platform.isLinux) {
    return FileHost(
      open: (String path) => _run('xdg-open', const <String>[], path),
    );
  }
  if (Platform.isWindows) {
    return FileHost(
      open: (String path) => _run('explorer.exe', const <String>[], path),
      reveal: (String path) =>
          _run('explorer.exe', const <String>['/select,'], path),
    );
  }
  return FileHost.unsupported;
}

/// Finder owns the file-object flavour of the clipboard. `on run argv` keeps every path out of the
/// script source, because a file name holding a quote would otherwise become AppleScript code.
/// Scripting Finder is also the one host action that asks the system for automation permission, so the
/// first use on a fresh machine is expected to produce a prompt rather than fail silently.
const List<String> _copyFilesScript = <String>[
  '-e',
  'on run argv',
  '-e',
  'set picked to {}',
  '-e',
  'repeat with anArg in argv',
  '-e',
  'set end of picked to POSIX file (anArg as text)',
  '-e',
  'end repeat',
  '-e',
  'tell application "Finder" to set the clipboard to picked',
  '-e',
  'end run',
];

Future<void> _run(String executable, List<String> before, String path) =>
    _runList(executable, <String>[...before, path], <String>[path]);

/// `paths` is the row or selection the caller asked for, and it travels with the failure so the status
/// line names what was handed over rather than a bare "Permission denied".
Future<void> _runList(
  String executable,
  List<String> arguments,
  List<String> paths,
) async {
  final String subject = paths.length == 1
      ? paths.single
      : '${paths.length} files';
  ProcessResult result;
  try {
    result = await Process.run(executable, arguments, runInShell: false);
  } on ProcessException catch (error) {
    throw FileHostException(
      executable: executable,
      path: subject,
      message: error.message,
    );
  }
  if (result.exitCode != 0) {
    final String detail = (result.stderr as String).trim();
    throw FileHostException(
      executable: executable,
      path: subject,
      message: detail.isEmpty ? 'exit code ${result.exitCode}' : detail,
    );
  }
}
