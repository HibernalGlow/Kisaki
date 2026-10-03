import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/kisaki_engine.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/src/rust/api/actions.dart' as g_actions;
import 'package:kisaki_app/src/rust/api/types.dart' as g;
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

  test('an out-of-range video scan clamps instead of tripping the engine asserts', () async {
    final root = await Directory.systemTemp.createTemp('kisaki_videos_');
    addTearDown(() => root.delete(recursive: true));
    for (final name in <String>['a.mp4', 'b.mp4']) {
      // The engine samples from skip_forward for hash_duration seconds and needs audio when the
      // audio branch is on, so the clips carry 30 seconds of picture and tone.
      final encode = await Process.run('ffmpeg', <String>[
        '-y',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        'testsrc=size=320x240:rate=15:duration=30',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:duration=30',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-shortest',
        '${root.path}/$name',
      ]);
      expect(encode.stderr, isEmpty, reason: 'ffmpeg: ${encode.stderr}');
    }

    // Values past the ranges SimilarVideosParameters::new asserts on, plus the thumbnail and
    // audio branches that the defaults never reached.
    const overrides = <String, FieldPayload>{
      'vid_window_count': FieldPayloadInteger(999),
      'vid_min_matching_windows': FieldPayloadText('5'),
      'vid_skip_forward': FieldPayloadInteger(-5),
      'vid_generate_thumbnails': FieldPayloadFlag(true),
      'vid_check_audio_content': FieldPayloadFlag(true),
    };
    final fields = <FieldValue>[
      for (final field in engine.defaultFields('similar_videos'))
        FieldValue(id: field.id, value: overrides[field.id] ?? field.value),
    ];

    final events = await engine
        .startScan(
          ScanRequest(
            tool: 'similar_videos',
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
            fields: fields,
          ),
        )
        .toList();

    // A panic on the scan thread shows up as a Failed event or as no terminal event at all.
    expect(
      events.whereType<ScanEventFailed>().map((e) => e.error).toList(),
      isEmpty,
      reason: '$events',
    );
    final outcome = events.whereType<ScanEventCompleted>().single.outcome;
    expect(outcome.critical, isNull, reason: outcome.messages);
    // Positive control: the clips must really have been hashed, otherwise the clamp assertion
    // above would pass on an empty scan.
    expect(
      outcome.fileCount,
      greaterThanOrEqualTo(2),
      reason: 'two clips were written, messages: ${outcome.messages}',
    );
    expect(engine.isScanning(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('bad names honour the option flags', () async {
    final root = await Directory.systemTemp.createTemp('kisaki_names_');
    final canonicalRoot = await root.resolveSymbolicLinks();
    addTearDown(() => root.delete(recursive: true));
    await _write(root, ' leading.txt', 'a');
    await _write(root, 'emoji_😀.txt', 'a');
    await _write(root, 'plain.txt', 'a');

    Future<ScanOutcome> scanWith(Map<String, FieldPayload> overrides) async {
      final fields = <FieldValue>[
        for (final field in engine.defaultFields('bad_names'))
          FieldValue(id: field.id, value: overrides[field.id] ?? field.value),
      ];
      final events = await engine
          .startScan(
            ScanRequest(
              tool: 'bad_names',
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
              fields: fields,
            ),
          )
          .toList();
      final outcome = events.whereType<ScanEventCompleted>().single.outcome;
      return outcome;
    }

    // The defaults check every issue, so both offending names come back and plain.txt does not.
    final defaults = await scanWith(const {});
    expect(defaults.critical, isNull, reason: defaults.messages);
    expect(defaults.rows.map((row) => row.path).toSet(), {
      '$canonicalRoot/ leading.txt',
      '$canonicalRoot/emoji_😀.txt',
    }, reason: 'only the two bad names should be reported');
    expect(defaults.fileCount, 2);

    // Switching every check off has to change the result, otherwise the flags never reached
    // czkawka_core and the assertion above was reading a fixed scan. The engine refuses outright.
    const allOff = <String, FieldPayload>{
      'name_uppercase_extension': FieldPayloadFlag(false),
      'name_emoji_used': FieldPayloadFlag(false),
      'name_space_at_start_or_end': FieldPayloadFlag(false),
      'name_non_ascii_graphical': FieldPayloadFlag(false),
      'name_remove_duplicated_non_alphanumeric': FieldPayloadFlag(false),
      'name_allowed_charset': FieldPayloadText(''),
    };
    final disabled = await scanWith(allOff);
    expect(disabled.fileCount, 0);
    expect(disabled.rows, isEmpty);
    expect(
      disabled.critical,
      contains('no bad name option'),
      reason: 'core must report why the scan stopped: ${disabled.critical}',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  // The rename verb is reachable from Dart only through the generated API so far: the board's
  // KisakiEngine interface would need a new member, and every implementer of that interface lives
  // in the parallel lane. This drives the FFI directly to prove the shipped dylib really does it.
  test(
    'renaming through the bridge fixes the selected bad names only',
    () async {
      final root = await Directory.systemTemp.createTemp('kisaki_rename_');
      final canonicalRoot = await root.resolveSymbolicLinks();
      addTearDown(() => root.delete(recursive: true));
      await _write(root, ' leading.txt', 'a');
      await _write(root, 'emoji_😀.txt', 'a');
      await _write(root, 'plain.txt', 'a');

      final selected = await _badNamePaths(engine, root.path);
      expect(
        selected,
        hasLength(2),
        reason: 'the two bad names are the selection',
      );

      final dry = await g_actions.renameFiles(
        request: _rename('bad_names', root.path, selected, dryRun: true),
      );
      expect((dry.renamed, dry.planned, dry.failed), (0, 2, 0));
      expect(
        dry.items.map((item) => item.status),
        everyElement(g.RenameStatus.planned),
      );
      expect(
        File('$canonicalRoot/ leading.txt').existsSync(),
        isTrue,
        reason: 'a dry run must leave the file where it is',
      );

      final applied = await g_actions.renameFiles(
        request: _rename('bad_names', root.path, selected, dryRun: false),
      );
      expect(
        (applied.renamed, applied.failed),
        (2, 0),
        reason: applied.messages,
      );
      expect(File('$canonicalRoot/leading.txt').readAsStringSync(), 'a');
      expect(File('$canonicalRoot/emoji_.txt').readAsStringSync(), 'a');
      expect(
        File('$canonicalRoot/ leading.txt').existsSync(),
        isFalse,
        reason: 'the old spelling has to be gone',
      );

      // The untouched file proves the run was scoped to the selection, not to the whole scan.
      expect(File('$canonicalRoot/plain.txt').existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'the bridge renames a file whose extension contradicts its content',
    () async {
      final root = await Directory.systemTemp.createTemp('kisaki_bext_');
      final canonicalRoot = await root.resolveSymbolicLinks();
      addTearDown(() => root.delete(recursive: true));
      // A PNG signature inside a .jpg name: only the engine's own content check can say so.
      final file = File('${root.path}/photo.jpg');
      await file.writeAsBytes(<int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        0x00,
        0x00,
        0x00,
        0x0d,
      ]);

      final outcome = await g_actions.renameFiles(
        request: _rename('bad_extensions', root.path, [
          '$canonicalRoot/photo.jpg',
        ], dryRun: false),
      );

      expect(
        (outcome.renamed, outcome.failed),
        (1, 0),
        reason: '${outcome.items}',
      );
      expect(outcome.items.single.to, '$canonicalRoot/photo.png');
      expect(
        File('$canonicalRoot/photo.png').readAsBytesSync().sublist(0, 4),
        <int>[0x89, 0x50, 0x4e, 0x47],
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'the bridge cleans EXIF into a side file and leaves the original alone',
    () async {
      final fixture = File('../czkawka_core/test_resources/images/normal.jpg');
      expect(
        fixture.existsSync(),
        isTrue,
        reason: 'the engine EXIF fixture moved: ${fixture.absolute.path}',
      );
      final root = await Directory.systemTemp.createTemp('kisaki_exif_');
      addTearDown(() => root.delete(recursive: true));
      final photo = File('${root.path}/photo.jpg');
      await photo.writeAsBytes(await fixture.readAsBytes());
      final canonicalPhoto = await photo.resolveSymbolicLinks();
      final before = await photo.readAsBytes();

      final dry = await g_actions.cleanExif(
        request: _exif(canonicalPhoto, root.path, dryRun: true),
      );
      expect(
        (dry.planned, dry.stripped, dry.candidates, dry.failed),
        (1, 0, 0, 0),
        reason: '${dry.items}',
      );
      expect(dry.items.single.tagsRemoved, greaterThan(0));
      expect(
        File('${root.path}/photo.czkawka_cleaned_exif.jpg').existsSync(),
        isFalse,
        reason: 'a dry run writes nothing',
      );

      final cleaned = await g_actions.cleanExif(
        request: _exif(canonicalPhoto, root.path, dryRun: false),
      );
      expect(
        (cleaned.candidates, cleaned.failed),
        (1, 0),
        reason: '${cleaned.items}',
      );
      expect(
        cleaned.items.single.target,
        canonicalPhoto.replaceFirst('.jpg', '.czkawka_cleaned_exif.jpg'),
      );
      expect(
        File(canonicalPhoto).readAsBytesSync(),
        before,
        reason: 'the original keeps its metadata',
      );
      expect(
        File('${root.path}/photo.czkawka_cleaned_exif.jpg').existsSync(),
        isTrue,
        reason: 'the cleaned copy should be on disk',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'the bridge moves a selection and never overwrites by default',
    () async {
      final root = await Directory.systemTemp.createTemp('kisaki_move_');
      final canonicalRoot = await root.resolveSymbolicLinks();
      addTearDown(() => root.delete(recursive: true));
      final one = await _write(root, 'in/one.txt', '1');
      final two = await _write(root, 'in/two.txt', '2');
      final destination = await Directory('${root.path}/out').create();
      final canonicalDestination = await destination.resolveSymbolicLinks();
      // Occupy the name the second file would take, so the default policy has something to refuse.
      await File('$canonicalDestination/two.txt').writeAsString('already');

      final paths = [one.path, two.path];
      // The dry run reports the refusal too, so the plan says what would really happen: one file
      // moves and the colliding one is left where it is.
      final dry = await g_actions.moveFiles(
        request: _move(paths, canonicalDestination, dryRun: true),
      );
      expect(
        (dry.planned, dry.moved, dry.skipped, dry.failed),
        (1, 0, 1, 0),
        reason: '${dry.items}',
      );
      expect(dry.items[1].to, '$canonicalDestination/two.txt');
      expect(dry.items[1].detail, 'Target already exists');
      expect(
        destination
            .listSync()
            .whereType<File>()
            .map((file) => file.path.split('/').last)
            .toList()
          ..sort(),
        ['two.txt'],
        reason: 'a planned move must not write anything',
      );

      final moved = await g_actions.moveFiles(
        request: _move(paths, canonicalDestination, dryRun: false),
      );
      expect(
        (moved.moved, moved.skipped, moved.failed),
        (1, 1, 0),
        reason: moved.messages,
      );
      expect(File('$canonicalDestination/one.txt').readAsStringSync(), '1');
      expect(
        File('$canonicalDestination/two.txt').readAsStringSync(),
        'already',
        reason: 'the skip policy keeps the occupant',
      );
      expect(
        File('$canonicalRoot/in/two.txt').existsSync(),
        isTrue,
        reason: 'a refused file stays put',
      );
      expect(
        File('$canonicalRoot/in/one.txt').existsSync(),
        isFalse,
        reason: 'a move leaves nothing behind',
      );
      expect(moved.messages, contains('Completed 1 operation(s)'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'the bridge copies instead of moving and renames around a collision',
    () async {
      final root = await Directory.systemTemp.createTemp('kisaki_copy_');
      addTearDown(() => root.delete(recursive: true));
      final source = await _write(root, 'in/frame.png', 'image');
      final destination = await Directory('${root.path}/out').create();
      final canonicalDestination = await destination.resolveSymbolicLinks();
      await File('$canonicalDestination/frame.png').writeAsString('first');

      final copied = await g_actions.moveFiles(
        request: _move(
          [source.path],
          canonicalDestination,
          action: g.MoveAction.copy,
          conflict: g.ConflictPolicy.rename,
          dryRun: false,
        ),
      );

      expect(
        (copied.copied, copied.moved, copied.failed),
        (1, 0, 0),
        reason: '${copied.items}',
      );
      expect(copied.items.single.to, '$canonicalDestination/frame (1).png');
      expect(
        File(source.path).existsSync(),
        isTrue,
        reason: 'a copy leaves the original alone',
      );
      expect(
        File('$canonicalDestination/frame.png').readAsStringSync(),
        'first',
      );
      expect(
        File('$canonicalDestination/frame (1).png').readAsStringSync(),
        'image',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<List<String>> _badNamePaths(KisakiEngine engine, String rootPath) async {
  final events = await engine
      .startScan(
        ScanRequest(
          tool: 'bad_names',
          included: [rootPath],
          reference: const [],
          excludedPaths: const [],
          excludedItems: const [],
          allowedExtensions: const [],
          excludedExtensions: const [],
          recursive: true,
          useCache: false,
          minSizeKib: '',
          maxSizeKib: '',
          fields: engine.defaultFields('bad_names'),
        ),
      )
      .toList();
  final outcome = events.whereType<ScanEventCompleted>().single.outcome;
  expect(outcome.critical, isNull, reason: outcome.messages);
  return outcome.rows.map((row) => row.path).toList();
}

/// A rename request as the board would send it. The scan block carries no option fields, so the
/// engine works from its own defaults, and the paths keep the spelling the scan reported.
g.RenameRequest _rename(
  String tool,
  String rootPath,
  List<String> paths, {
  required bool dryRun,
}) {
  return g.RenameRequest(
    tool: tool,
    scan: g.ScanRequest(
      tool: tool,
      included: [rootPath],
      reference: const [],
      excludedPaths: const [],
      excludedItems: const [],
      allowedExtensions: const [],
      excludedExtensions: const [],
      recursive: true,
      useCache: false,
      minSizeKib: '',
      maxSizeKib: '',
      fields: const [],
    ),
    paths: paths,
    dryRun: dryRun,
  );
}

/// An EXIF request for one photo. The engine re-reads the tags itself, so the request only carries
/// the folder and the choice of writing a side file or replacing the original.
g.ExifRequest _exif(String photoPath, String rootPath, {required bool dryRun}) {
  return g.ExifRequest(
    scan: g.ScanRequest(
      tool: 'exif_remover',
      included: [rootPath],
      reference: const [],
      excludedPaths: const [],
      excludedItems: const [],
      allowedExtensions: const [],
      excludedExtensions: const [],
      recursive: true,
      useCache: false,
      minSizeKib: '',
      maxSizeKib: '',
      fields: const [],
    ),
    paths: [photoPath],
    overrideFile: false,
    dryRun: dryRun,
  );
}

/// A move request as the board would send it: the destination already uses the spelling the
/// filesystem reports, and the defaults are the reference frontend's - move, never overwrite.
g.MoveRequest _move(
  List<String> paths,
  String destination, {
  g.MoveAction action = g.MoveAction.move,
  g.ConflictPolicy conflict = g.ConflictPolicy.skip,
  required bool dryRun,
}) {
  return g.MoveRequest(
    paths: paths,
    destination: destination,
    action: action,
    conflict: conflict,
    preserveStructure: false,
    dryRun: dryRun,
  );
}

Future<File> _write(Directory root, String relative, String content) async {
  final file = File('${root.path}/$relative');
  await file.create(recursive: true);
  await file.writeAsString(content);
  return file;
}
