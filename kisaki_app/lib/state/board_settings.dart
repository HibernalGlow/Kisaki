import 'dart:convert';
import 'dart:io';

import 'card_layout.dart';
import 'board_controller.dart';

/// What the board remembers between runs: the reader's arrangement, not their data.
///
/// Deliberately narrow. Scan results, selections and the current tool are a session, and restoring
/// them would invite acting on a stale set of files. Geometry and the dark choice are what a reader
/// expects to come back to.
class BoardSettings {
  const BoardSettings({
    required this.dark,
    required this.lanes,
    required this.cards,
  });

  static const int schemaVersion = 1;

  final bool dark;
  final LaneSettings lanes;

  /// Keyed by card, so a card the build no longer has is dropped instead of shifting the rest.
  final Map<CardId, CardSettings> cards;

  BoardSettings.capture(BoardController controller)
    : dark = controller.dark,
      lanes = LaneSettings.capture(controller.layout),
      cards = <CardId, CardSettings>{
        for (final CardConfig card in controller.cardLayout.cards)
          card.id: CardSettings.capture(card),
      };

  Map<String, Object?> toJson() => <String, Object?>{
    'version': BoardSettings.schemaVersion,
    'dark': dark,
    'lanes': lanes.toJson(),
    'cards': <String, Object?>{
      for (final MapEntry<CardId, CardSettings> entry in cards.entries)
        entry.key.name: entry.value.toJson(),
    },
  };

  /// Tolerant on purpose: one bad value drops back to the default for that one field. A whole-file
  /// failure here would silently reset a reader's board because one number was written wrong.
  factory BoardSettings.fromJson(Map<String, Object?> json) {
    if (json['version'] != BoardSettings.schemaVersion) {
      return BoardSettings.defaults();
    }
    final Object? rawCards = json['cards'];
    final Map<String, Object?> cardsJson = rawCards is Map
        ? Map<String, Object?>.from(rawCards)
        : const <String, Object?>{};
    final Map<CardId, CardSettings> cards = <CardId, CardSettings>{};
    for (final CardId id in CardId.values) {
      final Object? raw = cardsJson[id.name];
      if (raw is Map) {
        cards[id] = CardSettings.fromJson(raw.cast<String, Object?>(), id: id);
      }
    }
    return BoardSettings(
      dark: json['dark'] is bool ? json['dark'] as bool : true,
      lanes: LaneSettings.fromJson(
        json['lanes'] is Map
            ? (json['lanes'] as Map).cast<String, Object?>()
            : const <String, Object?>{},
      ),
      cards: cards,
    );
  }

  factory BoardSettings.defaults() => BoardSettings(
    dark: true,
    lanes: LaneSettings.defaults(),
    cards: const <CardId, CardSettings>{},
  );

  void applyTo(BoardController controller) {
    controller.dark = dark;
    lanes.applyTo(controller.layout);
    for (final MapEntry<CardId, CardSettings> entry in cards.entries) {
      if (!controller.cardLayout.cards.any((CardConfig c) => c.id == entry.key)) {
        continue;
      }
      final CardSettings card = entry.value;
      final CardConfig current = controller.cardLayout.configOf(entry.key);
      if (current.visible != card.visible) {
        controller.setCardVisible(entry.key, card.visible);
      }
      if (current.collapsed != card.collapsed) {
        controller.toggleCardCollapsed(entry.key);
      }
      if (current.height != card.height) {
        controller.setCardHeight(entry.key, card.height);
      }
    }
    // No notification: the caller applies a snapshot before the widget tree exists.
  }
}

/// The three lanes' widths, collapse flags, solo choice and order.
class LaneSettings {
  const LaneSettings({
    required this.sourceWidth,
    required this.resultsWidth,
    required this.analysisWidth,
    required this.sourceCollapsed,
    required this.resultsCollapsed,
    required this.analysisCollapsed,
    required this.soloLane,
    required this.order,
  });

  final double sourceWidth;
  final double resultsWidth;
  final double analysisWidth;
  final bool sourceCollapsed;
  final bool resultsCollapsed;
  final bool analysisCollapsed;
  final String? soloLane;
  final List<String> order;

  factory LaneSettings.capture(LaneLayout layout) => LaneSettings(
    sourceWidth: layout.sourceWidth,
    resultsWidth: layout.resultsWidth,
    analysisWidth: layout.analysisWidth,
    sourceCollapsed: layout.sourceCollapsed,
    resultsCollapsed: layout.resultsCollapsed,
    analysisCollapsed: layout.analysisCollapsed,
    soloLane: layout.soloLane,
    order: List<String>.of(layout.laneOrder),
  );

  factory LaneSettings.defaults() => LaneSettings(
    sourceWidth: LaneLayout.sourceDefault,
    resultsWidth: LaneLayout.resultsDefault,
    analysisWidth: LaneLayout.analysisDefault,
    sourceCollapsed: false,
    resultsCollapsed: false,
    analysisCollapsed: false,
    soloLane: null,
    order: const <String>['source', 'results', 'analysis'],
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceWidth': sourceWidth,
    'resultsWidth': resultsWidth,
    'analysisWidth': analysisWidth,
    'sourceCollapsed': sourceCollapsed,
    'resultsCollapsed': resultsCollapsed,
    'analysisCollapsed': analysisCollapsed,
    'soloLane': soloLane,
    'order': order,
  };

  factory LaneSettings.fromJson(Map<String, Object?> json) {
    final LaneSettings fallback = LaneSettings.defaults();
    final List<String> wanted = json['order'] is List
        ? (json['order'] as List).map((Object? item) => '$item').toList()
        : fallback.order;
    return LaneSettings(
      sourceWidth: _number(json['sourceWidth']) ?? fallback.sourceWidth,
      resultsWidth: _number(json['resultsWidth']) ?? fallback.resultsWidth,
      analysisWidth: _number(json['analysisWidth']) ?? fallback.analysisWidth,
      sourceCollapsed: json['sourceCollapsed'] is bool
          ? json['sourceCollapsed']! as bool
          : fallback.sourceCollapsed,
      resultsCollapsed: json['resultsCollapsed'] is bool
          ? json['resultsCollapsed']! as bool
          : fallback.resultsCollapsed,
      analysisCollapsed: json['analysisCollapsed'] is bool
          ? json['analysisCollapsed']! as bool
          : fallback.analysisCollapsed,
      soloLane: json['soloLane'] is String
          ? json['soloLane']! as String
          : null,
      order: wanted.length == 3 ? wanted : fallback.order,
    );
  }

  void applyTo(LaneLayout layout) {
    layout.sourceWidth = sourceWidth;
    layout.resultsWidth = resultsWidth;
    layout.analysisWidth = analysisWidth;
    layout.sourceCollapsed = sourceCollapsed;
    layout.resultsCollapsed = resultsCollapsed;
    layout.analysisCollapsed = analysisCollapsed;
    layout.soloLane = soloLane;
    layout.laneOrder = List<String>.of(order);
  }
}

/// One card's visibility, collapsed flag and height. Which lane a card was moved to is not restored:
/// the card manager owns that, and guessing a lane for a card that no longer exists is worse than
/// leaving it where the build puts it.
class CardSettings {
  const CardSettings({
    required this.visible,
    required this.collapsed,
    required this.height,
  });

  final bool visible;
  final bool collapsed;
  final double height;

  factory CardSettings.capture(CardConfig card) => CardSettings(
    visible: card.visible,
    collapsed: card.collapsed,
    height: card.height,
  );

  factory CardSettings.fromJson(Map<String, Object?> json, {required CardId id}) {
    final CardDefinition definition = cardDefinition(id);
    return CardSettings(
      visible: json['visible'] is bool ? json['visible']! as bool : true,
      collapsed: json['collapsed'] is bool
          ? json['collapsed']! as bool
          : false,
      height: _number(json['height']) ?? definition.defaultHeight,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'visible': visible,
    'collapsed': collapsed,
    'height': height,
  };
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

/// Reads and writes `board.json` next to the other files this product owns.
class BoardSettingsStore {
  const BoardSettingsStore({required this.directory});

  final String directory;

  File get _file => File('$directory/board.json');

  Future<BoardSettings> read() async {
    try {
      final String text = await _file.readAsString();
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) {
        return BoardSettings.fromJson(Map<String, Object?>.from(decoded));
      }
    } on Object {
      // Missing, unreadable or unparseable all mean the same thing to the reader: start fresh.
      return BoardSettings.defaults();
    }
    return BoardSettings.defaults();
  }

  Future<void> write(BoardSettings settings) async {
    try {
      await Directory(directory).create(recursive: true);
      await _file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      );
    } on Object {
      // A read-only home must not break the board; the arrangement simply is not remembered.
    }
  }
}
