import 'package:flutter/scheduler.dart';

import 'dwell.dart';

/// A monotonic clock plus one [SwimlaneDwell], driven by a [Ticker] that only runs
/// while a dwell is pending.
///
/// This is the part of Rossi's `SwimlaneWorkspace` that "feeds the real clock"
/// (`_ensureTicker`, `_stopTickerIfIdle`, `_pollDwells`, `_syncHoverHighlight`),
/// pulled out so the widget file stays about lanes.
///
/// ## Why a Ticker instead of Rossi's `Timer.periodic` + `Stopwatch`
///
/// Same shape and the same discipline - **never while idle**, because a permanent
/// 60Hz loop costs battery on a laptop - but the time comes from the scheduler's
/// frame clock. `flutter_test` advances the frame clock under
/// `tester.pump(Duration(...))` and leaves a real `Stopwatch` alone, so with
/// Rossi's clock "did the dwell fire at 210ms" could only be checked by sleeping for
/// real. Rossi wrote his own rule that the timing must not be tested that way (the
/// header of `workspace_dwell.dart`); this keeps that rule enforceable.
///
/// The clock is still monotonic - it accumulates frame deltas - so an NTP
/// correction cannot push a deadline out of reach, which is the failure his
/// `Stopwatch` comment is guarding against.
class SwimlaneDwellPump {
  SwimlaneDwellPump({
    required this.vsync,
    required this.onDue,
    required this.onArmedChanged,
  });

  /// The dwell's target reached its deadline. Fires **once** per dwell, because
  /// [SwimlaneDwell.takeDue] clears the pending target while reading it.
  final void Function(String laneId) onDue;

  /// The pointer settled for [SwimlaneDwell.settleMs] but the delay is still
  /// running; `null` when nothing is armed any more.
  final void Function(String? laneId) onArmedChanged;

  final TickerProvider vsync;
  final SwimlaneDwell _dwell = SwimlaneDwell();

  Ticker? _ticker;
  int _nowMs = 0;

  /// `_nowMs` when the ticker was started. `Ticker.elapsed` counts from the start,
  /// so a restart must not roll the clock back.
  int _tickerBaseMs = 0;

  /// The monotonic clock, in milliseconds.
  int get nowMs => _nowMs;

  bool get isPending => _dwell.isPending;

  /// Start timing [laneId]: [delayMs] after the pointer stops moving.
  void enter(String laneId, {required int delayMs}) {
    _dwell.enter(laneId, nowMs: _nowMs, delayMs: delayMs);
    _ensureTicker();
  }

  /// The pointer moved: push the deadline back. Nothing happens while no dwell is
  /// pending, so a plain pass-by can never land.
  void noteMotion() {
    if (!_dwell.isPending) return;
    _dwell.noteMotion(_nowMs);
    _syncArmed();
  }

  /// [laneId] left. Cancels only if [laneId] **is** the pending target.
  void leave(String laneId) {
    _dwell.leave(laneId);
    _syncArmed();
    _stopIfIdle();
  }

  /// Drop the pending dwell outright: a click, a strip exit, a suppression.
  void cancel() {
    _dwell.cancel();
    _syncArmed();
    _stopIfIdle();
  }

  /// While suppressed nothing fires, and entering suppression clears the pending
  /// target so nothing is delivered late when it lifts.
  ///
  /// Only the application knows when a modal, a floating menu, an IME composition or
  /// a pointer capture is up, so the host drives this through
  /// `SwimlaneWorkspace.dwellSuppressed`.
  void setSuppressed(bool value) {
    _dwell.setSuppressed(value);
    _syncArmed();
    _stopIfIdle();
  }

  void dispose() {
    _ticker?.dispose();
    _ticker = null;
  }

  void _ensureTicker() {
    final ticker = _ticker ??= vsync.createTicker(_onTick);
    if (ticker.isActive) return;
    _tickerBaseMs = _nowMs;
    ticker.start();
  }

  void _onTick(Duration elapsed) {
    _nowMs = _tickerBaseMs + elapsed.inMilliseconds;
    _poll();
  }

  void _stopIfIdle() {
    if (_dwell.isPending) return;
    final ticker = _ticker;
    if (ticker == null || !ticker.isActive) return;
    _tickerBaseMs = _nowMs;
    ticker.stop();
    // The armed highlight has to be dropped **here**: nothing recomputes it once the
    // ticker is parked, and a leftover one is a lane that still looks like it is
    // about to be focused with the pointer long gone.
    onArmedChanged(null);
  }

  void _poll() {
    final due = _dwell.takeDue(_nowMs);
    if (due != null) onDue(due);
    _syncArmed();
    _stopIfIdle();
  }

  void _syncArmed() {
    onArmedChanged(_dwell.isArmed(_nowMs) ? _dwell.pendingId : null);
  }
}
