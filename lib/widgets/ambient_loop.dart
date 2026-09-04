import 'dart:async';

import 'package:flutter/widgets.dart';

/// A looping 0→1 value for ambient decoration — drifting waves, a pulsing
/// wordmark — advanced at a capped rate instead of once per vsync.
///
/// PERF (resume stutter): an [AnimationController] is driven by a `Ticker`,
/// which asks for a frame on EVERY vsync for as long as it runs. That is
/// the right thing for gameplay, and the wrong thing for scenery. Measured
/// on a 120Hz phone, the menu's three decorative loops were putting the
/// whole pipeline — build, paint, and a full-surface composite — through
/// ~117 cycles a second, continuously, for as long as a screen was open,
/// and the app needed more than a full CPU core just to keep that up while
/// otherwise idle.
///
/// That is what makes a resume stutter. Sampling CPU in 250ms buckets after
/// returning from the background shows the app getting roughly half the CPU
/// it uses in steady state and taking about two seconds to ramp up to it —
/// it is not doing extra work on resume, it is being given less. With no
/// headroom in the budget, that ramp is paid for in dropped frames, and
/// then everything is fine again, which is exactly how it looks.
///
/// These loops run over 0.65 to 10 seconds, so half the frames buy nothing
/// anyone can see. Gameplay animation is deliberately NOT routed through
/// this — a shell crossing the board should use every frame the display
/// offers.
class AmbientLoop extends ValueNotifier<double> {
  AmbientLoop({required this.period, int fps = 60})
      : _interval = Duration(microseconds: (1000000 / fps).round()),
        super(0) {
    _start();
  }

  final Duration _interval;

  /// How long one full 0→1 cycle takes.
  final Duration period;

  /// Whether this loop should be advancing at all. Drive it from
  /// `TickerMode.valuesOf(context).enabled` in `didChangeDependencies`, the way
  /// [SingleTickerProviderStateMixin] does for a real controller.
  ///
  /// An `AnimationController` gets this for free: Flutter mutes the tickers
  /// of a route that another route has covered. A plain [Timer] does not,
  /// and a covered route is still built and painted (only `offstage` routes
  /// are skipped, which covered ones are not) — so without this, pushing
  /// the Shipyard on top of the menu would leave the menu's scenery
  /// animating away underneath it, at full cost, for nobody.
  ///
  /// Disabling stops the timer outright rather than just ignoring its
  /// callbacks — a cannon spends most of a match reloading with its
  /// ready-pulse off, and there is no reason for it to keep waking up
  /// sixty times a second to decide it has nothing to do.
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (value) {
      _start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  bool _enabled = true;

  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;

  void _start() => _timer ??= Timer.periodic(_interval, (_) => _tick());

  void _tick() {
    // Nothing is on screen to draw, so advancing would only dirty the tree
    // for a frame that will never be rendered. The stopwatch keeps running,
    // so the loop picks up at the right phase when the app comes back
    // rather than resuming wherever it was interrupted.
    //
    // A null state means no lifecycle event has arrived yet, which is the
    // normal situation for the first frames of a cold start (and for the
    // desktop builds). That is not "backgrounded" — treating it as such
    // would leave the scenery frozen until something else woke it.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    value = (_clock.elapsedMicroseconds % period.inMicroseconds) /
        period.inMicroseconds;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }
}
