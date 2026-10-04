import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/scan_presets.dart';

/// Ported rules from `scan-presets.ts`: a preset is a whole scan configuration, it round-trips
/// through text, and a document that is not ours is refused rather than half read.
void main() {
  ScanOptions options() => const ScanOptions(
    included: <String>['/data', '/more'],
    reference: <String>['/ref'],
    excludedPaths: <String>['/data/tmp'],
    excludedItems: <String>['*/.git/*'],
    allowedExtensions: <String>['jpg', 'png'],
    excludedExtensions: <String>['tmp'],
    recursive: false,
    useCache: false,
    minSizeKib: '10',
    maxSizeKib: '4096',
    fields: <String, FieldPayload>{
      'dup_use_prehash': FieldPayloadFlag(true),
      'dup_hash_type': FieldPayloadChoice('option_check_method_hash'),
      'dup_prehash_cache_size': FieldPayloadInteger(256),
      'mus_extensions': FieldPayloadTokens(<String>['mp3', 'flac']),
      'img_custom': FieldPayloadText('keep'),
    },
  );

  ScanPreset preset({
    String id = 'p1',
    String name = 'Daily',
    String tool = 'duplicate_files',
    int createdAt = 1000,
    int updatedAt = 2000,
  }) => ScanPreset(
    id: id,
    name: name,
    tool: tool,
    options: options(),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  group('saving', () {
    test('a blank name is refused before anything is written', () {
      expect(
        () => saveScanPreset(
          <ScanPreset>[],
          name: '   ',
          tool: 'duplicate_files',
          options: options(),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a new preset is appended with a minted id', () {
      final ScanPresetSave saved = saveScanPreset(
        <ScanPreset>[],
        name: ' Daily ',
        tool: 'duplicate_files',
        options: options(),
        now: 4242,
      );

      expect(saved.presets, hasLength(1));
      expect(saved.preset.name, 'Daily');
      expect(saved.preset.id, startsWith('preset-4242-'));
      expect(saved.preset.createdAt, 4242);
      expect(saved.preset.updatedAt, 4242);
    });

    test('saving over an id updates in place and keeps the creation time', () {
      final List<ScanPreset> before = <ScanPreset>[
        preset(id: 'a', name: 'First'),
        preset(id: 'b', name: 'Second'),
      ];

      final ScanPresetSave saved = saveScanPreset(
        before,
        name: 'First, revised',
        tool: 'big_files',
        options: options(),
        id: 'a',
        now: 9000,
      );

      expect(saved.preset.createdAt, 1000);
      expect(saved.preset.updatedAt, 9000);
      expect(saved.preset.tool, 'big_files');
      expect(saved.presets.map((ScanPreset item) => item.name), <String>[
        'First, revised',
        'Second',
      ], reason: 'the order the reader learned stays put');
    });

    test('an id that is not there mints a new preset instead of guessing', () {
      final ScanPresetSave saved = saveScanPreset(
        <ScanPreset>[preset(id: 'a')],
        name: 'Copied',
        tool: 'duplicate_files',
        options: options(),
        id: 'missing',
        now: 7,
      );

      expect(saved.presets, hasLength(2));
      expect(saved.preset.id, isNot('missing'));
    });

    test('deleting leaves the rest in order', () {
      final List<ScanPreset> kept = deleteScanPreset(<ScanPreset>[
        preset(id: 'a'),
        preset(id: 'b'),
        preset(id: 'c'),
      ], 'b');

      expect(kept.map((ScanPreset item) => item.id), <String>['a', 'c']);
    });
  });

  group('text transfer', () {
    test('a document comes back with every option and field value', () {
      final List<ScanPreset> presets = <ScanPreset>[preset()];

      final List<ScanPreset> read = importScanPresets(
        exportScanPresets(presets),
      );

      expect(read, hasLength(1));
      final ScanPreset back = read.single;
      expect(back.id, 'p1');
      expect(back.name, 'Daily');
      expect(back.tool, 'duplicate_files');
      expect(back.createdAt, 1000);
      expect(back.updatedAt, 2000);
      expect(back.options.included, <String>['/data', '/more']);
      expect(back.options.reference, <String>['/ref']);
      expect(back.options.excludedItems, <String>['*/.git/*']);
      expect(back.options.allowedExtensions, <String>['jpg', 'png']);
      expect(back.options.excludedExtensions, <String>['tmp']);
      expect(back.options.recursive, isFalse);
      expect(back.options.useCache, isFalse);
      expect(back.options.minSizeKib, '10');
      expect(back.options.maxSizeKib, '4096');
      expect(
        back.options.fields['dup_use_prehash'],
        const FieldPayloadFlag(true),
      );
      expect(
        back.options.fields['dup_hash_type'],
        const FieldPayloadChoice('option_check_method_hash'),
      );
      expect(
        back.options.fields['dup_prehash_cache_size'],
        const FieldPayloadInteger(256),
      );
      expect(
        back.options.fields['mus_extensions'],
        const FieldPayloadTokens(<String>['mp3', 'flac']),
      );
      expect(
        back.options.fields['mus_extensions'],
        isNot(const FieldPayloadTokens(<String>['mp3, flac'])),
        reason: 'a token list compares element by element, not by its text',
      );
      expect(back.options.fields['img_custom'], const FieldPayloadText('keep'));
    });

    test('the export is one document per line of readable json', () {
      final String text = exportScanPresets(<ScanPreset>[
        preset(),
        preset(id: 'p2'),
      ]);
      final Map<String, Object?> decoded =
          jsonDecode(text) as Map<String, Object?>;

      expect(text, endsWith('\n'));
      expect(decoded['schema'], 'kisaki.scan-presets');
      expect(decoded['version'], 1);
      expect(decoded['presets'], hasLength(2));
      expect(text, contains('\n  "presets"'));
    });

    test('merging keeps what was not mentioned and replaces the same id', () {
      final List<ScanPreset> existing = <ScanPreset>[
        preset(id: 'a', name: 'Mine'),
        preset(id: 'b', name: 'Also mine'),
      ];
      final String text = exportScanPresets(<ScanPreset>[
        preset(id: 'b', name: 'Theirs'),
        preset(id: 'c', name: 'New'),
      ]);

      final List<ScanPreset> merged = importScanPresets(
        text,
        existing: existing,
      );

      expect(
        merged.map((ScanPreset item) => '${item.id}:${item.name}'),
        <String>['a:Mine', 'b:Theirs', 'c:New'],
      );
    });

    test('replace mode returns exactly the document', () {
      final List<ScanPreset> replaced = importScanPresets(
        exportScanPresets(<ScanPreset>[preset(id: 'c')]),
        existing: <ScanPreset>[preset(id: 'a')],
        replace: true,
      );

      expect(replaced.map((ScanPreset item) => item.id), <String>['c']);
    });

    test('a document from another tool is refused, not half read', () {
      const String foreign =
          '{"schema":"xiranite.czkawka.scan-presets","version":1,"presets":[]}';

      expect(
        () => importScanPresets(foreign),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            'Unsupported Kisaki preset document.',
          ),
        ),
      );
    });

    test('junk, a wrong version and a missing list all fail the same way', () {
      expect(() => importScanPresets('not json at all'), throwsFormatException);
      expect(
        () => importScanPresets(
          '{"schema":"kisaki.scan-presets","version":2,"presets":[]}',
        ),
        throwsFormatException,
      );
      expect(
        () => importScanPresets('{"schema":"kisaki.scan-presets","version":1}'),
        throwsFormatException,
      );
    });

    test('a preset with a blank name or a borrowed shape is refused', () {
      final Map<String, Object?> good = preset().toJson();

      expect(
        () => validateScanPreset(<String, Object?>{}),
        throwsFormatException,
      );
      expect(
        () => validateScanPreset(<String, Object?>{...good, 'version': 2}),
        throwsFormatException,
      );
      expect(
        () => validateScanPreset(<String, Object?>{...good, 'name': '  '}),
        throwsFormatException,
      );
      expect(
        () =>
            validateScanPreset(<String, Object?>{...good, 'createdAt': '1000'}),
        throwsFormatException,
      );
      expect(
        () => validateScanPreset(<String, Object?>{...good, 'input': 'flat'}),
        throwsFormatException,
      );
    });

    test('the size cap refuses a blob no reader meant to paste', () {
      final String huge = 'x' * 1000001;

      expect(() => importScanPresets(huge), throwsFormatException);
    });

    test('an unknown field payload still comes back as text', () {
      final Map<String, Object?> document = preset().toJson();
      final Map<String, Object?> input = Map<String, Object?>.from(
        document['input']! as Map<String, Object?>,
      );
      input['fields'] = <String, Object?>{
        'weird': <String, Object?>{'k': 'mystery', 'v': 12},
        'broken': 'not a map',
      };
      input.remove('recursive');
      input.remove('useCache');

      final ScanOptions back = ScanOptions.fromJson(input);

      expect(back.fields['weird'], const FieldPayloadText('12'));
      expect(back.fields['broken'], const FieldPayloadText(''));
      expect(
        back.recursive,
        isTrue,
        reason:
            'a missing key keeps the default rather than turning scanning off',
      );
      expect(back.useCache, isTrue);
    });
  });
}
