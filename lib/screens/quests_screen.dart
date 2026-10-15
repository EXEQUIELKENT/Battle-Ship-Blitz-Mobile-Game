import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/ocean_background.dart';

/// Quests & medals: today's three seeded daily quests with live
/// progress, plus the one-time achievement shelf. Everything pays
/// Doubloons on completion (see `ProfileStore.recordMatchForAwards`).
class QuestsScreen extends StatelessWidget {
  const QuestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileStore>();
    final quests = ProfileStore.dailyQuestIds(DateTime.now());
    final unlocked =
        ProfileStore.achievementDefs.where((a) => profile.achievements.contains(a.id)).length;
    return Scaffold(
      body: OceanBackground(
        showSonar: false,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.cream),
                      onPressed: () {
                        SoundService.instance.click();
                        Navigator.pop(context);
                      },
                    ),
                    Expanded(
                      child: Text('QUESTS & MEDALS',
                          style: AppText.title(size: 20)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.outline, width: 2.5),
                      ),
                      child: Text(
                        '${profile.doubloons} DBL',
                        style: AppText.label(
                            size: 11, color: AppColors.outline),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text("TODAY'S QUESTS",
                    style: AppText.label(
                        size: 11,
                        color:
                            AppColors.cream.withValues(alpha: 0.75))),
                const SizedBox(height: 8),
                for (final q in quests) ...[
                  _questCard(
                    profile,
                    icon: q.icon,
                    name: q.name,
                    desc: q.desc,
                    progress: profile.questProgress[q.id] ?? 0,
                    target: q.target,
                    reward: q.reward,
                    done: profile.questDone.contains(q.id),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 12),
                Text('MEDALS  ($unlocked/${ProfileStore.achievementDefs.length})',
                    style: AppText.label(
                        size: 11,
                        color:
                            AppColors.cream.withValues(alpha: 0.75))),
                const SizedBox(height: 8),
                for (final a in ProfileStore.achievementDefs) ...[
                  _achievementRow(
                    unlocked: profile.achievements.contains(a.id),
                    icon: a.icon,
                    name: a.name,
                    desc: a.desc,
                    reward: a.reward,
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                NeonButton(
                  label: 'BACK',
                  icon: Icons.arrow_back,
                  color: AppColors.blue,
                  compact: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _questCard(
    ProfileStore profile, {
    required String icon,
    required String name,
    required String desc,
    required int progress,
    required int target,
    required int reward,
    required bool done,
  }) {
    final frac = (progress / target).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: cartoonBox(
        done ? AppColors.green : AppColors.navy,
        radius: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    style: AppText.heading(
                        size: 14, color: AppColors.cream)),
              ),
              Text(done ? 'DONE ✓  +$reward' : '+$reward DBL',
                  style: AppText.label(
                      size: 10,
                      color: done
                          ? AppColors.cream
                          : AppColors.gold)),
            ],
          ),
          const SizedBox(height: 2),
          Text(desc,
              style: AppText.body(
                  size: 11,
                  color: AppColors.cream.withValues(alpha: 0.8))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 8,
                    backgroundColor:
                        Colors.black.withValues(alpha: 0.4),
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.gold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$progress/$target',
                  style: AppText.label(
                      size: 10, color: AppColors.cream)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _achievementRow({
    required bool unlocked,
    required String icon,
    required String name,
    required String desc,
    required int reward,
  }) {
    return Opacity(
      opacity: unlocked ? 1.0 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: cartoonBox(AppColors.navy, radius: 14),
        child: Row(
          children: [
            Text(unlocked ? icon : '🔒',
                style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: AppText.heading(
                          size: 13, color: AppColors.cream)),
                  Text(desc,
                      style: AppText.body(
                          size: 11,
                          color: AppColors.cream
                              .withValues(alpha: 0.8))),
                ],
              ),
            ),
            Text('+$reward',
                style: AppText.label(
                    size: 10, color: AppColors.gold)),
          ],
        ),
      ),
    );
  }
}
