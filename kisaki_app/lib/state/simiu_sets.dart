import '../engine/models.dart';
import 'selection_rules.dart' show naturalCompare;
import 'similar_folders.dart' show parentPath;

/// Dart port of `packages/nodes/czkawka/src/simiu-sets.ts`.
///
/// The reference walks the disk to learn which images share a directory; Kisaki plans from the scan
/// result it already holds, so a file the scan did not report is never moved. The engine still owns
/// the mutation and re-reserves every target, so nothing is written over an existing file.
const Set<String> simiuSetImageExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.bmp',
  '.gif',
  '.tif',
  '.tiff',
  '.avif',
  '.jxl',
};

const String simiuSetMarker = '__set_';
const String simiuDefaultPrefix = 'simiu_set';
const int simiuMinimumFloor = 2;
const int simiuMaximumFloor = 10000;

enum SimiuScanOrder {
  path('path'),
  smallestFirst('smallest-first'),
  deepestFirst('deepest-first');

  const SimiuScanOrder(this.wire);

  /// The reference's wire value, kept so a stored plan round-trips through the same names.
  final String wire;

  static SimiuScanOrder fromWire(String value) =>
      SimiuScanOrder.values.firstWhere(
        (SimiuScanOrder order) => order.wire == value,
        orElse: () => SimiuScanOrder.smallestFirst,
      );
}

class SimiuOptions {
  const SimiuOptions({
    this.roots = const <String>[],
    this.recursive = true,
    this.scanOrder = SimiuScanOrder.smallestFirst,
    this.namePrefix = simiuDefaultPrefix,
    this.minimumGroupSize = simiuMinimumFloor,
  });

  final List<String> roots;
  final bool recursive;
  final SimiuScanOrder scanOrder;
  final String namePrefix;
  final int minimumGroupSize;

  SimiuOptions normalized() => SimiuOptions(
    roots: uniqueSimiuRoots(roots),
    recursive: recursive,
    scanOrder: scanOrder,
    namePrefix: sanitizeSimiuPrefix(namePrefix),
    minimumGroupSize: minimumGroupSize.clamp(
      simiuMinimumFloor,
      simiuMaximumFloor,
    ),
  );

  SimiuOptions copyWith({
    bool? recursive,
    SimiuScanOrder? scanOrder,
    String? namePrefix,
    int? minimumGroupSize,
  }) => SimiuOptions(
    roots: roots,
    recursive: recursive ?? this.recursive,
    scanOrder: scanOrder ?? this.scanOrder,
    namePrefix: namePrefix ?? this.namePrefix,
    minimumGroupSize: minimumGroupSize ?? this.minimumGroupSize,
  );
}

class SimiuSetGroup {
  const SimiuSetGroup({
    required this.root,
    required this.parentDirectory,
    required this.name,
    required this.files,
  });

  final String root;
  final String parentDirectory;
  final String name;
  final List<String> files;
}

class SimiuPlan {
  const SimiuPlan({
    required this.groups,
    required this.operations,
    required this.directoryCount,
    required this.imageCount,
  });

  final List<SimiuSetGroup> groups;
  final List<SimiuOperation> operations;
  final int directoryCount;
  final int imageCount;
}

class _Directory {
  _Directory({required this.root, required this.path});

  final String root;
  final String path;
  final List<String> images = <String>[];
}

/// Builds the set folders and the file moves that fill them, in the reference's order.
SimiuPlan planSimiuSets({
  required List<ScanRow> rows,
  required SimiuOptions options,
}) {
  final SimiuOptions normalized = options.normalized();
  final List<_Directory> directories = _collectDirectories(rows, normalized);
  final Map<String, List<List<String>>> candidates = _partitionByDirectory(
    rows,
    directories,
    normalized.minimumGroupSize,
  );
  final Map<String, Set<String>> children = _childNamesByDirectory(rows);
  final List<SimiuSetGroup> groups = <SimiuSetGroup>[];
  final List<SimiuOperation> operations = <SimiuOperation>[];
  final Set<String> claimed = <String>{};
  int imageCount = 0;

  for (final _Directory directory in directories) {
    imageCount += directory.images.length;
    final List<List<String>> found =
        candidates[_normalizedDirectory(directory.path)] ??
        const <List<String>>[];
    // One candidate holding every image in the folder is a directory that is already a single set.
    if (found.length == 1 && found.first.length == directory.images.length) {
      continue;
    }
    final List<String> names = _resolveGroupNames(
      directory.path,
      found.length,
      normalized.namePrefix,
      children[_normalizedDirectory(directory.path)] ?? const <String>{},
    );
    for (int index = 0; index < found.length; index++) {
      final String name = names[index];
      groups.add(
        SimiuSetGroup(
          root: directory.root,
          parentDirectory: directory.path,
          name: name,
          files: found[index],
        ),
      );
      for (final String file in found[index]) {
        operations.add(
          SimiuOperation(
            root: directory.root,
            source: file,
            target: _freePath(
              _join(_join(directory.path, name), _baseName(file)),
              claimed,
            ),
          ),
        );
      }
    }
  }

  return SimiuPlan(
    groups: groups,
    operations: operations,
    directoryCount: directories.length,
    imageCount: imageCount,
  );
}

bool isSimiuSetImage(String path) {
  final int dot = path.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  return simiuSetImageExtensions.contains(path.substring(dot).toLowerCase());
}

bool shouldSkipSimiuSetDirectory(String path, String namePrefix) {
  final String name = _baseName(path).toLowerCase();
  return name.startsWith('.simiu-') ||
      name.contains(simiuSetMarker) ||
      name.startsWith(namePrefix.toLowerCase());
}

String sanitizeSimiuPrefix(String value) {
  final String cleaned = value.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  return cleaned.isEmpty ? simiuDefaultPrefix : cleaned;
}

/// Roots that can hold a set, deduplicated the way the reference deduplicates them.
List<String> uniqueSimiuRoots(List<String> roots) {
  final Set<String> seen = <String>{};
  final List<String> result = <String>[];
  for (final String root in roots) {
    final String trimmed = root.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (seen.add(_normalizedDirectory(trimmed))) {
      result.add(trimmed);
    }
  }
  return result;
}

List<_Directory> _collectDirectories(List<ScanRow> rows, SimiuOptions options) {
  final Map<String, _Directory> found = <String, _Directory>{};
  for (final ScanRow row in rows) {
    if (!isSimiuSetImage(row.path)) {
      continue;
    }
    final String? directory = parentPath(row.path);
    if (directory == null) {
      continue;
    }
    final String? root = _rootOf(directory, options.roots, options.recursive);
    if (root == null) {
      continue;
    }
    found
        .putIfAbsent(
          _normalizedDirectory(directory),
          () => _Directory(root: root, path: directory),
        )
        .images
        .add(row.path);
  }
  final List<_Directory> kept = found.values
      .where(
        (_Directory directory) =>
            !shouldSkipSimiuSetDirectory(directory.path, options.namePrefix),
      )
      .toList();
  for (final _Directory directory in kept) {
    directory.images.sort(naturalCompare);
  }
  kept.sort((_Directory left, _Directory right) {
    return switch (options.scanOrder) {
      SimiuScanOrder.smallestFirst => _byCountThenPath(left, right),
      SimiuScanOrder.deepestFirst => _or(
        _depth(right.path) - _depth(left.path),
        _byCountThenPath(left, right),
      ),
      SimiuScanOrder.path => naturalCompare(left.path, right.path),
    };
  });
  return kept;
}

/// The reference's `a || b` on comparators: the first non-zero result wins.
int _or(int primary, int secondary) => primary != 0 ? primary : secondary;

int _byCountThenPath(_Directory left, _Directory right) => _or(
  left.images.length - right.images.length,
  naturalCompare(left.path, right.path),
);

/// Mirrors `partitionSimiuSimilarityGroups`: one candidate per directory inside a similarity group,
/// dropped below the minimum size, biggest candidate first.
Map<String, List<List<String>>> _partitionByDirectory(
  List<ScanRow> rows,
  List<_Directory> directories,
  int minimumGroupSize,
) {
  final Map<String, String> directoryByImage = <String, String>{};
  for (final _Directory directory in directories) {
    final String key = _normalizedDirectory(directory.path);
    for (final String image in directory.images) {
      directoryByImage[_normalizedFile(image)] = key;
    }
  }

  final Map<int, List<ScanRow>> similarityGroups = <int, List<ScanRow>>{};
  for (final ScanRow row in rows) {
    similarityGroups.putIfAbsent(row.groupIndex, () => <ScanRow>[]).add(row);
  }

  final Map<String, List<List<String>>> candidates =
      <String, List<List<String>>>{};
  for (final List<ScanRow> group in similarityGroups.values) {
    final Map<String, List<String>> members = <String, List<String>>{};
    for (final ScanRow row in group) {
      final String? key = directoryByImage[_normalizedFile(row.path)];
      if (key == null) {
        continue;
      }
      members.putIfAbsent(key, () => <String>[]).add(row.path);
    }
    members.forEach((String key, List<String> paths) {
      if (paths.length < minimumGroupSize) {
        return;
      }
      paths.sort(naturalCompare);
      candidates.putIfAbsent(key, () => <List<String>>[]).add(paths);
    });
  }
  for (final List<List<String>> perDirectory in candidates.values) {
    perDirectory.sort(
      (List<String> left, List<String> right) => _or(
        right.length - left.length,
        naturalCompare(left.first, right.first),
      ),
    );
  }
  return candidates;
}

/// The folder names visible under each parent in the scan. An empty folder cannot be seen by a scan,
/// which is why the engine re-reserves every target before it writes.
Map<String, Set<String>> _childNamesByDirectory(List<ScanRow> rows) {
  final Set<String> directories = <String>{};
  for (final ScanRow row in rows) {
    final String? parent = parentPath(row.path);
    if (parent != null) {
      directories.add(_normalizedDirectory(parent));
    }
  }
  final Map<String, Set<String>> children = <String, Set<String>>{};
  for (final String directory in directories) {
    final int slash = directory.lastIndexOf('/');
    if (slash <= 0) {
      continue;
    }
    children
        .putIfAbsent(directory.substring(0, slash), () => <String>{})
        .add(directory.substring(slash + 1));
  }
  return children;
}

List<String> _resolveGroupNames(
  String parent,
  int count,
  String prefix,
  Set<String> existing,
) {
  final Set<String> used = <String>{};
  final List<String> names = <String>[];
  for (int index = 1; index <= count; index++) {
    final String base =
        '$prefix$simiuSetMarker${index.toString().padLeft(3, '0')}';
    String candidate = base;
    int suffix = 1;
    while (used.contains(candidate.toLowerCase()) ||
        existing.contains(candidate.toLowerCase())) {
      candidate = '${base}_${suffix.toString().padLeft(2, '0')}';
      suffix++;
    }
    used.add(candidate.toLowerCase());
    names.add(candidate);
  }
  return names;
}

String _freePath(String path, Set<String> claimed) {
  final int slash = _lastSeparator(path);
  final int dot = path.lastIndexOf('.');
  final String stem = dot > slash ? path.substring(0, dot) : path;
  final String extension = dot > slash ? path.substring(dot) : '';
  String candidate = path;
  int index = 1;
  while (claimed.contains(candidate.toLowerCase())) {
    candidate = '${stem}_${index.toString().padLeft(2, '0')}$extension';
    index++;
  }
  claimed.add(candidate.toLowerCase());
  return candidate;
}

String? _rootOf(String directory, List<String> roots, bool recursive) {
  final String candidate = _normalizedDirectory(directory);
  String? best;
  for (final String root in roots) {
    final String key = _normalizedDirectory(root);
    if (candidate != key && !candidate.startsWith('$key/')) {
      continue;
    }
    if (!recursive && candidate != key) {
      // Without recursion the reference lists only the roots themselves, so a subfolder's images
      // are not candidates for a set.
      continue;
    }
    if (best == null || key.length > _normalizedDirectory(best).length) {
      best = root;
    }
  }
  return best;
}

String _join(String parent, String segment) {
  final String separator = parent.contains(r'\') ? r'\' : '/';
  return parent.endsWith(separator)
      ? '$parent$segment'
      : '$parent$separator$segment';
}

String _baseName(String path) {
  final int index = _lastSeparator(path);
  return index < 0 ? path : path.substring(index + 1);
}

int _lastSeparator(String path) {
  final int slash = path.lastIndexOf('/');
  final int backslash = path.lastIndexOf(r'\');
  return slash > backslash ? slash : backslash;
}

int _depth(String path) =>
    _normalizedDirectory(path)
        .split('/')
        .where((String part) => part.isNotEmpty)
        .length;

String _normalizedDirectory(String path) =>
    path.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();

String _normalizedFile(String path) => path.replaceAll(r'\', '/');
