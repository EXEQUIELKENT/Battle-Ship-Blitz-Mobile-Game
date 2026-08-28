import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/sound_service.dart';
import '../widgets/ocean_background.dart';
import 'lan_mode_screen.dart' show lanModeIcon;
import 'placement_screen.dart';

/// Mode picker for local pass-and-play — the shared-screen equivalent of
/// `VsAiModeScreen`, minus even the AI difficulty line, since there is no
/// opponent to configure at all here.
///
/// Only two cards, not all of [LanBattleMode.values]: local play never
/// lets a fleet rearrange (`GameController.isManoeuvreBattle` requires
/// `usesMatchProtocol`, which local matches never set), which rules out
/// MANOEUVRE, BLITZ and GHOST FLEET outright, and there is no second
/// device to vote with, which is what CHAOS and POWER PLAY are built
/// around. PHANTOM is the one LAN mode that asks nothing of either —
/// turn-based, fixed fleets, just a quieter board — so it is the only
/// one on offer beside the classic default. See
/// `GameController.localPhantom`, the standalone flag this sets (local
/// play has no `lanBattleMode` vote to store the choice in).
class LocalModeScreen extends StatefulWidget {
  const LocalModeScreen({super.key});

  @override
  State<LocalModeScreen> createState() => _LocalModeScreenState();
}

class _LocalModeScreenState extends State<LocalModeScreen> {
  bool _starting = false;

  void _pick(LanBattleMode mode) {
    if (_starting) return;
    SoundService.instance.click();
    setState(() => _starting = true);
    final controller = context.read<GameController>();
    controller.mode = GameMode.local;
    controller.localPhantom = mode == LanBattleMode.phantom;
    // Both seats start on the device owner's own gear; each player can
    // then swap to anything the profile owns on their deployment screen.
    controller.resetLocalLoadouts();
    controller.startPlacement();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PlacementScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_starting,
      child: Scaffold(
        body: OceanBackground(
          showSonar: false,
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: AppColors.navy,
                  padding: const EdgeInsets.fromLTRB(8, 10, 14, 14),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: AppColors.cream),
                        onPressed: _starting
                            ? null
                            : () {
                                SoundService.instance.click();
                                Navigator.pop(context);
                              },
                      ),
                      Expanded(
                        child: Text('CHOOSE BATTLE MODE',
                            style: AppText.title(size: 18)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      ListView(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                        children: [
                          Text(
                            'ONE DEVICE, TWO CAPTAINS — PICK HOW YOU WANT '
                            'TO PLAY.',
                            textAlign: TextAlign.center,
                            style:
                                AppText.label(size: 10, color: AppColors.navy),
                          ),
                          const SizedBox(height: 14),
                          _modeCard(LanBattleMode.turns),
                          const SizedBox(height: 12),
                          _modeCard(LanBattleMode.phantom),
                        ],
                      ),
                      if (_starting)
                        Container(
                          color: const Color(0x66000000),
                          child: const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.cream),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeCard(LanBattleMode mode) {
    return GestureDetector(
      onTap: _starting ? null : () => _pick(mode),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline, width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(lanModeIcon(mode), color: AppColors.navy, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(mode.label,
                      style: AppText.title(size: 20, color: AppColors.navy)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(mode.tagline,
                style: AppText.label(size: 10, color: AppColors.inkSoft)),
            const SizedBox(height: 6),
            Text(mode.blurb,
                style: AppText.body(size: 11, color: AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}
