import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/game_controller.dart';
import '../services/network_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';
import 'placement_screen.dart';

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
  final _codeCtrl = TextEditingController();
  bool _hosting = false;
  bool _connecting = false;
  bool _onlineChecked = false;
  bool _onlineOk = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final net = context.read<NetworkService>();
      final profile = context.read<ProfileStore>();
      net.setSelfName(profile.playerName);
      final ok = await net.onlineAvailable();
      if (mounted) {
        setState(() {
          _onlineChecked = true;
          _onlineOk = ok;
        });
      }
    });
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _codeCtrl.dispose();
    _tab.dispose();
    super.dispose();
  }

  void _enterPlacement(GameMode mode) {
    final controller = context.read<GameController>();
    controller.mode = mode;
    controller.attachNetwork();
    controller.startPlacement();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlacementScreen()),
    );
  }

  Future<void> _host(NetMode mode) async {
    final net = context.read<NetworkService>();
    final profile = context.read<ProfileStore>();
    setState(() => _hosting = true);
    SoundService.instance.click();

    final code = mode == NetMode.hotspot
        ? await net.hostHotspot(playerName: profile.playerName)
        : await net.hostOnline(playerName: profile.playerName);

    if (code == null) {
      setState(() => _hosting = false);
      return;
    }

    // Wait for connection, then proceed to placement
    void listener() {
      if (net.connected) {
        net.removeListener(listener);
        if (!mounted) return;
        setState(() => _hosting = false);
        _enterPlacement(
            mode == NetMode.hotspot ? GameMode.hotspot : GameMode.online);
      }
    }

    net.addListener(listener);
  }

  Future<void> _join(String host) async {
    final net = context.read<NetworkService>();
    final profile = context.read<ProfileStore>();
    setState(() => _connecting = true);
    SoundService.instance.click();

    final ok = await net.joinHotspot(host, playerName: profile.playerName);
    if (ok && mounted) {
      // Wait for the hello confirmation
      void listener() {
        if (net.connected) {
          net.removeListener(listener);
          if (!mounted) return;
          setState(() => _connecting = false);
          _enterPlacement(GameMode.hotspot);
        }
      }

      net.addListener(listener);
    } else {
      setState(() => _connecting = false);
      if (mounted && net.statusMessage.isNotEmpty) _toast(net.statusMessage);
    }
  }

  Future<void> _joinOnline() async {
    final net = context.read<NetworkService>();
    final profile = context.read<ProfileStore>();
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length != 4) {
      _toast('Enter the 4-letter room code');
      return;
    }
    setState(() => _connecting = true);
    final ok = await net.joinOnline(code, playerName: profile.playerName);
    if (ok && mounted) {
      void listener() {
        if (net.connected) {
          net.removeListener(listener);
          if (!mounted) return;
          setState(() => _connecting = false);
          _enterPlacement(GameMode.online);
        }
      }

      net.addListener(listener);
    } else {
      setState(() => _connecting = false);
      if (mounted && net.statusMessage.isNotEmpty) _toast(net.statusMessage);
    }
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
                    _buildOnlineTab(net),
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
                  onPressed: _hosting ? null : () => _host(NetMode.hotspot),
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
                      leading: const Icon(Icons.directions_boat,
                          color: AppColors.shipRed),
                      title: Text(room.playerName,
                          style: AppText.heading(
                              size: 12, color: AppColors.navy)),
                      subtitle: Text('${room.host} • ${room.code}',
                          style: AppText.label(
                              size: 9, color: AppColors.inkSoft)),
                      trailing: NeonButton(
                        label: 'JOIN',
                        color: AppColors.green,
                        compact: true,
                        onPressed:
                            _connecting ? null : () => _join(room.host),
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

  Widget _buildOnlineTab(NetworkService net) {
    final relayReady = _onlineChecked && _onlineOk;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _card(
          title: 'ONLINE MATCHMAKING',
          icon: Icons.public,
          color: AppColors.green,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    relayReady ? Icons.check_circle : Icons.warning_amber,
                    size: 16,
                    color: relayReady ? AppColors.green : AppColors.ember,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      !_onlineChecked
                          ? 'Checking relay…'
                          : relayReady
                              ? 'Relay online — play with anyone, anywhere!'
                              : 'Relay offline. Online mode uses the same room system as hotspot: host and share your IP, or play over hotspot instead.',
                      style:
                          AppText.body(size: 11, color: AppColors.inkSoft),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              NeonButton(
                label: _hosting ? 'HOSTING…' : 'HOST ONLINE GAME',
                icon: Icons.public,
                color: AppColors.green,
                onPressed: _hosting ? null : () => _host(NetMode.online),
              ),
              if (net.roomCode.isNotEmpty && _hosting) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text('ROOM CODE: ${net.roomCode}',
                      style: AppText.title(size: 22, color: AppColors.green)),
                ),
                Center(
                  child: Text('Share this code with your friend!',
                      style:
                          AppText.label(size: 9, color: AppColors.inkSoft)),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 4,
                      style: AppText.body(size: 14, color: AppColors.navy),
                      decoration: _inputDeco('ROOM CODE'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NeonButton(
                    label: _connecting ? '…' : 'JOIN',
                    color: AppColors.ember,
                    compact: true,
                    onPressed: _connecting ? null : _joinOnline,
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
