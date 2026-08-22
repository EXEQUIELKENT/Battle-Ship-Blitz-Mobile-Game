import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Which flavour of notice is being shown — picks the accent colour and
/// default icon so call sites don't have to.
enum AppNoticeType { info, success, error }

/// Chunky flat-cartoon notification banner that drops in from the TOP of
/// the screen and slides back out, replacing the framework's default
/// bottom [SnackBar] everywhere in the app.
///
/// The bottom SnackBar sat under the thumb, got clipped by on-screen
/// keyboards and Android's gesture bar, and used the plain Material
/// default look — completely out of step with the rest of this app's
/// outlined, drop-shadowed cartoon panels. This shows the same [cartoonBox]
/// styling everything else uses, anchors under the status bar where it's
/// always visible, and is easy to dismiss (tap it, swipe it up, or just
/// wait it out).
class AppNotification {
  AppNotification._();

  static OverlayEntry? _entry;
  static Timer? _timer;
  static GlobalKey<_TopNotificationBannerState>? _bannerKey;

  /// Shows [message] as a banner sliding down from the top of the screen.
  /// A notice already on screen is swapped out immediately rather than
  /// stacking, so a burst of quick messages never piles up.
  static void show(
    BuildContext context,
    String message, {
    AppNoticeType type = AppNoticeType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    _timer?.cancel();
    _entry?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);
    final key = GlobalKey<_TopNotificationBannerState>();
    _bannerKey = key;
    final entry = OverlayEntry(
      builder: (context) => _TopNotificationBanner(
        key: key,
        message: message,
        type: type,
        onDismissed: _clear,
      ),
    );
    _entry = entry;
    overlay.insert(entry);

    _timer = Timer(duration, () => _bannerKey?.currentState?.dismiss());
  }

  static void _clear() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
    _bannerKey = null;
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
    _slide = Tween<Offset>(begin: const Offset(0, -1.3), end: Offset.zero)
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
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: _slide,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: dismiss,
                onVerticalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) < 0) dismiss();
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
