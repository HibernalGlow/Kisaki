part of 'board_controller.dart';

/// Named scan configurations the reader can save, hand around as text and load back.
///
/// A preset covers the option block and the current tool, never the rows or the selection: it answers
/// "scan the way I scanned last time", and applying it must not pretend to restore results.
extension BoardScanPresets on BoardController {
  List<ScanPreset> get scanPresets =>
      List<ScanPreset>.unmodifiable(_scanPresets);

  /// The option block exactly as the source lane holds it now.
  ScanOptions currentScanOptions() => ScanOptions(
    included: List<String>.of(_included),
    reference: List<String>.of(_reference),
    excludedPaths: List<String>.of(_excludedPaths),
    excludedItems: List<String>.of(_excludedItems),
    allowedExtensions: List<String>.of(_allowedExtensions),
    excludedExtensions: List<String>.of(_excludedExtensions),
    recursive: recursive,
    useCache: useCache,
    minSizeKib: minSizeKib,
    maxSizeKib: maxSizeKib,
    fields: Map<String, FieldPayload>.of(
      _values.map(
        (String id, FieldValue value) =>
            MapEntry<String, FieldPayload>(id, value.value),
      ),
    ),
  );

  /// Upserts under the current tool; the id is what makes a second save an update, not a copy.
  void savePreset(String name, {String? id}) {
    final String tool = _tool?.id ?? '';
    if (name.trim().isEmpty || tool.isEmpty) {
      _setStatus('preset-name-needed');
      publish();
      return;
    }
    final String wanted = name.trim();
    final String? byName = _scanPresets
        .where((ScanPreset item) => item.name == wanted)
        .map((ScanPreset item) => item.id)
        .firstOrNull;
    final ScanPresetSave saved = saveScanPreset(
      _scanPresets,
      name: name,
      tool: tool,
      options: currentScanOptions(),
      id: id ?? byName,
    );
    _scanPresets
      ..clear()
      ..addAll(saved.presets);
    _setStatus(
      'preset-saved',
      args: <String, Object>{'name': saved.preset.name},
    );
    publish();
  }

  void deletePreset(String id) {
    final List<ScanPreset> next = deleteScanPreset(_scanPresets, id);
    if (next.length == _scanPresets.length) {
      return;
    }
    _scanPresets
      ..clear()
      ..addAll(next);
    publish();
  }

  /// Applies a preset: its tool, then its option block, then only the fields that tool declares, so
  /// a picture preset cannot leave a music field behind.
  void applyPreset(String id) {
    final ScanPreset? preset = _scanPresets
        .where((ScanPreset item) => item.id == id)
        .firstOrNull;
    if (preset == null) {
      _setStatus('preset-none');
      publish();
      return;
    }
    selectTool(preset.tool);
    final ScanOptions options = preset.options;
    _replaceAll(_included, options.included);
    _replaceAll(_reference, options.reference);
    _replaceAll(_excludedPaths, options.excludedPaths);
    _replaceAll(_excludedItems, options.excludedItems);
    _replaceAll(_allowedExtensions, options.allowedExtensions);
    _replaceAll(_excludedExtensions, options.excludedExtensions);
    recursive = options.recursive;
    useCache = options.useCache;
    minSizeKib = options.minSizeKib;
    maxSizeKib = options.maxSizeKib;
    for (final FieldDef def in _fields) {
      final FieldPayload? payload = options.fields[def.id];
      if (payload != null) {
        _values[def.id] = FieldValue(id: def.id, value: payload);
      }
    }
    _setStatus('preset-applied', args: <String, Object>{'name': preset.name});
    publish();
  }

  String exportPresetText() => exportScanPresets(_scanPresets);

  /// Copies the whole document. The status line names the preset count instead of echoing every
  /// byte of JSON through [copyText], whose wording is built for a single path.
  Future<void> copyPresetText() async {
    await Clipboard.setData(ClipboardData(text: exportPresetText()));
    _setStatus(
      'preset-copied',
      args: <String, Object>{'count': _scanPresets.length},
    );
    publish();
  }

  /// Loads pasted or picked text in. A refused document is reported, never half applied.
  void importPresetText(String text, {bool replace = false}) {
    try {
      final List<ScanPreset> next = importScanPresets(
        text,
        existing: _scanPresets,
        replace: replace,
      );
      _scanPresets
        ..clear()
        ..addAll(next);
      _setStatus(
        'preset-imported',
        args: <String, Object>{'count': next.length},
      );
      publish();
    } on FormatException catch (error) {
      _setStatus(
        'preset-import-failed',
        args: <String, Object>{'error': error.message},
      );
      publish();
    }
  }

  void _replaceAll(List<String> target, List<String> values) {
    target
      ..clear()
      ..addAll(values);
  }
}
