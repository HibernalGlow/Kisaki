import 'dart:math' as math;

/// "Dwell long enough, then fire once" - **pure logic**, no timers inside.
///
/// Every dwell in the lane system has the same shape: pointer enters, timing
/// starts, on the deadline it fires **once**; leaving or cancelling voids it.
///
/// Time comes in as milliseconds from the caller, so the assertions can dial the
/// clock forwards and backwards and check "not before the deadline, exactly once
/// at it, cancelled on leave" instead of betting on scheduling. The widget layer
/// feeds the real clock (Rossi states the same discipline at the top of
/// `workspace_dwell.dart`).
///
/// The four rules live in the type rather than at the call sites:
///
/// 1. **fires once**. [takeDue] clears the pending target while reading it, so a
///    pointer that stays put does not re-fire every frame - that would re-focus
///    on each frame and the picture would jitter sideways.
/// 2. **a new target restarts the timing**. Dwelling a while in A then moving to
///    B must not credit B with A's elapsed time, or B fires the instant the
///    pointer lands and looks "more responsive than A".
/// 3. **suppressed means nothing fires**, and entering suppression clears the
///    pending target right away. While a pointer is captured, a drag is running,
///    an IME is composing, or a popup is open, nothing may auto-fire; by the time
///    the suppression lifts, that dwell is stale.
/// 4. **a moving pointer is not a dwell**. [noteMotion] keeps pushing the
///    deadline back; only after [settleMs] of silence does the `delay` part start
///    counting. This replaces "start counting on enter", which made one number do
///    two jobs (do not misfire on a pass-by, and give the user reaction time) and
///    therefore had to be large - penalising the person who really did stop.
class SwimlaneDwell {
  String? _pendingId;
  int _armedMs = 0;
  int _deadlineMs = 0;
  int _delayMs = 0;
  bool _suppressed = false;

  /// How long the pointer must stay quiet after its last movement before the
  /// delay starts counting (milliseconds).
  ///
  /// Rossi `WorkspaceDwell.settleMs = 60`. It is deliberately an **internal**
  /// constant, not a fourth knob: the user only answers "after stopping, wait a
  /// bit more?", while "what counts as stopped" should not be something they
  /// tune by watching a clock.
  static const int settleMs = 60;

  /// The target currently being timed, or `null` when nothing is pending.
  String? get pendingId => _pendingId;

  bool get isPending => _pendingId != null;

  bool get isSuppressed => _suppressed;

  /// Start (or restart) timing [id].
  ///
  /// Deadline = `nowMs + settleMs + delayMs`: first [settleMs] of silence ("it
  /// really stopped"), then [delayMs] ("having stopped, look a moment longer").
  ///
  /// [delayMs] must be positive: a zero delay means "fire the moment it settles",
  /// and the picture sliding sideways on every pass-by is not "faster" but
  /// "worse". An illegal value becomes 1ms - still "almost immediately", but it
  /// has to survive one event loop.
  void enter(String id, {required int nowMs, required int delayMs}) {
    if (_pendingId == id) return;
    _pendingId = id;
    _delayMs = math.max(1, delayMs);
    _retime(nowMs);
  }

  /// The pointer **moved again**: push the whole deadline back (settle again,
  /// then wait out the full delay).
  ///
  /// Only acts while something is pending, and never changes the target -
  /// switching the target is [enter]'s job, and that path must restart timing.
  void noteMotion(int nowMs) {
    if (_pendingId == null) return;
    _retime(nowMs);
  }

  void _retime(int nowMs) {
    _armedMs = nowMs + SwimlaneDwell.settleMs;
    _deadlineMs = _armedMs + _delayMs;
  }

  /// Settled for real, still waiting out `delay`.
  ///
  /// This is the intermediate state the interface can react to: a lane shows "the
  /// system noticed me stopping here" through its border a couple of hundred
  /// milliseconds before the interaction is actually handed over. A pass-by never
  /// reaches it (movement keeps pushing [isArmed] back), so it cannot flicker.
  bool isArmed(int nowMs) =>
      !_suppressed && _pendingId != null && nowMs >= _armedMs;

  /// [id] is no longer under the pointer. Cancels **only** if [id] is the pending
  /// target.
  ///
  /// That guard is not pedantry: moving from A to B delivers A's exit before B's
  /// enter (the order is not guaranteed). An unconditional cancel would wipe B's
  /// timing on A's way out, which shows up as "I had to sweep over three lanes
  /// before one focused".
  void leave(String id) {
    if (_pendingId == id) _pendingId = null;
  }

  void cancel() {
    _pendingId = null;
  }

  /// Nothing may fire while suppressed; entering suppression drops the pending
  /// target immediately.
  void setSuppressed(bool value) {
    if (_suppressed == value) return;
    _suppressed = value;
    if (value) _pendingId = null;
  }

  /// Has the deadline passed? Always false while suppressed.
  bool isDue(int nowMs) =>
      !_suppressed && _pendingId != null && nowMs >= _deadlineMs;

  /// Take the due target and clear the timer, so this fires **once**.
  /// Returns `null` when not due.
  String? takeDue(int nowMs) {
    if (!isDue(nowMs)) return null;
    final id = _pendingId;
    _pendingId = null;
    return id;
  }

  /// Milliseconds left until the deadline, `null` when nothing is pending.
  ///
  /// Only exists so the assertions can look at the intermediate state.
  int? remainingMs(int nowMs) =>
      _pendingId == null ? null : math.max(0, _deadlineMs - nowMs);
}
