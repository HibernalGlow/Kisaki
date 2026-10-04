import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/scan_presets.dart';
import 'package:kisaki_app/ui/board.dart';

import 'support/stub_engine.dart';

/// A preset has to carry the whole option block back - the paths, the shared options and the tool's
/// own fields - and a document that is not ours has to be refused without touching what is loaded.
void main() {
  late StubEngine engine;
  late BoardController controller;

  setUp(() {
    engine = StubEngine();
    controller = BoardController(engine: engine);
  });

  Future<void> pumpBoard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    controller.addIncluded(<String>['/data']);
    controller.setMinSize('10');
    controller.setFieldValue(
      'dup_hash_type',
      const FieldPayloadChoice('option_check_method_name'),
    );
    await tester.pumpWidget(KisakiBoardApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Labels.of('tab-algorithm')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('scan-presets')));
    await tester.pumpAndSettle();
  }

  /// The card is taller than the lane's visible part, so each control is scrolled to before a tap.
  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  /// The caret handle a focused field anchors below itself has a hit pad that covers the row under
  /// it, so the field is blurred before a button there is pressed.
  Future<void> typeInto(WidgetTester tester, Key key, String text) async {
    await tester.enterText(find.byKey(key), text);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> saveNamed(WidgetTester tester, String name) async {
    await typeInto(tester, const Key('preset-name-field'), name);
    await tapKey(tester, const Key('preset-save'));
  }

  group('controller rules', () {
    test(
      'a saved preset trims its name and a second save updates it',
      () async {
        controller.addIncluded(<String>['/data']);
        controller.savePreset('  Daily  ');

        expect(controller.scanPresets, hasLength(1));
        expect(controller.scanPresets.single.name, 'Daily');
        expect(controller.statusText, 'Saved Daily.');
        final int created = controller.scanPresets.single.createdAt;

        controller.setMinSize('99');
        controller.savePreset('Daily');

        expect(controller.scanPresets, hasLength(1));
        expect(controller.scanPresets.single.createdAt, created);
        expect(
          controller.scanPresets.single.options.minSizeKib,
          '99',
          reason: 'an update carries the options as they are now',
        );
      },
    );

    test('a nameless save is refused and nothing is written', () {
      controller.savePreset('   ');
      expect(controller.scanPresets, isEmpty);
      expect(controller.statusText, 'Give the preset a name before saving it.');
    });

    test(
      'applying brings back the paths, the options and the fields',
      () async {
        controller
          ..addIncluded(<String>['/data'])
          ..addExcludedItem(<String>['*/.git/*'])
          ..setMinSize('10')
          ..setMaxSize('4096')
          ..setUseCache(false)
          ..setFieldValue(
            'dup_hash_type',
            const FieldPayloadChoice('option_check_method_name'),
          );
        controller.savePreset('Daily');
        final ScanPreset saved = controller.scanPresets.single;

        controller
          ..addIncluded(<String>['/other'])
          ..clearExcludedItems()
          ..setMinSize('')
          ..setMaxSize('')
          ..setUseCache(true)
          ..setFieldValue(
            'dup_hash_type',
            const FieldPayloadChoice('option_check_method_hash'),
          );
        controller.applyPreset(saved.id);

        expect(controller.included, <String>['/data']);
        expect(controller.excludedItems, <String>['*/.git/*']);
        expect(controller.minSizeKib, '10');
        expect(controller.maxSizeKib, '4096');
        expect(controller.useCache, isFalse);
        expect(
          controller.valueOf('dup_hash_type').value,
          const FieldPayloadChoice('option_check_method_name'),
        );
        expect(controller.statusText, 'Preset Daily applied.');
      },
    );

    test('applying a preset for another tool switches to it', () {
      controller.addIncluded(<String>['/data']);
      controller.savePreset('Big');
      final String id = controller.scanPresets.single.id;

      controller.selectTool('big_files');
      expect(controller.tool?.id, 'big_files');
      controller.applyPreset(id);

      expect(controller.tool?.id, 'duplicate_files');
      expect(
        controller.fields.map((FieldDef def) => def.id),
        contains('dup_hash_type'),
      );
    });

    test('an id that is gone is reported, not applied', () {
      controller.addIncluded(<String>['/data']);
      controller.applyPreset('missing');
      expect(controller.statusText, 'That preset is no longer listed.');
    });

    test('deleting leaves the others', () {
      controller
        ..addIncluded(<String>['/data'])
        ..savePreset('One')
        ..savePreset('Two')
        ..savePreset('Three');

      controller.deletePreset(controller.scanPresets[1].id);

      expect(
        controller.scanPresets.map((ScanPreset item) => item.name),
        <String>['One', 'Three'],
      );
    });

    test('the document round-trips into a fresh board', () {
      controller
        ..addIncluded(<String>['/data'])
        ..addReference(<String>['/ref'])
        ..setMinSize('10')
        ..savePreset('Daily');

      final BoardController second = BoardController(engine: StubEngine());
      second.importPresetText(controller.exportPresetText());

      expect(second.scanPresets, hasLength(1));
      second.applyPreset(second.scanPresets.single.id);
      expect(second.included, <String>['/data']);
      expect(second.reference, <String>['/ref']);
      expect(second.minSizeKib, '10');
    });

    test('a refused document leaves the loaded presets alone', () {
      controller
        ..addIncluded(<String>['/data'])
        ..savePreset('Mine');

      controller.importPresetText('{"schema":"someone.else","version":1}');

      expect(controller.scanPresets, hasLength(1));
      expect(controller.statusText, contains('refused'));
      expect(
        controller.statusText,
        contains('Unsupported Kisaki preset document.'),
      );
    });
  });

  group('the card', () {
    testWidgets('saving a preset from the card lists it and clears the name', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      await saveNamed(tester, 'Weekend');

      expect(controller.scanPresets, hasLength(1));
      expect(
        find.descendant(
          of: find.byKey(const Key('scan-presets')),
          matching: find.text('Weekend'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('preset-name-field')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        isEmpty,
        reason: 'the name field is spent once the preset exists',
      );
    });

    testWidgets('applying from the card puts a changed option back', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      await saveNamed(tester, 'Daily');
      final String id = controller.scanPresets.single.id;

      controller.setMinSize('77');
      await tester.pumpAndSettle();
      await tapKey(tester, Key('preset-apply-$id'));

      expect(controller.minSizeKib, '10');
    });

    testWidgets('deleting the last preset tells the reader there are none', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      await saveNamed(tester, 'Daily');
      final String id = controller.scanPresets.single.id;

      await tapKey(tester, Key('preset-delete-$id'));

      expect(controller.scanPresets, isEmpty);
      expect(find.byKey(const Key('preset-empty')), findsOneWidget);
      expect(find.byKey(Key('preset-apply-$id')), findsNothing);
    });

    testWidgets(
      'export copies the document and says how many, not every byte',
      (WidgetTester tester) async {
        final List<String> copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add(
                (call.arguments as Map<Object?, Object?>)['text']! as String,
              );
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await pumpBoard(tester);
        await saveNamed(tester, 'Daily');
        await tester.ensureVisible(find.byKey(const Key('preset-export')));
        await tapKey(tester, const Key('preset-export'));

        expect(copied, <String>[controller.exportPresetText()]);
        expect(copied.single, contains('"kisaki.scan-presets"'));
        expect(
          controller.statusText,
          'Copied 1 presets to the clipboard.',
          reason: 'the status line must not echo a whole document',
        );
      },
    );

    testWidgets(
      'import loads a document and refuses junk without losing the list',
      (WidgetTester tester) async {
        await pumpBoard(tester);
        await saveNamed(tester, 'Mine');
        final String document = exportScanPresets(<ScanPreset>[
          saveScanPreset(
            <ScanPreset>[],
            name: 'Theirs',
            tool: 'big_files',
            options: const ScanOptions(included: <String>['/share']),
            now: 5,
          ).preset,
        ]);

        await tapKey(tester, const Key('preset-import'));
        expect(find.byKey(const Key('preset-import-dialog')), findsOneWidget);

        await typeInto(
          tester,
          const Key('preset-import-field'),
          'complete nonsense',
        );
        await tapKey(tester, const Key('preset-import-confirm'));

        expect(controller.scanPresets.map((ScanPreset p) => p.name), <String>[
          'Mine',
        ]);
        expect(controller.statusText, contains('refused'));

        await tapKey(tester, const Key('preset-import'));
        await typeInto(tester, const Key('preset-import-field'), document);
        await tapKey(tester, const Key('preset-import-confirm'));

        expect(controller.scanPresets.map((ScanPreset p) => p.name), <String>[
          'Mine',
          'Theirs',
        ]);
        expect(controller.statusText, 'Loaded 2 presets.');
      },
    );

    testWidgets('every label the card paints is authored', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      await saveNamed(tester, 'Daily');
      Labels.fallbackKeys.clear();
      await tester.ensureVisible(find.byKey(const Key('scan-presets')));
      await tester.pumpAndSettle();

      expect(Labels.fallbackKeys, isEmpty);
      Labels.of('preset-key-that-does-not-exist');
      expect(Labels.fallbackKeys, <String>['preset-key-that-does-not-exist']);
    });
  });
}
