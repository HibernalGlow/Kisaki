import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';
import 'simiu_panel.dart';
import 'scan_preset_card.dart';
import 'token_list.dart';
import 'widgets/primitives.dart';

/// Left lane: shared path/filter block plus the schema-driven option fields.
class SourcePanel extends StatelessWidget {
  const SourcePanel({required this.controller, this.picker, super.key});

  final BoardController controller;
  final PathPicker? picker;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TabBar(
            tabs: <Widget>[
              Tab(text: Labels.of('tab-paths')),
              Tab(text: Labels.of('tab-algorithm')),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _PathsTab(controller: controller, picker: picker),
                _AlgorithmTab(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One editable path/filter list, bound to the controller by closures.
class _BlockSpec {
  const _BlockSpec({
    required this.labelKey,
    required this.placeholder,
    required this.entries,
    required this.add,
    required this.removeAt,
    required this.clear,
  });

  final String labelKey;
  final String placeholder;
  final List<String> Function() entries;
  final void Function(Iterable<String>) add;
  final void Function(int) removeAt;
  final VoidCallback clear;
}

class _PathsTab extends StatelessWidget {
  const _PathsTab({required this.controller, required this.picker});

  final BoardController controller;
  final PathPicker? picker;

  Future<void> _pick(
    BuildContext context,
    PathRequest request,
    void Function(Iterable<String>) apply,
  ) async {
    final List<String>? paths = picker != null
        ? await picker!(context, request)
        : await showManualPathSheet(context);
    if (paths != null && paths.isNotEmpty) {
      apply(paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ToolSpec? tool = controller.tool;
    final List<_BlockSpec> blocks = <_BlockSpec>[
      _BlockSpec(
        labelKey: 'label-excluded',
        placeholder: '/home/user/.cache',
        entries: () => controller.excludedPaths,
        add: controller.addExcludedPath,
        removeAt: controller.removeExcludedPath,
        clear: controller.clearExcludedPaths,
      ),
      _BlockSpec(
        labelKey: 'label-excluded-items',
        placeholder: '*/.git/*',
        entries: () => controller.excludedItems,
        add: controller.addExcludedItem,
        removeAt: controller.removeExcludedItem,
        clear: controller.clearExcludedItems,
      ),
      _BlockSpec(
        labelKey: 'label-allowed-ext',
        placeholder: 'jpg',
        entries: () => controller.allowedExtensions,
        add: controller.addAllowedExtension,
        removeAt: controller.removeAllowedExtension,
        clear: controller.clearAllowedExtensions,
      ),
      _BlockSpec(
        labelKey: 'label-excluded-ext',
        placeholder: 'tmp',
        entries: () => controller.excludedExtensions,
        add: controller.addExcludedExtension,
        removeAt: controller.removeExcludedExtension,
        clear: controller.clearExcludedExtensions,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(BoardTokens.pad),
      children: <Widget>[
        _IncludedBlock(
          controller: controller,
          onPick: (PathRequest request) =>
              _pick(context, request, controller.addIncluded),
        ),
        if (tool != null && tool.supportsReference) ...<Widget>[
          const SizedBox(height: BoardTokens.gap),
          const Hairline(),
          const SizedBox(height: BoardTokens.gap),
          _ReferenceBlock(
            controller: controller,
            onPick: (PathRequest request) =>
                _pick(context, request, controller.addReference),
          ),
        ],
        for (final _BlockSpec block in blocks) ...<Widget>[
          const SizedBox(height: BoardTokens.gap),
          _Block(block: block),
        ],
        const SizedBox(height: BoardTokens.gap),
        const Hairline(),
        const SizedBox(height: BoardTokens.gap),
        ToggleRow(
          labelKey: 'label-recursive',
          value: controller.recursive,
          onChanged: controller.setRecursive,
        ),
        ToggleRow(
          labelKey: 'label-cache',
          value: controller.useCache,
          onChanged: controller.setUseCache,
        ),
        const SizedBox(height: BoardTokens.gap),
        Row(
          children: <Widget>[
            Expanded(
              child: _SizeField(
                labelKey: 'label-min-size',
                value: controller.minSizeKib,
                onChanged: controller.setMinSize,
              ),
            ),
            const SizedBox(width: BoardTokens.gap),
            Expanded(
              child: _SizeField(
                labelKey: 'label-max-size',
                value: controller.maxSizeKib,
                onChanged: controller.setMaxSize,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IncludedBlock extends StatelessWidget {
  const _IncludedBlock({required this.controller, required this.onPick});

  final BoardController controller;
  final ValueChanged<PathRequest> onPick;

  @override
  Widget build(BuildContext context) {
    return _Block(
      block: _BlockSpec(
        labelKey: 'label-included',
        placeholder: '/home/user/Downloads',
        entries: () => controller.included,
        add: controller.addIncluded,
        removeAt: controller.removeIncluded,
        clear: controller.clearIncluded,
      ),
      footer: Wrap(
        spacing: BoardTokens.gapSmall,
        runSpacing: BoardTokens.gapSmall,
        children: <Widget>[
          BoardAction(
            labelKey: 'action-add-dirs',
            dense: true,
            onPressed: () => onPick(PathRequest.directory),
          ),
          BoardAction(
            labelKey: 'action-add-files',
            dense: true,
            onPressed: () => onPick(PathRequest.file),
          ),
        ],
      ),
    );
  }
}

class _ReferenceBlock extends StatelessWidget {
  const _ReferenceBlock({required this.controller, required this.onPick});

  final BoardController controller;
  final ValueChanged<PathRequest> onPick;

  @override
  Widget build(BuildContext context) {
    return _Block(
      block: _BlockSpec(
        labelKey: 'label-reference',
        placeholder: '/reference/set',
        entries: () => controller.reference,
        add: controller.addReference,
        removeAt: controller.removeReference,
        clear: controller.clearReference,
      ),
      footer: BoardAction(
        labelKey: 'action-add-dirs',
        dense: true,
        onPressed: () => onPick(PathRequest.directory),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block, this.footer});

  final _BlockSpec block;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TokenListEditor(
          label: Labels.of(block.labelKey),
          entries: block.entries(),
          placeholder: block.placeholder,
          onAdd: (String value) => block.add(<String>[value]),
          onRemoveAt: block.removeAt,
          onClear: block.clear,
        ),
        if (footer != null) ...<Widget>[
          const SizedBox(height: BoardTokens.gapSmall),
          footer!,
        ],
      ],
    );
  }
}

class _SizeField extends StatefulWidget {
  const _SizeField({
    required this.labelKey,
    required this.value,
    required this.onChanged,
  });

  final String labelKey;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_SizeField> createState() => _SizeFieldState();
}

class _SizeFieldState extends State<_SizeField> {
  final TextEditingController _text = TextEditingController(text: '');

  @override
  void initState() {
    super.initState();
    _text.text = widget.value;
  }

  @override
  void didUpdateWidget(_SizeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _text.text) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MicroHeading(Labels.of(widget.labelKey)),
        const SizedBox(height: BoardTokens.gapSmall),
        TextField(
          key: Key('size-field-${widget.labelKey}'),
          controller: _text,
          keyboardType: TextInputType.number,
          style: TextStyle(fontSize: BoardTokens.fsBody, color: palette.fg),
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}

class _AlgorithmTab extends StatelessWidget {
  const _AlgorithmTab({required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final List<FieldDef> fields = controller.fields;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BoardTokens.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (controller.supportsSimiuSets) ...<Widget>[
            SimiuFields(controller: controller),
            const SizedBox(height: BoardTokens.section),
          ],
          if (fields.isEmpty && !controller.supportsSimiuSets)
            const EmptyState(labelKey: 'label-no-options')
          else
            for (int index = 0; index < fields.length; index++) ...<Widget>[
              if (index > 0) const SizedBox(height: BoardTokens.gap),
              FieldControl(
                key: ValueKey<String>(
                  '${controller.tool?.id}-${fields[index].id}',
                ),
                def: fields[index],
                value: controller.valueOf(fields[index].id),
                onChanged: (FieldPayload payload) =>
                    controller.setFieldValue(fields[index].id, payload),
              ),
            ],
          const SizedBox(height: BoardTokens.section),
          ScanPresetCard(
            controller: controller,
            key: const Key('scan-presets'),
          ),
        ],
      ),
    );
  }
}

/// Renders one option from its declared kind, so a new engine field needs no UI change.
class FieldControl extends StatelessWidget {
  const FieldControl({
    required this.def,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final FieldDef def;
  final FieldValue value;
  final ValueChanged<FieldPayload> onChanged;

  @override
  Widget build(BuildContext context) {
    final FieldPayload payload = value.value;
    switch (def.kind) {
      case FieldKind.flag:
        return ToggleRow(
          labelKey: def.labelKey,
          value: payload is FieldPayloadFlag ? payload.value : false,
          onChanged: (bool next) => onChanged(FieldPayloadFlag(next)),
        );
      case FieldKind.choice:
        return _ChoiceField(
          def: def,
          selected: payload is FieldPayloadChoice ? payload.value : '',
          onChanged: onChanged,
        );
      case FieldKind.integer:
        return _IntegerField(
          def: def,
          number: payload is FieldPayloadInteger ? payload.value : 0,
          onChanged: onChanged,
        );
      case FieldKind.text:
        return _TextFieldControl(
          def: def,
          text: payload is FieldPayloadText ? payload.value : '',
          onChanged: onChanged,
        );
      case FieldKind.tokenList:
        return _TokenField(
          def: def,
          tokens: payload is FieldPayloadTokens
              ? payload.value
              : const <String>[],
          onChanged: onChanged,
        );
    }
  }
}

class _ChoiceField extends StatelessWidget {
  const _ChoiceField({
    required this.def,
    required this.selected,
    required this.onChanged,
  });

  final FieldDef def;
  final String selected;
  final ValueChanged<FieldPayload> onChanged;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MicroHeading(Labels.of(def.labelKey)),
        const SizedBox(height: BoardTokens.gapSmall),
        Wrap(
          spacing: BoardTokens.gapSmall,
          runSpacing: BoardTokens.gapSmall,
          children: def.options.map((String option) {
            final bool active = option == selected;
            return GestureDetector(
              key: Key('choice-${def.id}-$option'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(FieldPayloadChoice(option)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: BoardTokens.gap,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: active ? palette.primary : palette.raised,
                  borderRadius: BorderRadius.circular(BoardTokens.radius),
                  border: Border.all(
                    color: active ? palette.primary : palette.border,
                  ),
                ),
                child: Text(
                  Labels.of(option),
                  style: TextStyle(
                    fontSize: BoardTokens.fsLabel,
                    fontWeight: FontWeight.w600,
                    color: active ? palette.fgInverted : palette.fg,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _IntegerField extends StatefulWidget {
  const _IntegerField({
    required this.def,
    required this.number,
    required this.onChanged,
  });

  final FieldDef def;
  final int number;
  final ValueChanged<FieldPayload> onChanged;

  @override
  State<_IntegerField> createState() => _IntegerFieldState();
}

class _IntegerFieldState extends State<_IntegerField> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.text = '${widget.number}';
  }

  @override
  void didUpdateWidget(_IntegerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (int.tryParse(_text.text) != widget.number) {
      _text.text = '${widget.number}';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MicroHeading(Labels.of(widget.def.labelKey)),
        const SizedBox(height: BoardTokens.gapSmall),
        TextField(
          key: Key('field-${widget.def.id}'),
          controller: _text,
          keyboardType: TextInputType.number,
          style: TextStyle(fontSize: BoardTokens.fsBody, color: palette.fg),
          onChanged: (String raw) => widget.onChanged(
            FieldPayloadInteger(int.tryParse(raw.trim()) ?? 0),
          ),
        ),
        Text(
          '${widget.def.min} .. ${widget.def.max}',
          style: TextStyle(
            fontSize: BoardTokens.fsCaption,
            color: palette.fgFaint,
          ),
        ),
      ],
    );
  }
}

class _TextFieldControl extends StatefulWidget {
  const _TextFieldControl({
    required this.def,
    required this.text,
    required this.onChanged,
  });

  final FieldDef def;
  final String text;
  final ValueChanged<FieldPayload> onChanged;

  @override
  State<_TextFieldControl> createState() => _TextFieldControlState();
}

class _TextFieldControlState extends State<_TextFieldControl> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.text = widget.text;
  }

  @override
  void didUpdateWidget(_TextFieldControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _text.text) {
      _text.text = widget.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MicroHeading(Labels.of(widget.def.labelKey)),
        const SizedBox(height: BoardTokens.gapSmall),
        TextField(
          key: Key('field-${widget.def.id}'),
          controller: _text,
          style: TextStyle(fontSize: BoardTokens.fsBody, color: palette.fg),
          onChanged: (String value) =>
              widget.onChanged(FieldPayloadText(value)),
        ),
      ],
    );
  }
}

class _TokenField extends StatefulWidget {
  const _TokenField({
    required this.def,
    required this.tokens,
    required this.onChanged,
  });

  final FieldDef def;
  final List<String> tokens;
  final ValueChanged<FieldPayload> onChanged;

  @override
  State<_TokenField> createState() => _TokenFieldState();
}

class _TokenFieldState extends State<_TokenField> {
  late List<String> _local = List<String>.of(widget.tokens);

  @override
  void didUpdateWidget(_TokenField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.def.id != widget.def.id) {
      _local = List<String>.of(widget.tokens);
    }
  }

  void _emit() => widget.onChanged(FieldPayloadTokens(List<String>.of(_local)));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TokenListEditor(
          label: Labels.of(widget.def.labelKey),
          entries: _local,
          placeholder: 'jpg',
          onAdd: (String token) {
            setState(() => _local.add(token));
            _emit();
          },
          onRemoveAt: (int index) {
            setState(() => _local.removeAt(index));
            _emit();
          },
          onClear: () {
            setState(() => _local.clear());
            _emit();
          },
        ),
      ],
    );
  }
}
