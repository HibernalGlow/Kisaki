# swimlane

A standalone Flutter package for the **swimlane** layout: one horizontal strip of
resizable lanes that never overlap and never float above each other, with collapse to
a compact rail, solo, drag-to-resize, drag-to-reorder, scroll-to-focus, and dwell
(hover-to-focus) timing.

Extracted from Rossi's workspace (`/Users/glow/Base/Code/Freya/rossi`, read-only) so
other products get the same geometry instead of a new approximation of it. The port
keeps Rossi's numbers and his clamps; where a rule could only be kept by naming the
file it came from, the comment says so.

## The contract

**The package owns the lane model and its geometry. The host owns every pixel of lane
content, and owns the state.**

`SwimlaneWorkspace` is a *controlled* widget: `layout` and `activeLaneId` come in as
props, and every change goes out as a callback. Nothing is persisted, and nothing can
change without the host agreeing, so the host can veto, debounce, log, or write to
disk.

```dart
SwimlaneWorkspace(
  layout: layout,                       // host-owned lane model
  activeLaneId: active,                 // who has the interaction, or null
  interaction: const SwimlaneInteraction(),
  laneBuilder: (context, lane) => MyLaneBody(lane: lane),   // REQUIRED
  onLayoutChanged: (next) => setState(() => layout = next),
  onActiveLaneChanged: (next) => setState(() => active = next),
  menuHost: const MyLaneMenuHost(),     // per-lane "more" menu, optional
  headerStrip: const MyTabStripHost(),  // strip mounted in a lane header, optional
  headerActionsBuilder: myActions,      // extra header buttons, optional
  titleBuilder: myTitles,               // overrides LaneConfig.title, optional
  iconBuilder: myIcons,                 // overrides the default lane icon, optional
  focusResolver: myResolver,            // redirect a focus request, optional
  pointerMode: null,                    // null = derive from the platform
  absorbInactiveContent: true,
  dwellSuppressed: isModalOpen,         // host's modal / IME / pointer capture
  scrollController: null,
)
```

### What the host has to supply

| Slot | Type | Who needs it |
|---|---|---|
| `laneBuilder` | `Widget Function(BuildContext, SwimlaneLaneInfo)` | every lane's content. Required; the package draws none. |
| `menuHost` | `SwimlaneMenuHost` | the per-lane "more" menu: `buildButton` for the header slot, `showAtPointer` for right-clicking a header or a rail. Given a `SwimlaneMenuRequest` (lane id, viewport width, laid-out width, `showsAsRail`, solo, and already-routed `onToggleCollapse` / `onToggleSolo` / `onResetWidth`). |
| `headerStrip` | `SwimlaneHeaderStripHost` | a strip mounted **inside** a lane header (tabs, tool buttons). Must report a **hard** `widthFor(lane)`: the header budget decides who gives way, and a strip measured from its font moves that budget every time the font changes. |
| `headerActionsBuilder` | `List<Widget> Function(BuildContext, SwimlaneLaneInfo)` | extra header buttons. Keep them icon-button sized: the budget charges 40px each (`LaneChrome.iconButton`). |
| `titleBuilder` / `iconBuilder` | | label and icon per lane. `null` falls back to `LaneConfig.title` and `defaultLaneIcon`. |
| `focusResolver` | `String? Function(SwimlaneLayout, String?)` | "focusing lane X really means lane Y" (Rossi's `LaneFocusResolver`). |
| `dwellSuppressed` | `bool` | true while a modal, a floating menu, an IME composition or a pointer capture is up. Nothing fires while suppressed, and entering suppression drops the pending dwell so nothing is delivered late. |

`SwimlaneLaneInfo` is what the package hands back on the other side of those seams:
`laneId`, `config`, `index`, `laidOutWidth` (the width the lane **actually occupies** -
a rail is 44, a solo lane is the whole available width, and the elastic lane ate the
spare), `viewportWidth`, `isActive`, `isSolo`, `isRail`, `focusArmed`, `showsAsRail`.

### Public surface

`lib/swimlane.dart` exports: `SwimlaneWorkspace`, `SwimlaneColumn`, `SwimlaneResizer`,
`SwimlaneLayout`, `LaneConfig`, `LaneKind`, `SwimlaneStripMetrics`,
`SwimlaneStripSlot`, `SwimlaneDwell`, `SwimlaneDwellPump`, `SwimlaneFocusGeometry`,
`SwimlaneInteraction`, `LaneChrome`, `LaneHeaderFit`, `resolveLaneHeaderFit`,
`SwimlaneLaneInfo`, `SwimlaneMenuRequest`, `SwimlaneMenuHost`,
`SwimlaneHeaderStripHost`, the builder typedefs, `SwimlanePointerMode`.

The model layer (`LaneConfig`, `SwimlaneLayout`, `SwimlaneStripMetrics`,
`SwimlaneDwell`, `SwimlaneFocusGeometry`, `lane_header_fit`) imports no Flutter at all
except `dart:math`, which is Rossi's own discipline: the geometry is the one place a
wrong number shows up as a stripes overlay instead of a compile error, so it has to be
reachable from a plain assertion.

```bash
flutter pub get && dart analyze . && flutter test
```

## Geometry kept from Rossi

| Rule | Value | Rossi file |
|---|---|---|
| collapsed lane width | 44dp | `workspace_layout_config.dart` (`collapsedLaneWidth`) |
| handle width | 10dp | `workspace_strip_metrics.dart` (`defaultResizerWidth`) |
| strip padding | 8dp each side | `workspace_strip_metrics.dart` (`defaultPadding`) |
| sub-pixel tolerance | 0.5 | `workspace_strip_metrics.dart` (`fitTolerance`) |
| a lane never exceeds | 85% of the viewport | `workspace_strip_metrics.dart` (`maxLaneViewportFactor`) |
| spare width | goes to the reader lane, and `contentWidth` is then **assigned** to equal the available width | `workspace_strip_metrics.dart` |
| handles | drawn only between two adjacent **non-collapsed** lanes; the count follows the drawing rule, never "lanes - 1" | `workspace_strip_metrics.dart` (1b / step 4) |
| rails in solo | subtracted **from** the solo lane, floored at one rail width; the active lane is never a rail | `workspace_strip_metrics.dart` (1 / 1a) |
| pair drag | `applied = delta.clamp(-min(left.width - left.min, right.max - right.width), min(left.max - left.width, right.width - right.min))` | `workspace_cubit.dart` (`dragLanePair`) |
| absolute width | clamped to the lane's **own** band only | `workspace_cubit.dart` (`setLaneWidth`) |
| reader lane width | stored as a ratio, written back as `px / viewportWidth` | `workspace_cubit.dart` (`_withWidth`) |
| solo | a lane whose width for this pass is the available width, in the same strip | `workspace_strip_metrics.dart` |
| reader solo | ignores which lane is active; panel solo requires it | `workspace_state.dart` (`effectiveSoloLaneId`) |
| focus scroll | minimum movement; a lane already whole does not move; a lane wider than the viewport aligns its nearer edge | `workspace_lane_focus.dart` (`focusOffset`) |
| reader sliver | 56px kept visible while solo and unfocused, capped by half the viewport | `workspace_lane_focus.dart` + `workspace_interaction_settings.dart` |
| dwell | `settle 60ms` then the delay; fires once; retargeting restarts; a lane's exit cancels only its own dwell | `workspace_dwell.dart` |
| hover delay | 150ms after it stopped (Rossi's current default, down from 420) | `workspace_interaction_settings.dart` |
| header give-way | mounted strip first, then more, collapse, solo, width badge, title | `swimlane_column.dart` (`_fitHeader`, `_LaneChrome`) |
| first click on inactive lane content | eaten by the workspace (`AbsorbPointer`), header buttons still work | `swimlane_workspace.dart` (`_buildAbsorbingContent`) |
| rails are skipped by dwell focus | a rail is already a switch handle; a dwell there would make it a trap | `swimlane_workspace.dart` (`_handleLaneHoverEnter`) |
| programmatic-only scrolling | `shouldAcceptUserOffset` false keeps clamping, inertia and `animateTo` | `swimlane_workspace.dart` (`_ProgrammaticScrollPhysics`) |

## Deliberately not ported

These stayed on the application side because they are content or app knowledge, not
lane geometry. Each one is reachable through the injection points above.

- **The "more" menu's items.** Rossi's `lane_more_menu.dart` reads a `WorkspaceCubit`
  and offers solo, a width field, panel-bar docking, top-chrome visibility and "exit
  workspace". All of that is one product's feature list. The package offers
  `SwimlaneMenuHost` plus a `SwimlaneMenuRequest` carrying everything an equivalent
  menu needs (including `showsAsRail`, whose whole purpose is that a menu label must
  describe what is painted).
- **Tab strips, panel identity, and panel/card bookkeeping.**
  `workspace_board_layout.dart` (`WorkspacePanelSide`, `PanelLayout`, `CardLayout`,
  `placePanel`, `moveCard`, `sortByOrder`) and `workspace_panel_bar.dart`
  (`PanelBarLayout`, `panelBarDockCandidate`, `panelBarFloatingOffset`) are about what
  lives *inside* a lane and where its tab bar docks. `SwimlaneColumn` gives the host a
  header slot (`headerStrip` / `headerActionsBuilder`) and a content slot
  (`laneBuilder`) instead.
- **Per-card rendering.** `WorkspaceCardDragImage`, `resolveWorkspaceCardDrop`,
  `workspaceCardDropAllowed`, `WorkspacePanelBarReparenting` stay with the host: the
  package never renders a card, and cards crossing lanes is a content-level drag
  system.
- **Reader hosts.** `WorkspaceReaderHost`, reader targets, the page-navigation drag
  block, the reader overlay, fullscreen. Rossi's `isReaderFullscreen` also drops the
  strip padding and its own header; a host that wants that mode wraps the workspace
  differently.
- **Edge reveal dwell.** `workspace_reveal_zones.dart` (`WorkspaceRevealZones`,
  `RevealEdge`, `mirror`, the corner-resize arithmetic) plus the edge and restore
  dwells in `SwimlaneWorkspace._handleStripHover`. Those zones are edited on a canvas
  in the settings screen and their candidate lanes are named by app ids
  (`LaneId.left` / `LaneId.right`). The geometry they act on **is** here
  (`SwimlaneFocusGeometry.revealOffset`), and the timing primitive is here
  (`SwimlaneDwell`), so a host can rebuild the feature without this package knowing
  about zones.
- **Persistence.** Rossi writes a `WorkspaceLayoutSnapshot`; this package exposes
  `toJson` / `fromJson` on the model and leaves storage, migration and file locking to
  the host. `SwimlaneLayout.fromJson` keeps his normalization rules (unknown lane ids
  dropped, missing ones appended, one bad number falls back alone, a solo pointing at
  a removed lane dropped) - it just takes the host's `defaults` instead of a
  hard-coded table.
- **Column/vertical stack fallback.** Rossi degrades a narrow viewport by capping each
  lane at 85% of the viewport, turning on horizontal scrolling, and dropping header
  chrome in a fixed order. There is no "stack the lanes vertically" mode in the
  source, so there is none here either.

## Known deviations from Rossi

All of these are choices, not oversights:

1. **`LaneKind` instead of the `LaneId.reader` string.** Rossi hard-codes his reader
   lane id in the strip allocation, in `_handleStripHover`'s reveal candidate, and in
   `panelSide`'s `switch`. A package cannot know that `"reader"` means "elastic", so
   the property moved onto the lane. Every clamp, guard and formula around it is
   unchanged, and the guards (`widths[x] == null`, `collapsed != false`) already
   handled "no reader lane", so behaviour is identical when there is exactly one.
2. **`recommendedWidth` on the lane instead of a global defaults table.** Rossi reads
   `WorkspaceLayoutConfig.defaults()` when a double tap resets a lane; that table is
   one product's lane list. Each lane now carries its own recommendation (defaulting
   to the width it was built with). Same result on double tap, and a host can retire a
   lane without the package noticing a missing entry.
3. **Dwell timing driven by `Ticker` frame deltas, not `Timer.periodic` + `Stopwatch`.**
   `flutter_test` advances the frame clock under `tester.pump(Duration(...))` and
   leaves a real `Stopwatch` alone, so with Rossi's clock "did the dwell fire at
   210ms" can only be tested by sleeping - which his own comment in
   `workspace_dwell.dart` rules out. The clock here is still monotonic (frame deltas
   accumulate; an NTP correction cannot push a deadline out of reach) and the ticker
   still only runs while a dwell is pending.
4. **Nothing is absorbed while `activeLaneId == null`.** Rossi's `WorkspaceState`
   documents that null means "eat nothing, act as before", but
   `_buildAbsorbingContent` computes `absorbing: !isActive`, which absorbs every lane
   on a cold start until the first click lands. This package implements the documented
   rule. Hosts that want the literal behaviour pass
   `absorbInactiveContent: false` and drive focus themselves.
5. **Suppressing a dwell is a prop, not a cubit read.** Rossi checks
   `state.pointerCaptured || state.menuOpen ...` internally; the package cannot see a
   host's modal, so `dwellSuppressed` is handed in. The suppression semantics
   (pending target dropped the moment suppression starts, nothing delivered late) are
   his.
6. **Rail tap routing and the collapse flag stay one rule.** Rossi routes "tap the
   collapse control on a navigator rail" to *focus* rather than toggle
   (`isRail && !config.collapsed`). Kept, and covered by a test, because it is the
   difference between a navigator and a trap.
7. **`SwimlaneResizer` is `SwimlaneResizer`, not `LaneResizer`.** The name `LaneResizer`
   belongs to the host's vocabulary; the package's handles are prefixed like the rest
   of its API. Its `width` still references `SwimlaneStripMetrics.defaultResizerWidth`
   for the reason Rossi wrote down: the allocation is a pure function that cannot load
   the widget, so the number must have one source.
8. **The scroll geometry gets the scroller's own extent.** Rossi's `_targetOffset`
   receives `_viewportWidth` (= `constraints.maxWidth`), while his `Padding` wraps the
   `SingleChildScrollView` from outside, so the box the strip actually paints into is
   `2 * stripPadding` narrower. "Move exactly enough to make this lane whole" then
   comes up short by that much and a solo lane keeps its right edge clipped on every
   window size. The package passes the padded-out width to the offsets (and to
   `maxOffset`, whose real maximum is `contentWidth - (viewport - 2 * padding)`), and
   keeps multiplying **lane ratios** by the full viewport exactly as he does.
9. **A dwell that came due is delivered after the frame is built.** The pump's ticker
   runs in `handleBeginFrame`, which is before the widget tree sees the host's new
   props, so a modal raised in the same frame would still be read as "not suppressed"
   and the dwell would be handed over behind it. Rossi's `Timer.periodic` has the same
   window; waiting for the post-frame callback costs one frame of a 210ms dwell and
   makes the suppression rule hold for the frame the flag arrives in.
10. **A focus request is remembered for one frame.** Rossi's `activateLane` guard reads
    `state.activeLaneId`, and his `emit` updates that state synchronously, so a second
    request inside the same frame is a no-op for free. Pressing solo emits a layout and
    then asks for the focus the pointer-down already asked for; against a prop that only
    updates after the host rebuilds, that would report the intent twice. The package
    remembers what it last asked for, and the prop overrules the memory on every
    update, so a veto cannot block the lane afterwards.
11. **The resize handle measures from the press** (`dragStartBehavior: down`). With
    Flutter's default `start`, the recognizer takes its zero point from the **first move
    event**, so a pointer that goes down and moves once hands the whole delta to the
    arena and nothing to the lane: measured here, one `moveBy(100)` applied 0, and with
    `.down` it applies 100. A resize handle is the one control where "the edge is under
    the pointer" is the whole point. (Rossi leaves the default; his handle is only ever
    driven by a stream of mouse-move events, where the difference is a pixel or two.)

## Tests

`test/layout_test.dart` (model: reorder, collapse, solo, pair-drag clamps, absolute
width, reset, JSON normalization), `test/strip_metrics_test.dart` (spare, viewport cap,
rail subtraction, handle counting, sub-pixel tolerance) and its focus-geometry and
header-budget groups, `test/dwell_test.dart` (deadline arithmetic, settle window,
retarget, per-lane cancel, suppression), `test/support/harness.dart` (a host that owns
state and records what the package asked it to do),
`test/swimlane_workspace_test.dart` (reorder by drag, resize clamps at min and max with
in-band controls, collapse and expand, solo and unsolo, dwell-to-focus firing only
after `settle + delay`, menu and strip seams).

Every clamp test is paired with a control that shows the gauge can see a violation:
either the same operation with an in-band value that must apply, or an assertion that
the unclamped result would have been a different number.
