import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/models.dart';
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../state/row_projection.dart';
import '../state/row_selection.dart';
import '../theme/board_theme.dart';
import 'assistant_panel.dart';
import 'comparison_images.dart';
import 'comparison_view.dart';
import 'filter_panel.dart';
import 'preview_panel.dart';
import 'preview_view.dart';
import 'row_menu.dart';
import 'similar_folders_view.dart';
import 'widgets/primitives.dart';

part 'results_panel_rows.dart';

/// Middle lane: header strip, sticky column header, row list, and the empty states.
class ResultsPanel extends StatelessWidget {
  const ResultsPanel({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The header strip wraps its controls onto more runs as the text grows, and an uncapped Wrap
        // measured 438 tall in a narrow lane - it ate the table down to 3 pixels. So the strip is the
        // child that gives way first, and it scrolls its own overflow instead of spending the rows.
        Flexible(
          child: SingleChildScrollView(
            child: _ResultsHeader(controller: controller),
          ),
        ),
        _ScanNotice(controller: controller),
        if (controller.supportsFolderView) ...<Widget>[
          FoldersViewSwitch(controller: controller),
          const Hairline(),
        ],
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: controller.folderView
                    ? SimilarFoldersView(controller: controller)
                    : LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints constraints) {
                              final bool grouped =
                                  controller.tool?.grouped ?? false;
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
                              // The roll-up above owns the full lane width, so only the table gets
                              // the horizontal scroller - folder rows must not inherit column widths.
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: total,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      if (controller
                                          .visibleRows
                                          .isNotEmpty) ...<Widget>[
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
              if (controller.previewPanelOpen)
                PreviewPanel(controller: controller),
            ],
          ),
        ),
      ],
    );
  }
}

/// The reference keeps a stopped or failed scan visible above the rows it did return, with the
/// rescan one click away. With no rows the empty region already says the same thing.
class _ScanNotice extends StatelessWidget {
  const _ScanNotice({required this.controller});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final ScanPhase phase = controller.phase;
        if (controller.rows.isEmpty) {
          return const SizedBox.shrink();
        }
        // A scan that ended normally has nothing to warn about; a stopped one kept its rows and the
        // failed one keeps whatever was already on screen.
        final bool stopped =
            phase == ScanPhase.finished &&
            (controller.outcome?.stopped ?? false);
        final bool failed = phase == ScanPhase.failed;
        if (!stopped && !failed) {
          return const SizedBox.shrink();
        }
        if (failed && controller.confirm != null) {
          // The confirm overlay owns the screen while it is open.
          return const SizedBox.shrink();
        }
        return Container(
          key: const Key('scan-notice'),
          decoration: BoxDecoration(
            color: failed ? palette.dangerSoft : palette.sunken,
            border: Border(bottom: BorderSide(color: palette.hairline)),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: BoardTokens.pad,
            vertical: BoardTokens.gapSmall,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.stop_circle_outlined,
                size: 14,
                color: failed ? palette.danger : palette.fgMuted,
              ),
              const SizedBox(width: BoardTokens.gapSmall),
              Expanded(
                child: Text(
                  failed
                      ? (controller.critical ?? controller.statusText)
                      : controller.statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: palette.text.bodySmall,
                ),
              ),
              const SizedBox(width: BoardTokens.gapSmall),
              BoardAction(
                key: const Key('rescan-scan'),
                labelKey: 'result-rescan',
                icon: Icons.refresh_rounded,
                dense: true,
                onPressed: controller.scanning ? null : controller.refreshScan,
              ),
            ],
          ),
        );
      },
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
                  key: const Key('pin-preview'),
                  labelKey: 'preview-panel-pin',
                  dense: true,
                  tone: controller.pinnedPreview ? palette.primary : null,
                  onPressed: controller.previewPaths.isEmpty
                      ? null
                      : controller.togglePinnedPreview,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Tooltip(
                        message: Labels.of('label-thumbnails'),
                        child: Text(
                          Labels.of('label-thumbnails'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: palette.text.labelSmall,
                        ),
                      ),
                    ),
                    Switch(
                      key: const Key('toggle-thumbnails'),
                      value: controller.showThumbnails,
                      onChanged: controller.setShowThumbnails,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Tooltip(
                        message: Labels.of('label-reverse-path'),
                        child: Text(
                          Labels.of('label-reverse-path'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: palette.text.labelSmall,
                        ),
                      ),
                    ),
                    Switch(
                      key: const Key('toggle-reverse-path'),
                      value: controller.reversePath,
                      onChanged: controller.setReversePath,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: Tooltip(
                        message: Labels.of('label-wrap-text'),
                        child: Text(
                          Labels.of('label-wrap-text'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: palette.text.labelSmall,
                        ),
                      ),
                    ),
                    Switch(
                      key: const Key('toggle-wrap-text'),
                      value: controller.wrapText,
                      onChanged: controller.setWrapText,
                    ),
                  ],
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
