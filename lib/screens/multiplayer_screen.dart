import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/game_controller.dart';
import '../services/network_service.dart';
import '../services/online_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';
import 'battle_screen.dart';
import 'friends_screen.dart';
import 'lan_mode_screen.dart';
import 'matchmaking_screen.dart';

/// Hotspot (LAN) + Online matchmaking lobby — cartoon style.
class MultiplayerScreen extends StatefulWidget {
  const MultiplayerScreen({super.key});

  @override
  State<MultiplayerScreen> createState() => _MultiplayerScreenState();
}

class _MultiplayerScreenState extends State<MultiplayerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _ipCtrl = TextEditingController();
  bool _hosting = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final net = context.read<NetworkService>();
      final online = context.read<OnlineService>();
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
      // Find the game server automatically — remembered address first,
      // then a sweep of this Wi-Fi — and quietly re-establish the account
      // so the ONLINE tab is already usable when it succeeds.
      await online.connectAuto(profile);
    });
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _tab.dispose();
    super.dispose();
  }

  /// Both devices are connected — before anyone deploys a fleet, the two
  /// captains vote on which set of rules the match runs under. The mode
  /// screen is what actually sets `controller.mode`/`lanBattleMode` and
  /// moves on to placement once the vote locks in.
  void _enterModeVote(GameMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LanModeScreen(mode: mode)),
    );
  }

  /// Opens a hotspot room and waits for someone on the same network to
  /// walk into it. (Internet play is invitation-based instead — see the
  /// ONLINE tab and `FriendsScreen`.)
  Future<void> _host() async {
    final net = context.read<NetworkService>();
    final profile = context.read<ProfileStore>();
    setState(() => _hosting = true);
    SoundService.instance.click();

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
    SoundService.instance.click();

    final ok = await net.joinHotspot(
      host,
      playerName: profile.playerName,
      resuming: resuming,
    );
    if (ok && mounted) {
      // Wait for the hello confirmation — or, when rejoining, for the
      // snapshot that puts the match back together.
      void listener() {
        if (!mounted) return;
        final snapshot = net.takeResume();
        if (snapshot != null) {
          net.removeListener(listener);
          setState(() => _connecting = false);
          _resumeMatch(snapshot);
          return;
        }
        // `joiningResumable` keeps us from racing off into the new-match
        // flow while the snapshot is still in flight.
        if (net.connected && !net.joiningResumable) {
          net.removeListener(listener);
          setState(() => _connecting = false);
          _enterModeVote(GameMode.hotspot);
        }
      }

      net.addListener(listener);
    } else {
      setState(() => _connecting = false);
      if (mounted && net.statusMessage.isNotEmpty) _toast(net.statusMessage);
    }
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BattleScreen()),
    );
  }

  /// Looks for the game server again and signs in. The automatic attempt
  /// runs on tab entry; this is the manual retry for when it failed (the
  /// server was off, or the phone was on the wrong Wi-Fi).
  Future<void> _reconnectOnline() async {
    final online = context.read<OnlineService>();
    final profile = context.read<ProfileStore>();
    SoundService.instance.click();
    final ok = await online.connectAuto(profile);
    if (!mounted) return;
    _toast(ok
        ? 'Connected — your friend code is ${online.myTag}'
        : (online.lastError ?? 'Could not find the game server.'));
  }

  void _openFriends() {
    SoundService.instance.click();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FriendsScreen()),
    );
  }

  /// Random matchmaking: search queue → loading → both captains accept.
  void _findMatch() {
    SoundService.instance.click();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MatchmakingScreen()),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                padding: const EdgeInsets.fromLTRB(8, 10, 14, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.cream),
                      onPressed: () {
                        SoundService.instance.click();
                        net.stop();
                        Navigator.pop(context);
                      },
                    ),
                    Expanded(
                      child: Text(
                        'MULTIPLAYER LOBBY',
                        style: AppText.title(size: 19),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                color: AppColors.navy,
                child: TabBar(
                  controller: _tab,
                  indicatorColor: AppColors.gold,
                  indicatorWeight: 4,
                  labelColor: AppColors.cream,
                  unselectedLabelColor:
                      AppColors.cream.withValues(alpha: 0.55),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                  tabs: const [
                    Tab(text: 'HOTSPOT / LAN'),
                    Tab(text: 'ONLINE'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _buildHotspotTab(net),
                    _buildOnlineTab(context.watch<OnlineService>()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- HOTSPOT TAB ---

  Widget _buildHotspotTab(NetworkService net) {
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
                  child: Text('ROOM CODE',
                      style: AppText.label(size: 10, color: AppColors.inkSoft)),
                ),
                Center(
                  child: Text(net.roomCode,
                      style: AppText.title(size: 34, color: AppColors.ember)),
                ),
                Center(
                  child: Text(
                    '${net.localIp}:$kGamePort',
                    style: AppText.label(size: 10, color: AppColors.inkSoft),
                  ),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: AppColors.ember),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(net.statusMessage,
                      style:
                          AppText.body(size: 11, color: AppColors.inkSoft)),
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
              NeonButton(
                label: net.isSearching ? 'SCANNING…' : 'SCAN FOR GAMES',
                icon: Icons.search,
                color: AppColors.blue,
                compact: true,
                onPressed: net.isSearching
                    ? null
                    : () {
                        SoundService.instance.click();
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
                      border:
                          Border.all(color: AppColors.outline, width: 2.5),
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
                      title: Text(room.playerName,
                          style: AppText.heading(
                              size: 12, color: AppColors.navy)),
                      subtitle: Text(
                          room.resumable
                              ? 'MATCH IN PROGRESS — YOUR SEAT IS HELD'
                              : '${room.host} • ${room.code}',
                          style: AppText.label(
                              size: 9,
                              color: room.resumable
                                  ? AppColors.ember
                                  : AppColors.inkSoft)),
                      trailing: NeonButton(
                        label: room.resumable ? 'REJOIN' : 'JOIN',
                        color: room.resumable
                            ? AppColors.ember
                            : AppColors.green,
                        compact: true,
                        onPressed: _connecting
                            ? null
                            : () =>
                                _join(room.host, resuming: room.resumable),
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
                      keyboardType: TextInputType.number,
                      style: AppText.body(size: 13, color: AppColors.navy),
                      decoration: _inputDeco('HOST IP — e.g. 192.168.1.5'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NeonButton(
                    label: _connecting ? '…' : 'JOIN',
                    color: AppColors.green,
                    compact: true,
                    onPressed: _connecting
                        ? null
                        : () {
                            final ip = _ipCtrl.text.trim();
                            if (ip.isEmpty) {
                              _toast('Enter the host IP address');
                              return;
                            }
                            _join(ip);
                          },
                  ),
                ],
              ),
              if (net.statusMessage.isNotEmpty && !_hosting) ...[
                const SizedBox(height: 8),
                Text(net.statusMessage,
                    style: AppText.label(size: 9, color: AppColors.inkSoft),
                    textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ ONLINE TAB ---

  Widget _buildOnlineTab(OnlineService online) {
    final ready = online.signedIn && online.reachable;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _card(
          title: 'PLAY OVER THE INTERNET',
          icon: Icons.public,
          color: AppColors.green,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    ready
                        ? Icons.check_circle
                        : online.busy
                            ? Icons.radar
                            : Icons.warning_amber,
                    size: 16,
                    color: ready ? AppColors.green : AppColors.ember,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ready
                          ? 'Signed in as ${online.myName} (${online.myTag}).'
                          : online.busy
                              ? 'Looking for the game server on this '
                                  'Wi-Fi…'
                              : (online.lastError ??
                                  'Not connected to a game server yet.'),
                      style: AppText.body(size: 11, color: AppColors.inkSoft),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!ready && !online.busy) ...[
                NeonButton(
                  label: 'TRY AGAIN',
                  icon: Icons.refresh,
                  color: AppColors.blue,
                  onPressed: _reconnectOnline,
                ),
                const SizedBox(height: 10),
              ],
              if (ready) ...[
                NeonButton(
                  label: online.searching ? 'SEARCHING…' : 'FIND A MATCH',
                  icon: Icons.radar,
                  color: AppColors.ember,
                  onPressed: online.busy ? null : _findMatch,
                ),
                const SizedBox(height: 8),
                Text(
                  'Get paired with another searching captain — you both '
                  'accept, then you sail.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 10.5, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 12),
                NeonButton(
                  label: 'FRIENDS',
                  icon: Icons.people,
                  color: AppColors.green,
                  onPressed: _openFriends,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          title: 'HOW ONLINE PLAY WORKS',
          icon: Icons.help_outline,
          color: AppColors.ember,
          child: Text(
            'FIND A MATCH pairs you with another captain who is searching '
            'at the same moment. The match only starts once BOTH of you '
            'tap accept — decline and you are back to searching.\n\n'
            'Or play a friend: add each other by searching your captain '
            'names in FRIENDS, then invite whoever is online. Whoever '
            'sends the invitation hosts, commands the red fleet and fires '
            'first.',
            style: AppText.body(size: 11.5, color: AppColors.inkSoft),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
