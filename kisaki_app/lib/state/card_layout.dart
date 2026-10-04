import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Which lane a card sits in. The reference calls them panels; the board calls them lanes.
enum CardPanel { source, analysis }

/// How a lane shows its cards: the reference's cards view stacks them, its panels view tabs them.
enum CardDisplay { stack, tabs }

/// A block of the board the reader can place, hide, collapse and size.
enum CardId {
  sourceSettings('card-title-source-settings', 'cards-tab-source-settings'),
  preview('card-title-preview', 'cards-tab-preview'),
  analysis('card-title-analysis', 'cards-tab-analysis'),
  logs('card-title-logs', 'cards-tab-logs'),
  selection('card-title-selection', 'cards-tab-selection'),
  operations('card-title-operations', 'cards-tab-operations');

  const CardId(this.titleKey, this.tabKey);

  final String titleKey;

  /// The short name a tab strip can afford, as the reference keeps one per card.
  final String tabKey;
}

@immutable
class CardDefinition {
  const CardDefinition({
    required this.id,
    required this.defaultPanel,
    required this.defaultHeight,
    required this.minHeight,
    required this.maxHeight,
    this.fillViewport = false,
  });

  final CardId id;
  final CardPanel defaultPanel;

  /// Heights are on the board's 4 pixel step; the reference's 430 became 432.
  final double defaultHeight;
  final double minHeight;
  final double maxHeight;

  /// A card whose content carries its own scrolling - the tabbed scan settings - needs the card body
  /// as its viewport instead of being handed to a scroll view of its own.
  final bool fillViewport;
}

const List<CardDefinition> cardRegistry = <CardDefinition>[
  CardDefinition(
    id: CardId.sourceSettings,
    defaultPanel: CardPanel.source,
    defaultHeight: 520,
    minHeight: 220,
    maxHeight: 900,
    fillViewport: true,
  ),
  CardDefinition(
    id: CardId.preview,
    defaultPanel: CardPanel.analysis,
    defaultHeight: 100,
    minHeight: 72,
    maxHeight: 240,
  ),
  CardDefinition(
    id: CardId.analysis,
    defaultPanel: CardPanel.analysis,
    defaultHeight: 432,
    minHeight: 220,
    maxHeight: 900,
  ),
  CardDefinition(
    id: CardId.logs,
    defaultPanel: CardPanel.analysis,
    defaultHeight: 300,
    minHeight: 160,
    maxHeight: 720,
  ),
  CardDefinition(
    id: CardId.selection,
    defaultPanel: CardPanel.analysis,
    defaultHeight: 280,
    minHeight: 160,
    maxHeight: 640,
  ),
  CardDefinition(
    id: CardId.operations,
    defaultPanel: CardPanel.analysis,
    defaultHeight: 360,
    minHeight: 220,
    maxHeight: 760,
  ),
];

@immutable
class CardConfig {
  const CardConfig({
    required this.id,
    required this.panel,
    required this.visible,
    required this.collapsed,
    required this.height,
    required this.order,
  });

  final CardId id;
  final CardPanel panel;
  final bool visible;
  final bool collapsed;
  final double height;
  final int order;

  CardConfig copyWith({
    CardPanel? panel,
    bool? visible,
    bool? collapsed,
    double? height,
    int? order,
  }) => CardConfig(
    id: id,
    panel: panel ?? this.panel,
    visible: visible ?? this.visible,
    collapsed: collapsed ?? this.collapsed,
    height: height ?? this.height,
    order: order ?? this.order,
  );

  @override
  bool operator ==(Object other) =>
      other is CardConfig &&
      other.id == id &&
      other.panel == panel &&
      other.visible == visible &&
      other.collapsed == collapsed &&
      other.height == height &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, panel, visible, collapsed, height, order);
}

@immutable
class CardLayout {
  const CardLayout({required this.version, required this.cards});

  final int version;
  final List<CardConfig> cards;

  CardConfig configOf(CardId id) =>
      cards.firstWhere((CardConfig card) => card.id == id);

  CardLayout withCards(List<CardConfig> cards) =>
      CardLayout(version: version, cards: List<CardConfig>.unmodifiable(cards));

  @override
  bool operator ==(Object other) {
    if (other is! CardLayout || other.version != version) {
      return false;
    }
    return listEquals(other.cards, cards);
  }

  @override
  int get hashCode => Object.hash(version, Object.hashAll(cards));

  static const int currentVersion = 1;
}

/// Every card visible, in its own lane, in the reference's order.
CardLayout createDefaultCardLayout() {
  final Map<CardPanel, int> counts = <CardPanel, int>{
    CardPanel.source: 0,
    CardPanel.analysis: 0,
  };
  return CardLayout(
    version: CardLayout.currentVersion,
    cards: List<CardConfig>.unmodifiable(
      cardRegistry.map((CardDefinition definition) {
        final int order = counts[definition.defaultPanel]!;
        counts[definition.defaultPanel] = order + 1;
        return CardConfig(
          id: definition.id,
          panel: definition.defaultPanel,
          visible: true,
          collapsed: false,
          height: definition.defaultHeight,
          order: order,
        );
      }),
    ),
  );
}

/// A stored layout is merged onto the defaults by id, so a card added in a later build appears and a
/// card the registry no longer knows is dropped instead of rendering blank.
CardLayout normalizeCardLayout(CardLayout? value) {
  final CardLayout defaults = createDefaultCardLayout();
  if (value == null || value.version != CardLayout.currentVersion) {
    return defaults;
  }
  final Map<CardId, CardConfig> existing = <CardId, CardConfig>{
    for (final CardConfig card in value.cards) card.id: card,
  };
  final List<CardConfig> cards = defaults.cards.map((CardConfig fallback) {
    final CardConfig? card = existing[fallback.id];
    if (card == null) {
      return fallback;
    }
    final CardDefinition definition = cardDefinition(fallback.id);
    return card.copyWith(
      panel: card.panel,
      height: _clamp(card.height, definition.minHeight, definition.maxHeight),
    );
  }).toList();
  return CardLayout(
    version: CardLayout.currentVersion,
    cards: _normalizeOrders(cards),
  );
}

CardLayout updateCard(
  CardLayout layout,
  CardId id, {
  bool? visible,
  bool? collapsed,
  double? height,
}) {
  final CardDefinition definition = cardDefinition(id);
  return layout.withCards(
    layout.cards.map((CardConfig card) {
      if (card.id != id) {
        return card;
      }
      return card.copyWith(
        visible: visible,
        collapsed: collapsed,
        height: _clamp(
          height ?? card.height,
          definition.minHeight,
          definition.maxHeight,
        ),
      );
    }).toList(),
  );
}

/// Move a card to a lane at `targetIndex`, renumbering only that lane's order.
CardLayout moveCard(
  CardLayout layout,
  CardId id,
  CardPanel panel,
  int targetIndex,
) {
  final CardConfig? moving = layout.cards
      .where((CardConfig card) => card.id == id)
      .firstOrNull;
  if (moving == null) {
    return layout;
  }
  final List<CardConfig> remaining = layout.cards
      .where((CardConfig card) => card.id != id)
      .toList();
  final List<CardConfig> target =
      remaining.where((CardConfig card) => card.panel == panel).toList()
        ..sort((CardConfig a, CardConfig b) => a.order.compareTo(b.order));
  target.insert(
    _clampInt(targetIndex, 0, target.length),
    moving.copyWith(panel: panel),
  );
  final List<CardConfig> untouched = remaining
      .where((CardConfig card) => card.panel != panel)
      .toList();
  for (int index = 0; index < target.length; index += 1) {
    target[index] = target[index].copyWith(order: index);
  }
  return layout.withCards(
    _normalizeOrders(<CardConfig>[...untouched, ...target]),
  );
}

CardLayout moveCardBy(CardLayout layout, CardId id, int offset) {
  final CardConfig? card = layout.cards
      .where((CardConfig item) => item.id == id)
      .firstOrNull;
  if (card == null) {
    return layout;
  }
  return moveCard(layout, id, card.panel, card.order + offset);
}

/// The lane renders this, in order, skipping the hidden ones.
List<CardConfig> cardsForPanel(CardLayout layout, CardPanel panel) {
  final List<CardConfig> cards =
      layout.cards
          .where((CardConfig card) => card.panel == panel && card.visible)
          .toList()
        ..sort((CardConfig a, CardConfig b) => a.order.compareTo(b.order));
  return cards;
}

List<CardConfig> _normalizeOrders(List<CardConfig> cards) {
  final List<CardConfig> next = cards.toList();
  for (final CardPanel panel in CardPanel.values) {
    final List<CardConfig> inPanel =
        next.where((CardConfig card) => card.panel == panel).toList()
          ..sort((CardConfig a, CardConfig b) => a.order.compareTo(b.order));
    for (int order = 0; order < inPanel.length; order += 1) {
      final CardConfig card = inPanel[order];
      next[next.indexOf(card)] = card.copyWith(order: order);
    }
  }
  return next;
}

CardDefinition cardDefinition(CardId id) =>
    cardRegistry.firstWhere((CardDefinition item) => item.id == id);

double _clamp(double value, double min, double max) {
  if (!value.isFinite) {
    return min;
  }
  return math.min(max, math.max(min, value));
}

int _clampInt(int value, int min, int max) =>
    math.min(max, math.max(min, value));
