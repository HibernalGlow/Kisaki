import '../engine/models.dart';
import 'selection_rules.dart' show naturalCompare;

/// Dart port of `packages/nodes/czkawka/src/similar-folders.ts`.
///
/// The reference derives these statistics from the scan groups rather than from a scanner of its
/// own, so Kisaki computes them from the same groups the table shows.
class FolderStat {
  const FolderStat({
    required this.path,
    required this.count,
    required this.bytes,
    required this.groupCount,
    this.previewPath,
  });

  final String path;
  final int count;
  final int bytes;
  final int groupCount;
  final String? previewPath;

  @override
  bool operator ==(Object other) =>
      other is FolderStat &&
      other.path == path &&
      other.count == count &&
      other.bytes == bytes &&
      other.groupCount == groupCount &&
      other.previewPath == previewPath;

  @override
  int get hashCode => Object.hash(path, count, bytes, groupCount, previewPath);

  @override
  String toString() =>
      'FolderStat($path, count: $count, bytes: $bytes, groups: $groupCount, '
      'preview: $previewPath)';
}

class _Accumulator {
  int count = 0;
  int bytes = 0;
  final Set<int> groups = <int>{};
  String? previewPath;
  bool previewIsReference = true;
}

List<FolderStat> buildSimilarFolders(
  List<List<ScanRow>> groups, {
  int threshold = 2,
}) {
  // Dart's int cannot be non-finite, so only the reference's floor still applies here.
  final int minimum = threshold < 1 ? 1 : threshold;
  final Map<String, _Accumulator> stats = <String, _Accumulator>{};
  for (int index = 0; index < groups.length; index++) {
    for (final ScanRow row in groups[index]) {
      final String? folder = _parentPath(row.path);
      if (folder == null) {
        continue;
      }
      final _Accumulator current = stats.putIfAbsent(
        folder,
        () => _Accumulator(),
      );
      current.count += 1;
      current.bytes += row.sizeBytes;
      current.groups.add(index);
      if (current.previewPath == null ||
          (!row.isReference && current.previewIsReference)) {
        current.previewPath = row.path;
        current.previewIsReference = row.isReference;
      }
    }
  }
  final List<FolderStat> result = stats.entries
      .where(
        (MapEntry<String, _Accumulator> entry) => entry.value.count >= minimum,
      )
      .map(
        (MapEntry<String, _Accumulator> entry) => FolderStat(
          path: entry.key,
          count: entry.value.count,
          bytes: entry.value.bytes,
          groupCount: entry.value.groups.length,
          previewPath: entry.value.previewPath,
        ),
      )
      .toList();
  result.sort((FolderStat left, FolderStat right) {
    if (left.count != right.count) {
      return right.count - left.count;
    }
    if (left.bytes != right.bytes) {
      return right.bytes - left.bytes;
    }
    return naturalCompare(left.path, right.path);
  });
  return result;
}

/// Keeps the separator style of the incoming path, because a Windows result must not be shown with
/// forward slashes.
String? _parentPath(String path) {
  final String normalized = path
      .replaceAll(r'\', '/')
      .replaceAll(RegExp(r'/+$'), '');
  final int index = normalized.lastIndexOf('/');
  if (index <= 0) {
    return null;
  }
  final String parent = normalized.substring(0, index);
  return path.contains(r'\') ? parent.replaceAll('/', r'\') : parent;
}
