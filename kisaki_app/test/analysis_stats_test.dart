import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/engine/models.dart';
import 'package:kisaki_app/state/analysis_stats.dart';

/// Ported rules from `packages/nodes/czkawka/src/analysis.test.ts`: formats grouped by bytes, the
/// engine's own level boundaries, and the same table the reader can open as a quick reference.
void main() {
  ScanRow row(
    String path,
    int bytes, {
    int difference = 0,
    bool reference = false,
  }) => ScanRow(
    path: path,
    name: path.split('/').last,
    directory: '',
    cells: <String>['$difference', '$bytes'],
    sizeBytes: bytes,
    modifiedTs: 0,
    groupIndex: 0,
    groupSize: 2,
    isGroupStart: false,
    isReference: reference,
    sortKeys: <int>[difference, bytes],
  );

  group('format statistics', () {
    test('groups by extension, heaviest first, and counts the rest', () {
      final List<FormatStat> stats = buildFormatStats(<ScanRow>[
        row('a.JPG', 30),
        row('b.jpg', 10),
        row('archive.zip', 60),
        row('README', 0),
      ]);

      expect(stats.map((FormatStat item) => item.format), <String>[
        'zip',
        'jpg',
        'unknown',
      ]);
      expect(stats[0].count, 1);
      expect(stats[0].bytes, 60);
      expect(stats[0].countPercent, 25);
      expect(stats[0].bytesPercent, 60);
      expect(stats[1].count, 2);
      expect(stats[1].bytes, 40);
      expect(stats[1].countPercent, 50);
      expect(stats[1].bytesPercent, 40);
    });

    test('reads the extension off the last segment of a windows path', () {
      expect(extensionOf(r'C:\Users\me\Pictures\A.PNG'), 'png');
      expect(extensionOf('/data/no-dot'), 'unknown');
      expect(extensionOf('/data/.hidden'), 'unknown');
      expect(extensionOf('/data/trailing.'), 'unknown');
      expect(extensionOf('photo.jpeg'), 'jpeg');
    });

    test('a folder scan has one bucket, because folders have no extension', () {
      final List<FormatStat> stats = buildFormatStats(<ScanRow>[
        row('/data/empty', 0),
        row(r'E:\gone', 0),
      ], tool: 'empty_folders');

      expect(stats.map((FormatStat item) => item.format), <String>['folder']);
      expect(stats.single.count, 2);
    });

    test('an empty result set yields no percentages to divide by', () {
      expect(buildFormatStats(<ScanRow>[]), isEmpty);
    });

    test('zero bytes still bucket their formats', () {
      final List<FormatStat> stats = buildFormatStats(<ScanRow>[
        row('a.txt', 0),
        row('b.md', 0),
      ]);

      expect(stats.map((FormatStat item) => item.format), <String>[
        'md',
        'txt',
      ]);
      expect(stats.every((FormatStat item) => item.bytesPercent == 0), isTrue);
      expect(stats.first.countPercent, 50);
    });
  });

  group('similarity statistics', () {
    test(
      'classifies differences with the hash-size thresholds the core uses',
      () {
        final List<SimilarityStat> stats = buildSimilarityStats(
          <ScanRow>[
            row('reference.jpg', 1, difference: 0, reference: true),
            row('same.jpg', 1, difference: 0),
            row('very-high.jpg', 1, difference: 2),
            row('high.jpg', 1, difference: 5),
            row('minimal.jpg', 1, difference: 99),
          ],
          hashSize: 16,
          differenceIndex: 0,
        );

        expect(
          stats
              .map(
                (SimilarityStat item) => <Object>[
                  item.level.wire,
                  item.count,
                  item.range,
                ],
              )
              .toList(),
          <List<Object>>[
            <Object>['original', 1, '= 0'],
            <Object>['very-high', 1, '\u2264 2'],
            <Object>['high', 1, '\u2264 5'],
            <Object>['minimal', 1, '\u2264 40'],
          ],
        );
        expect(
          stats.fold<double>(
            0,
            (double sum, SimilarityStat item) => sum + item.percent,
          ),
          100,
          reason:
              'the reference row is not counted, so the buckets share the rest',
        );
      },
    );

    test('the same difference means another level at another hash size', () {
      List<SimilarityStat> at(int hashSize) => buildSimilarityStats(
        <ScanRow>[row('a.jpg', 1, difference: 2)],
        hashSize: hashSize,
        differenceIndex: 0,
      );

      expect(at(8).single.level, SimilarityLevel.high);
      expect(at(16).single.level, SimilarityLevel.veryHigh);
      expect(at(64).single.level, SimilarityLevel.veryHigh);
    });

    test('an unlisted hash size falls back to 16 like the reference', () {
      expect(normalizeHashSize(12), 16);
      expect(normalizeHashSize(32), 32);
    });

    test('videos classify against the audio intervals, not the bit counts', () {
      expect(similarityLevel(2.8, videoSimilarityThresholds).wire, 'high');
      expect(similarityLevel(18.5, videoSimilarityThresholds).wire, 'small');
      expect(
        similarityRange(
          SimilarityLevel.high,
          similarityLevels.indexOf(SimilarityLevel.high),
          videoSimilarityThresholds,
        ),
        '\u2264 5',
      );
      expect(formatThreshold(2.5), '2.5');
      expect(formatThreshold(5), '5');
    });

    test('a tool whose rows carry no difference yields nothing to draw', () {
      expect(
        buildSimilarityStats(<ScanRow>[row('a.bin', 1)], differenceIndex: -1),
        isEmpty,
      );
    });

    test(
      'a row shorter than the difference column is skipped, not guessed',
      () {
        final List<SimilarityStat> stats = buildSimilarityStats(<ScanRow>[
          row('a.jpg', 1, difference: 3),
          const ScanRow(
            path: 'b.jpg',
            name: 'b.jpg',
            directory: '',
            cells: <String>[],
            sizeBytes: 1,
            modifiedTs: 0,
            groupIndex: 0,
            groupSize: 2,
            isGroupStart: false,
            isReference: false,
            sortKeys: <int>[],
          ),
        ], differenceIndex: 0);

        expect(
          stats.fold<int>(
            0,
            (int sum, SimilarityStat item) => sum + item.count,
          ),
          1,
        );
      },
    );

    test('only levels that hold a row are listed', () {
      final List<SimilarityStat> stats = buildSimilarityStats(<ScanRow>[
        row('a.jpg', 1, difference: 0),
      ], differenceIndex: 0);

      expect(stats.map((SimilarityStat item) => item.level.wire), <String>[
        'original',
      ]);
    });
  });

  group('similarity quick reference', () {
    test('prints the core table for every hash size', () {
      final List<SimilarityReferenceRow> reference = buildSimilarityReference();

      expect(
        reference
            .map(
              (SimilarityReferenceRow row) => <String>[
                row.level.wire,
                row.ranges[8]!,
                row.ranges[16]!,
                row.ranges[32]!,
                row.ranges[64]!,
              ],
            )
            .toList(),
        <List<String>>[
          <String>['original', '= 0', '= 0', '= 0', '= 0'],
          <String>['very-high', '\u2264 1', '\u2264 2', '\u2264 4', '\u2264 6'],
          <String>['high', '\u2264 2', '\u2264 5', '\u2264 10', '\u2264 20'],
          <String>['medium', '\u2264 5', '\u2264 15', '\u2264 20', '\u2264 40'],
          <String>['small', '\u2264 7', '\u2264 30', '\u2264 40', '\u2264 40'],
          <String>[
            'very-small',
            '\u2264 14',
            '\u2264 40',
            '\u2264 40',
            '\u2264 40',
          ],
          <String>[
            'minimal',
            '\u2264 40',
            '\u2264 40',
            '\u2264 40',
            '\u2264 40',
          ],
        ],
      );
    });
  });
}
