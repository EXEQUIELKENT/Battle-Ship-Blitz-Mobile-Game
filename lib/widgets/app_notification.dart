import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Which flavour of notice is being shown — picks the accent colour and
/// default icon so call sites don't have to.
enum AppNoticeType { info, success, error }

/// Chunky flat-cartoon notification banner that slides up from the BOTTOM
/// of the screen and slides back down, replacing the framework's default
/// [SnackBar] everywhere in the app.
///
/// It lives where the old SnackBar did — under the thumb, out of the way
/// of screens' top navigation — but restyled to this app's outlined,
/// drop-shadowed cartoon panels via [cartoonBox], kept clear of Android's
/// gesture bar by [SafeArea], and is easy to dismiss (tap it, flick it
/// down, or just wait it out).
class AppNotification {
  AppNotification._();

  static OverlayEntry? _entry;
  static Timer? _timer;
  static GlobalKey<_TopNotificationBannerState>? _bannerKey;

  /// Bumped every time [show] runs. Everything that tears a banner down
  /// — the auto-dismiss timer, the slide-out completion — remembers the
  /// generation it belongs to and bows out if a newer banner has taken
  /// over. Without this, an old banner's exit animation finishing AFTER
  /// its replacement arrived would reach back through these statics and
  /// cancel the new banner's timer / rip it off screen mid-entrance.
  static int _generation = 0;

  /// Shows [message] as a banner sliding up from the bottom of the
  /// screen. A notice already on screen is swapped out immediately rather than
  /// stacking, so a burst of quick messages (say, hammering an item you
  /// can't afford) always leaves exactly one banner up.
  static void show(
    BuildContext context,
    String message, {
    AppNoticeType type = AppNoticeType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final gen = ++_generation;
    _timer?.cancel();
    // Safe to remove unconditionally: whatever onDismissed the old entry
    // might still be about to call is now generation-stale and no-ops.
    _entry?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);
    final key = GlobalKey<_TopNotificationBannerState>();
    _bannerKey = key;
    final entry = OverlayEntry(
      builder: (context) => _TopNotificationBanner(
        key: key,
        message: message,
        type: type,
        onDismissed: () => _clear(gen),
      ),
    );
    _entry = entry;
    overlay.insert(entry);

    // Auto-dismiss does NOT go through the GlobalKey's state directly:
    // if the timer ever fires before the banner's first frame has been
    // built (pathological frame starvation — or the test harness), that
    // state simply doesn't exist yet and a `currentState?.dismiss()`
    // would silently no-op, leaving an unkillable banner. Route through
    // [_autoDismiss], which falls back to tearing the entry down itself.
    _timer = Timer(duration, () => _autoDismiss(gen));
  }

  /// Fires when [gen]'s notice has lived out its duration.
  static void _autoDismiss(int gen) {
    if (gen != _generation) return;
    final state = _bannerKey?.currentState;
    if (state != null && state.mounted) {
      // The normal path: animate the slide-out; [_clear] runs when the
      // animation lands.
      state.dismiss();
    } else {
      // No live banner to animate — the timer beat its first frame
      // (frame starvation), or it's already on its way out. Tear down
      // directly instead of leaking an unkillable entry.
      _clear(gen);
    }
  }

  /// Tears down the banner of generation [gen] — but only if it is still
  /// the current one.
  static void _clear(int gen) {
    if (gen != _generation) return;
    _timer?.cancel();
    _timer = null;
    _bannerKey = null;
    // Unconditional: OverlayEntry.mounted means "its widget state has
    // been built", NOT merely "inserted" — gating removal on it would
    // leak a banner whose auto-dismiss fired before its first frame ever
    // rendered. remove() itself is safe on an inserted-but-unbuilt entry.
    _entry?.remove();
    _entry = null;
  }
}

class _TopNotificationBanner extends StatefulWidget {
  final String message;
  final AppNoticeType type;
  final VoidCallback onDismissed;

  const _TopNotificationBanner({
    super.key,
    required this.message,
    required this.type,
    required this.onDismissed,
  });

  @override
  State<_TopNotificationBanner> createState() =>
      _TopNotificationBannerState();
}

class _TopNotificationBannerState extends State<_TopNotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 1.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    await _ctrl.reverse();
    widget.onDismissed();
  }

  (Color, IconData) get _style => switch (widget.type) {
        AppNoticeType.success => (AppColors.green, Icons.check_circle),
        AppNoticeType.error => (AppColors.hit, Icons.error),
        AppNoticeType.info => (AppColors.navy, Icons.info),
      };

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _style;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: SlideTransition(
          position: _slide,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: dismiss,
                onVerticalDragEnd: (details) {
                  // Flick DOWN to send it back where it came from — the
                  // natural gesture for something docked at the bottom.
                  if ((details.primaryVelocity ?? 0) > 0) dismiss();
                },
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      decoration: cartoonBox(color, radius: 16),
                      child: Row(
                        children: [
                          Icon(icon, color: AppColors.cream, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.message,
                              style: AppText.body(size: 13, color: AppColors.cream)
                                  .copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.close,
                              color: AppColors.cream.withValues(alpha: 0.7),
                              size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
