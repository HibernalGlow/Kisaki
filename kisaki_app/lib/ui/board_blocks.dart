import 'package:flutter/material.dart';

import '../state/board_controller.dart';
import '../state/card_layout.dart';
import 'activity_log_panel.dart';
import 'analysis_blocks.dart';
import 'source_panel.dart';
import 'token_list.dart' show PathPicker;

/// Says what each card holds, so a lane, the docked panel and the float all show the same block.
Widget boardCard({
  required BoardController controller,
  required CardId id,
  PathPicker? picker,
}) => switch (id) {
  CardId.sourceSettings => SourcePanel(controller: controller, picker: picker),
  CardId.preview => PreviewBlock(controller: controller),
  CardId.analysis => AnalysisSummaryBlock(controller: controller),
  CardId.logs => ActivityLogPanel(
    controller: controller,
    key: const Key('activity-card'),
  ),
  CardId.selection => SelectionBlock(controller: controller),
  CardId.operations => OperationsBlock(controller: controller),
};
