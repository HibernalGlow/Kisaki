import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/row_projection.dart';
import '../theme/board_theme.dart';
import 'assistant_panel.dart';
import 'comparison_view.dart';
import 'filter_panel.dart';
import 'row_menu.dart';
import 'similar_folders_view.dart';
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
        if (controller.supportsFolderView) ...<Widget>[
          FoldersViewSwitch(controller: controller),
          const Hairline(),
        ],
        Expanded(
          child: controller.folderView
              ? SimilarFoldersView(controller: controller)
              : LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool grouped = controller.tool?.grouped ?? false;
                    final List<double> widths = tableWidths(
                      constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : 900,
                      controller.tool,
                      grouped,
                      overrides: controller.columnWidths,
                    );
                    final double total = widths.fold<double>(
                      0,
                      (double sum, double value) => sum + value,
                    );
                    // The roll-up above owns the full lane width, so only the table gets the
                    // horizontal scroller - folder rows must not inherit column widths.
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: total,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (controller.visibleRows.isNotEmpty) ...<Widget>[
                              ColumnHeader(
                                controller: controller,
                                widths: widths,
                              ),
                              const Hairline(),
                            ],
                            Expanded(
                              child: _Rows(
                                controller: controller,
                                widths: widths,
                              ),
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
                        vertical: BoardTokens.gapSmall,
                      ),
                    ),
                    onChanged: controller.setFilter,
                  ),
                ),
                BoardAction(
                  key: const Key('open-filters'),
                  labelKey: 'filter-filter',
                  dense: true,
                  tone: controller.filters.activeCount > 0
                      ? palette.primary
                      : null,
                  onPressed: () => FilterPanel.open(context, controller),
                ),
                if (controller.filters.activeCount > 0)
                  Text(
                    '${controller.filters.activeCount}',
                    key: const Key('active-filter-count'),
                    style: palette.text.labelSmall,
                  ),
                // An explicit reset beats a hidden double-tap: the drag recognizer owns the pointer
                // on the hairline, so a tap there never reaches a double-tap handler.
                if (controller.columnWidths.isNotEmpty)
                  BoardAction(
                    key: const Key('reset-columns'),
                    labelKey: 'action-reset-columns',
                    dense: true,
                    onPressed: controller.resetColumnWidths,
                  ),
                BoardAction(
                  key: const Key('open-comparison'),
                  labelKey: 'action-compare',
                  dense: true,
                  onPressed:
                      controller.canCompareSelection &&
                          controller.selectedRows.isNotEmpty
                      ? () => ComparisonView.open(
                          context,
                          controller,
                          controller.selectedRows.first,
                        )
                      : null,
                ),
                BoardAction(
                  key: const Key('open-assistant'),
                  labelKey: 'assistant-title',
                  dense: true,
                  onPressed: () => AssistantPanel.open(context, controller),
                ),
                if (controller.selectedCount > 0)
                  Text(
                    '${controller.selectedCount}',
                    key: const Key('assistant-selected-count'),
                    style: palette.tableFigure(),
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
///
/// A column the reader dragged keeps that width through a `tool:key` entry in [overrides]; the
/// chrome columns are addressable too, so the name column can be widened the same way.
List<double> tableWidths(
  double available,
  ToolSpec? tool,
  bool grouped, {
  Map<String, double> overrides = const <String, double>{},
}) {
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
  final List<double> widths = surplus <= 0
      ? minimums
      : _flexed(chrome, columns, surplus);
  return _applyOverrides(widths, tool, grouped, columns, overrides);
}

List<double> _flexed(
  List<double> chrome,
  List<ColumnDef> columns,
  double surplus,
) {
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

List<double> _applyOverrides(
  List<double> widths,
  ToolSpec? tool,
  bool grouped,
  List<ColumnDef> columns,
  Map<String, double> overrides,
) {
  final List<String> keys = <String>[
    'select',
    if (grouped) 'group',
    'name',
    ...columns.map((ColumnDef column) => column.key),
  ];
  final String prefix = '${tool?.id ?? ''}:';
  for (int index = 0; index < widths.length && index < keys.length; index++) {
    final double? wanted = overrides['$prefix${keys[index]}'];
    if (wanted != null) {
      widths[index] = wanted;
    }
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
      _sortCell(
        palette,
        widths[grouped ? 2 : 1],
        Labels.of('col-name'),
        -1,
        resizeKey: 'name',
        minWidth: BoardTokens.colName,
      ),
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
          resizeKey: def.key,
          minWidth: def.minWidth,
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
    required String resizeKey,
    required double minWidth,
  }) {
    final bool active = controller.sortColumn == column;
    return SizedBox(
      width: width,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          GestureDetector(
            key: Key('column-header-$text'),
            behavior: HitTestBehavior.opaque,
            onTap: () => controller.toggleSort(column),
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
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _ResizeStrip(
              controller: controller,
              resizeKey: resizeKey,
              width: width,
              minWidth: minWidth,
            ),
          ),
        ],
      ),
    );
  }
}

/// The hairline a reader drags to widen a column; a double-tap gives the column back to the layout.
class _ResizeStrip extends StatefulWidget {
  const _ResizeStrip({
    required this.controller,
    required this.resizeKey,
    required this.width,
    required this.minWidth,
  });

  final BoardController controller;
  final String resizeKey;
  final double width;
  final double minWidth;

  @override
  State<_ResizeStrip> createState() => _ResizeStripState();
}

class _ResizeStripState extends State<_ResizeStrip> {
  double? _startWidth;
  double? _originX;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: Key('column-resize-${widget.resizeKey}'),
        behavior: HitTestBehavior.opaque,
        // The drag recognizer stays silent until the pointer passes its slop, so the press point is
        // taken from the down event: the column then tracks the pointer instead of lagging behind it.
        onHorizontalDragDown: (DragDownDetails details) {
          _startWidth = widget.width;
          _originX = details.globalPosition.dx;
        },
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          final double? from = _startWidth;
          final double? origin = _originX;
          if (from == null || origin == null) {
            return;
          }
          widget.controller.setColumnWidth(
            widget.resizeKey,
            from + (details.globalPosition.dx - origin),
            widget.minWidth,
          );
        },
        onHorizontalDragEnd: (_) {
          _startWidth = null;
          _originX = null;
        },
        child: ColoredBox(
          color: palette.border,
          child: const SizedBox(width: 3),
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
      final ColumnDef definition = columns[column];
      final String text = displayCell(definition, row, column);
      cells.add(
        SizedBox(
          width: widths[offset++],
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BoardTokens.gapSmall,
            ),
            child: Align(
              alignment: definition.alignRight
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Right-aligned columns are the numeric ones, and they are set in tabular figures.
                style: definition.alignRight
                    ? palette.tableFigure()
                    : TextStyle(
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
      onSecondaryTapDown: (TapDownDetails details) => showRowMenu(
        context: context,
        controller: controller,
        row: row,
        position: details.globalPosition,
      ),
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
