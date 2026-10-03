import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/l10n/labels.dart';

/// The resolver substitutes only the spaced Fluent form, so a label authored as `{count}` paints its
/// own placeholder. This gate keeps the table and the resolver in step.
void main() {
  final RegExp placeholders = RegExp(r'\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}');

  test('the check sees a placeholder the resolver cannot reach', () {
    expect(
      placeholders
          .allMatches('Renamed {count} paths.')
          .map((RegExpMatch match) => match.group(1)!)
          .toList(),
      <String>['count'],
      reason: 'a broken label has to be visible here',
    );
  });

  test('every authored placeholder uses the spaced form', () {
    final List<String> broken = <String>[];
    Labels.table.forEach((String key, String text) {
      for (final RegExpMatch match in placeholders.allMatches(text)) {
        if (!text.contains('{ \$${match.group(1)} }')) {
          broken.add('$key writes ${match.group(0)}');
        }
      }
    });

    expect(broken, isEmpty);
  });

  test('a substituted label reaches the reader without braces', () {
    expect(
      Labels.of(
        'activity-result',
        args: const <String, Object>{'affected': 3, 'errors': 1},
      ),
      '3 affected / 1 errors',
    );
    expect(
      Labels.of(
        'log-operation-started',
        args: const <String, Object>{'action': 'Delete', 'count': 2},
      ),
      'Delete asked the engine for 2 paths.',
    );
  });
}
