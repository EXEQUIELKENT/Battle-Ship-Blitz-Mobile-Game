import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../services/vs_ai_session.dart';
import '../widgets/ocean_background.dart';
import 'lan_mode_screen.dart' show lanModeIcon;
import 'placement_screen.dart';

/// Mode picker for a vsAiLan match — everything `LanModeScreen` is, minus
/// the parts that only make sense with a second human to vote against:
/// no peer chip, no tally, no countdown, no chat. There's nobody to
/// disagree with, so tapping a card starts the match immediately (see
/// `VsAiSession.start`, which sets up the hidden AI opponent and its own
/// fleet before this screen moves on) and goes straight to placement —
/// the same next step `LanModeScreen._startMatch` reaches once a real
/// vote locks in.
class VsAiModeScreen extends StatefulWidget {
  final AIDifficulty difficulty;

  const VsAiModeScreen({super.key, required this.difficulty});

  @override
  State<VsAiModeScreen> createState() => _VsAiModeScreenState();
}

class _VsAiModeScreenState extends State<VsAiModeScreen> {
  bool _starting = false;

  Future<void> _pick(LanBattleMode mode) async {
    if (_starting) return;
    SoundService.instance.click();
    setState(() => _starting = true);
    final controller = context.read<GameController>();

    // TURN BASED keeps running on the original, lightweight vs-AI engine
    // (`GameController._aiThink`/`aiTurnToFire`) exactly as it always
    // has — untouched, and still the experience "BATTLE vs AI" gave
    // before this picker existed. Only the other five modes — which
    // never worked against the AI at all before — need the loopback
    // opponent (`VsAiSession`); routing TURN BASED through it too would
    // trade a proven, fast path for no real benefit.
    if (mode == LanBattleMode.turns) {
      controller.mode = GameMode.vsAI;
      controller.difficulty = widget.difficulty;
      controller.startPlacement();
    } else {
      final profile = context.read<ProfileStore>();
      final session = context.read<VsAiSession>();
      await session.start(
        player: controller,
        lanBattleMode: mode,
        playerName: profile.playerName,
        playerShipSkinId: profile.shipSkinId,
        playerShipChosen: profile.shipSkinChosen,
        playerCannonSkinId: profile.cannonSkinId,
        playerThemeId: profile.gameplayThemeId,
        difficulty: widget.difficulty,
      );
      if (!mounted) return;
      controller.startPlacement();
    }
    if (!mounted) return;
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
                            'PICK HOW YOU WANT TO FIGHT THE ${widget.difficulty.label} AI.',
                            textAlign: TextAlign.center,
                            style:
                                AppText.label(size: 10, color: AppColors.navy),
                          ),
                          const SizedBox(height: 14),
                          for (final mode in LanBattleMode.values) ...[
                            _modeCard(mode),
                            const SizedBox(height: 12),
                          ],
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
