import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/selection_model.dart';
import '../theme/board_theme.dart';
import '../util/format.dart';
import 'widgets/primitives.dart';

/// The selection assistant from `czkawka/selection-assistant.tsx`.
///
/// Rules live on the controller rather than in this widget, so an apply, an undo, and an imported
/// document all drive the same state the table reads.
class AssistantPanel extends StatefulWidget {
  const AssistantPanel({required this.controller, super.key});

  final BoardController controller;

  static Future<void> open(BuildContext context, BoardController controller) =>
      showDialog<void>(
        context: context,
        builder: (BuildContext context) =>
            AssistantPanel(controller: controller),
      );

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  AssistantRuleKind _tab = AssistantRuleKind.group;
  String _transferText = '';
  final FocusNode _keys = FocusNode(debugLabel: 'kisaki-assistant-keys');

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  SelectionConfig get _config => widget.controller.assistant;

  void _patch({
    SelectionApplyMode? applyMode,
    GroupRule? group,
    TextRule? text,
    DirectoryRule? directory,
  }) {
    widget.controller.setAssistantConfig(
      _config.copyWith(
        applyMode: applyMode,
        group: group,
        text: text,
        directory: directory,
      ),
    );
  }

  void _setCriteria(List<SelectionSortCriterion> criteria) =>
      _patch(group: _config.group.copyWith(sortCriteria: criteria));

  void _updateCriterion(int index, SelectionSortCriterion next) {
    final List<SelectionSortCriterion> criteria =
        List<SelectionSortCriterion>.of(_config.group.sortCriteria);
    criteria[index] = next;
    _setCriteria(criteria);
  }

  void _moveCriterion(int index, int offset) {
    final int target = index + offset;
    final List<SelectionSortCriterion> criteria =
        List<SelectionSortCriterion>.of(_config.group.sortCriteria);
    if (target < 0 || target >= criteria.length) {
      return;
    }
    final SelectionSortCriterion moved = criteria.removeAt(index);
    criteria.insert(target, moved);
    _setCriteria(criteria);
  }

  void _addCriterion() {
    _setCriteria(<SelectionSortCriterion>[
      ..._config.group.sortCriteria,
      const SelectionSortCriterion(
        id: 'added',
        field: SelectionSortField.fileSize,
        direction: SortDirection.desc,
      ),
    ]);
  }

  void _removeCriterion(int index) {
    final List<SelectionSortCriterion> criteria =
        List<SelectionSortCriterion>.of(_config.group.sortCriteria)
          ..removeAt(index);
    _setCriteria(criteria);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final bool modifier =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!modifier) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      widget.controller.applyAssistantRule(_tab);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.controller.redoSelection();
      } else {
        widget.controller.undoSelection();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyY) {
      widget.controller.redoSelection();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.controller.clearSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final SelectionStats stats = widget.controller.assistantStats;
        final String message = widget.controller.assistantMessage;
        return Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(Labels.of('assistant-title')),
                const SizedBox(height: BoardTokens.gapSmall),
                Text(
                  Labels.of(
                    'assistant-summary',
                    args: <String, Object>{
                      'count': stats.selectedCount,
                      'size': humanBytes(stats.selectedBytes),
                      'reclaimable': humanBytes(stats.reclaimableBytes),
                    },
                  ),
                  style: palette.metricFigure(),
                ),
              ],
            ),
            actions: <Widget>[
              BoardAction(
                key: const Key('assistant-undo'),
                labelKey: 'assistant-undo',
                dense: true,
                onPressed: widget.controller.canUndoSelection
                    ? widget.controller.undoSelection
                    : null,
              ),
              BoardAction(
                key: const Key('assistant-redo'),
                labelKey: 'assistant-redo',
                dense: true,
                onPressed: widget.controller.canRedoSelection
                    ? widget.controller.redoSelection
                    : null,
              ),
              BoardAction(
                labelKey: 'action-close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
            content: SizedBox(
              width: (MediaQuery.sizeOf(context).width * 0.96).clamp(
                320.0,
                640.0,
              ),
              height: (MediaQuery.sizeOf(context).height * 0.72).clamp(
                320.0,
                620.0,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(BoardTokens.gap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SectionCard(
                      title: Labels.of('assistant-apply-title'),
                      children: <Widget>[
                        BoardDropdown<SelectionApplyMode>(
                          key: const Key('assistant-apply-mode'),
                          labelKey: 'assistant-apply-mode',
                          values: SelectionApplyMode.values,
                          current: _config.applyMode,
                          label: (SelectionApplyMode mode) =>
                              Labels.of('assistant-apply-${mode.wire}'),
                          onChanged: (SelectionApplyMode mode) =>
                              _patch(applyMode: mode),
                        ),
                      ],
                    ),
                    _Tabs(
                      current: _tab,
                      onChanged: (AssistantRuleKind kind) =>
                          setState(() => _tab = kind),
                    ),
                    switch (_tab) {
                      AssistantRuleKind.group => _GroupTab(
                        config: _config,
                        onMode: (GroupSelectionMode mode) =>
                            _patch(group: _config.group.copyWith(mode: mode)),
                        onAdd: _addCriterion,
                        onField: (int index, SelectionSortField field) =>
                            _updateCriterion(
                              index,
                              _config.group.sortCriteria[index].copyWith(
                                field: field,
                              ),
                            ),
                        onDirection: (int index, SortDirection direction) =>
                            _updateCriterion(
                              index,
                              _config.group.sortCriteria[index].copyWith(
                                direction: direction,
                              ),
                            ),
                        onEnabled: (int index, bool enabled) =>
                            _updateCriterion(
                              index,
                              _config.group.sortCriteria[index].copyWith(
                                enabled: enabled,
                              ),
                            ),
                        onCondition: (int index, MatchCondition condition) =>
                            _updateCriterion(
                              index,
                              _config.group.sortCriteria[index].copyWith(
                                filterCondition: condition,
                              ),
                            ),
                        onValue: (int index, String value) => _updateCriterion(
                          index,
                          _config.group.sortCriteria[index].copyWith(
                            filterValue: value,
                          ),
                        ),
                        onPreferEmpty: (int index, bool preferEmpty) =>
                            _updateCriterion(
                              index,
                              _config.group.sortCriteria[index].copyWith(
                                preferEmpty: preferEmpty,
                              ),
                            ),
                        onMove: _moveCriterion,
                        onRemove: _removeCriterion,
                        onApply: () => widget.controller.applyAssistantRule(
                          AssistantRuleKind.group,
                        ),
                      ),
                      AssistantRuleKind.text => _TextTab(
                        config: _config,
                        onColumn: (SelectionTextColumn column) =>
                            _patch(text: _config.text.copyWith(column: column)),
                        onCondition: (MatchCondition condition) => _patch(
                          text: _config.text.copyWith(condition: condition),
                        ),
                        onPattern: (String pattern) => _patch(
                          text: _config.text.copyWith(pattern: pattern),
                        ),
                        onRegex: (bool useRegex) => _patch(
                          text: _config.text.copyWith(useRegex: useRegex),
                        ),
                        onCaseSensitive: (bool caseSensitive) => _patch(
                          text: _config.text.copyWith(
                            caseSensitive: caseSensitive,
                          ),
                        ),
                        onWholeColumn: (bool whole) => _patch(
                          text: _config.text.copyWith(matchWholeColumn: whole),
                        ),
                        onApply: () => widget.controller.applyAssistantRule(
                          AssistantRuleKind.text,
                        ),
                      ),
                      AssistantRuleKind.directory => _DirectoryTab(
                        config: _config,
                        onMode: (DirectorySelectionMode mode) => _patch(
                          directory: _config.directory.copyWith(mode: mode),
                        ),
                        onPaths: (String text) => _patch(
                          directory: _config.directory.copyWith(
                            directories: _lines(text),
                          ),
                        ),
                        onApply: () => widget.controller.applyAssistantRule(
                          AssistantRuleKind.directory,
                        ),
                      ),
                    },
                    const SizedBox(height: BoardTokens.gap),
                    SectionCard(
                      title: Labels.of('assistant-actions-title'),
                      children: <Widget>[
                        Wrap(
                          spacing: BoardTokens.gapSmall,
                          runSpacing: BoardTokens.gapSmall,
                          children: <Widget>[
                            BoardAction(
                              key: const Key('assistant-select-all'),
                              labelKey: 'assistant-select-all',
                              dense: true,
                              onPressed: widget.controller.visibleRows.isEmpty
                                  ? null
                                  : widget.controller.selectAllAssistantEntries,
                            ),
                            BoardAction(
                              key: const Key('assistant-invert'),
                              labelKey: 'assistant-invert',
                              dense: true,
                              onPressed: widget.controller.visibleRows.isEmpty
                                  ? null
                                  : widget.controller.invertAssistantSelection,
                            ),
                            BoardAction(
                              key: const Key('assistant-clear'),
                              labelKey: 'action-clear',
                              dense: true,
                              onPressed: widget.controller.selectedCount == 0
                                  ? null
                                  : widget.controller.clearSelection,
                            ),
                          ],
                        ),
                        const SizedBox(height: BoardTokens.gapSmall),
                        Wrap(
                          spacing: BoardTokens.gapSmall,
                          runSpacing: BoardTokens.gapSmall,
                          children: <Widget>[
                            BoardAction(
                              key: const Key('assistant-export'),
                              labelKey: 'assistant-export',
                              dense: true,
                              onPressed: () => setState(
                                () => _transferText = widget.controller
                                    .exportAssistant(),
                              ),
                            ),
                            BoardAction(
                              key: const Key('assistant-import'),
                              labelKey: 'assistant-import',
                              dense: true,
                              onPressed: () => widget.controller
                                  .importAssistant(_transferText),
                            ),
                            BoardAction(
                              key: const Key('assistant-reset'),
                              labelKey: 'assistant-reset',
                              dense: true,
                              onPressed: widget.controller.resetAssistant,
                            ),
                          ],
                        ),
                        if (_transferText.isNotEmpty) ...<Widget>[
                          const SizedBox(height: BoardTokens.gapSmall),
                          BoardField(
                            key: const Key('assistant-transfer'),
                            labelKey: 'assistant-transfer',
                            value: _transferText,
                            multiline: true,
                            onChanged: (String value) =>
                                setState(() => _transferText = value),
                          ),
                        ],
                      ],
                    ),
                    if (message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: BoardTokens.gapSmall,
                        ),
                        child: Text(
                          message,
                          key: const Key('assistant-message'),
                          style: palette.text.bodySmall?.copyWith(
                            color: widget.controller.assistantMessageIsError
                                ? palette.danger
                                : palette.fgMuted,
                          ),
                        ),
                      ),
                    Text(
                      Labels.of('assistant-shortcuts'),
                      style: palette.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onChanged});

  final AssistantRuleKind current;
  final ValueChanged<AssistantRuleKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: BoardTokens.gap),
      child: Row(
        children: <Widget>[
          for (final AssistantRuleKind kind in AssistantRuleKind.values)
            Expanded(
              child: BoardAction(
                key: Key('assistant-tab-${kind.wire}'),
                labelKey: 'assistant-tab-${kind.wire}',
                dense: true,
                tone: kind == current ? palette.primary : null,
                onPressed: () => onChanged(kind),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupTab extends StatelessWidget {
  const _GroupTab({
    required this.config,
    required this.onMode,
    required this.onAdd,
    required this.onField,
    required this.onDirection,
    required this.onEnabled,
    required this.onCondition,
    required this.onValue,
    required this.onPreferEmpty,
    required this.onMove,
    required this.onRemove,
    required this.onApply,
  });

  final SelectionConfig config;
  final ValueChanged<GroupSelectionMode> onMode;
  final VoidCallback onAdd;
  final void Function(int index, SelectionSortField field) onField;
  final void Function(int index, SortDirection direction) onDirection;
  final void Function(int index, bool enabled) onEnabled;
  final void Function(int index, MatchCondition condition) onCondition;
  final void Function(int index, String value) onValue;
  final void Function(int index, bool preferEmpty) onPreferEmpty;
  final void Function(int index, int offset) onMove;
  final ValueChanged<int> onRemove;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final List<SelectionSortCriterion> criteria = config.group.sortCriteria;
    return SectionCard(
      title: Labels.of('assistant-group-title'),
      children: <Widget>[
        BoardDropdown<GroupSelectionMode>(
          key: const Key('assistant-group-mode'),
          labelKey: 'assistant-group-mode',
          values: GroupSelectionMode.values,
          current: config.group.mode,
          label: (GroupSelectionMode mode) =>
              Labels.of('assistant-group-${mode.wire}'),
          onChanged: onMode,
        ),
        for (int index = 0; index < criteria.length; index++)
          _CriterionCard(
            index: index,
            criterion: criteria[index],
            last: index == criteria.length - 1,
            onField: (SelectionSortField field) => onField(index, field),
            onDirection: (SortDirection direction) =>
                onDirection(index, direction),
            onEnabled: (bool enabled) => onEnabled(index, enabled),
            onCondition: (MatchCondition condition) =>
                onCondition(index, condition),
            onValue: (String value) => onValue(index, value),
            onPreferEmpty: (bool preferEmpty) =>
                onPreferEmpty(index, preferEmpty),
            onMove: (int offset) => onMove(index, offset),
            onRemove: () => onRemove(index),
          ),
        BoardAction(
          key: const Key('assistant-add-criterion'),
          labelKey: 'assistant-add-criterion',
          dense: true,
          onPressed: onAdd,
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        BoardAction(
          key: const Key('assistant-apply-group'),
          labelKey: 'assistant-apply-group',
          onPressed: onApply,
        ),
      ],
    );
  }
}

class _CriterionCard extends StatelessWidget {
  const _CriterionCard({
    required this.index,
    required this.criterion,
    required this.last,
    required this.onField,
    required this.onDirection,
    required this.onEnabled,
    required this.onCondition,
    required this.onValue,
    required this.onPreferEmpty,
    required this.onMove,
    required this.onRemove,
  });

  final int index;
  final SelectionSortCriterion criterion;
  final bool last;
  final ValueChanged<SelectionSortField> onField;
  final ValueChanged<SortDirection> onDirection;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<MatchCondition> onCondition;
  final ValueChanged<String> onValue;
  final ValueChanged<bool> onPreferEmpty;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  String get _suffix => '$index';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BoardTokens.gapSmall),
      child: FlatCard(
        child: Padding(
          padding: const EdgeInsets.all(BoardTokens.gapSmall),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: BoardTokens.gapSmall,
                runSpacing: BoardTokens.gapSmall,
                children: <Widget>[
                  SizedBox(
                    width: BoardTokens.fieldWidth,
                    child: BoardDropdown<SelectionSortField>(
                      key: Key('assistant-criterion-field-$_suffix'),
                      labelKey: 'assistant-criterion-field',
                      values: SelectionSortField.values,
                      current: criterion.field,
                      label: (SelectionSortField field) =>
                          Labels.of('assistant-field-${_kebab(field.wire)}'),
                      onChanged: onField,
                    ),
                  ),
                  SizedBox(
                    width: BoardTokens.directionWidth,
                    child: BoardDropdown<SortDirection>(
                      key: Key('assistant-criterion-direction-$_suffix'),
                      labelKey: 'assistant-criterion-direction',
                      values: SortDirection.values,
                      current: criterion.direction,
                      label: (SortDirection direction) =>
                          Labels.of('assistant-direction-${direction.wire}'),
                      onChanged: onDirection,
                    ),
                  ),
                  BoardAction(
                    key: Key('assistant-criterion-up-$_suffix'),
                    labelKey: 'assistant-move-up',
                    dense: true,
                    onPressed: index == 0 ? null : () => onMove(-1),
                  ),
                  BoardAction(
                    key: Key('assistant-criterion-down-$_suffix'),
                    labelKey: 'assistant-move-down',
                    dense: true,
                    onPressed: last ? null : () => onMove(1),
                  ),
                  BoardAction(
                    key: Key('assistant-criterion-delete-$_suffix'),
                    labelKey: 'assistant-delete-criterion',
                    dense: true,
                    onPressed: onRemove,
                  ),
                ],
              ),
              const SizedBox(height: BoardTokens.gapSmall),
              Row(
                children: <Widget>[
                  SizedBox(
                    width: BoardTokens.modeWidth,
                    child: BoardDropdown<MatchCondition>(
                      key: Key('assistant-criterion-condition-$_suffix'),
                      labelKey: 'assistant-criterion-condition',
                      values: MatchCondition.values,
                      current: criterion.filterCondition,
                      label: (MatchCondition condition) =>
                          Labels.of('assistant-condition-${condition.wire}'),
                      onChanged: onCondition,
                    ),
                  ),
                  const SizedBox(width: BoardTokens.gapSmall),
                  Expanded(
                    child: BoardField(
                      key: Key('assistant-criterion-value-$_suffix'),
                      labelKey: 'assistant-criterion-value',
                      value: criterion.filterValue,
                      enabled: criterion.filterCondition != MatchCondition.none,
                      onChanged: onValue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BoardTokens.gapSmall),
              ToggleRow(
                key: Key('assistant-criterion-enabled-$_suffix'),
                labelKey: 'assistant-criterion-enabled',
                value: criterion.enabled,
                onChanged: onEnabled,
              ),
              ToggleRow(
                key: Key('assistant-criterion-prefer-empty-$_suffix'),
                labelKey: 'assistant-prefer-empty',
                value: criterion.preferEmpty,
                onChanged: onPreferEmpty,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextTab extends StatelessWidget {
  const _TextTab({
    required this.config,
    required this.onColumn,
    required this.onCondition,
    required this.onPattern,
    required this.onRegex,
    required this.onCaseSensitive,
    required this.onWholeColumn,
    required this.onApply,
  });

  final SelectionConfig config;
  final ValueChanged<SelectionTextColumn> onColumn;
  final ValueChanged<MatchCondition> onCondition;
  final ValueChanged<String> onPattern;
  final ValueChanged<bool> onRegex;
  final ValueChanged<bool> onCaseSensitive;
  final ValueChanged<bool> onWholeColumn;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final TextRule rule = config.text;
    return SectionCard(
      title: Labels.of('assistant-text-title'),
      children: <Widget>[
        BoardDropdown<SelectionTextColumn>(
          key: const Key('assistant-text-column'),
          labelKey: 'assistant-text-column',
          values: SelectionTextColumn.values,
          current: rule.column,
          label: (SelectionTextColumn column) =>
              Labels.of('assistant-text-${_kebab(column.wire)}'),
          onChanged: onColumn,
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        BoardDropdown<MatchCondition>(
          key: const Key('assistant-text-condition'),
          labelKey: 'assistant-text-condition',
          values: MatchCondition.values
              .where((MatchCondition item) => item != MatchCondition.none)
              .toList(),
          current: rule.condition,
          label: (MatchCondition condition) =>
              Labels.of('assistant-condition-${condition.wire}'),
          onChanged: onCondition,
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        BoardField(
          key: const Key('assistant-text-pattern'),
          labelKey: 'assistant-text-pattern',
          value: rule.pattern,
          onChanged: onPattern,
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        ToggleRow(
          key: const Key('assistant-text-regex'),
          labelKey: 'assistant-regex',
          value: rule.useRegex,
          onChanged: onRegex,
        ),
        ToggleRow(
          key: const Key('assistant-text-case'),
          labelKey: 'filter-case-sensitive',
          value: rule.caseSensitive,
          onChanged: onCaseSensitive,
        ),
        ToggleRow(
          key: const Key('assistant-text-whole'),
          labelKey: 'assistant-text-whole',
          value: rule.matchWholeColumn,
          onChanged: onWholeColumn,
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        BoardAction(
          key: const Key('assistant-apply-text'),
          labelKey: 'assistant-apply-text',
          onPressed: rule.pattern.isEmpty ? null : onApply,
        ),
      ],
    );
  }
}

class _DirectoryTab extends StatelessWidget {
  const _DirectoryTab({
    required this.config,
    required this.onMode,
    required this.onPaths,
    required this.onApply,
  });

  final SelectionConfig config;
  final ValueChanged<DirectorySelectionMode> onMode;
  final ValueChanged<String> onPaths;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final DirectoryRule rule = config.directory;
    return SectionCard(
      title: Labels.of('assistant-directory-title'),
      children: <Widget>[
        BoardDropdown<DirectorySelectionMode>(
          key: const Key('assistant-directory-mode'),
          labelKey: 'assistant-directory-mode',
          values: DirectorySelectionMode.values,
          current: rule.mode,
          label: (DirectorySelectionMode mode) =>
              Labels.of('assistant-directory-${mode.wire}'),
          onChanged: onMode,
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        BoardField(
          key: const Key('assistant-directory-paths'),
          labelKey: 'assistant-directory-placeholder',
          value: rule.directories.join('\n'),
          multiline: true,
          onChanged: onPaths,
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        Text(
          Labels.of('assistant-directory-protected'),
          style: palette.text.bodySmall,
        ),
        const SizedBox(height: BoardTokens.gapSmall),
        BoardAction(
          key: const Key('assistant-apply-directory'),
          labelKey: 'assistant-apply-directory',
          onPressed: onApply,
        ),
      ],
    );
  }
}

List<String> _lines(String value) => <String>{
  for (final String line in value.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
}.toList();

/// Keeps the label namespace kebab-cased, the way the Fluent files the app will grow into are.
String _kebab(String wire) => wire.replaceAllMapped(
  RegExp('[A-Z]'),
  (Match match) => '-${match[0]!.toLowerCase()}',
);
