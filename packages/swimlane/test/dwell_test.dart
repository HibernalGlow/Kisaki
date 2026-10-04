import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swimlane/swimlane.dart';

/// The timing rules are pure, so they are asserted on the millisecond and not by
/// waiting: `SwimlaneDwell` takes `nowMs` from the caller exactly because a test
/// that sleeps is betting on scheduling (Rossi's header comment on
/// `workspace_dwell.dart` says the same).
void main() {
  // settle 60ms + delay, so the deadline after an enter at t=0 is 60 + delay.
  const settle = SwimlaneDwell.settleMs;

  group('dwell timing', () {
    test('fires exactly at settle + delay, and not one millisecond before', () {
      final dwell = SwimlaneDwell();
      dwell.enter('a', nowMs: 0, delayMs: 150);

      // POSITIVE CONTROL: an implementation that never checks the deadline would
      // report due at t=1.
      expect(dwell.isDue(1), isFalse);
      expect(dwell.isDue(settle + 149), isFalse);
      expect(dwell.isDue(settle + 150), isTrue);
      expect(dwell.remainingMs(settle + 100), 50);
      expect(dwell.remainingMs(settle + 150), 0);
    });

    test('a zero or negative delay becomes 1ms, not "fire immediately"', () {
      // Rossi: a zero delay means the picture slides sideways as the pointer passes,
      // which is not "faster" but "worse". It still costs one event loop.
      final dwell = SwimlaneDwell();
      dwell.enter('a', nowMs: 0, delayMs: 0);
      expect(dwell.isDue(settle), isFalse);
      expect(dwell.isDue(settle + 1), isTrue);

      final negative = SwimlaneDwell()..enter('a', nowMs: 0, delayMs: -500);
      expect(negative.isDue(settle), isFalse);
      expect(negative.isDue(settle + 1), isTrue);
    });

    test('taking the due target clears it, so one dwell fires once', () {
      final dwell = SwimlaneDwell()..enter('a', nowMs: 0, delayMs: 10);
      expect(dwell.takeDue(settle + 10), 'a');
      // The pointer is still sitting here and the deadline is long past.
      expect(dwell.takeDue(settle + 1000), isNull);
      expect(dwell.isPending, isFalse);
    });

    test('motion pushes the deadline back instead of counting down', () {
      final dwell = SwimlaneDwell()..enter('a', nowMs: 0, delayMs: 150);
      // Sweeping across the strip: every move re-arms the settle window and the whole
      // delay, so a pass-by can never land.
      dwell.noteMotion(100);
      expect(dwell.isDue(200), isFalse);
      dwell.noteMotion(200);
      expect(dwell.isDue(300), isFalse);
      expect(dwell.isDue(200 + settle + 150), isTrue);
    });

    test('motion is ignored when nothing is pending', () {
      final dwell = SwimlaneDwell();
      dwell.noteMotion(1000);
      expect(dwell.isPending, isFalse);
      expect(dwell.pendingId, isNull);
    });

    test('the armed state needs the settle window, and nothing more', () {
      final dwell = SwimlaneDwell()..enter('a', nowMs: 0, delayMs: 150);
      expect(dwell.isArmed(settle - 1), isFalse);
      expect(
        dwell.isArmed(settle),
        isTrue,
        reason: 'stopped moving: border lights up',
      );
      expect(dwell.isArmed(settle + 149), isTrue);
      dwell.noteMotion(100);
      // Moving again is not "stopped", so the preview goes away until it settles.
      expect(dwell.isArmed(120), isFalse);
      expect(dwell.isArmed(100 + settle), isTrue);
    });

    test('switching lanes restarts the timing', () {
      final dwell = SwimlaneDwell()..enter('a', nowMs: 0, delayMs: 150);
      // Dwelling a while in A must not be credited to B, or B fires the moment the
      // pointer lands and looks "more responsive than A".
      dwell.enter('b', nowMs: 100, delayMs: 150);
      expect(dwell.pendingId, 'b');
      expect(dwell.isDue(150), isFalse);
      expect(dwell.isDue(100 + settle + 150), isTrue);
    });

    test('entering the same lane twice does not restart the timing', () {
      final dwell = SwimlaneDwell()..enter('a', nowMs: 0, delayMs: 100);
      dwell.enter('a', nowMs: 50, delayMs: 100);
      expect(
        dwell.remainingMs(50),
        110,
        reason: 'deadline stayed at 0 + 60 + 100',
      );
    });

    test('leaving cancels only its own target', () {
      final dwell = SwimlaneDwell()..enter('b', nowMs: 0, delayMs: 100);
      // A's exit is delivered before B's enter and the order is not guaranteed, so an
      // unconditional cancel here would wipe B and read as "I had to sweep over three
      // lanes before one focused".
      dwell.leave('a');
      expect(dwell.pendingId, 'b');
      expect(dwell.isDue(settle + 100), isTrue);
      dwell.leave('b');
      expect(dwell.isPending, isFalse);
    });

    test('suppression clears the pending target and delivers nothing late', () {
      final dwell = SwimlaneDwell()..enter('a', nowMs: 0, delayMs: 100);
      dwell.setSuppressed(true);
      expect(dwell.isSuppressed, isTrue);
      expect(
        dwell.isPending,
        isFalse,
        reason: 'dropped the moment it was suppressed',
      );
      expect(dwell.isDue(settle + 100), isFalse);
      expect(dwell.takeDue(10000), isNull);

      // Re-entering while suppressed is still timed but never fires.
      dwell.enter('a', nowMs: 0, delayMs: 100);
      expect(dwell.isDue(settle + 100), isFalse);
      dwell.setSuppressed(false);
      // Lifting suppression does not hand back a stale dwell that was armed behind the
      // modal: the pending target was dropped when suppression started.
      expect(dwell.isPending, isTrue);
      expect(dwell.takeDue(settle + 100), 'a');
    });

    test('setting the same suppression value twice changes nothing', () {
      final dwell = SwimlaneDwell()..enter('a', nowMs: 0, delayMs: 100);
      dwell.setSuppressed(false);
      expect(dwell.isPending, isTrue);
      dwell.cancel();
      expect(dwell.isPending, isFalse);
      expect(dwell.remainingMs(0), isNull);
    });
  });

  group('interaction defaults', () {
    test('carry Rossi\'s tuned numbers', () {
      const interaction = SwimlaneInteraction();
      // 150 and not the old 420: the delay now means "after it stopped", and the
      // settle window is what keeps a pass-by from misfiring.
      expect(interaction.hoverFocusDelayMs, 150);
      expect(settle, 60);
      expect(interaction.readerPeekWidth, 56);
      expect(interaction.hoverFocusEnabled, isTrue);
      expect(interaction.panelHoverFocusEnabled, isTrue);
      expect(interaction.autoSoloOnFocus, isFalse);
      expect(interaction.showLaneNavigatorInSolo, isFalse);
      expect(interaction.manualScrollEnabled, isTrue);
      expect(interaction.scrollDuration, const Duration(milliseconds: 220));
    });

    test(
      'JSON round trip keeps every field, and one bad value falls back alone',
      () {
        const custom = SwimlaneInteraction(
          hoverFocusDelayMs: 30,
          readerPeekWidth: 10,
        );
        expect(SwimlaneInteraction.fromJson(custom.toJson()), custom);

        final broken = SwimlaneInteraction.fromJson(<String, Object?>{
          'hoverFocusDelayMs': 'not a number',
          'readerPeekWidth': 20,
        });
        expect(
          broken.hoverFocusDelayMs,
          const SwimlaneInteraction().hoverFocusDelayMs,
        );
        expect(broken.readerPeekWidth, 20);
      },
    );
  });

  group('pointer mode', () {
    test('desktop platforms have a hover pointer, mobile does not', () {
      expect(
        SwimlanePointerMode.forTargetPlatform(TargetPlatform.macOS),
        SwimlanePointerMode.hover,
      );
      expect(
        SwimlanePointerMode.forTargetPlatform(TargetPlatform.linux),
        SwimlanePointerMode.hover,
      );
      expect(
        SwimlanePointerMode.forTargetPlatform(TargetPlatform.windows),
        SwimlanePointerMode.hover,
      );
      expect(
        SwimlanePointerMode.forTargetPlatform(TargetPlatform.android),
        SwimlanePointerMode.touchOnly,
      );
      expect(
        SwimlanePointerMode.forTargetPlatform(TargetPlatform.iOS),
        SwimlanePointerMode.touchOnly,
      );
    });
  });
}
