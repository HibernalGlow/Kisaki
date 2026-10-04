import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/card_layout.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// Builds the content of one card, so a lane and the floating panel can show the same block.
typedef CardBodyBuilder = Widget Function(BuildContext context, CardId id);

/// The reader's arrangement of the board's blocks: which lane holds each one, in what order, visible,
/// collapsed and how tall - the reference's card stack.
class CardStack extends StatelessWidget {
  const CardStack({
    required this.controller,
    required this.panel,
    required this.renderCard,
    super.key,
  });

  final BoardController controller;
  final CardPanel panel;
  final CardBodyBuilder renderCard;

  @override
  Widget build(BuildContext context) {
    final List<CardConfig> cards = controller.cardsIn(panel);
    if (cards.isEmpty) {
      return EmptyState(
        key: Key('cards-empty-${panel.name}'),
        labelKey: 'cards-empty',
      );
    }
    if (cards.length > 1 && controller.cardDisplay(panel) == CardDisplay.tabs) {
      return _CardTabs(
        controller: controller,
        panel: panel,
        cards: cards,
        renderCard: renderCard,
      );
    }
    return SingleChildScrollView(
      key: Key('card-stack-${panel.name}'),
      // The lane breathes on the section rhythm, as it did when it held one flat list.
      padding: const EdgeInsets.all(BoardTokens.section),
      // Every card is built, not only the ones on screen: the reference paints the whole stack, and a
      // lazily built list would leave a reader's own blocks missing above and below the fold.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < cards.length; index += 1) ...<Widget>[
            if (index > 0) const SizedBox(height: BoardTokens.gap),
            _LayoutCard(
              controller: controller,
              card: cards[index],
              first: index == 0,
              last: index == cards.length - 1,
              renderCard: renderCard,
            ),
          ],
        ],
      ),
    );
  }
}

class _LayoutCard extends StatelessWidget {
  const _LayoutCard({
    required this.controller,
    required this.card,
    required this.first,
    required this.last,
    required this.renderCard,
  });

  final BoardController controller;
  final CardConfig card;
  final bool first;
  final bool last;
  final CardBodyBuilder renderCard;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final String title = Labels.of(card.id.titleKey);
    return Container(
      key: Key('card-${card.id.name}'),
      height: card.collapsed ? null : card.height,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(BoardTokens.radius),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CardHeader(
            palette: palette,
            controller: controller,
            card: card,
            title: title,
            first: first,
            last: last,
          ),
          if (!card.collapsed) ...<Widget>[
            Expanded(
              child: cardDefinition(card.id).fillViewport
                  ? Padding(
                      padding: const EdgeInsets.all(BoardTokens.gap),
                      child: renderCard(context, card.id),
                    )
                  : SingleChildScrollView(
                      // The reference's card body scrolls whatever the block holds.
                      padding: const EdgeInsets.all(BoardTokens.gap),
                      child: renderCard(context, card.id),
                    ),
            ),
            _HeightRail(
              palette: palette,
              controller: controller,
              card: card,
              title: title,
            ),
          ],
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.palette,
    required this.controller,
    required this.card,
    required this.title,
    required this.first,
    required this.last,
  });

  final BoardPalette palette;
  final BoardController controller;
  final CardConfig card;
  final String title;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.sunken,
      padding: const EdgeInsets.symmetric(
        horizontal: BoardTokens.gapSmall,
        vertical: BoardTokens.gapSmall,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              key: Key('card-collapse-${card.id.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.toggleCardCollapsed(card.id),
              child: Row(
                children: <Widget>[
                  Icon(
                    card.collapsed
                        ? Icons.chevron_right_rounded
                        : Icons.expand_more_rounded,
                    size: 14,
                    color: palette.fgMuted,
                  ),
                  const SizedBox(width: BoardTokens.gapSmall),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: BoardTokens.fsLabel,
                        fontWeight: FontWeight.w700,
                        color: palette.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          BoardAction(
            key: Key('card-up-${card.id.name}'),
            labelKey: 'cards-move-up',
            labelArgs: <String, Object>{'title': title},
            icon: Icons.arrow_upward_rounded,
            dense: true,
            iconOnly: true,
            onPressed: first ? null : () => controller.nudgeCard(card.id, -1),
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          BoardAction(
            key: Key('card-down-${card.id.name}'),
            labelKey: 'cards-move-down',
            labelArgs: <String, Object>{'title': title},
            icon: Icons.arrow_downward_rounded,
            dense: true,
            iconOnly: true,
            onPressed: last ? null : () => controller.nudgeCard(card.id, 1),
          ),
        ],
      ),
    );
  }
}

/// Drag to size, double click to hand the height back to the board, as the reference's rail does.
class _HeightRail extends StatelessWidget {
  const _HeightRail({
    required this.palette,
    required this.controller,
    required this.card,
    required this.title,
  });

  final BoardPalette palette;
  final BoardController controller;
  final CardConfig card;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: Labels.of(
        'cards-resize-hint',
        args: <String, Object>{'title': title},
      ),
      child: Semantics(
        label: Labels.of(
          'cards-resize',
          args: <String, Object>{'title': title},
        ),
        value: '${card.height.round()} px',
        child: GestureDetector(
          key: Key('card-height-${card.id.name}'),
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (DragUpdateDetails details) =>
              controller.setCardHeight(card.id, card.height + details.delta.dy),
          onDoubleTap: () => controller.resetCardHeight(card.id),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: SizedBox(
              height: BoardTokens.gap,
              child: Center(
                child: ColoredBox(
                  color: palette.border,
                  child: const SizedBox(
                    width: double.infinity,
                    height: BoardTokens.hairline,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The reference's card manager: visibility, lane and the way back to the default arrangement.
class CardManagerDialog {
  static Future<void> open(BuildContext context, BoardController controller) =>
      showDialog<void>(
        context: context,
        builder: (BuildContext context) => _CardManager(controller: controller),
      );
}

/// The switch between the two arrangements a lane can show its blocks in.
class CardDisplayToggle extends StatelessWidget {
  const CardDisplayToggle({
    required this.controller,
    required this.panel,
    super.key,
  });

  final BoardController controller;
  final CardPanel panel;

  @override
  Widget build(BuildContext context) {
    final bool stacked = controller.cardDisplay(panel) == CardDisplay.stack;
    return BoardAction(
      key: Key('cards-display-${panel.name}'),
      labelKey: stacked ? 'cards-display-tabs' : 'cards-display-stack',
      icon: stacked ? Icons.tab_rounded : Icons.layers_outlined,
      dense: true,
      iconOnly: true,
      onPressed: () => controller.toggleCardDisplay(panel),
    );
  }
}

/// One card at a time, the reference's panels view: a strip over the chosen block.
class _CardTabs extends StatelessWidget {
  const _CardTabs({
    required this.controller,
    required this.panel,
    required this.cards,
    required this.renderCard,
  });

  final BoardController controller;
  final CardPanel panel;
  final List<CardConfig> cards;
  final CardBodyBuilder renderCard;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final CardId? active = controller.activeCard(panel);
    return Padding(
      padding: const EdgeInsets.all(BoardTokens.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (final CardConfig card in cards) ...<Widget>[
                Expanded(
                  child: BoardAction(
                    key: Key('card-tab-${card.id.name}'),
                    labelKey: card.id.tabKey,
                    dense: true,
                    tone: card.id == active ? palette.primary : null,
                    onPressed: () => controller.setActiveCard(panel, card.id),
                  ),
                ),
                if (card != cards.last)
                  const SizedBox(width: BoardTokens.gapSmall),
              ],
            ],
          ),
          const SizedBox(height: BoardTokens.gap),
          Expanded(
            child: active == null
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(BoardTokens.gap),
                    child: renderCard(context, active),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CardManager extends StatelessWidget {
  const _CardManager({required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) => AlertDialog(
        key: const Key('card-manager-dialog'),
        title: Text(Labels.of('cards-manager-title')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                Labels.of('cards-manager-description'),
                style: TextStyle(
                  fontSize: BoardTokens.fsCaption,
                  color: BoardTheme.of(context).fgMuted,
                ),
              ),
              const SizedBox(height: BoardTokens.gap),
              for (final CardDefinition definition in cardRegistry)
                _CardRow(controller: controller, definition: definition),
              const SizedBox(height: BoardTokens.gap),
              MicroHeading(Labels.of('layout-lanes')),
              const SizedBox(height: BoardTokens.gapSmall),
              for (final String lane in controller.layout.laneOrder)
                _LaneRow(controller: controller, lane: lane),
            ],
          ),
        ),
        actions: <Widget>[
          BoardAction(
            key: const Key('cards-restore'),
            labelKey: 'cards-restore',
            icon: Icons.restart_alt_rounded,
            dense: true,
            onPressed: controller.restoreCards,
          ),
          BoardAction(
            key: const Key('cards-manager-close'),
            labelKey: 'action-close',
            dense: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// One lane's place in the row. The reference drags a lane onto its neighbour; the dialog moves it one
/// step at a time so the keyboard reaches the same result.
class _LaneRow extends StatelessWidget {
  const _LaneRow({required this.controller, required this.lane});

  final BoardController controller;
  final String lane;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final List<String> order = controller.layout.laneOrder;
    final int index = order.indexOf(lane);
    return Padding(
      key: Key('lane-order-row-$lane'),
      padding: const EdgeInsets.only(bottom: BoardTokens.gapSmall),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              Labels.of('lane-$lane'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: BoardTokens.fsLabel,
                fontWeight: FontWeight.w600,
                color: palette.fg,
              ),
            ),
          ),
          BoardAction(
            key: Key('lane-earlier-$lane'),
            labelKey: 'layout-move-earlier',
            icon: Icons.arrow_back_rounded,
            dense: true,
            iconOnly: true,
            onPressed: index == 0
                ? null
                : () => controller.moveLane(lane, index - 1),
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          BoardAction(
            key: Key('lane-later-$lane'),
            labelKey: 'layout-move-later',
            icon: Icons.arrow_forward_rounded,
            dense: true,
            iconOnly: true,
            onPressed: index == order.length - 1
                ? null
                : () => controller.moveLane(lane, index + 1),
          ),
        ],
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.controller, required this.definition});

  final BoardController controller;
  final CardDefinition definition;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final CardConfig card = controller.cardConfig(definition.id);
    final String title = Labels.of(definition.id.titleKey);
    return Padding(
      key: Key('card-manager-row-${definition.id.name}'),
      padding: const EdgeInsets.only(bottom: BoardTokens.gapSmall),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: BoardTokens.fsLabel,
                    fontWeight: FontWeight.w600,
                    color: palette.fg,
                  ),
                ),
                Text(
                  card.collapsed
                      ? Labels.of('cards-collapsed')
                      : '${card.height.round()} px',
                  style: TextStyle(
                    fontSize: BoardTokens.fsCaption,
                    color: palette.fgFaint,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: BoardTokens.modeWidth,
            child: BoardDropdown<CardPanel>(
              key: Key('card-panel-${definition.id.name}'),
              labelKey: 'cards-panel',
              values: CardPanel.values,
              current: card.panel,
              label: (CardPanel panel) => Labels.of(
                panel == CardPanel.source
                    ? 'cards-panel-source'
                    : 'cards-panel-analysis',
              ),
              onChanged: (CardPanel panel) => controller.moveCardTo(
                definition.id,
                panel,
                controller.cardsIn(panel).length,
              ),
            ),
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          BoardAction(
            key: Key('card-visible-${definition.id.name}'),
            labelKey: card.visible ? 'cards-hide' : 'cards-show',
            labelArgs: <String, Object>{'title': title},
            icon: card.visible
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            dense: true,
            iconOnly: true,
            onPressed: () =>
                controller.setCardVisible(definition.id, !card.visible),
          ),
        ],
      ),
    );
  }
}
