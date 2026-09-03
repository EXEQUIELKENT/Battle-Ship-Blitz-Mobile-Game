import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/route_observer.dart';
import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/match_store.dart';
import '../services/network_service.dart';
import '../services/online_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/hero_ship_dock.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';
import 'customize_screen.dart';
import 'friends_screen.dart';
import 'hotspot_screen.dart';
import 'match_resume.dart';
import 'local_mode_screen.dart';
import 'vs_ai_mode_screen.dart';

/// Cartoon main menu: coral deck, navy panels, chunky outlined buttons.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  late final AnimationController _titleCtrl;
  AIDifficulty _difficulty = AIDifficulty.normal;

  @override
  void initState() {
    super.initState();
    SoundService.instance.enabled = context.read<ProfileStore>().soundOn;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SoundService.instance.startMenuMusic();
    });
    _titleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    SoundService.instance.stopMenuMusic();
    _titleCtrl.dispose();
    super.dispose();
  }

  /// See the doc comment on [appRouteObserver] — fires whenever HomeScreen
  /// becomes the visible top route again (e.g. REMATCH / MAIN MENU on the
  /// result screen popping back to it), which is exactly when the menu
  /// music — turned off back when PlacementScreen/BattleScreen started —
  /// needs to be turned back on. `startMenuMusic()` is a safe no-op if
  /// it's already playing.
  @override
  void didPopNext() {
    super.didPopNext();
    if (mounted) SoundService.instance.startMenuMusic();
  }

  /// TURN BASED here still runs on the original, lightweight vs-AI engine
  /// (`GameController._aiThink`/`aiTurnToFire`) unchanged — this only
  /// adds a mode PICKER in front of it. The other five modes route
  /// through `VsAiModeScreen` into the loopback AI opponent instead (see
  /// `VsAiSession`), the only way any of them can be played against the
  /// AI at all.
  void _startVsAI() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VsAiModeScreen(difficulty: _difficulty),
      ),
    );
  }

  /// A hotspot/online match `MatchStore` remembers as still in progress
  /// — see that class's own doc for what "in progress" means here: not
  /// just a dropped connection (that already has its own in-battle
  /// overlay), but the app having been fully closed and reopened. Null
  /// when there is nothing to offer, so callers can treat that as "don't
  /// show a banner" directly.
  Widget? _resumeBanner(MatchStore matchStore) {
    final saved = matchStore.saved;
    if (saved == null) return null;
    final isOnline = saved['transport'] == NetMode.online.index;
    final iAmHost = saved['iAmHost'] as bool? ?? false;
    final peerName = saved['peerName'] as String? ?? 'Opponent';

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: cartoonBox(AppColors.ember, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${isOnline ? 'ONLINE' : 'HOTSPOT'} BATTLE IN PROGRESS\n'
              'vs ${peerName.toUpperCase()}',
              style: AppText.label(size: 11),
            ),
            const SizedBox(height: 4),
            Text(
              isOnline
                  ? 'Your seat is still held on the server.'
                  : iAmHost
                      ? 'Reopen your room and wait for them to rejoin.'
                      : "Rejoin the host's room — they'll need to have "
                          'reopened it too.',
              style: AppText.body(size: 11, color: AppColors.cream),
            ),
            const SizedBox(height: 12),
            NeonButton(
              label: isOnline
                  ? 'GO TO ONLINE'
                  : iAmHost
                      ? 'REOPEN ROOM'
                      : 'FIND ROOM',
              icon: Icons.sailing,
              color: AppColors.seafoam,
              compact: true,
              onPressed: () {
                SoundService.instance.click();
                if (isOnline) {
                  // The server — not this stale disk copy — is the real
                  // authority on whether the match is still there; the
                  // FRIENDS screen's own rejoin banner is what actually
                  // acts on it, once it has asked.
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FriendsScreen()),
                  );
                } else if (iAmHost) {
                  unawaited(resumeHotspotAsHost(context, saved));
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HotspotScreen(
                          initialRoomCode: saved['roomCode'] as String?),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startLocal() {
    // Routes through a mode picker (classic TURN BASED or PHANTOM) rather
    // than starting a match directly — see `LocalModeScreen`, which does
    // what this used to do inline once a mode is actually chosen.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LocalModeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileStore>();
    final matchStore = context.watch<MatchStore>();
    return Scaffold(
      body: OceanBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        // ---- Profile bar ----
                        Row(
                          children: [
                            Expanded(child: _profileCard(profile)),
                            const SizedBox(width: 10),
                            _soundButton(profile),
                          ],
                        ),
                        const SizedBox(height: 22),
                        // ---- Resume banner (if MatchStore has one) ----
                        if (_resumeBanner(matchStore) case final banner?)
                          banner,
                        // ---- Title card ----
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          decoration: cartoonBox(AppColors.navy, radius: 20),
                          child: Column(
                            children: [
                              Text(
                                'BATTLESHIP',
                                style: AppText.title(size: 32),
                              ),
                              AnimatedBuilder(
                                animation: _titleCtrl,
                                builder: (context, _) {
                                  final bump =
                                      1.0 + 0.06 * sin(_titleCtrl.value * pi);
                                  return Transform.scale(
                                    scale: bump,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.bolt,
                                            color: AppColors.gold, size: 26),
                                        Text(
                                          'BLITZ',
                                          style: AppText.title(
                                              size: 28,
                                              color: AppColors.gold),
                                        ),
                                        const Icon(Icons.bolt,
                                            color: AppColors.gold, size: 26),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'REAL-TIME NAVAL WARFARE',
                                style: AppText.label(
                                  size: 10,
                                  color:
                                      AppColors.cream.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ---- Hero ship on an interactive water dock ----
                        // Bobs on its own, can be dragged around inside
                        // the plate, and cycles through the shipyard's
                        // hull classes (always in the equipped skin) on
                        // tap — see HeroShipDock for the choreography.
                        HeroShipDock(equippedSkin: profile.shipSkin),
                        const SizedBox(height: 18),
                        // ---- Difficulty selector ----
                        _difficultySelector(),
                        const SizedBox(height: 14),
                        // ---- Mode buttons ----
                        SizedBox(
                          width: double.infinity,
                          child: NeonButton(
                            label: 'BATTLE vs AI',
                            icon: Icons.anchor,
                            color: AppColors.blue,
                            onPressed: _startVsAI,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: NeonButton(
                                label: 'LOCAL',
                                icon: Icons.people,
                                color: AppColors.green,
                                compact: true,
                                onPressed: _startLocal,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // ONLINE is the two-tab online section now — FRIENDS (invites,
                            // search, match history) and MATCHMAKING (random
                            // pair-up) side by side in one screen. See
                            // `FriendsScreen`. The HOTSPOT / LAN button
                            // below opens its own dedicated page for
                            // same-Wi-Fi play.
                            Expanded(
                              child: NeonButton(
                                label: 'ONLINE',
                                icon: Icons.public,
                                color: AppColors.seafoam,
                                compact: true,
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const FriendsScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Hotspot/LAN is same-Wi-Fi play, so it gets its own dedicated
                        // page — opening straight into the host/join
                        // screen (`HotspotScreen`) instead of a tab inside
                        // a broader multiplayer lobby.
                        SizedBox(
                          width: double.infinity,
                          child: NeonButton(
                            label: 'HOTSPOT / LAN',
                            icon: Icons.wifi_tethering,
                            color: AppColors.ember,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const HotspotScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: NeonButton(
                            label: 'SHIPYARD — CUSTOMIZE',
                            icon: Icons.palette,
                            color: AppColors.gold,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CustomizeScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        _statsRow(profile),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _profileCard(ProfileStore profile) {
    return GestureDetector(
      onTap: () => _editName(profile),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: cartoonBox(AppColors.navy, radius: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.outline, width: 2.5),
              ),
              child: Center(
                child: Text(
                  profile.playerName.isNotEmpty
                      ? profile.playerName[0].toUpperCase()
                      : 'C',
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.playerName,
                    style: AppText.heading(size: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${profile.rankTitle}  •  ${profile.rp} RP',
                    style: AppText.label(size: 9.5, color: AppColors.gold),
                  ),
                ],
              ),
            ),
            if (profile.streak >= 2)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.hit,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.outline, width: 2),
                ),
                child: Text(
                  'x${profile.streak}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: AppColors.cream,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _soundButton(ProfileStore profile) {
    return GestureDetector(
      onTap: () {
        // Play the click while sound is still in its current state, so
        // toggling OFF gets an audible confirmation on the way out.
        SoundService.instance.click();
        profile.toggleSound();
        SoundService.instance.enabled = !SoundService.instance.enabled;
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: cartoonBox(
          profile.soundOn ? AppColors.blue : AppColors.inkSoft,
          radius: 14,
        ),
        child: Icon(
          profile.soundOn ? Icons.volume_up : Icons.volume_off,
          color: AppColors.cream,
          size: 20,
        ),
      ),
    );
  }

  Widget _difficultySelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: cartoonBox(AppColors.coralLight, radius: 14),
      child: Row(
        children: AIDifficulty.values.map((d) {
          final selected = d == _difficulty;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                SoundService.instance.click();
                setState(() => _difficulty = d);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: selected ? AppColors.blue : Colors.transparent,
                  border: selected
                      ? Border.all(color: AppColors.outline, width: 2.5)
                      : null,
                  boxShadow: selected
                      ? const [
                          BoxShadow(
                            color: Color(0x33000000),
                            offset: Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  d.label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: selected ? AppColors.cream : AppColors.navy,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _statsRow(ProfileStore p) {
    Widget stat(String label, String value, Color color) => Expanded(
          child: Column(
            children: [
              Text(value, style: AppText.heading(size: 18, color: color)),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppText.label(
                  size: 9,
                  color: AppColors.cream.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: cartoonBox(AppColors.navyDark, radius: 16),
      child: Row(
        children: [
          stat('WINS', '${p.wins}', AppColors.green),
          stat('LOSSES', '${p.losses}', AppColors.hit),
          stat('BEST STREAK', '${p.bestStreak}', AppColors.gold),
          stat(
            'WIN RATE',
            p.wins + p.losses == 0
                ? '—'
                : '${(p.wins / (p.wins + p.losses) * 100).round()}%',
            AppColors.waterLight,
          ),
        ],
      ),
    );
  }

  void _editName(ProfileStore profile) {
    final ctrl = TextEditingController(text: profile.playerName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navy,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.outline, width: 3),
        ),
        title: Text('CALLSIGN', style: AppText.heading(size: 16)),
        content: TextField(
          controller: ctrl,
          maxLength: 14,
          style: AppText.body(),
          decoration: InputDecoration(
            counterStyle: AppText.label(size: 10),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.cream),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.gold, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              SoundService.instance.click();
              Navigator.pop(ctx);
            },
            child: Text(
              'CANCEL',
              style: AppText.label(
                  color: AppColors.cream.withValues(alpha: 0.7)),
            ),
          ),
          TextButton(
            onPressed: () {
              SoundService.instance.click();
              profile.setName(ctrl.text);
              // A renamed captain must not stay under the old name on the
              // friends list: push the new one up straight away. Fire and
              // forget — the dialog closes either way.
              final online = context.read<OnlineService>();
              if (online.signedIn) {
                online.syncProfile(profile);
              }
              Navigator.pop(ctx);
            },
            child: Text('SAVE', style: AppText.label(color: AppColors.gold)),
          ),
        ],
      ),
    );
  }
}
