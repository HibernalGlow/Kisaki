/// A reader for the subset of Fluent this project's catalogues are written in.
///
/// The catalogues are `.ftl` files so they stay on the same pipeline as every other frontend in
/// this workspace (`just pack_translations` -> Crowdin -> `just unpack_translations`), but the app
/// needs only message lookup: `Labels.of` performs the placeholder substitution itself. Anything
/// beyond that - selectors, attributes, terms - is therefore refused out loud rather than parsed
/// into a wrong string.
library;

/// Message syntax this reader understands: `key = value`, optionally continued on indented lines.
final RegExp _message = RegExp(r"^([a-zA-Z][a-zA-Z0-9_-]*)[ \t]*=[ \t]?(.*)$");
final RegExp _continuation = RegExp(r'^\s+\S');

Map<String, String> parseFluentCatalog(
  String source, {
  required String origin,
}) {
  final Map<String, String> messages = <String, String>{};
  final List<String> lines = source.split('\n');
  String? current;
  for (int index = 0; index < lines.length; index++) {
    final String line = lines[index].trimRight();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    if (line.contains('->') || line.trimLeft().startsWith('.')) {
      throw FormatException(
        'Fluent selectors and attributes are not supported; $origin line ${index + 1}: $line',
      );
    }
    if (current != null && _continuation.hasMatch(line)) {
      // A message opened with `key =` and no inline text takes its first continuation line
      // as the start, not as a second line of an empty value.
      final String head = messages[current]!;
      messages[current] = head.isEmpty ? line.trim() : '$head\n${line.trim()}';
      continue;
    }
    final RegExpMatch? message = _message.firstMatch(line);
    if (message == null) {
      throw FormatException(
        'Unreadable message in $origin at line ${index + 1}: $line',
      );
    }
    current = message.group(1);
    messages[current!] = message.group(2)!.trim();
  }
  return messages;
}
