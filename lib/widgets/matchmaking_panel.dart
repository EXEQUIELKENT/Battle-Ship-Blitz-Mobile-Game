import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/online_service.dart';
import '../services/sound_service.dart';
import 'neon_widgets.dart';

/// The MATCHMAKING page of the ONLINE section — the second tab next to
/// FRIENDS inside `FriendsScreen`'s two-tab body.
///
/// Same flow the old standalone matchmaking screen ran:
///
///   1. SEARCHING — the loading state, radar spinning, until the server
///      pairs this captain with another searching player.
///   2. MATCH FOUND — BOTH captains must tap accept before anything
///      starts. Saying yes shows how far the other one has got; saying
///      no (or letting the prompt time out) releases both players.
///   3. Both yeses land within the window — the match turns active and
///      the owning `FriendsScreen` picks it up from the shared
///      `OnlineService`, handing it to the ordinary match flow exactly as
///      it does for an accepted invitation.
///
/// The panel deliberately never launches a match itself: single-owner
/// rules say the screen that owns the match lifecycle
/// (`FriendsScreen._onOnline`) does the launch, so an invitation and a
/// matchmaking pairing can never double-fire from two listeners watching
/// the same `match`.
class MatchmakingPanel extends StatefulWidget {
  const MatchmakingPanel({super.key});

  @override
  State<MatchmakingPanel> createState() => _MatchmakingPanelState();
}

class _MatchmakingPanelState extends State<MatchmakingPanel>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final OnlineService _online;

  late final AnimationController _radar;
  Timer? _rejoinTimer;
  Timer? _ticker;
  DateTime? _searchSince;

  /// Whether the player still wants to be matched. Backing out — or the
  /// match finally sailing — stops the automatic re-queue.
  bool _wantSearch = true;

  /// Set when WE declined a pairing ourselves, so the release that our
  /// own action causes doesn't get reported as "the other captain left".
  bool _selfDeclined = false;

  /// True while a poll had us either queued or paired. The first poll
  /// showing neither means the pairing dissolved under us.
  bool _inFlow = false;

  /// One-line reason shown between pairings ("opponent declined", "could
  /// not reach the server", …). Cleared on the next search.
  String? _notice;

  String _lastPeerName = 'THE OTHER CAPTAIN';

  /// Flipping to the FRIENDS tab must not drop the search — the queue
  /// stays live whenever the ONLINE section is open.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _online = context.read<OnlineService>();
    _online.addListener(_onOnline);
    _radar = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Fast polls while matchmaking, so "they accepted!" lands in a
      // blink rather than on the friends-list tick.
      _online.setFastPolling(true);
      await _join();
    });

    // Drives the elapsed-seconds line while the radar spins.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _online.searching && _wantSearch) setState(() {});
    });
  }
  @override
  void dispose() {
    // Leaving the ONLINE section entirely (back to the main menu) stops
    // everything: the search, the fast polls, the radar, the clock.
    _online.removeListener(_onOnline);
    _rejoinTimer?.cancel();
    _ticker?.cancel();
    _radar.dispose();
    _online.setFastPolling(false);
    unawaited(_online.leaveQueue());
    super.dispose();
  }

  Future<void> _join() async {
    if (!_wantSearch || !mounted) return;
    setState(() {
      _notice = null;
      _selfDeclined = false;
    });
    final ok = await _online.joinQueue();
    if (!ok && mounted && _wantSearch) {
      setState(
        () => _notice = _online.lastError ?? 'Could not join the search.',
      );
      _scheduleRejoin(const Duration(seconds: 3));
    }
  }

  void _scheduleRejoin(Duration delay) {
    _rejoinTimer?.cancel();
    _rejoinTimer = Timer(delay, () {
      if (mounted && _wantSearch) unawaited(_join());
    });
  }

  /// The pairing dissolved under us — the other captain declined, or let
  /// the prompt expire. Say so, then quietly re-join the queue.
  void _handleRelease() {
    if (!_wantSearch) return;
    final why = _selfDeclined
        ? 'DECLINED — STILL SEARCHING…'
        : '$_lastPeerName DECLINED OR TIMED OUT.';
    if (!mounted) return;
    setState(() => _notice = why);
    _scheduleRejoin(const Duration(milliseconds: 1500));
  }

  void _onOnline() {
    if (!mounted) return;
    final match = _online.match;

    if (match != null) _lastPeerName = match.peerName;

    // Both captains accepted — the owning `FriendsScreen` launches the
    // match. Step aside and stop the queue machinery so nothing here
    // re-joins once the battle is over.
    if (match != null && match.isActive && match.id != 0) {
      _wantSearch = false;
      _inFlow = false;
      _rejoinTimer?.cancel();
      return;
    }

    final inFlowNow = _online.searching || (match?.isFound ?? false);
    if (inFlowNow) {
      _inFlow = true;
      return;
    }
    if (_inFlow && !_online.searching && match == null && _wantSearch) {
      _inFlow = false;
      _handleRelease();
    }
  }

  Future<void> _accept(OnlineMatch match) async {
    await _online.acceptMatch(match.id);
  }

  /// Declining ends the pairing for BOTH players; our own poll then
  /// reports neither queue nor match, which [_onOnline] reads as a
  /// release — tagged self-inflicted — and the search resumes.
  Future<void> _decline(OnlineMatch match) async {
    _selfDeclined = true;
    await _online.leaveQueue();
  }

  /// Stops the search and rests the page (no `Navigator.pop` — this is a
  /// tab, not a route).
  void _cancel() {
    SoundService.instance.click();
    _wantSearch = false;
    _rejoinTimer?.cancel();
    unawaited(_online.leaveQueue());
    _online.setFastPolling(false);
    if (mounted) setState(() {});
  }

  /// Starts a fresh search from the resting state.
  Future<void> _startSearch() async {
    if (!mounted) return;
    setState(() {
      _wantSearch = true;
      _selfDeclined = false;
      _notice = null;
    });
    _online.setFastPolling(true);
    await _join();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final online = context.watch<OnlineService>();
    final match = online.match;
    final busy = online.busy;

    // Drives the elapsed-seconds line while the radar spins (a poll may
    // flip us out of the searching state without a tick in between).
    if (online.searching && _searchSince == null) {
      _searchSince = DateTime.now();
    } else if (!online.searching) {
      _searchSince = null;
    }

    final body = match != null && match.isFound
        ? (match.youAccepted
              ? _waitingOnPeer(match, busy)
              : _foundCard(match, busy))
        : online.searching
        ? _searchingBody(online)
        : _betweenBody(online);

    return Padding(padding: const EdgeInsets.all(24), child: body);
  }
// ------------------------------------------------------------ STATES --

  /// Loading: radar sweep, waiting copy, cancel.
  Widget _searchingBody(OnlineService online) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AnimatedBuilder(
            animation: _radar,
            builder: (_, __) => CustomPaint(
              size: const Size(150, 150),
              painter: _RadarPainter(sweep: _radar.value),
            ),
          ),
        ),
        const SizedBox(height: 28),
        // Dark navy ink, not the default cream — this sits straight on
        // the light coral deck with no card behind it, and cream-on-coral
        // (or gold-on-coral, below) is nearly unreadable.
        Text(
          'SEARCHING FOR\nAN OPPONENT…',
          textAlign: TextAlign.center,
          style: AppText.title(size: 20, color: AppColors.navy),
        ),
        const SizedBox(height: 10),
        Text(
          'Both captains must accept the match\nbefore it begins.',
          textAlign: TextAlign.center,
          style: AppText.body(size: 12, color: AppColors.inkSoft),
        ),
        if (_elapsedLabel.isNotEmpty) ...[
          const SizedBox(height: 16),
          // The elapsed-time timer itself — a solid navy chip instead of
          // bare gold text, so it stays legible no matter what's behind
          // it and reads as a proper HUD readout rather than a caption.
          Center(
            child: HudChip(
              icon: Icons.timer,
              text: _elapsedLabel,
              color: AppColors.navy,
            ),
          ),
        ],
        if (online.lastError != null) ...[
          const SizedBox(height: 12),
          _errorBanner(online.lastError!),
        ],
        const SizedBox(height: 34),
        NeonButton(
          label: 'CANCEL',
          icon: Icons.close,
          color: AppColors.hit,
          onPressed: _cancel,
        ),
      ],
    );
  }

  /// A short server/connection error, shown as a full-width chunky pill
  /// instead of bare text — this page has no card behind it here, and
  /// gold or cream text directly on the coral deck was unreadable.
  Widget _errorBanner(String message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: cartoonBox(AppColors.hit, radius: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber, color: AppColors.cream, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.label(size: 10, color: AppColors.cream),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _elapsedLabel {
    final since = _searchSince;
    if (since == null) return '';
    final secs = DateTime.now().difference(since).inSeconds;
    if (secs < 60) return '$secs SECONDS AT SEA';
    return '${(secs / 60).floor()}M ${secs % 60}S AT SEA';
  }
/// Paired; neither of us has answered yet.
  Widget _foundCard(OnlineMatch match, bool busy) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: cartoonBox(AppColors.gold, radius: 20),
          child: Column(
            children: [
              const Icon(Icons.sports_esports,
                  size: 40, color: AppColors.outline),
              const SizedBox(height: 10),
              Text('MATCH FOUND!',
                  textAlign: TextAlign.center,
                  style: AppText.title(size: 24, color: AppColors.outline)),
              const SizedBox(height: 6),
              Text('vs ${match.peerName.toUpperCase()}',
                  textAlign: TextAlign.center,
                  style: AppText.heading(size: 15, color: AppColors.navy)),
              const SizedBox(height: 4),
              Text('Both captains must accept to play.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 11.5, color: AppColors.inkSoft)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        NeonButton(
          label: 'ACCEPT',
          icon: Icons.check_circle,
          color: AppColors.seafoam,
          onPressed: busy ? null : () => _accept(match),
        ),
        const SizedBox(height: 10),
        NeonButton(
          label: 'DECLINE',
          icon: Icons.close,
          color: AppColors.hit,
          onPressed: busy ? null : () => _decline(match),
        ),
      ],
    );
  }

  /// We said yes; the other captain hasn't yet.
  Widget _waitingOnPeer(OnlineMatch match, bool busy) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: cartoonBox(AppColors.cream, radius: 20),
          child: Column(
            children: [
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  valueColor: AlwaysStoppedAnimation(AppColors.blue),
                ),
              ),
              const SizedBox(height: 16),
              Text('YOU ACCEPTED',
                  textAlign: TextAlign.center,
                  style: AppText.label(size: 11, color: AppColors.green)),
              const SizedBox(height: 8),
              Text(
                'WAITING FOR\n${match.peerName.toUpperCase()} TO ACCEPT…',
                textAlign: TextAlign.center,
                style: AppText.title(size: 17, color: AppColors.navy),
              ),
              const SizedBox(height: 6),
              Text('The match begins the moment they do.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 11, color: AppColors.inkSoft)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        NeonButton(
          label: 'CANCEL',
          icon: Icons.close,
          color: AppColors.hit,
          onPressed: busy ? null : () => _decline(match),
        ),
      ],
    );
  }
/// Between pairings — declined, timed out, or a failed request. Brief
  /// notice, then the automatic re-join takes over. When the player has
  /// stepped OUT (cancelled, or just sailed a match back in the friends
  /// tab), this rests instead until they tap SEARCH AGAIN.
  Widget _betweenBody(OnlineService online) {
    final resting = !_wantSearch;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          resting
              ? (_notice ?? 'READY WHEN YOU ARE')
              : (_notice ?? 'BACK IN THE SEARCH…'),
          textAlign: TextAlign.center,
          style: AppText.body(size: 13, color: AppColors.navy),
        ),
        if (online.lastError != null) ...[
          const SizedBox(height: 12),
          _errorBanner(online.lastError!),
        ],
        const SizedBox(height: 24),
        if (!resting) ...[
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(AppColors.gold),
              ),
            ),
          ),
        ],
        const SizedBox(height: 30),
        NeonButton(
          label: resting ? 'SEARCH AGAIN' : 'CANCEL',
          icon: resting ? Icons.radar : Icons.close,
          color: resting ? AppColors.ember : AppColors.hit,
          onPressed: resting ? _startSearch : _cancel,
        ),
      ],
    );
  }
}

/// The loading-state radar: rings, two blips and a rotating sonar sweep.
class _RadarPainter extends CustomPainter {
  final double sweep;
  const _RadarPainter({required this.sweep});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    final rings = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppColors.sonar.withValues(alpha: 0.55);
    for (final f in const [1.0, 0.72, 0.44]) {
      canvas.drawCircle(c, r * f, rings);
    }

    canvas.drawCircle(
      c + Offset.fromDirection(-0.9, r * 0.62),
      4.5,
      Paint()..color = AppColors.seafoam,
    );
    canvas.drawCircle(
      c + Offset.fromDirection(2.3, r * 0.35),
      3,
      Paint()..color = AppColors.seafoam.withValues(alpha: 0.7),
    );

    final beam = Paint()
      ..shader = SweepGradient(
        colors: [
          AppColors.sonar.withValues(alpha: 0.0),
          AppColors.sonar.withValues(alpha: 0.55),
        ],
        transform: GradientRotation(sweep * 6.283 - 1.57),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r * 0.98, beam);

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.outline,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) => oldDelegate.sweep != sweep;
}