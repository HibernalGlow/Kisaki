import 'package:flutter/material.dart';

import '../l10n/labels.dart';
import '../state/activity_log.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';
import 'widgets/primitives.dart';

/// The board's own record of scans and file operations, from `czkawka/activity-log.tsx`.
///
/// Newest first, because the question this panel answers is what just happened. The reference also
/// keeps the log across sessions through the node store; Kisaki has no settings slot for it yet, so
/// the log covers the running board.
class ActivityLogPanel extends StatelessWidget {
  const ActivityLogPanel({required this.controller, super.key});

  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        final List<ActivityEntry> entries = controller.activityLog;
        final List<ActivityEntry> shown = controller.filteredActivity;
        return SectionCard(
          title: Labels.of('activity-title'),
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '${shown.length}/${entries.length}',
                  key: const Key('activity-count'),
                  style: palette.tableFigure(color: palette.fgMuted),
                ),
                const Spacer(),
                BoardAction(
                  key: const Key('activity-copy'),
                  labelKey: 'activity-copy',
                  icon: Icons.copy_all_outlined,
                  dense: true,
                  onPressed: entries.isEmpty
                      ? null
                      : controller.copyActivityLog,
                ),
                const SizedBox(width: BoardTokens.gapSmall),
                BoardAction(
                  key: const Key('activity-clear'),
                  labelKey: 'activity-clear',
                  icon: Icons.delete_sweep_outlined,
                  dense: true,
                  onPressed: entries.isEmpty
                      ? null
                      : controller.clearActivityLog,
                ),
              ],
            ),
            const SizedBox(height: BoardTokens.gapSmall),
            TextField(
              key: const Key('activity-filter'),
              style: TextStyle(
                fontSize: BoardTokens.fsLabel,
                color: palette.fg,
              ),
              decoration: InputDecoration(
                hintText: Labels.of('activity-placeholder'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: BoardTokens.gap,
                  vertical: BoardTokens.gapSmall,
                ),
              ),
              onChanged: controller.setActivityQuery,
            ),
            const SizedBox(height: BoardTokens.gapSmall),
            if (shown.isEmpty)
              Text(
                Labels.of('activity-empty'),
                key: const Key('activity-empty'),
                style: palette.text.bodySmall,
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  key: const Key('activity-log'),
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _Entry(entry: shown[shown.length - 1 - index]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final BoardPalette palette = BoardTheme.of(context);
    final Color rule = switch (entry.level) {
      ActivityLevel.error => palette.danger,
      ActivityLevel.warning => palette.warn,
      ActivityLevel.success => palette.ok,
      ActivityLevel.info => palette.fgFaint,
    };
    return Padding(
      key: Key('activity-entry-${entry.id}'),
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: formatActivityEntry(entry),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(width: 3, height: 26, color: rule),
            const SizedBox(width: BoardTokens.gapSmall),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${_clock(entry.timestamp)} \u00b7 ${entry.tool}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: palette.text.bodySmall?.copyWith(
                      color: palette.fgMuted,
                    ),
                  ),
                  Text(
                    // The level marker keeps the severity readable without the rule colour; the
                    // percentage already has its own column, so it is not repeated here.
                    formatActivityMessage(entry.level, entry.message),
                    style: palette.text.bodySmall,
                  ),
                  if (entry.affectedCount != null)
                    Text(
                      Labels.of(
                        'activity-result',
                        args: <String, Object>{
                          'affected': entry.affectedCount!,
                          'errors': entry.errorCount ?? 0,
                        },
                      ),
                      style: palette.text.bodySmall?.copyWith(
                        color: palette.fgFaint,
                      ),
                    ),
                ],
              ),
            ),
            if (entry.progress != null)
              Text(
                '${entry.progress}%',
                style: palette.tableFigure(color: palette.fgMuted),
              ),
            if (entry.progress == null)
              Text(
                entry.kind.wire,
                style: palette.text.bodySmall?.copyWith(color: palette.fgFaint),
              ),
          ],
        ),
      ),
    );
  }

  String _clock(int millis) {
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}
