import '../engine/models.dart' show ScanRow;
import 'similar_folders.dart' show parentPath;

/// Dart port of `packages/nodes/czkawka/src/operations.ts`.
const String organizeDefaultTemplate = 'variants_{groupId}';

class OrganizeOptions {
  const OrganizeOptions({
    this.subfolderTemplate = organizeDefaultTemplate,
    this.skipSingleFileFolders = true,
  });

  final String subfolderTemplate;
  final bool skipSingleFileFolders;

  OrganizeOptions copyWith({
    String? subfolderTemplate,
    bool? skipSingleFileFolders,
  }) => OrganizeOptions(
    subfolderTemplate: subfolderTemplate ?? this.subfolderTemplate,
    skipSingleFileFolders: skipSingleFileFolders ?? this.skipSingleFileFolders,
  );
}

class OrganizeItem {
  const OrganizeItem({required this.path, required this.destination});

  final String path;
  final String destination;

  @override
  bool operator ==(Object other) =>
      other is OrganizeItem &&
      other.path == path &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(path, destination);

  @override
  String toString() => 'OrganizeItem($path -> $destination)';
}

class OrganizePlan {
  const OrganizePlan({
    required this.items,
    required this.selectedGroupCount,
    required this.targetFolderCount,
  });

  final List<OrganizeItem> items;
  final int selectedGroupCount;
  final int targetFolderCount;
}

/// Expands each selected row to every non-reference row of its group and gives them one folder per
/// source directory, as the reference does.
OrganizePlan buildGroupOrganizePlan(
  List<List<ScanRow>> groups,
  Iterable<String> selectedPaths,
  OrganizeOptions options,
) {
  final Set<String> selected = selectedPaths.toSet();
  final Set<int> selectedGroupIds = groups
      .where(
        (List<ScanRow> group) => group.any(
          (ScanRow row) => !row.isReference && selected.contains(row.path),
        ),
      )
      .map(_groupId)
      .toSet();

  final Map<String, _Folder> grouped = <String, _Folder>{};
  for (final List<ScanRow> group in groups) {
    final int groupId = _groupId(group);
    if (!selectedGroupIds.contains(groupId)) {
      continue;
    }
    for (final ScanRow row in group) {
      if (row.isReference) {
        continue;
      }
      final String? parent = parentPath(row.path);
      if (parent == null) {
        continue;
      }
      final String key = '$groupId|$parent';
      final _Folder current = grouped.putIfAbsent(
        key,
        () => _Folder(groupId: groupId, parent: parent),
      );
      if (!current.paths.contains(row.path)) {
        current.paths.add(row.path);
      }
    }
  }

  final List<OrganizeItem> items = <OrganizeItem>[];
  for (final _Folder folder in grouped.values) {
    if (options.skipSingleFileFolders && folder.paths.length < 2) {
      continue;
    }
    final String destination = _joinPortable(
      folder.parent,
      resolveSubfolderName(options.subfolderTemplate, folder.groupId),
    );
    for (final String path in folder.paths) {
      items.add(OrganizeItem(path: path, destination: destination));
    }
  }

  return OrganizePlan(
    items: items,
    selectedGroupCount: selectedGroupIds.length,
    targetFolderCount: items
        .map((OrganizeItem item) => item.destination)
        .toSet()
        .length,
  );
}

String resolveSubfolderName(String template, int groupId) {
  final String sanitized = template
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .trim();
  final String used = sanitized.isEmpty ? organizeDefaultTemplate : sanitized;
  return used.replaceAll('{groupId}', groupId.toString().padLeft(4, '0'));
}

int _groupId(List<ScanRow> group) =>
    group.isEmpty ? -1 : group.first.groupIndex;

String _joinPortable(String parent, String child) {
  final String separator = parent.contains(r'\') ? r'\' : '/';
  final String base = parent.endsWith('/') || parent.endsWith(r'\')
      ? parent
      : '$parent$separator';
  return '$base$child';
}

class _Folder {
  _Folder({required this.groupId, required this.parent});

  final int groupId;
  final String parent;
  final List<String> paths = <String>[];
}
