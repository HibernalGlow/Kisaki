import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/l10n/fluent_catalog.dart';
import 'package:kisaki_app/l10n/labels.dart';

/// The catalogue is only a translation source if the code and the file cannot drift apart, and a
/// loader is only real if a locale actually reaches the screen. Both halves are asserted here.
void main() {
  const String enPath = 'i18n/en/kisaki_app.ftl';

  setUp(() {
    Labels.fallbackKeys.clear();
    Labels.useCatalog(const <String, String>{});
    Labels.loadedLocaleCode = 'en';
  });

  tearDown(() {
    Labels.useCatalog(const <String, String>{});
    Labels.loadedLocaleCode = 'en';
  });

  test(
    'the English catalogue and the built-in table hold the same messages',
    () {
      final Map<String, String> catalog = parseFluentCatalog(
        File(enPath).readAsStringSync(),
        origin: enPath,
      );

      expect(
        catalog,
        isNotEmpty,
        reason: 'a gate that reads nothing must not look green',
      );
      expect(
        catalog.keys.toSet(),
        Labels.table.keys.toSet(),
        reason:
            'a key in one source and not the other cannot both be the truth',
      );
      for (final MapEntry<String, String> entry in catalog.entries) {
        expect(
          entry.value,
          Labels.table[entry.key],
          reason:
              'message ${entry.key} differs between $enPath and labels.dart',
        );
      }
    },
  );

  test('the shipped catalogues use no Fluent syntax the reader refuses', () {
    for (final Directory locale in Directory(
      'i18n',
    ).listSync().whereType<Directory>()) {
      final String path = '${locale.path}/kisaki_app.ftl';
      if (!File(path).existsSync()) {
        continue;
      }
      expect(
        parseFluentCatalog(File(path).readAsStringSync(), origin: path),
        isNotEmpty,
        reason: path,
      );
    }

    // Positive control: selectors and attributes must be rejected, not read as empty strings.
    expect(
      () =>
          parseFluentCatalog('a = { \$n -> *[other] x }\n', origin: 'fixture'),
      throwsFormatException,
    );
    expect(
      () => parseFluentCatalog('a.accesskey = A\n', origin: 'fixture'),
      throwsFormatException,
    );
    expect(
      () =>
          parseFluentCatalog('this line is not a message\n', origin: 'fixture'),
      throwsFormatException,
    );
  });

  test('comments and continued messages survive the round trip', () {
    final Map<String, String> parsed = parseFluentCatalog(
      '# comment\n'
      '## group comment\n'
      '\n'
      'one = First\n'
      'two =\n'
      '    continued\n'
      '    text\n'
      'three = Third { \$count }\n',
      origin: 'fixture',
    );

    expect(parsed.keys, <String>['one', 'two', 'three']);
    expect(parsed['one'], 'First');
    expect(parsed['two'], 'continued\ntext');
    expect(parsed['three'], 'Third { \$count }');
  });

  test('a loaded catalogue wins over the built-in English', () {
    Labels.useCatalog(<String, String>{'action-scan': '扫描'});
    expect(Labels.of('action-scan'), '扫描');
    // An untranslated key falls back to the table rather than showing a bare key.
    expect(Labels.of('action-stop'), 'Stop');
    expect(Labels.fallbackKeys, isEmpty);
  });

  test('placeholders accept both Fluent spellings', () {
    Labels.useCatalog(<String, String>{
      'spaced': '共 { \$count } 项',
      'tight': '共{\$count}项',
    });

    expect(Labels.of('spaced', args: <String, Object>{'count': 3}), '共 3 项');
    expect(Labels.of('tight', args: <String, Object>{'count': 3}), '共3项');
  });

  test('a key nobody authored is still recorded', () {
    expect(Labels.of('never-authored-key'), 'Never Authored Key');
    expect(Labels.fallbackKeys, <String>['never-authored-key']);
  });

  test('locale lookup walks the same ladder the engine uses', () {
    expect(Labels.localeCandidates('zh-CN'), <String>['zh-CN', 'zh', 'en']);
    // The workspace ships zh-CN and zh-TW but no bare zh, so a zh request must not reach English.
    expect(Labels.localeCandidates('zh'), <String>['zh', 'zh-CN', 'en']);
    expect(Labels.localeCandidates('de-AT'), <String>['de-AT', 'de', 'en']);
    expect(Labels.localeCandidates('  '), <String>['en']);
  });

  test('KISAKI_LANG overrides the platform locale', () {
    expect(
      Labels.resolveLocaleCode(<String, String>{
        'KISAKI_LANG': 'zh-CN',
      }, 'en-US'),
      'zh-CN',
    );
    expect(
      Labels.resolveLocaleCode(<String, String>{'KISAKI_LANG': '  '}, 'en-US'),
      'en-US',
    );
    expect(Labels.resolveLocaleCode(<String, String>{}, 'fr'), 'fr');
  });

  test('every catalogue on disk is declared as an asset', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final List<String> onDisk = Directory('i18n')
        .listSync()
        .whereType<Directory>()
        .where(
          (Directory dir) => File('${dir.path}/kisaki_app.ftl').existsSync(),
        )
        .map(
          (Directory dir) =>
              'i18n/${dir.path.split(Platform.pathSeparator).last}/',
        )
        .toList();

    expect(onDisk, containsAll(<String>['i18n/en/', 'i18n/zh-CN/']));
    for (final String entry in onDisk) {
      expect(
        pubspec,
        contains('- $entry'),
        reason:
            '$entry exists but pubspec.yaml does not bundle it, so the locale can never load',
      );
    }
  });

  testWidgets('the bundle itself serves a catalogue', (
    WidgetTester tester,
  ) async {
    // The tests above read files from disk; this one goes through rootBundle, which is the path the
    // packaged app takes. A locale directory missing from pubspec's asset list fails here, not only
    // in the static scan.
    expect(await Labels.load('zh-CN'), 'zh-CN');
    expect(Labels.of('lane-source'), '扫描条件');
    expect(Labels.of('action-delete'), '删除所选');
    expect(Labels.loadedLocale.toLanguageTag(), 'zh-CN');

    // A tag with no catalogue falls through to English rather than throwing.
    expect(await Labels.load('xx-ZZ'), 'en');
    expect(Labels.of('lane-source'), 'Scan conditions');
  });

  test('the shipped Chinese catalogue translates the board chrome', () {
    final Map<String, String> zh = parseFluentCatalog(
      File('i18n/zh-CN/kisaki_app.ftl').readAsStringSync(),
      origin: 'i18n/zh-CN/kisaki_app.ftl',
    );
    Labels.useCatalog(zh);

    expect(Labels.of('lane-source'), '扫描条件');
    expect(Labels.of('lane-results'), '结果');
    expect(Labels.of('metric-reclaimable'), '可释放');
    expect(Labels.of('action-delete'), '删除所选');
    expect(Labels.knows('lane-source'), isTrue);
  });
}
