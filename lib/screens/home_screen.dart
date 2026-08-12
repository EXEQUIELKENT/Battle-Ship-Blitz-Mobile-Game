import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';
import '../widgets/ship_painter.dart';
import 'customize_screen.dart';
import 'multiplayer_screen.dart';
import 'placement_screen.dart';

/// Animated home / main menu.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _titleCtrl;
  AIDifficulty _difficulty = AIDifficulty.normal;

  @override
  void initState() {
    super.initState();
    _titleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _startVsAI() {
    final controller = context.read<GameController>();
    controller.mode = GameMode.vsAI;
    controller.difficulty = _difficulty;
    controller.startPlacement();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlacementScreen()),
    );
  }

  void _startLocal() {
    final controller = context.read<GameController>();
    controller.mode = GameMode.local;
    controller.startPlacement();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlacementScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileStore>();
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
                        const SizedBox(height: 20),
                        // ---- Profile bar ----
                        Row(
                          children: [
                            Expanded(child: _profileCard(profile)),
                            const SizedBox(width: 8),
                            _soundButton(profile),
                          ],
                        ),
                        const SizedBox(height: 26),
                        // ---- Animated title ----
                        AnimatedBuilder(
                          animation: _titleCtrl,
                          builder: (context, _) {
                            final glow = 0.6 + 0.4 * sin(_titleCtrl.value * pi);
                            return Column(
                              children: [
                                Text(
                                  'BATTLESHIP',
                                  style: AppText.title(
                                    size: 34,
                                    color: AppColors.radar.withValues(alpha: glow),
                                  ),
                                ),
                                Text(
                                  '⚡ BLITZ ⚡',
                                  style: AppText.title(
                                    size: 26,
                                    color: AppColors.ember.withValues(alpha: glow),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'REAL-TIME NAVAL WARFARE',
                          style: AppText.label(color: AppColors.steel),
                        ),
                        const SizedBox(height: 18),
                        // ---- Hero ship ----
                        AnimatedShip(
                          spec: kFleet.first,
                          skin: profile.shipSkin,
                          size: 220,
                        ),
                        const SizedBox(height: 24),
                        // ---- Mode buttons ----
                        _difficultySelector(),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: NeonButton(
                            label: '⚓  BATTLE vs AI',
                            color: AppColors.sonar,
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
                                color: AppColors.victory,
                                compact: true,
                                onPressed: _startLocal,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: NeonButton(
                                label: 'MULTIPLAYER',
                                icon: Icons.wifi_tethering,
                                color: AppColors.ember,
                                compact: true,
                                onPressed: () {
                                  SoundService.instance.click();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const MultiplayerScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: NeonButton(
                            label: '🎨  SHIPYARD — CUSTOMIZE',
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
                        const SizedBox(height: 20),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.ink.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.sonar.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.sonarDim,
              child: Text(
                profile.playerName.isNotEmpty
                    ? profile.playerName[0].toUpperCase()
                    : 'C',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.fire.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.fire),
                ),
                child: Text(
                  '🔥${profile.streak}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
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
        profile.toggleSound();
        SoundService.instance.enabled = !SoundService.instance.enabled;
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.ink.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: profile.soundOn
                ? AppColors.sonar.withValues(alpha: 0.6)
                : AppColors.fog.withValues(alpha: 0.4),
          ),
        ),
        child: Icon(
          profile.soundOn ? Icons.volume_up : Icons.volume_off,
          color: profile.soundOn ? AppColors.sonar : AppColors.fog,
          size: 20,
        ),
      ),
    );
  }

  Widget _difficultySelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.sonarDim.withValues(alpha: 0.6)),
      ),
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
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: selected
                      ? AppColors.sonar.withValues(alpha: 0.22)
                      : Colors.transparent,
                  border: selected
                      ? Border.all(color: AppColors.sonar, width: 1.2)
                      : null,
                ),
                child: Text(
                  d.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: selected ? AppColors.radar : AppColors.steel,
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
              Text(value,
                  style: AppText.heading(size: 18, color: color)),
              const SizedBox(height: 2),
              Text(label, style: AppText.label(size: 9)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.sonarDim.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          stat('WINS', '${p.wins}', AppColors.victory),
          stat('LOSSES', '${p.losses}', AppColors.danger),
          stat('BEST STREAK', '${p.bestStreak}', AppColors.gold),
          stat('WIN RATE',
              p.wins + p.losses == 0
                  ? '—'
                  : '${(p.wins / (p.wins + p.losses) * 100).round()}%',
              AppColors.radar),
        ],
      ),
    );
  }

  void _editName(ProfileStore profile) {
    final ctrl = TextEditingController(text: profile.playerName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.deepSea,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.sonar.withValues(alpha: 0.5)),
        ),
        title: Text('CALLSIGN', style: AppText.heading(size: 15, color: AppColors.radar)),
        content: TextField(
          controller: ctrl,
          maxLength: 14,
          style: AppText.body(color: Colors.white),
          decoration: InputDecoration(
            counterStyle: AppText.label(size: 10),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.sonar.withValues(alpha: 0.5)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.sonar),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: AppText.label(color: AppColors.steel)),
          ),
          TextButton(
            onPressed: () {
              profile.setName(ctrl.text);
              Navigator.pop(ctx);
            },
            child: Text('SAVE', style: AppText.label(color: AppColors.sonar)),
          ),
        ],
      ),
    );
  }
}
