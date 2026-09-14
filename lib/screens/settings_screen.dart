import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/motion.dart';
import '../widgets/ocean_background.dart';

/// Everything about the game that is a preference rather than a rule.
///
/// Three groups, in the order a player is likely to want them: what they
/// can HEAR, what the game spends its frames on, and the one piece of
/// presentation that is deliberately off until asked for.
///
/// Every control writes straight through `ProfileStore`, which persists it
/// and pushes it at whatever actually reads it — the sound service for
/// volume, `impact_fx.dart`'s density global for graphics. There is no
/// "apply" button because there is nothing to apply: each change is live
/// the moment it is made, and audible or visible immediately.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileStore>();
    final pop = PopSequence();
    return Scaffold(
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
                      icon: const Icon(Icons.arrow_back, color: AppColors.cream),
                      onPressed: () {
                        SoundService.instance.click();
                        Navigator.pop(context);
                      },
                    ),
                    Expanded(
                      child: Text('SETTINGS', style: AppText.title(size: 18)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                  children: [
                    pop.wrap(_section('AUDIO', Icons.volume_up, [
                      _ToggleRow(
                        label: 'SOUND',
                        blurb: profile.soundOn
                            ? 'Effects and music are playing.'
                            : 'Everything is muted.',
                        value: profile.soundOn,
                        onChanged: (_) {
                          // Clicked while sound is still in its CURRENT
                          // state, so switching off gets an audible
                          // confirmation on the way out.
                          SoundService.instance.click();
                          profile.toggleSound();
                          SoundService.instance.enabled =
                              !SoundService.instance.enabled;
                        },
                      ),
                      _SliderRow(
                        label: 'EFFECTS',
                        icon: Icons.graphic_eq,
                        value: profile.sfxVolume,
                        enabled: profile.soundOn,
                        onChanged: profile.setSfxVolume,
                        // The click IS one of the cues being adjusted, so
                        // it doubles as the preview of the new level.
                        onSettled: () => SoundService.instance.click(),
                      ),
                      _SliderRow(
                        label: 'MUSIC',
                        icon: Icons.music_note,
                        value: profile.musicVolume,
                        enabled: profile.soundOn,
                        onChanged: profile.setMusicVolume,
                      ),
                    ])),
                    const SizedBox(height: 14),
                    pop.wrap(_section('GRAPHICS', Icons.auto_awesome, [
                      for (final q in GraphicsQuality.values)
                        _ChoiceRow(
                          label: q.label,
                          blurb: q.blurb,
                          selected: profile.graphics == q,
                          onTap: () {
                            SoundService.instance.click();
                            profile.setGraphics(q);
                          },
                        ),
                    ])),
                    const SizedBox(height: 14),
                    pop.wrap(_section(
                        'PRESENTATION', Icons.movie_creation_outlined, [
                      _ToggleRow(
                        label: 'CINEMATIC FINISH',
                        blurb: 'The shell that sinks a fleet’s last hull gets '
                            'a slow, close-up camera. Off by default — it '
                            'holds the match up for a couple of seconds.',
                        value: profile.cinematicFinish,
                        onChanged: (v) {
                          SoundService.instance.click();
                          profile.setCinematicFinish(v);
                        },
                      ),
                    ])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _section(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: cartoonBox(AppColors.navy, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Text(title, style: AppText.heading(size: 14)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// An on/off setting.
class _ToggleRow extends StatelessWidget {
  final String label;
  final String blurb;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.blurb,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => onChanged(!value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: cartoonBox(AppColors.navyDark, radius: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.label(size: 11)),
                  const SizedBox(height: 3),
                  Text(blurb,
                      style: AppText.body(size: 10, color: AppColors.mist)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // A chunky switch rather than Material's, so it belongs to the
            // same cartoon set as every other control in the game.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: 46,
              height: 26,
              decoration: BoxDecoration(
                color: value ? AppColors.green : AppColors.inkSoft,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.outline, width: 2.5),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 17,
                  decoration: const BoxDecoration(
                    color: AppColors.cream,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 0..1 setting with a live preview.
class _SliderRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback? onSettled;

  const _SliderRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.onSettled,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      // Dimmed rather than removed while sound is off: the level is still
      // set, it just is not being heard, and hiding it would make the mute
      // look like it had wiped the setting.
      opacity: enabled ? 1 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: cartoonBox(AppColors.navyDark, radius: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.mist, size: 16),
            const SizedBox(width: 8),
            SizedBox(
              width: 58,
              child: Text(label, style: AppText.label(size: 10)),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.gold,
                  inactiveTrackColor: AppColors.outline,
                  thumbColor: AppColors.cream,
                  overlayColor: AppColors.gold.withValues(alpha: 0.18),
                  trackHeight: 5,
                ),
                child: Slider(
                  value: value.clamp(0.0, 1.0),
                  onChanged: enabled ? onChanged : null,
                  onChangeEnd: enabled ? (_) => onSettled?.call() : null,
                ),
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${(value * 100).round()}',
                textAlign: TextAlign.right,
                style: AppText.label(size: 10, color: AppColors.mist),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One option in a pick-exactly-one group.
class _ChoiceRow extends StatelessWidget {
  final String label;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceRow({
    required this.label,
    required this.blurb,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: cartoonBox(
          selected ? AppColors.blue : AppColors.navyDark,
          radius: 12,
          border: selected ? AppColors.gold : null,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.gold : AppColors.mist,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.label(size: 11)),
                  const SizedBox(height: 3),
                  Text(blurb,
                      style: AppText.body(size: 10, color: AppColors.mist)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
