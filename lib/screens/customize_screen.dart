import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/cannon_widget.dart';
import '../widgets/ocean_background.dart';
import '../widgets/ship_painter.dart';

/// Shipyard — unlock & equip ship hulls and cannons with RP.
class CustomizeScreen extends StatefulWidget {
  const CustomizeScreen({super.key});

  @override
  State<CustomizeScreen> createState() => _CustomizeScreenState();
}

class _CustomizeScreenState extends State<CustomizeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileStore>();
    return Scaffold(
      body: OceanBackground(
        showSonar: false,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.steel),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        '🎨 SHIPYARD',
                        textAlign: TextAlign.center,
                        style: AppText.heading(size: 18, color: AppColors.radar),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.ink.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.6)),
                      ),
                      child: Text(
                        '⭐ ${profile.rp} RP',
                        style: AppText.label(size: 11, color: AppColors.gold),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
              TabBar(
                controller: _tab,
                indicatorColor: AppColors.ember,
                labelStyle: AppText.label(size: 11, color: AppColors.ember),
                unselectedLabelStyle:
                    AppText.label(size: 11, color: AppColors.steel),
                tabs: const [
                  Tab(text: 'SHIP HULLS'),
                  Tab(text: 'CANNONS'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _ShipsTab(profile: profile),
                    _CannonsTab(profile: profile),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShipsTab extends StatelessWidget {
  final ProfileStore profile;
  const _ShipsTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: Catalog.shipSkins.length,
      itemBuilder: (context, i) {
        final skin = Catalog.shipSkins[i];
        final owned = profile.owns(skin.id);
        final equipped = profile.shipSkinId == skin.id;
        final affordable = profile.rp >= skin.cost;
        return GestureDetector(
          onTap: () {
            final ok = profile.equipShipSkin(skin);
            if (ok) {
              SoundService.instance.victory();
            } else {
              SoundService.instance.denied();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Not enough RP! Need ${skin.cost} RP.',
                      style: const TextStyle(fontFamily: 'monospace')),
                  backgroundColor: AppColors.danger,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.ink.withValues(alpha: 0.6),
              border: Border.all(
                color: equipped
                    ? AppColors.victory
                    : skin.trim.withValues(alpha: 0.6),
                width: equipped ? 2 : 1.2,
              ),
              boxShadow: equipped
                  ? [
                      BoxShadow(
                          color: AppColors.victory.withValues(alpha: 0.3),
                          blurRadius: 14)
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: AnimatedShip(
                      spec: kFleet[1], // battleship preview
                      skin: skin,
                      size: 110,
                    ),
                  ),
                ),
                Text(skin.name,
                    style: AppText.label(size: 10, color: Colors.white)),
                const SizedBox(height: 4),
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: equipped
                        ? AppColors.victory.withValues(alpha: 0.2)
                        : owned
                            ? AppColors.sonar.withValues(alpha: 0.15)
                            : AppColors.gold.withValues(alpha: 0.12),
                  ),
                  child: Text(
                    equipped
                        ? 'EQUIPPED'
                        : owned
                            ? 'TAP TO EQUIP'
                            : '⭐ ${skin.cost} RP',
                    style: AppText.label(
                      size: 9,
                      color: equipped
                          ? AppColors.victory
                          : owned
                              ? AppColors.radar
                              : (affordable ? AppColors.gold : AppColors.danger),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CannonsTab extends StatelessWidget {
  final ProfileStore profile;
  const _CannonsTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: Catalog.cannonSkins.length,
      itemBuilder: (context, i) {
        final cannon = Catalog.cannonSkins[i];
        final owned = profile.owns(cannon.id);
        final equipped = profile.cannonSkinId == cannon.id;
        final affordable = profile.rp >= cannon.cost;
        return GestureDetector(
          onTap: () {
            final ok = profile.equipCannonSkin(cannon);
            if (ok) {
              SoundService.instance.victory();
            } else {
              SoundService.instance.denied();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Not enough RP! Need ${cannon.cost} RP.',
                      style: const TextStyle(fontFamily: 'monospace')),
                  backgroundColor: AppColors.danger,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.ink.withValues(alpha: 0.6),
              border: Border.all(
                color: equipped
                    ? AppColors.victory
                    : cannon.projectile.withValues(alpha: 0.55),
                width: equipped ? 2 : 1.2,
              ),
            ),
            child: Row(
              children: [
                CannonWidget(
                  skin: cannon,
                  cooldownFraction: 1,
                  enabled: false,
                  label: '',
                  size: 74,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cannon.name,
                          style: AppText.heading(size: 13, color: Colors.white)),
                      const SizedBox(height: 3),
                      Text(cannon.description,
                          style: AppText.body(size: 11)),
                      const SizedBox(height: 6),
                      Text(
                        equipped
                            ? '✔ EQUIPPED'
                            : owned
                                ? 'TAP TO EQUIP'
                                : '⭐ ${cannon.cost} RP',
                        style: AppText.label(
                          size: 10,
                          color: equipped
                              ? AppColors.victory
                              : owned
                                  ? AppColors.radar
                                  : (affordable
                                      ? AppColors.gold
                                      : AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
