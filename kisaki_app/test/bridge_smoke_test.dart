import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/kisaki_engine.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/util/rust_lib.dart';

/// Drives the real Rust library, so it is an integration test and needs the dylib built by
/// `cargo build -p kisaki_bridge`.
void main() {
  // flutter_rust_bridge refuses a second init in the same isolate, so the engine is opened once
  // for the whole file.
  late final KisakiEngine engine;
  setUpAll(() async {
    engine = await KisakiRustLib.init();
  });

  test('bridge scans a temp tree and reports duplicate groups', () async {
    final info = engine.engineInfo();
    expect(info.coreVersion, isNotEmpty);
    expect(
      engine.listTools().map((tool) => tool.id),
      contains('duplicate_files'),
    );

    final root = await Directory.systemTemp.createTemp('kisaki_bridge_');
    // The engine hands back canonicalized absolute paths, which on macOS resolves the
    // /var -> /private/var symlink; selection and deletion key on that spelling.
    final canonicalRoot = await root.resolveSymbolicLinks();
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'a/dup.txt', 'x' * 4096);
    await _write(root, 'b/dup.txt', 'x' * 4096);
    await _write(root, 'b/unique.txt', 'y' * 4096);

    final request = ScanRequest(
      tool: 'duplicate_files',
      included: [root.path],
      reference: const [],
      excludedPaths: const [],
      excludedItems: const [],
      allowedExtensions: const [],
      excludedExtensions: const [],
      recursive: true,
      useCache: false,
      minSizeKib: '',
      maxSizeKib: '',
      fields: engine.defaultFields('duplicate_files'),
    );

    final events = await engine.startScan(request).toList();
    final outcomes = events.whereType<ScanEventCompleted>().toList();
    expect(
      outcomes,
      hasLength(1),
      reason: 'exactly one terminal event, got: $events',
    );
    final outcome = outcomes.single.outcome;

    expect(outcome.critical, isNull, reason: outcome.messages);
    expect(outcome.grouped, isTrue);
    expect(outcome.fileCount, 2);
    expect(outcome.groupCount, 1);
    expect(
      outcome.reclaimableBytes,
      4096,
      reason: 'one copy of the pair is spare',
    );
    expect(outcome.rows.map((row) => row.path).toSet(), {
      '$canonicalRoot/a/dup.txt',
      '$canonicalRoot/b/dup.txt',
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'the video scanner publishes every engine option with a default',
    () async {
      final defs = engine.fieldDefs('similar_videos');
      final defaults = engine.defaultFields('similar_videos');
      expect(
        defs.map((def) => def.id),
        hasLength(19),
        reason: 'all SimilarVideosParameters args',
      );
      expect(
        defaults.map((field) => field.id).toSet(),
        defs.map((def) => def.id).toSet(),
      );

      // Fractions travel as text because the FFI integer payload would truncate them.
      final tolerance = defs.firstWhere(
        (def) => def.id == 'vid_min_matching_windows',
      );
      expect(tolerance.kind, FieldKind.text);
      final toleranceDefault = defaults
          .firstWhere((field) => field.id == 'vid_min_matching_windows')
          .value;
      expect((toleranceDefault as FieldPayloadText).value, '0.6');

      final crop = engine
          .fieldDefs('video_optimizer')
          .firstWhere((def) => def.id == 'vid_opt_crop_mechanism');
      expect(crop.kind, FieldKind.choice);
      expect(crop.options, ['BlackBars', 'StaticContent']);
    },
  );

  test(
    'every option the bridge publishes has a label the board can show',
    () async {
      for (final tool in engine.listTools()) {
        for (final def in engine.fieldDefs(tool.id)) {
          expect(
            Labels.knows(def.labelKey),
            isTrue,
            reason: '${tool.id}/${def.id}: ${def.labelKey} missing from Labels',
          );
        }
      }
    },
  );
}

Future<File> _write(Directory root, String relative, String content) async {
  final file = File('${root.path}/$relative');
  await file.create(recursive: true);
  await file.writeAsString(content);
  return file;
}
