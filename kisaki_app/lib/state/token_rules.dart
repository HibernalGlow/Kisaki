/// Whether a typed token can actually do what the reader meant.
///
/// Ported from `packages/nodes/czkawka/src/source-inputs.ts`. An excluded rule only reaches anything
/// when it is a glob or one of the two named presets, and an extension never carries a dot or a space,
/// so a dead entry is worth saying out loud instead of letting a scan quietly ignore it.
enum TokenKind { path, extension, rule }

/// One of the two rules the engine understands without a wildcard.
const String trashRule = r'$TRASH';

bool isValidExtensionToken(String token) {
  final String value = token.startsWith('.') ? token.substring(1) : token;
  return value.isNotEmpty &&
      !value.contains('.') &&
      !value.contains(RegExp(r'\s'));
}

bool isValidExcludedRule(String rule) =>
    rule == 'DEFAULT' || rule == trashRule || rule.contains('*');

/// The label that explains a marked entry, or null when the entry is usable. Paths are not judged:
/// a path that does not exist yet is a legitimate thing to have in the list.
String? tokenProblemKey(TokenKind kind, String token) => switch (kind) {
  TokenKind.path => null,
  TokenKind.extension =>
    isValidExtensionToken(token) ? null : 'token-bad-extension',
  TokenKind.rule => isValidExcludedRule(token) ? null : 'token-bad-rule',
};
