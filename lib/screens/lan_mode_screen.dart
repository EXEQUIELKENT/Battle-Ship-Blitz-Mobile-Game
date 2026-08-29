import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fleet_identity.dart';
import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/network_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/match_chat.dart';
import '../widgets/ocean_background.dart';
import 'placement_screen.dart';

/// One icon per mode. MANOEUVRE used to share TURN BASED's icon, which
/// made the two cards read as the same thing at a glance — the very
/// distinction the card is there to draw. The "move" cross is what the
/// mode is actually about: a fleet that can still be dragged around.
///
/// Top-level (not a method on [LanModeScreen]) so [VsAiModeScreen]'s own
/// mode cards — same picker, no peer to vote with — can share it too.
IconData lanModeIcon(LanBattleMode mode) => switch (mode) {
      LanBattleMode.chaos => Icons.whatshot,
      LanBattleMode.turns => Icons.swap_vert_circle,
      LanBattleMode.rearrange => Icons.open_with,
      LanBattleMode.blitz => Icons.bolt,
      LanBattleMode.ghost => Icons.blur_on,
      LanBattleMode.powerPlay => Icons.auto_awesome,
      LanBattleMode.phantom => Icons.visibility_off,
    };

/// Sits between "the two devices are connected" and "deploy your fleet":
/// both captains tap the mode they want to play, the mode with the most
/// taps wins, and once BOTH have picked, a 5-second countdown runs so
/// either of them can still change their mind before it locks in.
///
/// All of the actual vote state (who picked what, the countdown, the
/// final answer) lives in [NetworkService] rather than here — see the
/// notes there for why it deliberately isn't pushed through the message
/// stream. This screen is purely the face of it.
class LanModeScreen extends StatefulWidget {
  /// The network mode this match is running under — [GameMode.hotspot] or
  /// [GameMode.online]. Handed straight to the controller once the vote
  /// resolves.
  final GameMode mode;

  const LanModeScreen({super.key, required this.mode});

  @override
  State<LanModeScreen> createState() => _LanModeScreenState();
}

class _LanModeScreenState extends State<LanModeScreen> {
  late final NetworkService _net;
  bool _navigated = false;

  /// Short hold after the vote locks, so both players actually SEE which
  /// mode won (and the final tally) before the screen changes out from
  /// under them.
  Timer? _lockHold;
  static const _lockHoldDuration = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    _net = context.read<NetworkService>();
    _net.addListener(_onNet);
    // Deliberately NOT resetting the vote here: `hostHotspot`/`joinHotspot`
    // both call `stop()` (which clears it) before the socket is even
    // opened, so it's already fresh by the time a connection exists.
    // Clearing it on THIS screen instead would open a race where a peer
    // who tapped a mode a frame earlier had their vote wiped.
  }

  @override
  void dispose() {
    _lockHold?.cancel();
    _net.removeListener(_onNet);
    super.dispose();
  }

  void _onNet() {
    if (!mounted) return;
    if (_net.lockedMode != null && _lockHold == null && !_navigated) {
      // The "match locked" clunk plays the device owner's own equipped
      // cannon's reload sound — the gun they're about to sail into the
      // match with (see `_firePreviewShot` on the deploy screen for the
      // same rule).
      SoundService.instance.cannonReady(
        cannonSkinId: Loadout.of(context.read<ProfileStore>()).cannonSkinId,
      );
      _lockHold = Timer(_lockHoldDuration, _startMatch);
    }
  }

  void _startMatch() {
    if (!mounted || _navigated) return;
    final chosen = _net.lockedMode;
    if (chosen == null) return;
    _navigated = true;
    final controller = context.read<GameController>();
    controller.mode = widget.mode;
    controller.lanBattleMode = chosen;
    controller.attachNetwork();
    controller.startPlacement();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PlacementScreen()),
    );
  }

  void _vote(LanBattleMode mode) {
    SoundService.instance.click();
    _net.castVote(mode);
  }

  /// Backing out here abandons the match, so the socket has to come down
  /// with it. Handled in one place — the `PopScope` below — so the header
  /// arrow and the system back gesture behave identically.
  void _leave() {
    SoundService.instance.click();
    Navigator.pop(context);
  }

  /// How each captain reads on screen. The host commands the red fleet
  /// and the joiner the blue one — unless one of them equipped a hull of
  /// their own in the shipyard, in which case that is their colour here
  /// too. Same shared rule the deployment screen and the battle grid use
  /// (`fleet_identity.dart`), so the colour a player is introduced with
  /// on this screen is the colour they actually sail.
  FleetLook get _myLook {
    final p = context.read<ProfileStore>();
    return fleetLook(
      isRedSide: _net.isHost,
      equippedShipSkinId: p.shipSkinId,
      chosen: p.shipSkinChosen,
    );
  }

  FleetLook get _peerLook => fleetLook(
        isRedSide: !_net.isHost,
        equippedShipSkinId: _net.peerShipSkinId,
        chosen: _net.peerShipSkinChosen,
      );

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkService>();
    final myName = context.watch<ProfileStore>().playerName;
    final locked = net.lockedMode;

    // Leaving this screen backwards means abandoning the match, so the
    // connection is torn down with it — but NOT when we're leaving
    // forwards into placement, which replaces this route with the vote
    // already agreed and the socket very much still needed.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_navigated) _net.stop();
      },
      child: Scaffold(
        body: OceanBackground(
          showSonar: false,
          child: SafeArea(
            child: Column(
              children: [
                // ---------- Navy header ----------
                Container(
                  width: double.infinity,
                  color: AppColors.navy,
                  padding: const EdgeInsets.fromLTRB(8, 10, 14, 14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: AppColors.cream),
                            onPressed: _leave,
                          ),
                          Expanded(
                            child: Text('CHOOSE BATTLE MODE',
                                style: AppText.title(size: 18)),
                          ),
                          // In the header rather than floating over the
                          // cards: a split vote is resolved by talking,
                          // so the chat has to be reachable without
                          // covering the very thing you're discussing.
                          const MatchChatButton(size: 36),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Who's who — this is also the first place either
                      // player sees which fleet colour they command.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _CaptainChip(
                            name: myName.toUpperCase(),
                            role: net.isHost ? 'HOST' : 'CHALLENGER',
                            look: _myLook,
                          ),
                          const SizedBox(width: 10),
                          Text('VS', style: AppText.label(size: 11)),
                          const SizedBox(width: 10),
                          _CaptainChip(
                            name: net.peerName.toUpperCase(),
                            role: net.isHost ? 'CHALLENGER' : 'HOST',
                            look: _peerLook,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ---------- The two modes ----------
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                    children: [
                      Text(
                        'BOTH CAPTAINS MUST PICK THE SAME MODE.\n'
                        'THE MATCH WILL NOT START ON A SPLIT VOTE.',
                        textAlign: TextAlign.center,
                        // Sits directly on the coral deck (no card, no
                        // navy panel behind it) — cream was unreadable
                        // here, so this uses the same dark navy ink the
                        // cards below it use.
                        style: AppText.label(size: 10, color: AppColors.navy),
                      ),
                      const SizedBox(height: 14),
                      // Four modes now, so this scrolls — which it
                      // already did, since a phone was never going to fit
                      // three cards of this weight either.
                      for (final mode in LanBattleMode.values) ...[
                        _modeCard(net, mode, myName),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),

                // ---------- Countdown / status ----------
                Container(
                  width: double.infinity,
                  color: AppColors.navy,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                  child: locked != null
                      ? _lockedBanner(locked)
                      : net.voteCountdown != null
                          ? _countdown(net.voteCountdown!)
                          : _waitingLine(net),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- CARDS ---

  Widget _modeCard(NetworkService net, LanBattleMode mode, String myName) {
    final myPick = net.myVote == mode;
    final peerPick = net.peerVote == mode;
    final votes = (myPick ? 1 : 0) + (peerPick ? 1 : 0);
    final locked = net.lockedMode;
    final isWinner = locked == mode;
    final lostOut = locked != null && !isWinner;

    final me = _myLook;
    final peer = _peerLook;
    // The card's highlight is the colour of whoever picked it, taken from
    // the same place their hulls are — so a captain in Arctic Storm gets
    // a pale border with dark ink on their badge, not a red one.
    final accent = isWinner
        ? AppColors.seafoam
        : myPick
            ? me.color
            : peerPick
                ? peer.color
                : AppColors.outline;

    return Opacity(
      opacity: lostOut ? 0.42 : 1,
      child: GestureDetector(
        onTap: locked != null ? null : () => _vote(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // Snug: three modes have to share the screen with a header and
          // a countdown without turning the list into a scroll marathon.
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent,
              width: (myPick || peerPick || isWinner) ? 5 : 3,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x55000000), offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    lanModeIcon(mode),
                    // The card body is cream, so a near-white hull colour
                    // would vanish on it — fall back to the outline ink
                    // for very pale identities.
                    color: accent == AppColors.outline ||
                            accent.computeLuminance() > 0.7
                        ? AppColors.navy
                        : accent,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(mode.label,
                        style: AppText.title(size: 20, color: AppColors.navy)),
                  ),
                  // Live tally — the "most taps" rule made visible.
                  _VoteTally(votes: votes, accent: accent),
                ],
              ),
              const SizedBox(height: 4),
              Text(mode.tagline,
                  style: AppText.label(size: 10, color: AppColors.inkSoft)),
              const SizedBox(height: 6),
              Text(mode.blurb,
                  style: AppText.body(size: 11, color: AppColors.inkSoft)),
              const SizedBox(height: 10),
              // Who voted for THIS mode. Both badges can sit here at once
              // (a 2–0 agreement); a badge moves the instant that player
              // taps the other card, which is what makes changing your
              // pick mid-countdown legible to both sides.
              SizedBox(
                height: 26,
                child: Row(
                  children: [
                    if (myPick)
                      _VoterBadge(
                          label: '${myName.toUpperCase()} (YOU)', look: me),
                    if (myPick && peerPick) const SizedBox(width: 8),
                    if (peerPick)
                      _VoterBadge(
                          label: net.peerName.toUpperCase(), look: peer),
                    if (!myPick && !peerPick)
                      Text('NO VOTES YET',
                          style: AppText.label(
                              size: 9, color: AppColors.inkSoft)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------ BOTTOM STATUS ---

  Widget _waitingLine(NetworkService net) {
    final String msg;
    IconData? icon;
    Color color = AppColors.cream;
    if (net.bothVoted && !net.votesAgree) {
      // The one case that needs to read as a blocker rather than as
      // patience: both have picked, and the match still isn't starting.
      icon = Icons.sync_problem;
      color = AppColors.gold;
      msg = 'PICKS DO NOT MATCH — ONE OF YOU MUST SWITCH\n'
          'BEFORE THE BATTLE CAN START';
    } else if (net.myVote == null && net.peerVote == null) {
      msg = 'BOTH CAPTAINS STILL DECIDING…';
    } else if (net.myVote == null) {
      msg = '${net.peerName.toUpperCase()} PICKED ${net.peerVote!.label}'
          ' — YOUR CALL';
    } else {
      msg = 'WAITING FOR ${net.peerName.toUpperCase()}…';
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(msg,
              textAlign: TextAlign.center,
              style: AppText.label(size: 10.5, color: color)),
        ),
      ],
    );
  }

  Widget _countdown(int seconds) {
    final total = NetworkService.kVoteCountdownSeconds;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Smoothly sweeps between whole seconds rather than
              // snapping, so the bar reads as a real timer.
              TweenAnimationBuilder<double>(
                tween: Tween(end: seconds / total),
                duration: const Duration(milliseconds: 950),
                builder: (context, v, _) => SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: v.clamp(0.0, 1.0),
                    strokeWidth: 5,
                    backgroundColor: AppColors.navyDeep,
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.gold),
                  ),
                ),
              ),
              Text('$seconds', style: AppText.title(size: 20)),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            'LOCKING IN…\nTAP THE OTHER MODE TO CHANGE YOUR VOTE',
            style: AppText.label(size: 10),
          ),
        ),
      ],
    );
  }

  Widget _lockedBanner(LanBattleMode mode) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, color: AppColors.seafoam, size: 22),
        const SizedBox(width: 10),
        Flexible(
          child: Text('${mode.label} — DEPLOYING FLEETS…',
              style: AppText.label(size: 12)),
        ),
      ],
    );
  }
}

/// Name + role pill used in the header to show which captain commands
/// which fleet colour.
class _CaptainChip extends StatelessWidget {
  final String name;
  final String role;
  final FleetLook look;

  const _CaptainChip(
      {required this.name, required this.role, required this.look});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: look.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outline, width: 2.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ink picked from the fill's own brightness. Hull colours run
            // from Midnight Ops to Arctic Storm, so a fixed cream label
            // is unreadable on a good third of the catalogue.
            Text(name,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(size: 11, color: look.ink)),
            Text(role, style: AppText.label(size: 8, color: look.inkSoft)),
          ],
        ),
      ),
    );
  }
}

/// Small "1 VOTE" / "2 VOTES" counter on a mode card.
class _VoteTally extends StatelessWidget {
  final int votes;
  final Color accent;

  const _VoteTally({required this.votes, required this.accent});

  @override
  Widget build(BuildContext context) {
    final on = votes > 0;
    final fill = on ? accent : AppColors.miss;
    final ink =
        fill.computeLuminance() > 0.5 ? AppColors.outline : AppColors.cream;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outline, width: 2),
      ),
      child: Text(votes == 1 ? '1 VOTE' : '$votes VOTES',
          style: AppText.label(size: 9, color: ink)),
    );
  }
}

/// Badge showing that a specific captain voted for the card it sits on.
class _VoterBadge extends StatelessWidget {
  final String label;
  final FleetLook look;

  const _VoterBadge({required this.label, required this.look});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: look.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.outline, width: 2.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.how_to_vote, size: 12, color: look.ink),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(size: 9.5, color: look.ink)),
            ),
          ],
        ),
      ),
    );
  }
}
