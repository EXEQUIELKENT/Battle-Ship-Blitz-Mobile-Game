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
/// Cartoon style: navy header, cream item cards with thick outlines.
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
    _tab = TabController(length: 3, vsync: this);
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
              // ---- Navy header ----
              Container(
                width: double.infinity,
                color: AppColors.navy,
                padding: const EdgeInsets.fromLTRB(8, 10, 14, 12),
                child: Row(
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
                      child: Text(
                        'SHIPYARD',
                        style: AppText.title(size: 20),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.outline, width: 2.5),
                      ),
                      child: Text(
                        '${profile.rp} RP',
                        style: AppText.label(
                            size: 11, color: AppColors.outline),
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
                  isScrollable: true,
                  tabs: const [
                    Tab(text: 'SHIP HULLS'),
                    Tab(text: 'CANNONS'),
                    Tab(text: 'GAMEPLAY'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _ShipsTab(profile: profile),
                    _CannonsTab(profile: profile),
                    _ThemesTab(profile: profile),
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
                  content: Text(
                    'Not enough RP! Need ${skin.cost} RP.',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  backgroundColor: AppColors.hit,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: AppColors.cream,
              border: Border.all(
                color: equipped ? AppColors.green : AppColors.outline,
                width: equipped ? 4 : 3,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x44000000), offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.water,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.cellBorder, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Center(
                        child: AnimatedShip(
                          spec: kFleet[1], // battleship preview
                          skin: skin,
                          size: 130,
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  skin.name,
                  style: AppText.label(size: 10, color: AppColors.navy),
                ),
                const SizedBox(height: 5),
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: equipped
                        ? AppColors.green
                        : owned
                            ? AppColors.blue
                            : (affordable
                                ? AppColors.gold
                                : AppColors.inkSoft),
                    border:
                        Border.all(color: AppColors.outline, width: 2),
                  ),
                  child: Text(
                    equipped
                        ? 'EQUIPPED'
                        : owned
                            ? 'TAP TO EQUIP'
                            : '${skin.cost} RP',
                    style: AppText.label(
                      size: 9,
                      color: (!owned && affordable)
                          ? AppColors.outline
                          : AppColors.cream,
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
                  content: Text(
                    'Not enough RP! Need ${cannon.cost} RP.',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  backgroundColor: AppColors.hit,
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
              borderRadius: BorderRadius.circular(18),
              color: AppColors.cream,
              border: Border.all(
                color: equipped ? AppColors.green : AppColors.outline,
                width: equipped ? 4 : 3,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x44000000), offset: Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.water,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: AppColors.cellBorder, width: 2),
                  ),
                  child: CannonWidget(
                    skin: cannon,
                    cooldownFraction: 1,
                    enabled: false,
                    label: '',
                    size: 70,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cannon.name,
                        style:
                            AppText.heading(size: 13, color: AppColors.navy),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        cannon.description,
                        style: AppText.body(size: 11, color: AppColors.inkSoft),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: equipped
                              ? AppColors.green
                              : owned
                                  ? AppColors.blue
                                  : (affordable
                                      ? AppColors.gold
                                      : AppColors.inkSoft),
                          border: Border.all(
                              color: AppColors.outline, width: 2),
                        ),
                        child: Text(
                          equipped
                              ? 'EQUIPPED'
                              : owned
                                  ? 'TAP TO EQUIP'
                                  : '${cannon.cost} RP',
                          style: AppText.label(
                            size: 9,
                            color: (!owned && affordable)
                                ? AppColors.outline
                                : AppColors.cream,
                          ),
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


class _ThemesTab extends StatelessWidget {
  final ProfileStore profile;
  const _ThemesTab({required this.profile});
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 1, mainAxisSpacing: 12, childAspectRatio: 1.9),
      itemCount: Catalog.gameplayThemes.length,
      itemBuilder: (context, i) {
        final theme = Catalog.gameplayThemes[i];
        final owned = profile.owns(theme.id);
        final equipped = profile.gameplayThemeId == theme.id;
        final affordable = profile.rp >= theme.cost;
        return GestureDetector(
          onTap: () {
            final ok = profile.equipGameplayTheme(theme);
            if (ok) {
              SoundService.instance.victory();
            } else {
              SoundService.instance.denied();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Not enough RP! Need ${theme.cost} RP.', style: const TextStyle(fontWeight: FontWeight.w800)), backgroundColor: AppColors.hit, behavior: SnackBarBehavior.floating));
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: theme.deck, borderRadius: BorderRadius.circular(18), border: Border.all(color: equipped ? AppColors.green : AppColors.outline, width: equipped ? 4 : 3), boxShadow: const [BoxShadow(color: Color(0x44000000), offset: Offset(0, 4))]),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.grid,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.gridLine, width: 3),
                    ),
                    child: CustomPaint(
                      painter: _ThemePreviewPainter(theme),
                      child: Center(
                        child: Text(
                          theme.name.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: AppText.label(size: 12),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(theme.name, style: AppText.heading(size: 15)),
                      const SizedBox(height: 4),
                      Text(theme.description, style: AppText.body(size: 11)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: equipped
                              ? AppColors.green
                              : owned
                                  ? AppColors.blue
                                  : (affordable ? AppColors.gold : AppColors.inkSoft),
                          border: Border.all(color: AppColors.outline, width: 2),
                        ),
                        child: Text(
                          equipped
                              ? 'EQUIPPED'
                              : owned
                                  ? 'TAP TO EQUIP'
                                  : '${theme.cost} RP',
                          style: AppText.label(
                            size: 9,
                            color: (!owned && affordable)
                                ? AppColors.outline
                                : AppColors.cream,
                          ),
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

class _ThemePreviewPainter extends CustomPainter {
  final GameplayTheme theme;
  _ThemePreviewPainter(this.theme);
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = theme.gridLine.withValues(alpha: 0.55)..strokeWidth = 1.4;
    final cw = size.width / 5, ch = size.height / 4;
    for (var c = 1; c < 5; c++) canvas.drawLine(Offset(c * cw, 0), Offset(c * cw, size.height), line);
    for (var r = 1; r < 4; r++) canvas.drawLine(Offset(0, r * ch), Offset(size.width, r * ch), line);
    canvas.drawCircle(Offset(size.width * 0.64, size.height * 0.48), size.shortestSide * 0.13, Paint()..color = theme.accent);
  }
  @override
  bool shouldRepaint(covariant _ThemePreviewPainter oldDelegate) => oldDelegate.theme.id != theme.id;
}
