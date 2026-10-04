import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/l10n/labels.dart';
import 'package:kisaki_app/state/token_rules.dart';
import 'package:kisaki_app/ui/token_list.dart';
import 'package:kisaki_app/ui/widgets/primitives.dart';

/// A dead rule or a dotted extension silently matches nothing, so the list has to say which entry is
/// the problem and why, exactly the way the reference marks the badge destructive and explains it in
/// the tooltip. The two rules and the `$TRASH` preset come straight from `source-inputs.ts`.
void main() {
  group('what counts as a usable token', () {
    test('an extension carries neither a dot nor a space', () {
      expect(isValidExtensionToken('jpg'), isTrue);
      expect(
        isValidExtensionToken('.jpg'),
        isTrue,
        reason: 'a leading dot is dropped',
      );
      expect(isValidExtensionToken('tar.gz'), isFalse);
      expect(isValidExtensionToken('jp g'), isFalse);
      expect(isValidExtensionToken('.'), isFalse);
      expect(isValidExtensionToken(''), isFalse);
    });

    test('an excluded rule is a glob or one of the two named presets', () {
      expect(isValidExcludedRule('*/.git/*'), isTrue);
      expect(isValidExcludedRule('DEFAULT'), isTrue);
      expect(isValidExcludedRule(trashRule), isTrue);
      expect(isValidExcludedRule('/home/user/tmp'), isFalse);
      expect(
        trashRule,
        r'$TRASH',
        reason: 'the preset name has a dollar in it',
      );
    });

    test('paths are not judged', () {
      expect(tokenProblemKey(TokenKind.path, '/nope'), isNull);
      expect(
        tokenProblemKey(TokenKind.extension, 'tar.gz'),
        'token-bad-extension',
      );
      expect(
        tokenProblemKey(TokenKind.rule, '/home/user/tmp'),
        'token-bad-rule',
      );
    });
  });

  Widget harness(List<String> initial, TokenKind kind) => MaterialApp(
    home: Scaffold(
      body: _Harness(initial: initial, kind: kind),
    ),
  );

  testWidgets('a dead rule is marked and says why, a live one is not', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      harness(<String>['*/.git/*', '/home/user/tmp'], TokenKind.rule),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('token-problem-/home/user/tmp')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Tooltip>(
            find.byKey(const Key('token-problem-/home/user/tmp')),
          )
          .message,
      Labels.of('token-bad-rule'),
    );
    expect(
      find.byKey(const Key('token-problem-*/.git/*')),
      findsNothing,
      reason: 'a glob is a rule that will actually match',
    );
  });

  testWidgets('the trash preset adds itself once and then stands down', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(harness(<String>['*/.cache'], TokenKind.rule));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('token-trash-rules')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('token-entry-$trashRule')),
      findsOneWidget,
      reason: 'one click puts the named preset in the list, like the reference button',
    );

    final BoardAction afterAdd = tester.widget(
      find.byKey(const Key('token-trash-rules')),
    );
    expect(
      afterAdd.onPressed,
      isNull,
      reason: 'the reference disables the preset once the rule is in the list',
    );
  });

  testWidgets('an extension list marks a dotted entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      harness(<String>['jpg', 'tar.gz'], TokenKind.extension),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('token-problem-tar.gz')), findsOneWidget);
    expect(find.byKey(const Key('token-problem-jpg')), findsNothing);
    expect(
      find.byKey(const Key('token-trash-rules')),
      findsNothing,
      reason: 'only the rule list offers the preset',
    );
  });
}

class _Harness extends StatefulWidget {
  const _Harness({required this.initial, required this.kind});

  final List<String> initial;
  final TokenKind kind;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final List<String> _entries = List<String>.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    return TokenListEditor(
      label: 'rules',
      kind: widget.kind,
      entries: _entries,
      placeholder: '*/.git/*',
      onAdd: (String value) => setState(() => _entries.add(value)),
      onRemoveAt: (int index) => setState(() => _entries.removeAt(index)),
      onClear: () => setState(() => _entries.clear()),
    );
  }
}
