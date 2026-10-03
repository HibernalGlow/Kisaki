import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/filter_model.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// The multi-dimensional filter popover from `czkawka/filter-panel.tsx`.
///
/// Every section mutates the live state and pushes it back through the controller, because the
/// statistics line and the table have to move together while a control is being set.
class FilterPanel extends StatefulWidget {
  const FilterPanel({required this.controller, super.key});

  final BoardController controller;

  static Future<void> open(BuildContext context, BoardController controller) =>
      showDialog<void>(
        context: context,
        builder: (BuildContext context) => FilterPanel(controller: controller),
      );

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  String _presetName = '';
  String _transferText = '';
  String _presetError = '';

  ToolSpec? get _tool => widget.controller.tool;

  void _apply(FilterState next) => widget.controller.setFilters(next);

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final FilterState state = widget.controller.filters;
        final FilterStats stats = widget.controller.filterStats;
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(Labels.of('filter-title')),
              const SizedBox(height: BoardTokens.gapSmall),
              Text(
                Labels.of(
                  'filter-stats',
                  args: <String, Object>{
                    'filtered': stats.filteredItems,
                    'total': stats.totalItems,
                    'filteredGroups': stats.filteredGroups,
                    'totalGroups': stats.totalGroups,
                  },
                ),
                style: palette.text.bodySmall,
              ),
            ],
          ),
          actions: <Widget>[
            BoardAction(
              labelKey: 'filter-reset',
              onPressed: widget.controller.resetFilters,
            ),
            BoardAction(
              labelKey: 'action-close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          content: SizedBox(
            width: 520,
            height: 620,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BoardTokens.gap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Presets(
                    controller: widget.controller,
                    name: _presetName,
                    onName: (String value) =>
                        setState(() => _presetName = value),
                    onError: (String value) =>
                        setState(() => _presetError = value),
                    error: _presetError,
                    transfer: _transferText,
                    onTransfer: (String value) =>
                        setState(() => _transferText = value),
                  ),
                  _Section(
                    labelKey: 'filter-text-title',
                    children: <Widget>[
                      _SwitchRow(
                        labelKey: 'filter-text-enabled',
                        value: state.textEnabled,
                        onChanged: (bool value) =>
                            _apply(state.copy()..textEnabled = value),
                      ),
                      _Field(
                        keyName: 'filter-text-pattern',
                        labelKey: 'filter-text-placeholder',
                        value: state.textPattern,
                        onChanged: (String value) => _apply(
                          state.copy()
                            ..textPattern = value
                            ..textEnabled = value.trim().isNotEmpty,
                        ),
                      ),
                      Wrap(
                        spacing: BoardTokens.gapSmall,
                        children: <Widget>[
                          for (final TextFilterField field
                              in TextFilterField.values)
                            _Chip(
                              label: Labels.of(
                                'filter-text-field-${field.wire}',
                              ),
                              selected: state.textFields.contains(field),
                              onTap: () => _apply(
                                state.copy()
                                  ..textFields =
                                      state.textFields.contains(field)
                                      ? state.textFields
                                            .where(
                                              (TextFilterField item) =>
                                                  item != field,
                                            )
                                            .toList()
                                      : <TextFilterField>[
                                          ...state.textFields,
                                          field,
                                        ],
                              ),
                            ),
                        ],
                      ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _SwitchRow(
                              labelKey: 'filter-regex',
                              value: state.textRegex,
                              onChanged: (bool value) =>
                                  _apply(state.copy()..textRegex = value),
                            ),
                          ),
                          Expanded(
                            child: _SwitchRow(
                              labelKey: 'filter-case-sensitive',
                              value: state.textCaseSensitive,
                              onChanged: (bool value) => _apply(
                                state.copy()..textCaseSensitive = value,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.controller.filterPatternError.isNotEmpty)
                        _ErrorLine(widget.controller.filterPatternError),
                    ],
                  ),
                  _Section(
                    labelKey: 'filter-mark-title',
                    children: <Widget>[
                      _Dropdown<MarkFilter>(
                        keyName: 'filter-mark',
                        values: MarkFilter.values,
                        current: state.mark,
                        label: (MarkFilter mark) =>
                            Labels.of('filter-mark-${mark.wire}'),
                        onChanged: (MarkFilter mark) =>
                            _apply(state.copy()..mark = mark),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: _RangeSection(
                          labelKey: 'filter-group-count',
                          range: state.groupCount,
                          onChanged: (RangeFilter value) =>
                              _apply(state.copy()..groupCount = value),
                        ),
                      ),
                      const SizedBox(width: BoardTokens.gap),
                      Expanded(
                        child: _RangeSection(
                          labelKey: 'filter-group-size',
                          range: state.groupSize,
                          withUnit: true,
                          onChanged: (RangeFilter value) =>
                              _apply(state.copy()..groupSize = value),
                        ),
                      ),
                    ],
                  ),
                  _RangeSection(
                    labelKey: 'filter-file-size',
                    range: state.fileSize,
                    withUnit: true,
                    onChanged: (RangeFilter value) =>
                        _apply(state.copy()..fileSize = value),
                  ),
                  _Section(
                    labelKey: 'filter-extension-title',
                    children: <Widget>[
                      _SwitchRow(
                        labelKey: 'filter-extension-enabled',
                        value: state.extensionEnabled,
                        onChanged: (bool value) =>
                            _apply(state.copy()..extensionEnabled = value),
                      ),
                      Row(
                        children: <Widget>[
                          SizedBox(
                            width: 132,
                            child: _Dropdown<bool>(
                              keyName: 'filter-extension-mode',
                              values: const <bool>[true, false],
                              current: state.extensionMode,
                              label: (bool include) => Labels.of(
                                include
                                    ? 'filter-extension-include'
                                    : 'filter-extension-exclude',
                              ),
                              onChanged: (bool value) =>
                                  _apply(state.copy()..extensionMode = value),
                            ),
                          ),
                          const SizedBox(width: BoardTokens.gapSmall),
                          Expanded(
                            child: _Field(
                              keyName: 'filter-extension-list',
                              labelKey: 'filter-extension-placeholder',
                              value: state.extensions.join(', '),
                              onChanged: (String value) => _apply(
                                state.copy()
                                  ..extensions = _tokens(value)
                                  ..extensionEnabled = true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: BoardTokens.gapSmall,
                        runSpacing: BoardTokens.gapSmall,
                        children: <Widget>[
                          for (final CategoryStat category in stats.categories)
                            _Chip(
                              label:
                                  '${Labels.of('filter-category-${category.category.wire}')} '
                                  '${category.filteredCount}/${category.totalCount}',
                              selected: !state.excludedCategories.contains(
                                category.category,
                              ),
                              onTap: () => _apply(
                                state.copy()
                                  ..extensionEnabled = true
                                  ..excludedCategories = _toggled(
                                    state.excludedCategories,
                                    category.category,
                                  ),
                              ),
                            ),
                        ],
                      ),
                      Wrap(
                        spacing: BoardTokens.gapSmall,
                        runSpacing: BoardTokens.gapSmall,
                        children: <Widget>[
                          for (final ExtensionStat extension
                              in stats.extensions.take(10))
                            _Chip(
                              label:
                                  '${extension.extension == kNoExtension ? Labels.of('filter-extension-none') : extension.extension} '
                                  '${extension.filteredCount}/${extension.totalCount}',
                              selected: state.extensions.contains(
                                extension.extension,
                              ),
                              onTap: () => _apply(
                                state.copy()
                                  ..extensionEnabled = true
                                  ..extensions = _toggled(
                                    state.extensions,
                                    extension.extension,
                                  ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  _Section(
                    labelKey: 'filter-date-title',
                    children: <Widget>[
                      _SwitchRow(
                        labelKey: 'filter-date-enabled',
                        value: state.dateEnabled,
                        onChanged: (bool value) =>
                            _apply(state.copy()..dateEnabled = value),
                      ),
                      _Dropdown<DatePreset>(
                        keyName: 'filter-date-preset',
                        values: DatePreset.values,
                        current: state.datePreset,
                        label: (DatePreset preset) =>
                            Labels.of('filter-date-${preset.wire}'),
                        onChanged: (DatePreset value) =>
                            _apply(state.copy()..datePreset = value),
                      ),
                    ],
                  ),
                  _Section(
                    labelKey: 'filter-path-title',
                    children: <Widget>[
                      _SwitchRow(
                        labelKey: 'filter-path-enabled',
                        value: state.pathEnabled,
                        onChanged: (bool value) =>
                            _apply(state.copy()..pathEnabled = value),
                      ),
                      Row(
                        children: <Widget>[
                          SizedBox(
                            width: 132,
                            child: _Dropdown<PathMatchMode>(
                              keyName: 'filter-path-mode',
                              values: PathMatchMode.values,
                              current: state.pathMode,
                              label: (PathMatchMode mode) =>
                                  Labels.of('filter-path-${mode.wire}'),
                              onChanged: (PathMatchMode value) =>
                                  _apply(state.copy()..pathMode = value),
                            ),
                          ),
                          const SizedBox(width: BoardTokens.gapSmall),
                          Expanded(
                            child: _Field(
                              keyName: 'filter-path-pattern',
                              labelKey: 'filter-path-placeholder',
                              value: state.pathPattern,
                              onChanged: (String value) =>
                                  _apply(state.copy()..pathPattern = value),
                            ),
                          ),
                        ],
                      ),
                      _SwitchRow(
                        labelKey: 'filter-case-sensitive',
                        value: state.pathCaseSensitive,
                        onChanged: (bool value) =>
                            _apply(state.copy()..pathCaseSensitive = value),
                      ),
                    ],
                  ),
                  if (supportsSimilarityFilter(_tool))
                    _RangeSection(
                      labelKey: 'filter-similarity',
                      range: state.similarity,
                      onChanged: (RangeFilter value) =>
                          _apply(state.copy()..similarity = value),
                    ),
                  if (supportsResolutionFilter(_tool))
                    _Section(
                      labelKey: 'filter-resolution-title',
                      children: <Widget>[
                        _SwitchRow(
                          labelKey: 'filter-resolution-enabled',
                          value: state.resolutionEnabled,
                          onChanged: (bool value) =>
                              _apply(state.copy()..resolutionEnabled = value),
                        ),
                        Wrap(
                          spacing: BoardTokens.gap,
                          runSpacing: BoardTokens.gapSmall,
                          children: <Widget>[
                            _NumberField(
                              labelKey: 'filter-resolution-min-width',
                              value: state.minWidth,
                              onChanged: (int? value) =>
                                  _apply(state.copy()..minWidth = value),
                            ),
                            _NumberField(
                              labelKey: 'filter-resolution-min-height',
                              value: state.minHeight,
                              onChanged: (int? value) =>
                                  _apply(state.copy()..minHeight = value),
                            ),
                            _NumberField(
                              labelKey: 'filter-resolution-max-width',
                              value: state.maxWidth,
                              onChanged: (int? value) =>
                                  _apply(state.copy()..maxWidth = value),
                            ),
                            _NumberField(
                              labelKey: 'filter-resolution-max-height',
                              value: state.maxHeight,
                              onChanged: (int? value) =>
                                  _apply(state.copy()..maxHeight = value),
                            ),
                          ],
                        ),
                        _Dropdown<FilterAspectRatio>(
                          keyName: 'filter-resolution-aspect',
                          values: FilterAspectRatio.values,
                          current: state.aspectRatio,
                          label: (FilterAspectRatio ratio) =>
                              ratio == FilterAspectRatio.any
                              ? Labels.of('filter-resolution-any')
                              : ratio.wire,
                          onChanged: (FilterAspectRatio value) =>
                              _apply(state.copy()..aspectRatio = value),
                        ),
                      ],
                    ),
                  _SwitchRow(
                    labelKey: 'filter-show-whole-group',
                    value: state.showAllInFilteredGroups,
                    onChanged: (bool value) =>
                        _apply(state.copy()..showAllInFilteredGroups = value),
                  ),
                  const SizedBox(height: BoardTokens.gap),
                  Text(
                    Labels.of('filter-shortcuts'),
                    style: palette.text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Presets extends StatelessWidget {
  const _Presets({
    required this.controller,
    required this.name,
    required this.onName,
    required this.error,
    required this.onError,
    required this.transfer,
    required this.onTransfer,
  });

  final BoardController controller;
  final String name;
  final ValueChanged<String> onName;
  final String error;
  final ValueChanged<String> onError;
  final String transfer;
  final ValueChanged<String> onTransfer;

  @override
  Widget build(BuildContext context) {
    final List<FilterPreset> presets = controller.filterPresets;
    return _Section(
      labelKey: 'filter-presets-title',
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                container: true,
                label: Labels.of('filter-preset-select'),
                child: DropdownButtonFormField<String>(
                  key: const Key('filter-preset-select'),
                  initialValue: 'none',
                  isExpanded: true,
                  items: <DropdownMenuItem<String>>[
                    for (final BuiltinPreset preset in BuiltinPreset.values)
                      DropdownMenuItem(
                        value: preset.wire,
                        child: Text(Labels.of('filter-preset-${preset.wire}')),
                      ),
                    for (final FilterPreset preset in presets)
                      DropdownMenuItem(
                        value: preset.id,
                        child: Text(preset.name),
                      ),
                  ],
                  onChanged: (String? value) {
                    if (value == null) {
                      return;
                    }
                    for (final BuiltinPreset builtin in BuiltinPreset.values) {
                      if (builtin.wire == value) {
                        controller.applyBuiltinPreset(builtin);
                        return;
                      }
                    }
                    final FilterPreset? preset = presets
                        .where((FilterPreset item) => item.id == value)
                        .firstOrNull;
                    if (preset != null) {
                      controller.setFilters(preset.state.copy());
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: BoardTokens.gapSmall),
            BoardAction(
              key: const Key('filter-preset-delete'),
              labelKey: 'filter-preset-delete',
              onPressed: () => controller.removeFilterPreset(''),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _Field(
                keyName: 'filter-preset-name',
                labelKey: 'filter-preset-name-placeholder',
                value: name,
                onChanged: onName,
              ),
            ),
            const SizedBox(width: BoardTokens.gapSmall),
            BoardAction(
              key: const Key('filter-preset-save'),
              labelKey: 'filter-preset-save',
              onPressed: () {
                if (name.trim().isEmpty) {
                  onError(Labels.of('filter-preset-needs-name'));
                  return;
                }
                onError('');
                controller.saveFilterPreset(name);
              },
            ),
          ],
        ),
        Wrap(
          spacing: BoardTokens.gapSmall,
          runSpacing: BoardTokens.gapSmall,
          children: <Widget>[
            BoardAction(
              key: const Key('filter-preset-export'),
              labelKey: 'filter-preset-export',
              onPressed: () => onTransfer(controller.exportFilterPresets()),
            ),
            BoardAction(
              key: const Key('filter-preset-import'),
              labelKey: 'filter-preset-import',
              onPressed: () {
                if (!controller.importFilterPresets(transfer)) {
                  onError(Labels.of('filter-preset-unsupported'));
                  return;
                }
                onError('');
              },
            ),
          ],
        ),
        if (transfer.isNotEmpty)
          _Field(
            keyName: 'filter-preset-json',
            labelKey: 'filter-preset-json',
            value: transfer,
            multiline: true,
            onChanged: onTransfer,
          ),
        if (error.isNotEmpty) _ErrorLine(error),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.labelKey, required this.children});

  final String labelKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: Key(labelKey),
      title: Labels.of(labelKey),
      children: children,
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.labelKey,
    required this.value,
    required this.onChanged,
  });

  final String labelKey;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ToggleRow(
      key: Key(labelKey),
      labelKey: labelKey,
      value: value,
      onChanged: onChanged,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: BoardTokens.gapSmall,
            vertical: BoardTokens.gapSmall,
          ),
          decoration: BoxDecoration(
            color: selected ? palette.selection : Colors.transparent,
            border: Border.all(
              color: selected ? palette.primary : palette.border,
              width: BoardTokens.hairline,
            ),
          ),
          child: Text(label, style: palette.text.bodySmall),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.keyName,
    required this.labelKey,
    required this.value,
    required this.onChanged,
    this.multiline = false,
  });

  final String keyName;
  final String labelKey;
  final String value;
  final ValueChanged<String> onChanged;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return BoardField(
      key: Key(keyName),
      labelKey: labelKey,
      value: value,
      multiline: multiline,
      onChanged: onChanged,
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.labelKey,
    required this.value,
    required this.onChanged,
  });

  final String labelKey;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return SizedBox(
      width: 152,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(Labels.of(labelKey), style: palette.text.labelSmall),
          const SizedBox(height: BoardTokens.gapSmall),
          _Field(
            keyName: labelKey,
            labelKey: labelKey,
            value: value == null ? '' : '$value',
            onChanged: (String raw) {
              final int? parsed = int.tryParse(raw.trim());
              onChanged(parsed);
            },
          ),
        ],
      ),
    );
  }
}

class _RangeSection extends StatelessWidget {
  const _RangeSection({
    required this.labelKey,
    required this.range,
    required this.onChanged,
    this.withUnit = false,
  });

  final String labelKey;
  final RangeFilter range;
  final ValueChanged<RangeFilter> onChanged;
  final bool withUnit;

  @override
  Widget build(BuildContext context) {
    return _Section(
      labelKey: labelKey,
      children: <Widget>[
        _SwitchRow(
          labelKey: labelKey,
          value: range.enabled,
          onChanged: (bool value) => onChanged(
            RangeFilter(
              enabled: value,
              min: range.min,
              max: range.max,
              unit: range.unit,
            ),
          ),
        ),
        Wrap(
          spacing: BoardTokens.gapSmall,
          runSpacing: BoardTokens.gapSmall,
          children: <Widget>[
            _NumberField(
              labelKey: '$labelKey-min',
              value: range.min,
              onChanged: (int? value) => onChanged(
                RangeFilter(
                  enabled: range.enabled,
                  min: value,
                  max: range.max,
                  unit: range.unit,
                ),
              ),
            ),
            _NumberField(
              labelKey: '$labelKey-max',
              value: range.max,
              onChanged: (int? value) => onChanged(
                RangeFilter(
                  enabled: range.enabled,
                  min: range.min,
                  max: value,
                  unit: range.unit,
                ),
              ),
            ),
            if (withUnit)
              SizedBox(
                width: 96,
                child: _Dropdown<SizeUnit>(
                  keyName: '$labelKey-unit',
                  values: SizeUnit.values,
                  current: range.unit ?? SizeUnit.b,
                  label: (SizeUnit unit) => unit.wire,
                  onChanged: (SizeUnit unit) => onChanged(
                    RangeFilter(
                      enabled: range.enabled,
                      min: range.min,
                      max: range.max,
                      unit: unit,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.keyName,
    required this.values,
    required this.current,
    required this.label,
    required this.onChanged,
  });

  final String keyName;
  final List<T> values;
  final T current;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return BoardDropdown<T>(
      key: Key(keyName),
      labelKey: keyName,
      values: values,
      current: current,
      label: label,
      onChanged: onChanged,
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: BoardTokens.gapSmall),
      child: Text(
        message,
        key: const Key('filter-error'),
        style: palette.text.bodySmall?.copyWith(color: palette.danger),
      ),
    );
  }
}

List<String> _tokens(String value) => value
    .split(RegExp(r'[\s,;]+'))
    .map(
      (String item) =>
          item.trim().replaceFirst(RegExp(r'^\.'), '').toLowerCase(),
    )
    .where((String item) => item.isNotEmpty)
    .toSet()
    .toList();

List<T> _toggled<T>(List<T> current, T value) => current.contains(value)
    ? current.where((T item) => item != value).toList()
    : <T>[...current, value];
