import 'dart:convert';
import 'dart:math';

import '../engine/models.dart';

/// Dart port of `packages/nodes/czkawka/src/scan-presets.ts`.
///
/// A preset is a whole scan configuration - the tool, every path list, the shared options and the
/// tool's own fields - so it can be saved, handed to someone else as text, and loaded back without
/// anyone touching a settings file. The document keeps the reference's rules but its own schema id,
/// because the payload shape is Kisaki's: a wrong schema id here would claim a compatibility that
/// does not exist.
class ScanPreset {
  const ScanPreset({
    required this.id,
    required this.name,
    required this.tool,
    required this.options,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String tool;
  final ScanOptions options;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'id': id,
    'name': name,
    'tool': tool,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'input': options.toJson(),
  };
}

/// The option block of a scan: what the source lane holds, minus the rows and the selection.
class ScanOptions {
  const ScanOptions({
    this.included = const <String>[],
    this.reference = const <String>[],
    this.excludedPaths = const <String>[],
    this.excludedItems = const <String>[],
    this.allowedExtensions = const <String>[],
    this.excludedExtensions = const <String>[],
    this.recursive = true,
    this.useCache = true,
    this.minSizeKib = '',
    this.maxSizeKib = '',
    this.fields = const <String, FieldPayload>{},
  });

  final List<String> included;
  final List<String> reference;
  final List<String> excludedPaths;
  final List<String> excludedItems;
  final List<String> allowedExtensions;
  final List<String> excludedExtensions;
  final bool recursive;
  final bool useCache;
  final String minSizeKib;
  final String maxSizeKib;
  final Map<String, FieldPayload> fields;

  Map<String, Object?> toJson() => <String, Object?>{
    'includedDirectories': included,
    'includedDirectoriesReferenced': reference,
    'excludedDirectories': excludedPaths,
    'excludedItems': excludedItems,
    'allowedExtensions': allowedExtensions,
    'excludedExtensions': excludedExtensions,
    'recursive': recursive,
    'useCache': useCache,
    'minimumFileSize': minSizeKib,
    'maximumFileSize': maxSizeKib,
    'fields': fields.map(
      (String id, FieldPayload payload) =>
          MapEntry<String, Object?>(id, _encodePayload(payload)),
    ),
  };

  static ScanOptions fromJson(Map<String, Object?> json) {
    final Object? rawFields = json['fields'];
    return ScanOptions(
      included: _strings(json['includedDirectories']),
      reference: _strings(json['includedDirectoriesReferenced']),
      excludedPaths: _strings(json['excludedDirectories']),
      excludedItems: _strings(json['excludedItems']),
      allowedExtensions: _strings(json['allowedExtensions']),
      excludedExtensions: _strings(json['excludedExtensions']),
      recursive: json['recursive'] is bool ? json['recursive']! as bool : true,
      useCache: json['useCache'] is bool ? json['useCache']! as bool : true,
      minSizeKib: json['minimumFileSize'] is String
          ? json['minimumFileSize']! as String
          : '',
      maxSizeKib: json['maximumFileSize'] is String
          ? json['maximumFileSize']! as String
          : '',
      fields: rawFields is Map
          ? rawFields.map((Object? key, Object? value) {
              return MapEntry<String, FieldPayload>(
                '$key',
                _decodePayload(value),
              );
            })
          : const <String, FieldPayload>{},
    );
  }
}

/// The saved presets after adding or updating one, plus the preset that was written.
class ScanPresetSave {
  const ScanPresetSave({required this.presets, required this.preset});

  final List<ScanPreset> presets;
  final ScanPreset preset;
}

/// Upsert by [id]; without one a new id is minted. A blank name is refused the same way the
/// reference refuses it, because a preset nobody can name is a preset nobody can pick.
ScanPresetSave saveScanPreset(
  List<ScanPreset> presets, {
  required String name,
  required String tool,
  required ScanOptions options,
  String? id,
  int? now,
  String Function()? createId,
}) {
  final String trimmed = name.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Preset name is required.');
  }
  final int stamp = now ?? DateTime.now().millisecondsSinceEpoch;
  final ScanPreset? existing = id == null
      ? null
      : presets.where((ScanPreset preset) => preset.id == id).firstOrNull;
  final ScanPreset preset = ScanPreset(
    id: existing?.id ?? createId?.call() ?? _createId(stamp),
    name: trimmed,
    tool: tool,
    options: options,
    createdAt: existing?.createdAt ?? stamp,
    updatedAt: stamp,
  );
  final List<ScanPreset> next = existing == null
      ? <ScanPreset>[...presets, preset]
      : presets
            .map((ScanPreset item) => item.id == existing.id ? preset : item)
            .toList();
  return ScanPresetSave(presets: next, preset: preset);
}

List<ScanPreset> deleteScanPreset(List<ScanPreset> presets, String id) =>
    presets.where((ScanPreset preset) => preset.id != id).toList();

String exportScanPresets(List<ScanPreset> presets) {
  final String document = const JsonEncoder.withIndent('  ')
      .convert(<String, Object?>{
        'schema': scanPresetSchema,
        'version': 1,
        'presets': presets.map((ScanPreset preset) => preset.toJson()).toList(),
      });
  return '$document\n';
}

/// Reads a preset document back in. The size cap and the schema check come from the reference: a
/// pasted blob is untrusted input, and a file from another tool must fail loudly rather than import
/// nothing while saying it worked.
List<ScanPreset> importScanPresets(
  String text, {
  List<ScanPreset> existing = const <ScanPreset>[],
  bool replace = false,
}) {
  if (text.length > 1000000) {
    throw const FormatException('Preset document is too large.');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('Unsupported Kisaki preset document.');
  }
  if (decoded is! Map<String, Object?> ||
      decoded['schema'] != scanPresetSchema ||
      decoded['version'] != 1 ||
      decoded['presets'] is! List<Object?>) {
    throw const FormatException('Unsupported Kisaki preset document.');
  }
  final List<ScanPreset> imported = (decoded['presets']! as List<Object?>)
      .map(validateScanPreset)
      .toList();
  if (replace) {
    return imported;
  }
  final Map<String, ScanPreset> merged = <String, ScanPreset>{
    for (final ScanPreset preset in existing) preset.id: preset,
  };
  for (final ScanPreset preset in imported) {
    merged[preset.id] = preset;
  }
  return merged.values.toList();
}

ScanPreset validateScanPreset(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid preset.');
  }
  final String id = (value['id'] as String? ?? '').trim();
  final String name = (value['name'] as String? ?? '').trim();
  final Object? input = value['input'];
  if (value['version'] != 1 ||
      id.isEmpty ||
      name.isEmpty ||
      value['createdAt'] is! int ||
      value['updatedAt'] is! int ||
      input is! Map<String, Object?>) {
    throw const FormatException('Invalid preset.');
  }
  return ScanPreset(
    id: id,
    name: name,
    tool: value['tool'] as String? ?? '',
    options: ScanOptions.fromJson(input),
    createdAt: value['createdAt']! as int,
    updatedAt: value['updatedAt']! as int,
  );
}

const String scanPresetSchema = 'kisaki.scan-presets';

List<String> _strings(Object? value) => value is List<Object?>
    ? value.map((Object? item) => '$item').toList()
    : const <String>[];

Object? _encodePayload(FieldPayload payload) => switch (payload) {
  FieldPayloadFlag() => <String, Object?>{'k': 'flag', 'v': payload.value},
  FieldPayloadChoice() => <String, Object?>{'k': 'choice', 'v': payload.value},
  FieldPayloadInteger() => <String, Object?>{
    'k': 'integer',
    'v': payload.value,
  },
  FieldPayloadTokens() => <String, Object?>{'k': 'tokens', 'v': payload.value},
  FieldPayloadText() => <String, Object?>{'k': 'text', 'v': payload.value},
};

FieldPayload _decodePayload(Object? value) {
  if (value is! Map) {
    return const FieldPayloadText('');
  }
  return switch ('${value['k']}') {
    'flag' => FieldPayloadFlag(
      value['v'] is bool ? value['v']! as bool : false,
    ),
    'choice' => FieldPayloadChoice('${value['v'] ?? ''}'),
    'integer' => FieldPayloadInteger(
      value['v'] is int ? value['v']! as int : 0,
    ),
    'tokens' => FieldPayloadTokens(_strings(value['v'])),
    _ => FieldPayloadText('${value['v'] ?? ''}'),
  };
}

String _createId(int stamp) =>
    'preset-$stamp-${_random.nextInt(1 << 32).toRadixString(36)}';

final Random _random = Random.secure();
