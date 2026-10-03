import 'package:flutter/material.dart';

import '../engine/models.dart' show ScanRow;
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';

/// Right-click actions for one result row, from `czkawka/result-table.tsx`.
///
/// The reference also offers open, reveal and copy-file, but only when the host supplies those
/// callbacks; Kisaki has no file-manager bridge yet, so the menu ships the actions that work.
enum RowAction { selectGroup, clearGroup, copyPath, copyName }

Future<void> showRowMenu({
  required BuildContext context,
  required BoardController controller,
  required ScanRow row,
  required Offset position,
}) async {
  final BoardPalette palette = BoardTheme.of(context);
  final bool grouped = row.groupIndex >= 0;
  final bool groupWhole =
      grouped &&
      controller.groupSelection(row.groupIndex) == GroupSelection.all;

  final List<PopupMenuEntry<RowAction>> entries = <PopupMenuEntry<RowAction>>[];
  if (grouped) {
    entries.add(
      _item(
        RowAction.selectGroup,
        'row-menu-select-group',
        enabled: !groupWhole,
        palette: palette,
      ),
    );
    entries.add(
      _item(
        RowAction.clearGroup,
        'row-menu-clear-group',
        enabled: groupWhole,
        palette: palette,
      ),
    );
    entries.add(const PopupMenuDivider());
  }
  entries.add(
    _item(
      RowAction.copyPath,
      'row-menu-copy-path',
      enabled: true,
      palette: palette,
    ),
  );
  entries.add(
    _item(
      RowAction.copyName,
      'row-menu-copy-name',
      enabled: true,
      palette: palette,
    ),
  );

  final RowAction? choice = await showMenu<RowAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx + 1,
      position.dy + 1,
    ),
    // Swiss law: a menu is a flat panel with a hairline, never a lifted card.
    elevation: 0,
    color: palette.card,
    shape: Border.all(color: palette.border, width: 1),
    items: entries,
  );
  if (choice == null) {
    return;
  }
  switch (choice) {
    case RowAction.selectGroup:
      controller.setGroupSelected(row.groupIndex, true);
    case RowAction.clearGroup:
      controller.setGroupSelected(row.groupIndex, false);
    case RowAction.copyPath:
      await controller.copyText(row.path);
    case RowAction.copyName:
      await controller.copyText(row.name);
  }
}

PopupMenuItem<RowAction> _item(
  RowAction value,
  String labelKey, {
  required bool enabled,
  required BoardPalette palette,
}) => PopupMenuItem<RowAction>(
  key: Key('row-menu-${value.name}'),
  value: value,
  enabled: enabled,
  height: 28,
  child: Text(
    Labels.of(labelKey),
    style: TextStyle(
      fontSize: BoardTokens.fsLabel,
      color: enabled ? palette.fg : palette.fgFaint,
    ),
  ),
);
