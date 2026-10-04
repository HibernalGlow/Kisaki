part of 'board_controller.dart';

/// The include, reference, exclude and extension lists the scan is built from.
///
/// They share one add, remove and clear triple, so the panel only ever calls a list-named verb and
/// the de-duplication cannot be forgotten in one of them.
extension BoardSourceLists on BoardController {
  void addIncluded(Iterable<String> paths) => _addInto(_included, paths);

  void addReference(Iterable<String> paths) => _addInto(_reference, paths);

  void addExcludedPath(Iterable<String> paths) =>
      _addInto(_excludedPaths, paths);

  void addExcludedItem(Iterable<String> patterns) =>
      _addInto(_excludedItems, patterns);

  void addAllowedExtension(Iterable<String> extensions) =>
      _addInto(_allowedExtensions, extensions);

  void addExcludedExtension(Iterable<String> extensions) =>
      _addInto(_excludedExtensions, extensions);

  void _addInto(List<String> target, Iterable<String> values) {
    final Iterable<String> fresh = values
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty);
    if (fresh.isEmpty) {
      return;
    }
    for (final String value in fresh) {
      if (!target.contains(value)) {
        target.add(value);
      }
    }
    publish();
  }

  void removeIncluded(int index) {
    if (index < 0 || index >= _included.length) {
      return;
    }
    _reference.remove(_included.removeAt(index));
    publish();
  }

  void removeReference(int index) => _removeAt(_reference, index);

  void removeExcludedPath(int index) => _removeAt(_excludedPaths, index);

  void removeExcludedItem(int index) => _removeAt(_excludedItems, index);

  void removeAllowedExtension(int index) =>
      _removeAt(_allowedExtensions, index);

  void removeExcludedExtension(int index) =>
      _removeAt(_excludedExtensions, index);

  void _removeAt(List<String> target, int index) {
    if (index < 0 || index >= target.length) {
      return;
    }
    target.removeAt(index);
    publish();
  }

  void clearIncluded() {
    if (_included.isEmpty && _reference.isEmpty) {
      return;
    }
    _included.clear();
    _reference.clear();
    publish();
  }

  void clearReference() => _clearList(_reference);

  bool isIncludedReference(String path) => _reference.contains(path);

  bool get everyIncludedIsReference =>
      _included.isNotEmpty && _included.every(isIncludedReference);

  void toggleIncludedReference(String path) {
    if (!_included.contains(path)) {
      return;
    }
    if (_reference.contains(path)) {
      _reference.remove(path);
    } else {
      _reference.add(path);
    }
    publish();
  }

  /// "Set all as reference" and its inverse, straight off the paths list header.
  void setAllIncludedReferences(bool on) {
    _reference
      ..clear()
      ..addAll(on ? _included : const <String>[]);
    publish();
  }

  void clearExcludedPaths() => _clearList(_excludedPaths);

  void clearExcludedItems() => _clearList(_excludedItems);

  void clearAllowedExtensions() => _clearList(_allowedExtensions);

  void clearExcludedExtensions() => _clearList(_excludedExtensions);

  void _clearList(List<String> target) {
    if (target.isEmpty) {
      return;
    }
    target.clear();
    publish();
  }
}
