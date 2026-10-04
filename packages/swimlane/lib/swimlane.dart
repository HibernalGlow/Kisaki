/// Multi-column swimlane strip, extracted from Rossi's workspace so other
/// products can use the same geometry.
///
/// Read `README.md` for the host-injection contract: the package owns the lane
/// model and its geometry, the host owns every pixel of lane content.
library;

export 'src/dwell.dart' show SwimlaneDwell;
export 'src/dwell_pump.dart' show SwimlaneDwellPump;
export 'src/lane_config.dart' show LaneConfig, LaneKind;
export 'src/lane_focus.dart' show SwimlaneFocusGeometry;
export 'src/lane_header_fit.dart'
    show LaneChrome, LaneHeaderFit, resolveLaneHeaderFit;
export 'src/lane_host.dart';
export 'src/strip_metrics.dart' show SwimlaneStripMetrics, SwimlaneStripSlot;
export 'src/swimlane_column.dart' show SwimlaneColumn;
export 'src/swimlane_interaction.dart' show SwimlaneInteraction;
export 'src/swimlane_layout.dart' show SwimlaneLayout;
export 'src/swimlane_resizer.dart' show SwimlaneResizer;
export 'src/swimlane_workspace.dart' show SwimlaneWorkspace;
