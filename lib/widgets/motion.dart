import 'dart:async';

import 'package:flutter/material.dart';

/// Small, reusable motion for individual elements — tap feedback and the
/// staggered "pop in" every button/card/element on a screen plays once,
/// the first time that screen appears.
///
/// FEEDBACK ("all of the buttons, cards, elements will have unique pop up
/// animation when first time opening a screen... 1 by 1 not
/// simultaneously"), later slowed and smoothed on its own feedback
/// ("make all of the animations smooth and slowly"). [PopIn] is that
/// entrance: a slow, smooth scale-up-from-under-size (no bounce/
/// overshoot — see the curve note in [_PopInState]) plus a fade, and
/// [PopSequence] is what staggers a whole screen's worth of them one
/// after another without every call site having to compute its own
/// index or delay by hand.
///
/// FEEDBACK (earlier round, now reverted): a matching set of custom
/// PAGE-to-page route transitions used to live in this file too. That
/// was a different ask — how a screen ARRIVES — and has been pulled back
/// out to plain `MaterialPageRoute` everywhere; this file is now only
/// about what happens on the screen once it's there.
///
/// PERF: every animation here is either a Flutter built-in
/// (`ScaleTransition`/`FadeTransition`) or a single short-lived
/// `AnimationController` that runs once and stops — never a repeating
/// ticker, and never a `RepaintBoundary` placed under a `Transform` (see
/// `cannon_widget.dart`'s doc from the last round of performance work for
/// exactly what that combination costs).

/// Wraps any tappable custom element (a list row, a chip, a shop card) in
/// a small press-down squash, exactly the feedback `NeonButton` already
/// gives its own buttons — this is that same language extended to the
/// bespoke widgets that were built with a bare `GestureDetector` and no
/// visual response at all until whatever the tap DID finished.
///
/// A drop-in replacement for that `GestureDetector`: pass the same
/// [onTap] and wrap the same child. `null` disables both the gesture and
/// the squash, matching a disabled button rather than a dead tap target
/// that still visually depresses.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final Duration duration;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    // FEEDBACK ("make all of the animations smooth and slowly"): was
    // 110ms. Kept short of [PopIn]'s own slower pace on purpose — this is
    // the one animation here that has to answer an actual finger on
    // glass, and a press that visibly lags the touch reads as the app
    // being slow to respond, not as a smoother app.
    this.duration = const Duration(milliseconds: 160),
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapCancel: () => _set(false),
      onTapUp: enabled ? (_) => _set(false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Hands out one incrementing slot per element on a screen, so wrapping a
/// whole `build()` in pop-in entrances doesn't mean hand-computing a
/// delay for every single button and card.
///
/// Usage: create ONE per `build()` call (it is cheap — just a counter —
/// so a fresh one every rebuild is correct and intentional; see [PopIn]
/// for why a later rebuild doesn't replay the animation), then wrap each
/// element as it's built:
/// ```dart
/// final pop = PopSequence();
/// ...
/// pop.wrap(NeonButton(...)),
/// ...
/// pop.wrap(_someCard()),
/// ```
/// Slots are capped (see [maxSteps]) so a screen with a great many small
/// elements doesn't leave the last one waiting an absurd amount of time
/// — everything past the cap starts at the same, latest delay together.
class PopSequence {
  int _next = 0;
  final Duration step;
  final Duration duration;
  final int maxSteps;

  /// Bump this (a `ValueNotifier<int>`, say) to replay the whole
  /// sequence — see [PopIn.restart]. Only needed by a screen that stays
  /// mounted while it is not visible; a pushed screen gets a fresh
  /// `State` (and so a fresh entrance) every time it is opened.
  final Listenable? restart;

  // FEEDBACK ("there is a small pause on each screen that have that"):
  // step was 130ms with a 520ms pop and a cap of 8, so the LAST element
  // on a busy screen didn't start until ~1.04s and didn't finish until
  // ~1.56s. The page itself lands in about 300ms (the platform route
  // transition), so for over a second after arriving it sat there
  // visibly unfinished — content trickling in long after the screen was
  // "there", which is exactly what reads as a pause.
  //
  // Tightened so the whole screen is settled inside ~1s while each
  // individual element still moves slowly enough to read as deliberate:
  // the pop itself is barely shorter, it is the WAIT between elements
  // and the cap on how many waits deep it can go that came down.
  PopSequence({
    this.step = const Duration(milliseconds: 90),
    this.duration = const Duration(milliseconds: 380),
    this.maxSteps = 6,
    this.restart,
  });

  Widget wrap(Widget child, {Key? key}) {
    final slot = _next < maxSteps ? _next : maxSteps;
    _next++;
    return PopIn(
      key: key,
      delay: step * slot,
      duration: duration,
      restart: restart,
      child: child,
    );
  }
}

/// One element popping into place: scaled slowly and smoothly up from
/// just under full size, fading in at the same time.
///
/// Plays exactly ONCE, on this element's first appearance — the
/// [AnimationController] behind it starts in [initState] (after
/// [delay]) and never repeats. A parent rebuilding for an unrelated
/// reason (a poll landing, a `setState` elsewhere on the screen) does
/// NOT replay it: Flutter reuses this widget's `State` across rebuilds
/// as long as it stays at the same place in the tree, and `initState`
/// only ever runs on the FIRST of those. Give it an explicit [key] when
/// wrapping an element that could otherwise be mistaken for a different
/// one at the same position (a list row, keyed on its own id) — see
/// [PopSequence.wrap]. Pass [restart] where the entrance needs to play
/// again on a screen that never unmounts.
///
/// Prefer going through [PopSequence] over using this directly: it's
/// what keeps twenty elements on one screen from all having to agree by
/// hand on which of them goes first.
class PopIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  /// How far under full size the pop starts — 0.9 reads as a gentle
  /// pop; smaller reads bigger/bouncier.
  final double fromScale;

  /// Notifying this replays the entrance from the beginning, [delay]
  /// included.
  ///
  /// FEEDBACK ("the main menu does not have pop up on the buttons
  /// animations and elements"). Every other screen is PUSHED, so it is
  /// built fresh — new `State`, new `initState`, entrance plays — every
  /// single time it is opened. The main menu is the app's root route: it
  /// is built once at launch and then just sits underneath whatever is
  /// pushed on top of it, so coming "back" to it never rebuilds anything
  /// and its entrance had already played, once, before the player had
  /// really looked at it.
  ///
  /// Deliberately a [Listenable] rather than remounting the subtree on a
  /// changed key: remounting would throw away the state of everything
  /// wrapped, and on the menu that includes the hero dock's own hull
  /// cycling and drag position.
  final Listenable? restart;

  const PopIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    // FEEDBACK ("make all of the animations smooth and slowly", then
    // "there is a small pause"): 340ms, then 520ms, now 380ms — see
    // [PopSequence]'s own note for why the wait BETWEEN elements is what
    // actually needed to come down, and [_PopInState.initState] for the
    // curve.
    this.duration = const Duration(milliseconds: 380),
    this.fromScale = 0.9,
    this.restart,
  });

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  /// The pending "start after [PopIn.delay]" wait, held so [dispose] can
  /// cancel it outright.
  ///
  /// BUGFIX: this used to be a bare `Future.delayed`, which has no
  /// handle to cancel — the `if (mounted)` guard inside it was already
  /// enough to make an unmounted widget's delay a safe no-op, but the
  /// underlying `Timer` a `Future.delayed` schedules keeps running
  /// regardless, and a screen that navigates away before a longer delay
  /// (several elements into a slow stagger) elapses left it ticking.
  /// Harmless in the running app; `flutter_test` asserts on it directly
  /// ("A Timer is still pending even after the widget tree was
  /// disposed"), which is what actually caught this. A real `Timer` can
  /// be cancelled, so the wait no longer outlives the widget it belongs
  /// to either way.
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(
      parent: _ctrl,
      // Faded in across most of the pop rather than racing ahead of it,
      // so the two finish together instead of the shape sitting fully
      // opaque while it's still visibly growing.
      curve: const Interval(0.0, 0.85, curve: Curves.easeOut),
    );
    // FEEDBACK ("make all of the animations smooth and slowly"):
    // `Curves.easeOutBack` overshoots past 1.0 and springs back — a
    // "pop" by design, but a snap rather than smooth, and one that reads
    // twitchier the more of these are on screen staggering in one after
    // another. A plain decelerating curve keeps the "grows into place"
    // read without the bounce.
    _scale = Tween<double>(begin: widget.fromScale, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _play();
    widget.restart?.addListener(_replay);
  }

  /// Runs the entrance from wherever the controller currently sits,
  /// after this element's own place in the stagger comes up.
  void _play() {
    _delayTimer?.cancel();
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  /// Back to the start and away again — see [PopIn.restart].
  void _replay() {
    if (!mounted) return;
    _ctrl.value = 0;
    _play();
  }

  @override
  void didUpdateWidget(PopIn old) {
    super.didUpdateWidget(old);
    if (old.restart != widget.restart) {
      old.restart?.removeListener(_replay);
      widget.restart?.addListener(_replay);
    }
  }

  @override
  void dispose() {
    widget.restart?.removeListener(_replay);
    _delayTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
