import 'package:flutter_test/flutter_test.dart';
import 'package:swimlane/swimlane.dart';

import 'support/harness.dart';

void main() {
  group('swimlane layout model', () {
    test('reorder moves the dragged lane onto the target slot, touching nothing else', () {
      final layout = threeLanes();
      final next = layout.reordered(draggedLaneId: 'a', targetLaneId: 'c');

      expect(next.laneOrder, <String>['b', 'c', 'a']);
      // Reorder must not change a single width, collapse flag or the solo record:
      // "reordering only changes who is on the left" (Rossi `reorderLane`).
      expect(next.lanes.keys, layout.lanes.keys);
      expect(next.lane('a')!.width, 380);
      expect(next.lane('b')!.widthRatio, 0.5);
      expect(next.soloLaneId, isNull);
      // The original is untouched: the model is immutable.
      expect(layout.laneOrder, <String>['a', 'b', 'c']);
    });

    test(
      'dropping a lane on itself is a no-op that returns the same instance',
      () {
        final layout = threeLanes();
        expect(
          identical(
            layout.reordered(draggedLaneId: 'a', targetLaneId: 'a'),
            layout,
          ),
          isTrue,
        );
        // An unknown id must not throw or reorder anything either.
        expect(
          identical(
            layout.reordered(draggedLaneId: 'zz', targetLaneId: 'a'),
            layout,
          ),
          isTrue,
        );
      },
    );

    test('movedLaneTo clamps past the ends instead of throwing', () {
      expect(threeLanes().movedLaneTo('a', 99).laneOrder, <String>[
        'b',
        'c',
        'a',
      ]);
      expect(threeLanes().movedLaneTo('c', -99).laneOrder, <String>[
        'c',
        'a',
        'b',
      ]);
      // The index counts the order without the dragged lane (ReorderableListView
      // semantics): moving 'a' to 1 lands it between b and c.
      expect(threeLanes().movedLaneTo('a', 1).laneOrder, <String>[
        'b',
        'a',
        'c',
      ]);
    });

    test('collapse and expand a lane', () {
      final layout = threeLanes();
      final collapsed = layout.toggledCollapsed('a');
      expect(collapsed.lane('a')!.collapsed, isTrue);
      expect(collapsed.lane('b')!.collapsed, isFalse);
      expect(collapsed.toggledCollapsed('a').lane('a')!.collapsed, isFalse);
      // Setting the value it already has returns the same instance, so a host can
      // tell "nothing happened" without diffing.
      expect(
        identical(collapsed.setCollapsed('a', collapsed: true), collapsed),
        isTrue,
      );
    });

    test('drag resize clamps at the max of the lane being grown', () {
      // Rossi `dragLanePair`: the grow side is capped by its own maxWidth **and**
      // by the neighbour's room above its minWidth. a: 380 (300..700), b: 800 at a
      // 1600 viewport (400..2000).
      final layout = threeLanes();
      final grown = layout.draggedPair(
        leftLaneId: 'a',
        rightLaneId: 'b',
        delta: 1000,
        viewportWidth: 1600,
      );
      expect(
        grown.lane('a')!.width,
        700,
        reason: 'a stops at its own maxWidth',
      );
      expect(grown.lane('b')!.width, 480, reason: 'the pair conserves width');
      expect(
        grown.lane('b')!.widthRatio,
        closeTo(0.3, 1e-9),
        reason: 'a reader lane remembers the ratio, not the pixel count',
      );

      // POSITIVE CONTROL: the same call without a clamp would have produced 1380,
      // and a clamp that rejects everything would have left 380.
      expect(grown.lane('a')!.width, isNot(1380));
      expect(grown.lane('a')!.width, isNot(380));
    });

    test('drag resize clamps at the min of the lane being shrunk', () {
      final layout = threeLanes();
      final shrunk = layout.draggedPair(
        leftLaneId: 'a',
        rightLaneId: 'b',
        delta: -2000,
        viewportWidth: 1600,
      );
      expect(
        shrunk.lane('a')!.width,
        300,
        reason: 'a stops at its own minWidth',
      );
      expect(shrunk.lane('b')!.width, 880);
      // The neighbour's band is part of the clamp too: growing b is capped by how
      // far a can still shrink, so 5000px of drag moves exactly 80px.
      final wide = threeLanes().draggedPair(
        leftLaneId: 'b',
        rightLaneId: 'a',
        delta: 5000,
        viewportWidth: 1600,
      );
      expect(wide.lane('b')!.width, 880);
      expect(
        wide.lane('a')!.width,
        300,
        reason: 'a is pinned at its own minWidth',
      );
      expect(wide.lane('b')!.width, isNot(2000));
      expect(wide.lane('b')!.width, isNot(800));
    });

    test(
      'a legal delta is applied exactly, so the clamps above are not a stub',
      () {
        final layout = threeLanes();
        final next = layout.draggedPair(
          leftLaneId: 'a',
          rightLaneId: 'b',
          delta: 50,
          viewportWidth: 1600,
        );
        expect(next.lane('a')!.width, 430);
        expect(next.lane('b')!.width, 750);
        expect(next.lane('a')!.width + next.lane('b')!.width, 1180);
        // A delta of zero cannot have moved anything: same instance back.
        expect(
          identical(
            layout.draggedPair(
              leftLaneId: 'a',
              rightLaneId: 'b',
              delta: 0,
              viewportWidth: 1600,
            ),
            layout,
          ),
          isTrue,
        );
      },
    );

    test('setting an absolute width clamps to the lane own band only', () {
      final layout = threeLanes();
      // Unlike a pair drag this does not care about the neighbour, and it may push
      // the strip into horizontal scrolling on purpose: panel lanes are not clamped
      // to the window width (Rossi `setLaneWidth`).
      expect(layout.withLaneWidth('a', 900, 1600).lane('a')!.width, 700);
      expect(layout.withLaneWidth('a', 10, 1600).lane('a')!.width, 300);
      expect(layout.withLaneWidth('a', 500, 1600).lane('a')!.width, 500);
    });

    test('double tap reset restores the recommended width of both sides', () {
      final dragged = threeLanes()
          .withLaneWidth('a', 700, 1600)
          .draggedPair(
            leftLaneId: 'a',
            rightLaneId: 'b',
            delta: -100,
            viewportWidth: 1600,
          );
      expect(dragged.lane('a')!.width, 600);
      final reset = dragged.withResetPair('a', 'b');
      expect(reset.lane('a')!.width, 380);
      expect(reset.lane('a')!.widthRatio, isNull);
      expect(reset.lane('b')!.widthRatio, 0.5);
      // Resetting one lane only touches that lane.
      expect(
        identical(dragged.withResetWidth('c'), dragged),
        isTrue,
        reason: 'c was never moved, so it is already at its recommendation',
      );
    });

    test('solo toggling never rewrites the stored width', () {
      final layout = threeLanes().withLaneWidth('b', 900, 1600);
      final solo = layout.toggledSolo('b');
      expect(solo.soloLaneId, 'b');
      expect(solo.lane('b')!.width, 900);
      expect(solo.lane('b')!.widthRatio, closeTo(900 / 1600, 1e-9));
      expect(solo.toggledSolo('b').soloLaneId, isNull);
      // Solo on a lane that does not exist cannot be granted.
      expect(identical(layout.withSolo('zz'), layout), isTrue);
    });

    test('a reader solo ignores who is active, a panel solo does not', () {
      final readerSolo = threeLanes().withSolo('b');
      expect(
        readerSolo.effectiveSoloLaneId(activeLaneId: 'a'),
        'b',
        reason: 'focusing elsewhere must only move the strip, not resize the reader',
      );
      expect(readerSolo.effectiveSoloLaneId(activeLaneId: null), 'b');

      final panelSolo = threeLanes().withSolo('a');
      expect(panelSolo.effectiveSoloLaneId(activeLaneId: 'a'), 'a');
      expect(
        panelSolo.effectiveSoloLaneId(activeLaneId: 'b'),
        isNull,
        reason: 'a panel lane is only solo while it is also the active lane',
      );
    });

    test('JSON round trip survives, and normalization follows Rossi', () {
      final original = threeLanes().withSolo('b').toggledCollapsed('c');
      final restored = SwimlaneLayout.fromJson(
        original.toJson(),
        defaults: threeLanes(),
      );
      expect(restored.laneOrder, original.laneOrder);
      expect(restored.lanes, original.lanes);
      expect(restored.soloLaneId, 'b');

      // Unknown ids are dropped and missing ones appended in default order, so a
      // retired lane leaves no empty slot and a new lane still shows up.
      final messy = SwimlaneLayout.fromJson(<String, Object?>{
        'laneOrder': <String>['c', 'retired', 'a'],
        'lanes': <String, Object?>{
          'a': <String, Object?>{'width': 'not a number'},
        },
        'soloLaneId': 'ghost',
      }, defaults: threeLanes());
      expect(messy.laneOrder, <String>['c', 'a', 'b']);
      expect(
        messy.lane('a')!.width,
        380,
        reason: 'the bad number fell back alone',
      );
      expect(
        messy.soloLaneId,
        isNull,
        reason: 'a solo pointing at nothing is dropped',
      );
    });
  });

  group('lane config', () {
    test('resolveWidth picks the unit the kind declares', () {
      final reader = laneB();
      expect(
        reader.resolveWidth(1600),
        800,
        reason: 'ratio times viewport width',
      );
      expect(
        reader.resolveWidth(0),
        650,
        reason: 'no viewport, so the nominal px',
      );
      expect(reader.resolveWidth(100), 400, reason: 'never below minWidth');
      expect(
        laneA().resolveWidth(1600),
        380,
        reason: 'a panel lane ignores viewport',
      );
    });

    test('withStoredWidth keeps a reader lane proportional', () {
      final reader = laneB().withStoredWidth(px: 900, viewportWidth: 1600);
      expect(reader.width, 900);
      expect(reader.widthRatio, closeTo(0.5625, 1e-9));
      expect(
        reader.resolveWidth(800),
        450,
        reason: 'the same ratio, half a window',
      );

      // A panel lane stores pixels only.
      final panel = laneA().withStoredWidth(px: 500, viewportWidth: 1600);
      expect(panel.width, 500);
      expect(panel.widthRatio, isNull);
      expect(
        panel.resolveWidth(120),
        500,
        reason: 'a panel lane is pixels, never a fraction of the window',
      );
    });
  });
}
