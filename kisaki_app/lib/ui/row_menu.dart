import 'package:flutter/material.dart';

import '../engine/models.dart' show ScanRow;
import '../l10n/labels.dart';
import '../state/board_controller.dart';
import '../theme/board_theme.dart';

/// Right-click actions for one result row, from `czkawka/result-table.tsx`.
///
/// The three host actions - open, reveal and copy the file object - are listed exactly as the
/// reference lists them: always present, disabled when the embedding host has no callback for them,
/// and saying why for copy-file the way its tooltip does. A dead item that explains itself beats an
/// absent one the reader never learns about.
enum RowAction {
  selectGroup,
  clearGroup,
  copyPath,
  copyName,
  copyFiles,
  open,
  reveal,
}

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
  entries.add(
    _item(
      RowAction.copyFiles,
      'row-menu-copy-files',
      enabled: controller.canCopyFiles,
      disabledReasonKey: controller.canCopyFiles
          ? null
          : 'row-menu-copy-files-unsupported',
      palette: palette,
    ),
  );
  entries.add(const PopupMenuDivider());
  entries.add(
    _item(
      RowAction.open,
      'row-menu-open',
      enabled: controller.canOpenFiles,
      palette: palette,
    ),
  );
  entries.add(
    _item(
      RowAction.reveal,
      'row-menu-reveal',
      enabled: controller.canRevealFiles,
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
    case RowAction.open:
      await controller.openPath(row.path);
    case RowAction.reveal:
      await controller.revealPath(row.path);
    case RowAction.copyPath:
      await controller.copyText(row.path);
    case RowAction.copyName:
      await controller.copyText(row.name);
    case RowAction.copyFiles:
      await controller.copyFilesToClipboard(<String>[row.path]);
  }
}

PopupMenuItem<RowAction> _item(
  RowAction value,
  String labelKey, {
  required bool enabled,
  required BoardPalette palette,
  String? disabledReasonKey,
}) {
  final Text label = Text(
    Labels.of(labelKey),
    style: TextStyle(
      fontSize: BoardTokens.fsLabel,
      color: enabled ? palette.fg : palette.fgFaint,
    ),
  );
  return PopupMenuItem<RowAction>(
    key: Key('row-menu-${value.name}'),
    value: value,
    enabled: enabled,
    height: 28,
    child: disabledReasonKey == null
        ? label
        : Tooltip(message: Labels.of(disabledReasonKey), child: label),
  );
}
