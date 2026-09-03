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

class _HotspotScreenState extends State<HotspotScreen> {
  final _ipCtrl = TextEditingController();
  bool _hosting = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
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
    context.read<NetworkService>().stopScan();
    _ipCtrl.dispose();
    super.dispose();
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
        if (!mounted) return;
        setState(() => _hosting = false);
        _enterModeVote(GameMode.hotspot);
      }
    }

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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // --- Host card ---
        _card(
          title: 'HOST A MATCH',
          icon: Icons.cell_tower,
          color: AppColors.ember,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Creates a room on this device. Your friend connects to the same Wi-Fi or hotspot and joins.',
                style: AppText.body(size: 11.5, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              if (net.roomCode.isNotEmpty && _hosting) ...[
                Center(
                  child: Text(
                    'ROOM CODE',
                    style: AppText.label(size: 10, color: AppColors.inkSoft),
                  ),
                ),
                Center(
                  child: Text(
                    net.roomCode,
                    style: AppText.title(size: 34, color: AppColors.ember),
                  ),
                ),
                Center(
                  child: Text(
                    '${net.localIp}:$kGamePort',
                    style: AppText.label(size: 10, color: AppColors.inkSoft),
                  ),
                ),
                if (net.localIps.length > 1) ...[
                  const SizedBox(height: 2),
                  Center(
                    child: Text(
                      'Scan not finding it? Try entering one of: '
                      '${net.localIps.skip(1).join(", ")}',
                      style: AppText.label(size: 8.5, color: AppColors.inkSoft),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.ember,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    net.statusMessage,
                    style: AppText.body(size: 11, color: AppColors.inkSoft),
                  ),
                ),
              ] else
                NeonButton(
                  label: _hosting ? 'HOSTING…' : 'HOST GAME',
                  icon: Icons.anchor,
                  color: AppColors.ember,
                  onPressed: _hosting ? null : () => _host(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // --- Join card ---
        _card(
          title: 'JOIN A MATCH',
          icon: Icons.radar,
          color: AppColors.blue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Scan to find a nearby captain's room, or join by room code / IP.",
                style: AppText.body(size: 11.5, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              NeonButton(
                label: net.isSearching ? 'SCANNING…' : 'SCAN FOR GAMES',
                icon: Icons.search,
                color: AppColors.blue,
                compact: true,
                onPressed: net.isSearching
                    ? null
                    : () {
                        net.scanRooms();
                      },
              ),
              const SizedBox(height: 10),
              if (net.foundRooms.isNotEmpty)
                ...net.foundRooms.map(
                  (room) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.outline, width: 2.5),
                      color: AppColors.coralLight,
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        room.resumable
                            ? Icons.history_toggle_off
                            : Icons.directions_boat,
                        color: room.resumable
                            ? AppColors.ember
                            : AppColors.shipRed,
                      ),
                      title: Text(
                        room.playerName,
                        style: AppText.heading(size: 12, color: AppColors.navy),
                      ),
                      subtitle: Text(
                        room.resumable
                            ? 'MATCH IN PROGRESS — YOUR SEAT IS HELD'
                            : '${room.host} • ${room.code}',
                        style: AppText.label(
                          size: 9,
                          color: room.resumable
                              ? AppColors.ember
                              : AppColors.inkSoft,
                        ),
                      ),
                      trailing: NeonButton(
                        label: room.resumable ? 'REJOIN' : 'JOIN',
                        color: room.resumable
                            ? AppColors.ember
                            : AppColors.green,
                        compact: true,
                        onPressed: _connecting
                            ? null
                            : () => _join(room.host, resuming: room.resumable),
                      ),
                    ),
                  ),
                )
              else
                Text(
                  net.isSearching
                      ? 'Listening for nearby captains…'
                      : 'No rooms found yet — scan or enter an IP below.',
                  style: AppText.body(size: 11, color: AppColors.inkSoft),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 12),
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
                      style: AppText.body(size: 13, color: AppColors.navy),
                      decoration: _inputDeco('ROOM CODE — e.g. 2XMA'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NeonButton(
                    label: _connecting ? '…' : 'JOIN',
                    color: AppColors.green,
                    compact: true,
                    onPressed: _connecting ? null : _joinByCode,
                  ),
                ],
              ),
              if (net.statusMessage.isNotEmpty && !_hosting) ...[
                const SizedBox(height: 8),
                Text(
                  net.statusMessage,
                  style: AppText.label(size: 9, color: AppColors.inkSoft),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cartoonBox(AppColors.cream, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.outline, width: 2),
                ),
                child: Icon(icon, color: AppColors.cream, size: 16),
              ),
              const SizedBox(width: 10),
              Text(title, style: AppText.label(size: 12, color: color)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: AppText.body(size: 11, color: AppColors.inkSoft),
    counterText: '',
    filled: true,
    fillColor: AppColors.coralLight,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.outline, width: 2.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.blue, width: 2.5),
    ),
  );
}