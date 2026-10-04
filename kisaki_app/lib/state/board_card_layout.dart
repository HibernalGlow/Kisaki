part of 'board_controller.dart';

/// Where each block of the board lives: which lane, in what order, visible, collapsed and how tall.
extension BoardCardLayout on BoardController {
  CardLayout get cardLayout => _cards;

  List<CardConfig> cardsIn(CardPanel panel) => cardsForPanel(_cards, panel);

  CardConfig cardConfig(CardId id) => _cards.configOf(id);

  void setCardVisible(CardId id, bool visible) {
    _patchCards(updateCard(_cards, id, visible: visible));
  }

  void toggleCardCollapsed(CardId id) {
    _patchCards(
      updateCard(_cards, id, collapsed: !_cards.configOf(id).collapsed),
    );
  }

  void setCardHeight(CardId id, double height) {
    _patchCards(updateCard(_cards, id, height: height));
  }

  /// The reference restores the height on a double click of the sizing rail.
  void resetCardHeight(CardId id) {
    setCardHeight(id, cardDefinition(id).defaultHeight);
  }

  void moveCardTo(CardId id, CardPanel panel, int index) {
    _patchCards(moveCard(_cards, id, panel, index));
  }

  void nudgeCard(CardId id, int offset) {
    _patchCards(moveCardBy(_cards, id, offset));
  }

  void restoreCards() {
    _patchCards(createDefaultCardLayout());
  }

  void _patchCards(CardLayout next) {
    if (next == _cards) {
      return;
    }
    _cards = next;
    publish();
  }
}
