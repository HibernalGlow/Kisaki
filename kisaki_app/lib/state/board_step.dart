import 'board_controller.dart';

/// The three stages the board walks through, in the order the reader meets them.
///
/// The lanes are the product's structure, so the stage is not a layout choice: it answers "where am
/// I in this task" from state that already exists.
enum BoardStep { source, results, analysis }

extension BoardStepNumber on BoardStep {
  /// Zero-padded, because the board numbers its stages the way the composition reference numbers its
  /// sections - `01`/`02`/`03` in a column can be scanned, `1`/`2`/`3` cannot.
  String get number => (index + 1).toString().padLeft(2, '0');
}

/// The stage that holds the work right now.
///
/// Derived on every build rather than stored: a saved "current step" could stay lit after the reader
/// scrolled away, and the whole point of the marker is that it cannot lie.
/// Analysis wins over results because a selection only exists once there are rows to select; a scan
/// in flight lights results even before its first row arrives.
BoardStep currentBoardStep(BoardController controller) {
  if (controller.selectedCount > 0) {
    return BoardStep.analysis;
  }
  if (controller.scanning || controller.rows.isNotEmpty) {
    return BoardStep.results;
  }
  return BoardStep.source;
}
