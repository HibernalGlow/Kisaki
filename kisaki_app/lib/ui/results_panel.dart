import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// Middle lane: header strip, sticky column header, row list, and the empty states.
class ResultsPanel extends StatelessWidget {
  const ResultsPanel({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ResultsHeader(controller: controller),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool grouped = controller.tool?.grouped ?? false;
              final List<double> widths = tableWidths(
                constraints.maxWidth.isFinite ? constraints.maxWidth : 900,
                controller.tool,
                grouped,
              );
              final double total = widths.fold<double>(
                0,
                (double sum, double value) => sum + value,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: total,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (controller.visibleRows.isNotEmpty) ...<Widget>[
                        ColumnHeader(controller: controller, widths: widths),
                        const Hairline(),
                      ],
                      Expanded(
                        child: _Rows(controller: controller, widths: widths),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BoardTokens.pad,
        vertical: BoardTokens.gapSmall,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${Labels.of('header-results')}  ${controller.rows.length}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: BoardTokens.fsLabel,
                fontWeight: FontWeight.w700,
                color: palette.fgMuted,
              ),
            ),
          ),
          Flexible(
            flex: 2,
            child: Wrap(
              spacing: BoardTokens.gapSmall,
              runSpacing: BoardTokens.gapSmall,
              alignment: WrapAlignment.end,
              children: <Widget>[
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: const Key('results-filter'),
                    style: TextStyle(
                      fontSize: BoardTokens.fsLabel,
                      color: palette.fg,
                    ),
                    decoration: InputDecoration(
                      hintText: Labels.of('placeholder-filter'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: BoardTokens.gap,
                        vertical: 6,
                      ),
                    ),
                    onChanged: controller.setFilter,
                  ),
                ),
                BoardAction(
                  key: const Key('select-all'),
                  labelKey: 'action-select-all',
                  dense: true,
                  onPressed: controller.visibleRows.isEmpty
                      ? null
                      : controller.selectAllVisible,
                ),
                BoardAction(
                  key: const Key('clear-selection'),
                  labelKey: 'action-clear',
                  dense: true,
                  onPressed: controller.selectedCount == 0
                      ? null
                      : controller.clearSelection,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Column widths: fixed chrome first, then the surplus split by each column's flex.
List<double> tableWidths(double available, ToolSpec? tool, bool grouped) {
  final List<ColumnDef> columns = tool?.columns ?? const <ColumnDef>[];
  final List<double> chrome = <double>[
    BoardTokens.colSelect,
    if (grouped) BoardTokens.colGroup,
    BoardTokens.colName,
  ];
  final List<double> minimums = <double>[
    ...chrome,
    ...columns.map((ColumnDef column) => column.minWidth),
  ];
  final double fixed = minimums.fold<double>(
    0,
    (double sum, double value) => sum + value,
  );
  final double surplus = available - fixed;
  if (surplus <= 0) {
    return minimums;
  }

  const double nameFlex = 1.4;
  final double flexSum =
      nameFlex +
      columns.fold<double>(
        0,
        (double sum, ColumnDef column) => sum + column.flex,
      );
  final List<double> widths = <double>[];
  for (int index = 0; index < chrome.length; index++) {
    final bool isName = index == chrome.length - 1;
    widths.add(chrome[index] + (isName ? surplus * (nameFlex / flexSum) : 0));
  }
  for (final ColumnDef column in columns) {
    widths.add(column.minWidth + surplus * (column.flex / flexSum));
  }
  return widths;
}

class ColumnHeader extends StatelessWidget {
  const ColumnHeader({
    required this.controller,
    required this.widths,
    super.key,
  });

  final BoardController controller;
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final ToolSpec? tool = controller.tool;
    final bool grouped = tool?.grouped ?? false;
    final List<Widget> cells = <Widget>[
      SizedBox(
        width: widths[0],
        height: 28,
        child: ColoredBox(color: palette.sunken),
      ),
      if (grouped) _cell(widths[1], palette, Labels.of('col-group')),
      _sortCell(palette, widths[grouped ? 2 : 1], Labels.of('col-name'), -1),
    ];
    for (int column = 0; column < (tool?.columns.length ?? 0); column++) {
      final ColumnDef def = tool!.columns[column];
      cells.add(
        _sortCell(
          palette,
          widths[(grouped ? 3 : 2) + column],
          Labels.of(def.labelKey),
          column,
          alignRight: def.alignRight,
        ),
      );
    }
    return SizedBox(height: 28, child: Row(children: cells));
  }

  Widget _cell(double width, BoardPalette palette, String text) => SizedBox(
    width: width,
    height: 28,
    child: ColoredBox(
      color: palette.sunken,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BoardTokens.gapSmall),
        child: MicroHeading(text),
      ),
    ),
  );

  Widget _sortCell(
    BoardPalette palette,
    double width,
    String text,
    int column, {
    bool alignRight = false,
  }) {
    final bool active = controller.sortColumn == column;
    return GestureDetector(
      key: Key('column-header-$text'),
      behavior: HitTestBehavior.opaque,
      onTap: () => controller.toggleSort(column),
      child: SizedBox(
        width: width,
        height: 28,
        child: ColoredBox(
          color: palette.sunken,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BoardTokens.gapSmall,
            ),
            child: Row(
              mainAxisAlignment: alignRight
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: <Widget>[
                Flexible(
                  child: MicroHeading(
                    text,
                    color: active ? palette.primary : null,
                  ),
                ),
                if (active)
                  Icon(
                    controller.sortAscending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 11,
                    color: palette.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.controller, required this.widths});

  final BoardController controller;
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    final List<ScanRow> visible = controller.visibleRows;
    if (visible.isEmpty) {
      return _EmptyRegion(controller: controller);
    }
    final bool grouped = controller.tool?.grouped ?? false;
    return ListView.builder(
      key: const Key('results-list'),
      padding: EdgeInsets.zero,
      itemCount: visible.length,
      itemBuilder: (BuildContext context, int index) {
        final ScanRow row = visible[index];
        return Column(
          children: <Widget>[
            if (grouped && row.isGroupStart)
              _GroupStrip(controller: controller, row: row, widths: widths),
            _ResultRow(controller: controller, row: row, widths: widths),
          ],
        );
      },
    );
  }
}

class _GroupStrip extends StatelessWidget {
  const _GroupStrip({
    required this.controller,
    required this.row,
    required this.widths,
  });

  final BoardController controller;
  final ScanRow row;
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final bool allSelected =
        controller.groupSelection(row.groupIndex) == GroupSelection.all;
    return Container(
      color: palette.sunken,
      padding: const EdgeInsets.symmetric(
        horizontal: BoardTokens.gapSmall,
        vertical: 4,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 12,
            color: palette.chartByIndex(row.groupIndex),
          ),
          const SizedBox(width: BoardTokens.gapSmall),
          // Colour is never the only signal, so the group number is printed.
          Text(
            '${Labels.of('col-group')} ${row.groupIndex + 1}',
            style: TextStyle(
              fontSize: BoardTokens.fsCaption,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: palette.fgMuted,
            ),
          ),
          const SizedBox(width: BoardTokens.gap),
          Text(
            '${row.groupSize}',
            style: TextStyle(
              fontSize: BoardTokens.fsCaption,
              color: palette.fgFaint,
            ),
          ),
          BoardAction(
            key: Key('group-toggle-${row.groupIndex}'),
            labelKey: 'action-select-group',
            dense: true,
            tone: allSelected ? palette.primary : null,
            onPressed: () => controller.toggleGroup(row.groupIndex),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.controller,
    required this.row,
    required this.widths,
  });

  final BoardController controller;
  final ScanRow row;
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final ToolSpec? tool = controller.tool;
    final List<ColumnDef> columns = tool?.columns ?? const <ColumnDef>[];
    final bool selected = controller.isSelected(row);
    int offset = 0;

    final List<Widget> cells = <Widget>[
      SizedBox(
        width: widths[offset++],
        child: Checkbox(
          key: Key('row-select-${row.path}'),
          value: selected,
          onChanged: (_) => controller.toggleSelected(row),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    ];
    if (tool != null && tool.grouped) {
      cells.add(
        SizedBox(
          width: widths[offset++],
          child: Center(
            child: Text(
              '${row.groupIndex + 1}',
              style: TextStyle(
                fontSize: BoardTokens.fsLabel,
                color: palette.fgFaint,
              ),
            ),
          ),
        ),
      );
    }
    cells.add(
      SizedBox(
        width: widths[offset++],
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BoardTokens.gapSmall,
            vertical: 6,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: BoardTokens.fsBody,
                        fontWeight: FontWeight.w600,
                        color: selected ? palette.primary : palette.fg,
                      ),
                    ),
                  ),
                  if (row.isReference) ...<Widget>[
                    const SizedBox(width: BoardTokens.gapSmall),
                    _RefBadge(),
                  ],
                ],
              ),
              Text(
                row.directory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: BoardTokens.fsCaption,
                  color: palette.fgFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    for (int column = 0; column < columns.length; column++) {
      final String text = column < row.cells.length ? row.cells[column] : '';
      cells.add(
        SizedBox(
          width: widths[offset++],
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BoardTokens.gapSmall,
            ),
            child: Align(
              alignment: columns[column].alignRight
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: BoardTokens.fsLabel,
                  color: palette.fg,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      key: Key('result-row-${row.path}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => controller.toggleSelected(row),
      child: Container(
        height: BoardTokens.rowHeight,
        decoration: BoxDecoration(
          color: selected ? palette.selection : Colors.transparent,
          border: Border(bottom: BorderSide(color: palette.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cells,
        ),
      ),
    );
  }
}

class _RefBadge extends StatelessWidget {
  const _RefBadge();
  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: palette.warn),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        Labels.of('badge-reference'),
        style: TextStyle(
          fontSize: BoardTokens.fsCaption,
          fontWeight: FontWeight.w700,
          color: palette.warn,
        ),
      ),
    );
  }
}

class _EmptyRegion extends StatelessWidget {
  const _EmptyRegion({required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.rows.isNotEmpty) {
      return const EmptyState(labelKey: 'empty-filtered');
    }
    return switch (controller.phase) {
      ScanPhase.running ||
      ScanPhase.stopping => const EmptyState(labelKey: 'empty-running'),
      ScanPhase.failed => EmptyState(
        labelKey: 'empty-error',
        detail: controller.critical,
      ),
      ScanPhase.finished => const EmptyState(labelKey: 'empty-done'),
      ScanPhase.idle => EmptyState(
        labelKey: 'empty-idle',
        detail: controller.included.isEmpty ? Labels.of('empty-paths') : null,
      ),
    };
  }
}
