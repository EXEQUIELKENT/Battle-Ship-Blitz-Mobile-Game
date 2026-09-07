import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/network_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_notification.dart';
import '../widgets/lobby_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';
import 'battle_screen.dart';
import 'lan_mode_screen.dart';
import 'placement_screen.dart';

/// The dedicated HOTSPOT / LAN page.
///
/// This is its OWN screen, not a tab inside a broader multiplayer lobby:
/// the main menu's HOTSPOT / LAN entry lands straight here, and the ONLINE
/// entry lands on `FriendsScreen` instead — see `HomeScreen`. Everything
/// this page does is same-Wi-Fi play: host a room, scan for a nearby
/// captain's room, or join one by room code / IP.
///
/// Once two devices are connected the identical match flow takes over —
/// mode vote, deployment, battle — exactly like an online relay match does.
class HotspotScreen extends StatefulWidget {
  /// Pre-fills the ROOM CODE field — used when arriving here to resume a
  /// hotspot match `MatchStore` remembers this device as the JOINER of
  /// (see the resume banner on `HomeScreen`). The host has to be
  /// re-advertising under the same code for JOIN to actually find them;
  /// this only saves retyping it.
  final String? initialRoomCode;

  const HotspotScreen({super.key, this.initialRoomCode});

  @override
  State<HotspotScreen> createState() => _HotspotScreenState();
}

class _HotspotScreenState extends State<HotspotScreen>
    with SingleTickerProviderStateMixin {
  final _ipCtrl = TextEditingController();
  bool _hosting = false;
  bool _connecting = false;

  /// Drives the scan dial's sweep AND the progress bar under it, both off
  /// one controller running for exactly [NetworkService.scanWindow] — so
  /// the bar cannot drift out of step with the sweep, and neither can
  /// drift out of step with the socket that actually closes at the end of
  /// it.
  late final AnimationController _scan;

  /// The "someone connected" listener [_host] installs, held so closing
  /// the room can take it back off again — it used to be an anonymous
  /// closure that only ever removed ITSELF on success, so backing out of
  /// a room left it subscribed for the life of the service.
  VoidCallback? _hostListener;

  /// Captured once, in [initState], rather than read from the context in
  /// [dispose].
  ///
  /// BUGFIX: teardown used to call `context.read<NetworkService>()`. By
  /// the time `dispose` runs the element is already deactivated, and
  /// looking up an inherited widget from there is not allowed — it throws
  /// "Looking up a deactivated widget's ancestor is unsafe" in debug, and
  /// in release it is reading a tree that is being taken apart. The
  /// service outlives this screen either way, so holding the reference is
  /// both safe and the documented way to do this.
  late final NetworkService _net;

  @override
  void initState() {
    super.initState();
    _net = context.read<NetworkService>();
    _scan = AnimationController(
      vsync: this,
      duration: NetworkService.scanWindow,
    );
    if (widget.initialRoomCode != null) {
      _ipCtrl.text = widget.initialRoomCode!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final net = context.read<NetworkService>();
      final profile = context.read<ProfileStore>();
      net.setSelfName(profile.playerName);
      // Announce what we have equipped so the opponent's device can draw
      // our ships, cannon and battlefield the way we bought them.
      net.setSelfLoadout(
        shipSkinId: profile.shipSkinId,
        cannonSkinId: profile.cannonSkinId,
        themeId: profile.gameplayThemeId,
        shipChosen: profile.shipSkinChosen,
      );
    });
  }

  @override
  void dispose() {
    // BUGFIX: `scanRooms` was never paired with a `stopScan` call anywhere
    // in the app, so backing out of this screen mid-scan (well within the
    // 6s window) left the UDP socket bound and listening for however long
    // was left, for no listener left to see the result.
    if (_hostListener != null) _net.removeListener(_hostListener!);
    _net.stopScan();
    _scan.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  /// Starts a sweep and runs the dial/bar across the same window the
  /// socket stays open for.
  void _startScan() {
    SoundService.instance.click();
    context.read<NetworkService>().scanRooms();
    _scan.forward(from: 0);
  }

  /// Takes the room back down without leaving the page — the room panel's
  /// own way out. Backing out with the header arrow already did this; the
  /// panel needed it too, since it replaces the whole top of the page
  /// while a room is open.
  void _closeRoom() {
    final net = context.read<NetworkService>();
    if (_hostListener != null) {
      net.removeListener(_hostListener!);
      _hostListener = null;
    }
    net.stop();
    setState(() => _hosting = false);
  }

  /// Both devices are connected — before anyone deploys a fleet, the two
  /// captains vote on which set of rules the match runs under. The mode
  /// screen is what actually sets `controller.mode`/`lanBattleMode` and
  /// moves on to placement once the vote locks in.
  void _enterModeVote(GameMode mode) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LanModeScreen(mode: mode)));
  }

  /// Opens a hotspot room and waits for someone on the same network to
  /// walk into it. (Internet play is invitation-based instead — see
  /// `FriendsScreen`.)
  Future<void> _host() async {
    final net = context.read<NetworkService>();
    final profile = context.read<ProfileStore>();
    setState(() => _hosting = true);

    final code = await net.hostHotspot(playerName: profile.playerName);
    if (code == null) {
      setState(() => _hosting = false);
      return;
    }

    // Wait for connection, then proceed to the mode vote.
    void listener() {
      if (net.connected) {
        net.removeListener(listener);
        _hostListener = null;
        if (!mounted) return;
        setState(() => _hosting = false);
        _enterModeVote(GameMode.hotspot);
      }
    }

    _hostListener = listener;
    net.addListener(listener);
  }

  /// Joins a room. [resuming] is set when the beacon advertised a match
  /// already in progress with a seat held open for whoever dropped out of
  /// it — in that case we wait for the surviving player's state snapshot
  /// and drop straight back into the battle instead of starting fresh.
  Future<void> _join(String host, {bool resuming = false}) async {
    final net = context.read<NetworkService>();
    final profile = context.read<ProfileStore>();
    setState(() => _connecting = true);

    final ok = await net.joinHotspot(
      host,
      playerName: profile.playerName,
      resuming: resuming,
    );
    if (ok && mounted) {
      // Wait for the hello confirmation — or, when rejoining, for the
      // snapshot that puts the match back together.
      //
      // BUGFIX: this used to wait with no timeout — if the socket
      // connected but the host never actually finished the handshake
      // (accepted, then stalled or crashed before sending a `hello`/
      // `resume`), `_connecting` stayed true forever and the screen was
      // left permanently unable to try again without a full app restart.
      late Timer timeout;
      void listener() {
        if (!mounted) return;
        final snapshot = net.takeResume();
        if (snapshot != null) {
          timeout.cancel();
          net.removeListener(listener);
          setState(() => _connecting = false);
          _resumeMatch(snapshot);
          return;
        }
        // Pre-battle rejoin: the survivor's match is still on the mode
        // VOTE or the DEPLOY screen (no battle snapshot exists yet). The
        // `prematch` signal tells us which, so we rebuild that same state
        // instead of starting a fresh lobby match.
        final preSignal = net.takePreMatchSignal();
        if (preSignal != null) {
          timeout.cancel();
          net.removeListener(listener);
          setState(() => _connecting = false);
          _enterPreMatch(preSignal);
          return;
        }
        // `joiningResumable` keeps us from racing off into the new-match
        // flow while the snapshot is still in flight.
        if (net.connected && !net.joiningResumable) {
          timeout.cancel();
          net.removeListener(listener);
          setState(() => _connecting = false);
          _enterModeVote(GameMode.hotspot);
        }
      }

      net.addListener(listener);
      timeout = Timer(const Duration(seconds: 25), () {
        net.removeListener(listener);
        if (!mounted) return;
        setState(() => _connecting = false);
        _toast(
          'Connected, but never heard back from the host. Try again.',
          type: AppNoticeType.error,
        );
      });
    } else {
      setState(() => _connecting = false);
      if (mounted && net.statusMessage.isNotEmpty) {
        _toast(net.statusMessage, type: AppNoticeType.error);
      }
    }
  }

  /// A literal dotted-quad still works directly — useful when broadcast is
  /// blocked and someone reads the IP straight off the host's own screen
  /// (shown there next to the code, see `net.localIp` below).
  bool _looksLikeIp(String s) => s.split('.').length == 4;

  /// Resolves the typed ROOM CODE against whatever `scanRooms` has already
  /// found (`NetworkService.roomByCode`), kicking off a scan and resolving
  /// the instant a matching beacon lands if it hasn't been seen yet —
  /// rather than making the player wait out the full 6s scan window every
  /// time. Everything needed is already on the wire: the beacon carries
  /// both the code and the host IP (`NetworkService._startBeacon`).
  Future<void> _joinByCode() async {
    final typed = _ipCtrl.text.trim();
    if (typed.isEmpty) {
      _toast('Enter the room code', type: AppNoticeType.error);
      return;
    }
    if (_looksLikeIp(typed)) {
      _join(typed);
      return;
    }
    final net = context.read<NetworkService>();
    final already = net.roomByCode(typed, myIps: net.localIps);
    if (already != null) {
      _join(already.host, resuming: already.resumable);
      return;
    }

    setState(() => _connecting = true);
    net.scanRooms();
    late VoidCallback listener;
    final timeout = Timer(const Duration(seconds: 7), () {
      net.removeListener(listener);
      if (!mounted) return;
      setState(() => _connecting = false);
      _toast(
        'No room found with that code — check it and try again.',
        type: AppNoticeType.error,
      );
    });
    listener = () {
      final room = net.roomByCode(typed, myIps: net.localIps);
      if (room == null) return;
      timeout.cancel();
      net.removeListener(listener);
      net.stopScan();
      if (!mounted) return;
      setState(() => _connecting = false);
      _join(room.host, resuming: room.resumable);
    };
    net.addListener(listener);
  }

  /// Rebuilds the interrupted match from the surviving player's snapshot
  /// and goes straight to the battle, exactly where it left off.
  void _resumeMatch(Map<String, dynamic> snapshot) {
    final controller = context.read<GameController>();
    final net = context.read<NetworkService>();
    controller.mode = GameMode.hotspot;
    // Which side we were is part of the match, not of who reconnected —
    // see NetworkService.setMatchHost.
    net.setMatchHost(snapshot['youAreHost'] == true);
    controller.restoreFromSnapshot(snapshot);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BattleScreen()));
  }

  /// Rebuilds the interrupted PRE-battle match — the opponent dropped
  /// while we were still voting or deploying, and the survivor's
  /// `prematch` signal tells us which. Restores the fixed host role (a
  /// returning player always arrives as the joiner; if they were the
  /// host, nobody would run the vote countdown) and routes to the same
  /// screen the match is on.
  void _enterPreMatch(Map<String, dynamic> signal) {
    final controller = context.read<GameController>();
    final net = context.read<NetworkService>();
    net.setMatchHost(!(signal['host'] == true));
    final stage = signal['stage'] as String;
    final lockedIdx = signal['mode'] as int?;

    if (stage == 'deploy') {
      final locked = lockedIdx == null
          ? LanBattleMode.turns
          : LanBattleMode.values[lockedIdx];
      controller.mode = GameMode.hotspot;
      controller.lanBattleMode = locked;
      controller.attachNetwork();
      controller.startPlacement();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PlacementScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const LanModeScreen(mode: GameMode.hotspot),
        ),
      );
    }
  }

  void _toast(String msg, {AppNoticeType type = AppNoticeType.info}) {
    AppNotification.show(context, msg, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkService>();
    return Scaffold(
      body: OceanBackground(
        showSonar: false,
        child: SafeArea(
          child: Column(
            children: [
              // ---- Navy header ----
              Container(
                width: double.infinity,
                color: AppColors.navy,
                padding: const EdgeInsets.fromLTRB(8, 10, 14, 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.cream,
                      ),
                      onPressed: () {
                        SoundService.instance.click();
                        net.stop();
                        Navigator.pop(context);
                      },
                    ),
                    Expanded(
                      child: Text(
                        'HOTSPOT / LAN',
                        style: AppText.title(size: 19),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody(net)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(NetworkService net) {
    if (kIsWeb) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: cartoonBox(AppColors.cream, radius: 18),
            child: Text(
              'Hotspot multiplayer runs on Android devices.\n\nInstall the APK on two phones on the same Wi-Fi / hotspot network!',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13, color: AppColors.navy),
            ),
          ),
        ),
      );
    }
    // REDESIGN: the page used to be two symmetrical cards — HOST A MATCH
    // and JOIN A MATCH — each holding a paragraph and a button, which read
    // as a settings page rather than a lobby. It is now ordered by what a
    // captain actually arrives here to do, most common first: type the
    // code a friend just read out, open a room of your own, or sweep the
    // Wi-Fi to see who is already listening. While a room IS open, that
    // block takes over the top of the page as the panel to hold up to the
    // other player.
    final roomOpen = _hosting && net.roomCode.isNotEmpty;
    // FEEDBACK ("...pop up animation when first opening a screen, one by
    // one"). The room-open/closed swap right below keeps its own
    // cross-fade (that's a state CHANGE, not the screen arriving), but
    // the cards a captain sees on first opening this page — join, host,
    // scan — each get their own slot in one staggered entrance.
    final pop = PopSequence();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        // FEEDBACK ("different transition animations... whether you click
        // or do any activity"): HOST swapping this whole block for the
        // room panel used to be a jump-cut mid-`build` — the controls a
        // captain was just looking at replaced outright, same frame. A
        // cross-fade+rise says "this became that" instead of "that's
        // gone, here's something else" — each side is keyed so
        // `AnimatedSwitcher` treats them as genuinely different subtrees
        // rather than trying (and failing) to tween between unrelated
        // widget trees.
        AnimatedSwitcher(
          // FEEDBACK ("make all of the animations smooth and slowly").
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: roomOpen
              ? Column(
                  key: const ValueKey('room-open'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _openRoomPanel(net),
                    const SizedBox(height: 16),
                  ],
                )
              : Column(
                  key: const ValueKey('room-closed'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    pop.wrap(_joinByCodeCard(net)),
                    const SizedBox(height: 16),
                    pop.wrap(_hostButton()),
                    const SizedBox(height: 16),
                  ],
                ),
        ),
        pop.wrap(_scanCard(net)),
      ],
    );
  }

  // ------------------------------------------------------------ BLOCKS --

  /// The room this device is hosting, as the thing to physically show the
  /// other captain: the code big enough to read across a table, the IP
  /// underneath as the fallback when a code won't go through, and a live
  /// line for what the room is doing.
  Widget _openRoomPanel(NetworkService net) {
    final waiting = net.statusMessage.isEmpty
        ? 'Waiting for a captain to walk in…'
        : net.statusMessage;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: cartoonBox(AppColors.navy, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text('ROOM IS OPEN', style: AppText.title(size: 18)),
          ),
          const SizedBox(height: 14),
          CodeTiles(code: net.roomCode),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'YOUR IP — ${net.localIp}:$kGamePort  ·  WORKS IF THE CODE FAILS',
              textAlign: TextAlign.center,
              style: AppText.label(
                size: 8.5,
                color: AppColors.cream.withValues(alpha: 0.7),
              ),
            ),
          ),
          if (net.localIps.length > 1) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                'ALSO REACHABLE AT ${net.localIps.skip(1).join(" · ")}',
                textAlign: TextAlign.center,
                style: AppText.label(
                  size: 8,
                  color: AppColors.cream.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(AppColors.gold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  waiting,
                  style: AppText.label(size: 10, color: AppColors.gold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // FEEDBACK ("the button text isn't visible"): `NeonButton`
          // always draws its label and icon in `AppColors.cream` — see its
          // own build method — so passing `color: AppColors.cream` here
          // made a cream label on a cream field, invisible except for the
          // dark outline. `AppColors.hit` is the colour every other
          // leave/cancel action in the lobby screens already uses (the
          // matchmaking panel's CANCEL/DECLINE), so this now matches them
          // instead of introducing a fourth colour for the same action.
          NeonButton(
            label: 'CLOSE ROOM',
            icon: Icons.close,
            color: AppColors.hit,
            onPressed: _closeRoom,
          ),
        ],
      ),
    );
  }

  Widget _joinByCodeCard(NetworkService net) {
    return LobbyCard(
      title: 'JOIN BY ROOM CODE',
      icon: Icons.vpn_key,
      color: AppColors.seafoam,
      subtitle: "Ask the host for their 4-letter code — or read the IP "
          'off their screen.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipCtrl,
                  textCapitalization: TextCapitalization.characters,
                  // Room codes are the `_newCode` alphabet — I/O/0/1
                  // deliberately excluded so a code can't be misread —
                  // but a literal dotted-quad IP is still accepted as
                  // a fallback (see `_looksLikeIp`), hence allowing
                  // digits and dots too.
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[A-Za-z2-9.]'),
                    ),
                    LengthLimitingTextInputFormatter(15),
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) => newValue.copyWith(
                        text: newValue.text.toUpperCase(),
                      ),
                    ),
                  ],
                  // Widely spaced, like the tiles the host is looking at,
                  // so a code being read out lands one character at a time
                  // instead of as a word to spell.
                  style: AppText.title(size: 20, color: AppColors.navy)
                      .copyWith(letterSpacing: 6),
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _connecting ? null : _joinByCode(),
                  decoration: _inputDeco('K7QX'),
                ),
              ),
              const SizedBox(width: 10),
              NeonButton(
                label: _connecting ? '…' : 'JOIN',
                color: AppColors.seafoam,
                onPressed: _connecting ? null : _joinByCode,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const LobbyHint(
            'CODES NEVER USE I · O · 0 · 1  —  A DOTTED IP JOINS DIRECTLY',
            align: TextAlign.center,
          ),
          if (net.statusMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              net.statusMessage,
              style: AppText.label(size: 9, color: AppColors.inkSoft),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// Hosting is one tap, so it is one button rather than a card wrapped
  /// around one — the explanation it used to carry is on the room panel
  /// it opens, where it is actually needed.
  Widget _hostButton() {
    return NeonButton(
      label: _hosting ? 'OPENING A ROOM…' : 'HOST A ROOM',
      icon: Icons.anchor,
      color: AppColors.ember,
      onPressed: _hosting ? null : () => _host(),
    );
  }

  Widget _scanCard(NetworkService net) {
    final rooms = net.foundRooms;
    final headline = net.isSearching
        ? 'Sweeping the Wi-Fi…'
        : rooms.isEmpty
            ? 'Nobody listening yet'
            : '${rooms.length} room${rooms.length == 1 ? '' : 's'} on this Wi-Fi';
    final sub = net.isSearching
        ? '${NetworkService.scanWindow.inSeconds}-SECOND BEACON WINDOW'
        : rooms.isEmpty
            ? 'BOTH DEVICES MUST BE ON THE SAME WI-FI OR HOTSPOT'
            : 'TAP A ROOM TO JOIN  ·  SCAN AGAIN TO REFRESH';

    return LobbyCard(
      title: 'SCAN THIS WI-FI',
      icon: Icons.radar,
      color: AppColors.blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _scan,
                builder: (_, __) => ScanDial(
                  sweep: _scan.value,
                  blips: rooms.length,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: AppText.heading(size: 13, color: AppColors.navy),
                    ),
                    const SizedBox(height: 4),
                    LobbyHint(sub),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              NeonButton(
                label: net.isSearching ? '…' : 'SCAN',
                color: AppColors.blue,
                compact: true,
                onPressed: net.isSearching ? null : _startScan,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Only while a sweep is actually running: a bar sitting at empty
          // between scans would read as a broken control.
          if (net.isSearching)
            AnimatedBuilder(
              animation: _scan,
              builder: (_, __) => LobbyProgressBar(
                progress: _scan.value,
                color: AppColors.blue,
              ),
            ),
          if (rooms.isNotEmpty) ...[
            const SizedBox(height: 4),
            // Staggered so a fresh batch of results settles in one after
            // another rather than popping in as a block — capped at 6
            // steps of delay so a big Wi-Fi's worth of rooms doesn't leave
            // the last row waiting on the others to finish.
            for (var i = 0; i < rooms.length; i++)
              PopIn(
                key: ValueKey('room-${rooms[i].code}'),
                delay: Duration(milliseconds: 90 * i.clamp(0, 6)),
                child: _roomRow(rooms[i]),
              ),
          ],
        ],
      ),
    );
  }

  /// One discovered room. The whole row is the tap target — the button on
  /// the right says what will happen, but a captain aiming at a name
  /// should not miss.
  Widget _roomRow(RoomInfo room) {
    final resumable = room.resumable;
    final accent = resumable ? AppColors.ember : AppColors.seafoam;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Pressable(
        onTap: _connecting
            ? null
            : () => _join(room.host, resuming: resumable),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: cartoonBox(AppColors.coralLight, radius: 14),
          child: Row(
            children: [
              RoomBadge(
                color: accent,
                icon: resumable ? Icons.history_toggle_off : Icons.wifi,
              ),
              const SizedBox(width: 10),
              // The code sits on the row's SECOND line, beside the status,
              // rather than as a third column between the name and the
              // button — at phone width those four columns overflowed the
              // row by ~30px, and the code is a detail you read once
              // rather than something to keep a column for.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            room.playerName.toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: AppText.heading(
                              size: 13,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        if (resumable) ...[
                          const SizedBox(width: 6),
                          const StatusPill(
                            text: 'REJOIN',
                            color: AppColors.gold,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        CodePill(code: room.code),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            resumable
                                ? 'MATCH IN PROGRESS  ·  SEAT HELD'
                                : 'OPEN  ·  ${room.host}',
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label(
                              size: 8.5,
                              color: resumable
                                  ? AppColors.ember
                                  : AppColors.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NeonButton(
                label: resumable ? 'REJOIN' : 'JOIN',
                color: accent,
                compact: true,
                onPressed: _connecting
                    ? null
                    : () => _join(room.host, resuming: resumable),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // The generic titled card this screen used to build for itself now
  // lives in `lobby_widgets.dart` as [LobbyCard], shared with the ONLINE
  // screens so all three read as one lobby rather than three designs.

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    // The hint is the code's own shape, so it is set in the code's own
    // style — a captain sees the field already showing them what four
    // characters look like there.
    hintStyle: AppText.title(
      size: 20,
      color: AppColors.inkSoft.withValues(alpha: 0.45),
    ).copyWith(letterSpacing: 6),
    counterText: '',
    filled: true,
    fillColor: AppColors.coralLight,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.outline, width: 2.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.blue, width: 2.5),
    ),
  );
}