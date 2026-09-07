import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/online_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import 'lobby_widgets.dart';
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

  /// When this device first saw the current pairing, which is what the
  /// accept countdown runs from — see [OnlineService.pairHold].
  DateTime? _foundAt;

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

    // Drives both clocks: the elapsed one while the radar spins, and the
    // pairing countdown once a captain answers. The countdown was the
    // reason this had to stop being search-only — a number that only
    // moves while you are searching is not a deadline.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final paired = _online.match?.isFound ?? false;
      if (paired || (_online.searching && _wantSearch)) setState(() {});
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

    // Same for the pairing clock — stamped the first frame a pairing is
    // on screen, and dropped the moment it isn't, so a second pairing
    // never inherits the first one's remaining time.
    if (match != null && match.isFound) {
      _foundAt ??= DateTime.now();
    } else {
      _foundAt = null;
    }

    final Widget body;
    final Key bodyKey;
    if (match != null && match.isFound) {
      body = _pairedCard(online, match, busy);
      bodyKey = const ValueKey('paired');
    } else if (online.searching) {
      body = _searchingBody(online);
      bodyKey = const ValueKey('searching');
    } else {
      body = _betweenBody(online);
      bodyKey = const ValueKey('between');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      // FEEDBACK ("different transition animations... whether you click
      // or do any activity"): these three states used to swap via a bare
      // ternary — a poll landing mid-frame replaced the whole subtree with
      // no transition at all, so "someone accepted" or "the search timed
      // out" read as a flicker rather than something having happened. A
      // scale+fade here doubles as the cue itself: this state ended,
      // that one began.
      child: AnimatedSwitcher(
        // FEEDBACK ("make all of the animations smooth and slowly").
        duration: const Duration(milliseconds: 460),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: bodyKey, child: body),
      ),
    );
  }
// ------------------------------------------------------------ STATES --

  /// Searching: the wait itself, in a card, with the radar as its dial.
  ///
  /// REDESIGN: this used to be a bare column on the coral deck — a big
  /// radar, two lines of centred prose and a button, none of it bounded by
  /// anything. It reads as a panel now, the same shape the pairing prompt
  /// that replaces it does, so the page doesn't visibly change its mind
  /// about what kind of surface it is the moment a captain is found.
  ///
  /// The clock counts UP, and the bar under it is indeterminate: a search
  /// runs until somebody else joins the queue, and there is no honest
  /// deadline to draw a draining bar against. The pairing card is where a
  /// real countdown belongs, because there a real one exists.
  Widget _searchingBody(OnlineService online) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          decoration: cartoonBox(AppColors.cream, radius: 20),
          child: Column(
            children: [
              Text(
                'SEARCHING THE SEAS',
                textAlign: TextAlign.center,
                style: AppText.title(size: 20, color: AppColors.navy),
              ),
              const SizedBox(height: 6),
              Text(
                // Accurate to what the server actually does: it pairs the
                // captain who has been waiting longest, not by rank.
                'Whoever has been waiting longest is paired first —\n'
                'give it a moment.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 11.5, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 18),
              AnimatedBuilder(
                animation: _radar,
                builder: (_, __) => ScanDial(sweep: _radar.value, size: 96),
              ),
              const SizedBox(height: 18),
              Text(
                _elapsedClock,
                style: AppText.title(size: 30, color: AppColors.navy),
              ),
              const SizedBox(height: 4),
              Text(
                _elapsedLabel,
                style: AppText.label(size: 9, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              const LobbyProgressBar(color: AppColors.blue),
            ],
          ),
        ),
        if (online.lastError != null) ...[
          const SizedBox(height: 12),
          _errorBanner(online.lastError!),
        ],
        const SizedBox(height: 18),
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

  String get _elapsedClock {
    final since = _searchSince;
    if (since == null) return '0:00';
    return CountdownBar.format(DateTime.now().difference(since));
  }

  String get _elapsedLabel =>
      _searchSince == null ? 'AT SEA' : 'AT SEA, LOOKING FOR A CAPTAIN';

  /// Paired. One card covers both halves of the handshake — waiting on
  /// either captain, or on both — because they are the same moment seen
  /// from different sides, and swapping the whole panel between them made
  /// the prompt appear to restart the instant you tapped accept.
  ///
  /// What replaced two near-identical cards: who the opponent is, how long
  /// the pairing is held for, and which of the two yeses are in. The
  /// buttons are the only part that actually differs.
  Widget _pairedCard(OnlineService online, OnlineMatch match, bool busy) {
    final youIn = match.youAccepted;
    final remaining = _pairRemaining;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: cartoonBox(AppColors.cream, radius: 20),
          child: Column(
            children: [
              Text(
                'A CAPTAIN ANSWERED',
                textAlign: TextAlign.center,
                style: AppText.title(size: 20, color: AppColors.navy),
              ),
              const SizedBox(height: 6),
              Text(
                'Both of you accept and the mode vote opens.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 11.5, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 16),
              CountdownBar(
                remaining: remaining,
                total: OnlineService.pairHold,
              ),
              const SizedBox(height: 16),
              _opponentRow(online, match),
              const SizedBox(height: 16),
              AcceptPair(
                youAccepted: youIn,
                peerAccepted: match.peerAccepted,
                peerName: match.peerName,
              ),
              const SizedBox(height: 14),
              Text(
                youIn
                    ? 'WAITING ON ${match.peerName.toUpperCase()} — THE MATCH '
                        'STARTS THE MOMENT THEY ACCEPT'
                    : 'BOTH MUST ACCEPT BEFORE THE CLOCK RUNS OUT, OR YOU '
                        'BOTH GO BACK IN THE QUEUE',
                textAlign: TextAlign.center,
                style: AppText.label(size: 8.5, color: AppColors.hit),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: NeonButton(
                label: youIn ? 'CANCEL' : 'DECLINE',
                icon: Icons.close,
                color: AppColors.hit,
                compact: true,
                onPressed: busy ? null : () => _decline(match),
              ),
            ),
            if (!youIn) ...[
              const SizedBox(width: 12),
              Expanded(
                child: NeonButton(
                  label: 'ACCEPT',
                  icon: Icons.check_circle,
                  color: AppColors.seafoam,
                  compact: true,
                  onPressed: busy ? null : () => _accept(match),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Who you have been paired with. Their record is shown only when this
  /// device actually knows it — a friend, or someone already in the
  /// captain's log — because matchmaking pairs strangers by wait time and
  /// the pairing itself carries nothing but a name.
  Widget _opponentRow(OnlineService online, OnlineMatch match) {
    OnlinePlayer? known;
    for (final f in online.friends) {
      if (f.id == match.peerId) {
        known = f;
        break;
      }
    }
    final subtitle = known == null
        ? 'MET IN THE OPEN SEAS'
        : '${rankTitleForRp(known.rp)}  ·  ${known.rp} RP  ·  '
            '${known.wins}W ${known.losses}L';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: cartoonBox(AppColors.coralLight, radius: 14),
      child: Row(
        children: [
          CaptainAvatar(name: match.peerName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.peerName.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: AppText.heading(size: 14, color: AppColors.navy),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(size: 8.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Time left on the pairing, measured from when this device first saw
  /// it — see [OnlineService.pairHold] for why that is the honest clock
  /// to count from and why it errs short.
  Duration get _pairRemaining {
    final since = _foundAt;
    if (since == null) return OnlineService.pairHold;
    final left = OnlineService.pairHold - DateTime.now().difference(since);
    return left.isNegative ? Duration.zero : left;
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

// The loading-state radar this file used to carry is now `ScanDial` in
// `lobby_widgets.dart`, shared with the HOTSPOT screen's own sweep — the
// two were drawing the same idea in two different hands.