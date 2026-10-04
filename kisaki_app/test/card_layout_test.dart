import 'package:flutter_test/flutter_test.dart';
import 'package:kisaki_app/state/board_controller.dart';
import 'package:kisaki_app/state/card_layout.dart';

import 'support/stub_engine.dart';

/// The card layout decides what the reader sees and where, so every rule is checked with a value that
/// would break it: an out-of-band height, a foreign version, an index past the end.
void main() {
  group('the default arrangement', () {
    test('every registered card is visible and in its own lane', () {
      final CardLayout layout = createDefaultCardLayout();
      expect(layout.version, CardLayout.currentVersion);
      expect(layout.cards, hasLength(cardRegistry.length));
      for (final CardDefinition definition in cardRegistry) {
        expect(
          layout.configOf(definition.id).visible,
          isTrue,
          reason: '${definition.id.name} starts hidden',
        );
        expect(layout.configOf(definition.id).panel, definition.defaultPanel);
        expect(layout.configOf(definition.id).height, definition.defaultHeight);
      }
    });

    test(
      'the scan settings start in the source lane and the rest in analysis',
      () {
        expect(
          cardsForPanel(
            createDefaultCardLayout(),
            CardPanel.source,
          ).map((CardConfig card) => card.id),
          <CardId>[CardId.sourceSettings],
        );
        expect(
          cardsForPanel(
            createDefaultCardLayout(),
            CardPanel.analysis,
          ).map((CardConfig card) => card.id),
          <CardId>[
            CardId.preview,
            CardId.analysis,
            CardId.logs,
            CardId.selection,
            CardId.operations,
          ],
        );
      },
    );

    test('the order runs from zero within each lane', () {
      for (final CardPanel panel in CardPanel.values) {
        final List<int> orders = cardsForPanel(
          createDefaultCardLayout(),
          panel,
        ).map((CardConfig card) => card.order).toList();
        expect(orders, List<int>.generate(orders.length, (int index) => index));
      }
    });
  });

  group('editing a card', () {
    test('a height outside the band is taken back inside', () {
      final CardLayout layout = updateCard(
        createDefaultCardLayout(),
        CardId.analysis,
        height: 5000,
      );
      expect(layout.configOf(CardId.analysis).height, 900);

      final CardLayout small = updateCard(layout, CardId.analysis, height: 10);
      expect(small.configOf(CardId.analysis).height, 220);
    });

    test('a height that is not a number cannot collapse the card away', () {
      final CardLayout layout = updateCard(
        createDefaultCardLayout(),
        CardId.logs,
        height: double.nan,
      );
      expect(layout.configOf(CardId.logs).height, 160);
    });

    test('hiding and collapsing touch only the named card', () {
      final CardLayout layout = updateCard(
        updateCard(createDefaultCardLayout(), CardId.logs, visible: false),
        CardId.preview,
        collapsed: true,
      );
      expect(layout.configOf(CardId.logs).visible, isFalse);
      expect(layout.configOf(CardId.preview).collapsed, isTrue);
      expect(layout.configOf(CardId.analysis).collapsed, isFalse);
      expect(layout.configOf(CardId.analysis).visible, isTrue);
    });

    test('a hidden card leaves the lane but keeps its place', () {
      final CardLayout layout = updateCard(
        createDefaultCardLayout(),
        CardId.analysis,
        visible: false,
      );
      expect(
        cardsForPanel(layout, CardPanel.analysis).map((CardConfig c) => c.id),
        <CardId>[
          CardId.preview,
          CardId.logs,
          CardId.selection,
          CardId.operations,
        ],
      );
      expect(layout.configOf(CardId.analysis).order, 1);
    });
  });

  group('moving', () {
    test('a card moved to another lane takes the end of that lane', () {
      final CardLayout layout = moveCard(
        createDefaultCardLayout(),
        CardId.sourceSettings,
        CardPanel.analysis,
        99,
      );
      expect(
        cardsForPanel(layout, CardPanel.source),
        isEmpty,
        reason: 'the source lane gave up its only card',
      );
      expect(
        cardsForPanel(
          layout,
          CardPanel.analysis,
        ).map((CardConfig c) => c.id).last,
        CardId.sourceSettings,
      );
      expect(
        cardsForPanel(
          layout,
          CardPanel.analysis,
        ).map((CardConfig c) => c.order),
        <int>[0, 1, 2, 3, 4, 5],
      );
    });

    test('a card inserted at the front pushes the others down', () {
      final CardLayout layout = moveCard(
        createDefaultCardLayout(),
        CardId.operations,
        CardPanel.analysis,
        0,
      );
      expect(
        cardsForPanel(
          layout,
          CardPanel.analysis,
        ).map((CardConfig c) => c.id).first,
        CardId.operations,
      );
      expect(
        cardsForPanel(
          layout,
          CardPanel.analysis,
        ).map((CardConfig c) => c.id).toList()[1],
        CardId.preview,
      );
    });

    test('a nudge past either end is refused', () {
      final CardLayout layout = createDefaultCardLayout();
      expect(
        cardsForPanel(
          moveCardBy(layout, CardId.preview, -1),
          CardPanel.analysis,
        ).first.id,
        CardId.preview,
        reason: 'the first card has nowhere to go',
      );
      expect(
        cardsForPanel(
          moveCardBy(layout, CardId.operations, 1),
          CardPanel.analysis,
        ).last.id,
        CardId.operations,
        reason: 'the last card has nowhere to go',
      );
    });

    test('a nudge swaps with its neighbour', () {
      final CardLayout layout = moveCardBy(
        createDefaultCardLayout(),
        CardId.logs,
        -1,
      );
      expect(
        cardsForPanel(layout, CardPanel.analysis).map((CardConfig c) => c.id),
        <CardId>[
          CardId.preview,
          CardId.logs,
          CardId.analysis,
          CardId.selection,
          CardId.operations,
        ],
      );
    });

    test('an unknown card leaves the layout alone', () {
      final CardLayout layout = createDefaultCardLayout();
      expect(
        moveCardBy(layout, CardId.preview, 0).cards.length,
        layout.cards.length,
      );
    });
  });

  group('reading a stored layout back', () {
    test('a foreign version is refused outright', () {
      final CardLayout layout = normalizeCardLayout(
        const CardLayout(version: 2, cards: <CardConfig>[]),
      );
      expect(layout.cards, hasLength(cardRegistry.length));
      expect(layout.version, CardLayout.currentVersion);
    });

    test('a card the registry no longer knows is dropped', () {
      final CardLayout stored = createDefaultCardLayout();
      final CardLayout layout = normalizeCardLayout(
        CardLayout(
          version: CardLayout.currentVersion,
          cards: <CardConfig>[
            ...stored.cards,
            const CardConfig(
              id: CardId.logs,
              panel: CardPanel.source,
              visible: true,
              collapsed: false,
              height: 400,
              order: 7,
            ),
          ],
        ),
      );
      expect(
        layout.cards.where((CardConfig card) => card.id == CardId.logs).length,
        1,
        reason: 'one entry per registered card, the last one winning',
      );
      expect(layout.configOf(CardId.logs).panel, CardPanel.source);
    });

    test('a card missing from the document falls back to its default', () {
      final CardLayout layout = normalizeCardLayout(
        CardLayout(
          version: CardLayout.currentVersion,
          cards: <CardConfig>[
            const CardConfig(
              id: CardId.analysis,
              panel: CardPanel.analysis,
              visible: false,
              collapsed: true,
              height: 32,
              order: 0,
            ),
          ],
        ),
      );
      expect(layout.configOf(CardId.analysis).visible, isFalse);
      expect(layout.configOf(CardId.analysis).collapsed, isTrue);
      expect(
        layout.configOf(CardId.analysis).height,
        220,
        reason: 'the stored 32 is under the band, so the minimum is used',
      );
      expect(layout.configOf(CardId.logs).height, 300);
      expect(
        layout.cards
            .where((CardConfig card) => card.panel == CardPanel.analysis)
            .map((CardConfig card) => card.order)
            .toList()
          ..sort(),
        <int>[0, 1, 2, 3, 4],
        reason:
            'a hidden card keeps its slot, so the lane numbers stay gapless',
      );
    });

    test('a round trip through the normalizer is stable', () {
      final CardLayout once = normalizeCardLayout(createDefaultCardLayout());
      expect(normalizeCardLayout(once).cards, once.cards);
    });
  });

  group('the controller', () {
    late BoardController controller;

    setUp(() {
      controller = BoardController(engine: StubEngine())
        ..addIncluded(<String>['/data']);
    });

    test('hiding a card takes it out of its lane', () {
      controller.setCardVisible(CardId.logs, false);
      expect(
        controller.cardsIn(CardPanel.analysis).map((CardConfig c) => c.id),
        isNot(contains(CardId.logs)),
      );
      controller.setCardVisible(CardId.logs, true);
      expect(
        controller.cardsIn(CardPanel.analysis).map((CardConfig c) => c.id),
        contains(CardId.logs),
      );
    });

    test('a collapse and a height change are published', () {
      int notified = 0;
      controller.addListener(() => notified += 1);
      controller.toggleCardCollapsed(CardId.preview);
      controller.setCardHeight(CardId.preview, 240);
      expect(notified, 2);
      expect(controller.cardConfig(CardId.preview).collapsed, isTrue);
      expect(controller.cardConfig(CardId.preview).height, 240);
    });

    test('a height that changes nothing does not wake the board', () {
      int notified = 0;
      controller.addListener(() => notified += 1);
      controller.setCardHeight(CardId.preview, 100);
      expect(notified, 0);
    });

    test('double clicking the rail hands the height back', () {
      controller.setCardHeight(CardId.logs, 700);
      controller.resetCardHeight(CardId.logs);
      expect(controller.cardConfig(CardId.logs).height, 300);
    });

    test('restoring the layout brings every card back in order', () {
      controller.setCardVisible(CardId.analysis, false);
      controller.nudgeCard(CardId.operations, -2);
      controller.restoreCards();
      expect(
        controller.cardsIn(CardPanel.analysis).map((CardConfig c) => c.id),
        createDefaultCardLayout().cards
            .where((CardConfig c) => c.panel == CardPanel.analysis)
            .map((CardConfig c) => c.id),
      );
    });

    test('resetting the layout restores the cards too', () {
      controller.moveCardTo(CardId.selection, CardPanel.source, 1);
      controller.resetLayout();
      expect(controller.cardConfig(CardId.selection).panel, CardPanel.analysis);
    });
  });
}
