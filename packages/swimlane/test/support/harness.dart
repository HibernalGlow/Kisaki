import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swimlane/swimlane.dart';

/// The lane set the assertions run against.
///
/// Widths, bands and titles are Rossi's `WorkspaceLayoutConfig.defaults()`
/// (`rossi/lib/workspace/model/workspace_layout_config.dart`): left 380 (300..700),
/// reader 650 with ratio 0.5 (400..2000), right 360 (280..620). Using his numbers
/// means the geometry is exercised on the values it was written for, and a 1600px
/// viewport is his own capture size.
LaneConfig laneA() =>
    LaneConfig(width: 380, minWidth: 300, maxWidth: 700, title: 'Alpha');

LaneConfig laneB() => LaneConfig(
  width: 650,
  widthRatio: 0.5,
  minWidth: 400,
  maxWidth: 2000,
  title: 'Beta',
  kind: LaneKind.reader,
);

LaneConfig laneC() =>
    LaneConfig(width: 360, minWidth: 280, maxWidth: 620, title: 'Gamma');

SwimlaneLayout threeLanes({
  bool aCollapsed = false,
  bool cCollapsed = false,
  String? soloLaneId,
}) {
  return SwimlaneLayout(
    laneOrder: const <String>['a', 'b', 'c'],
    lanes: <String, LaneConfig>{
      'a': laneA().copyWith(collapsed: aCollapsed),
      'b': laneB(),
      'c': laneC().copyWith(collapsed: cCollapsed),
    },
    soloLaneId: soloLaneId,
  );
}

/// Calls into the host's lane builder, so a test can show that moving the
/// interaction does not rebuild any lane content.
final List<String> contentBuilds = <String>[];

/// Lane content that reports its own taps: the workspace eats the first click on a
/// non-active lane, and only this list can tell "the click was eaten" from "the
/// click was delivered".
final List<String> contentTaps = <String>[];

Widget laneContent(BuildContext context, SwimlaneLaneInfo lane) {
  contentBuilds.add(lane.laneId);
  return ColoredBox(
    color: Colors.white,
    child: Center(
      child: GestureDetector(
        key: ValueKey<String>('lane-content-${lane.laneId}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => contentTaps.add(lane.laneId),
        child: const SizedBox(
          width: 40,
          height: 20,
          child: ColoredBox(color: Colors.black12),
        ),
      ),
    ),
  );
}

/// A host that owns the state, exactly as the package expects its callers to.
///
/// Every mutation arrives as a callback, is applied to the fields below, and is
/// recorded, so a test can assert both "what the host was told" and "what the strip
/// then painted". That double check is only possible because the package holds no
/// state of its own.
class LaneHarness extends StatefulWidget {
  const LaneHarness({
    super.key,
    required this.layout,
    this.interaction = const SwimlaneInteraction(),
    this.startActive,
    this.menuHost,
    this.headerStrip,
    this.pointerMode = SwimlanePointerMode.hover,
    this.headerActionsBuilder,
    this.titleBuilder,
    this.iconBuilder,
    this.focusResolver,
    this.absorbInactiveContent = true,
    this.dwellSuppressed = false,
  });

  final SwimlaneLayout layout;
  final SwimlaneInteraction interaction;
  final String? startActive;
  final SwimlaneMenuHost? menuHost;
  final SwimlaneHeaderStripHost? headerStrip;
  final SwimlanePointerMode pointerMode;
  final SwimlaneHeaderActionsBuilder? headerActionsBuilder;
  final SwimlaneTitleBuilder? titleBuilder;
  final SwimlaneIconBuilder? iconBuilder;
  final String? Function(SwimlaneLayout layout, String? requestedLaneId)?
  focusResolver;
  final bool absorbInactiveContent;
  final bool dwellSuppressed;

  @override
  State<LaneHarness> createState() => LaneHarnessState();
}

class LaneHarnessState extends State<LaneHarness> {
  late SwimlaneLayout layout;
  String? active;

  /// Mutable so a test can raise the host's "a modal is open" flag mid-gesture.
  late bool dwellSuppressed;

  @override
  void initState() {
    super.initState();
    layout = widget.layout;
    active = widget.startActive;
    dwellSuppressed = widget.dwellSuppressed;
  }

  void setDwellSuppressed(bool value) =>
      setState(() => dwellSuppressed = value);

  /// Every layout the package handed back, in order.
  final List<SwimlaneLayout> emittedLayouts = <SwimlaneLayout>[];

  /// Every focus change the package asked for, in order.
  final List<String?> emittedFocus = <String?>[];

  SwimlaneInteraction get interaction => widget.interaction;

  void applyLayout(SwimlaneLayout next) {
    emittedLayouts.add(next);
    setState(() => layout = next);
  }

  void applyFocus(String? laneId) {
    emittedFocus.add(laneId);
    setState(() => active = laneId);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SwimlaneWorkspace(
          // The **state field**, not `widget.layout`: a controlled widget only moves
          // when the host feeds its answer back in, and `widget.layout` is the value
          // the harness was constructed with. Reading the field here is what makes
          // "the package emitted, the host applied, the strip repainted" observable.
          layout: layout,
          activeLaneId: active,
          interaction: widget.interaction,
          // `flutter test` reports an Android target, which would derive touch-only;
          // each test says which device it is pretending to be.
          pointerMode: widget.pointerMode,
          menuHost: widget.menuHost,
          headerStrip: widget.headerStrip,
          headerActionsBuilder: widget.headerActionsBuilder,
          titleBuilder: widget.titleBuilder,
          iconBuilder: widget.iconBuilder,
          focusResolver: widget.focusResolver,
          absorbInactiveContent: widget.absorbInactiveContent,
          dwellSuppressed: dwellSuppressed,
          laneBuilder: laneContent,
          onLayoutChanged: applyLayout,
          onActiveLaneChanged: applyFocus,
        ),
      ),
    );
  }
}

/// Puts the harness on a 1600x900 logical window, which is Rossi's own capture size
/// and the one his default widths were picked for.
Future<void> pumpHarness(WidgetTester tester, Widget harness) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(harness);
  await tester.pump();
}

/// Drag the handle between two lanes by exactly [dx] logical pixels.
///
/// Not `tester.drag`, for one measured reason: that helper delivers **one 20px step
/// short** of the offset it is handed (a `+100` drag applies 80 to the pair), which is
/// a detail of the test driver rather than of the lane system. Driving the pointer by
/// hand - down, a single move of the full delta, up - applies exactly `dx`, so the
/// clamp assertions in the widget tests can state numbers instead of measurements of
/// the harness.
Future<void> dragHandleBy(
  WidgetTester tester,
  String lanePair,
  double dx,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(ValueKey<String>('resizer-$lanePair'))),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(Offset(dx, 0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A menu host the package never looks inside: it only draws the button and records/// the request, which is all the injection point has to support.
class RecordingMenuHost extends SwimlaneMenuHost {
  const RecordingMenuHost();

  static final List<SwimlaneMenuRequest> requests = <SwimlaneMenuRequest>[];

  @override
  Widget? buildButton(BuildContext context, SwimlaneMenuRequest request) {
    return GestureDetector(
      key: ValueKey<String>('lane-menu-${request.laneId}'),
      onTap: () => requests.add(request),
      child: const Icon(Icons.more_vert_rounded, size: 16),
    );
  }

  @override
  void showAtPointer(
    BuildContext context,
    SwimlaneMenuRequest request,
    Offset globalPosition,
  ) {
    requests.add(request);
  }
}

/// A header strip that reports a hard width, so the give-way budget is exercised
/// through the same seam a real host would use.
class FixedHeaderStrip extends SwimlaneHeaderStripHost {
  const FixedHeaderStrip({this.needed = 210});

  final double needed;

  @override
  double widthFor(SwimlaneLaneInfo lane) => needed;

  @override
  Widget build(BuildContext context, SwimlaneLaneInfo lane) {
    return SizedBox(
      key: ValueKey<String>('header-strip-${lane.laneId}'),
      width: needed,
      child: const ColoredBox(color: Colors.black26),
    );
  }
}
