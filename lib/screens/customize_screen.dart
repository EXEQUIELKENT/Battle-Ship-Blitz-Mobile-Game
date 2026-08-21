import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../art/family_board_art.dart';
import '../art/family_shell_art.dart';
import '../art/fleet_family.dart';
import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/cannon_widget.dart';
import '../widgets/ocean_background.dart';
import '../widgets/ship_painter.dart';

/// Shipyard — unlock & equip ship hulls, cannons and battlefields with RP.
///
/// **The store sells the design, not the swatch.** That line from the
/// "Skin system architecture" design is the whole brief for this screen,
/// and the shell around it is deliberately unchanged — navy header, gold
/// RP pill, three tabs, cream cards. What changed is what a card is
/// allowed to show.
///
/// The old cards were honest about the old skins: one hull drawing in a
/// pair of tint colours, so a single battleship silhouette said
/// everything there was to say. A family is not that. It is five bespoke
/// hull classes, a gun that arrives with its own shell, and a battlefield
/// that replaces the grid rather than recolouring it — and none of that
/// survives being reduced to one ship on a blue square. So:
///
///  * a hull card shows the carrier large and the other four classes as a
///    strip beneath it, which is the design's own acceptance test made
///    visible: the card proves all five change;
///  * a cannon card carries its shell on the disc beside it, so the
///    pairing is visible before purchase rather than at the first shot;
///  * a battlefield card previews the real board, its own markers
///    included;
///  * and the matched set is finally buyable, at the top of GAMEPLAY.
///
/// The nine original skins are still here and still equippable — they
/// just no longer lead, because they are the smaller thing. They sit
/// behind a LEGACY divider that opens on a tap, and opens by itself if
/// what you have equipped is in it.
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
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.cream,
                      ),
                      onPressed: () {
                        SoundService.instance.click();
                        Navigator.pop(context);
                      },
                    ),
                    Expanded(
                      child: Text('SHIPYARD', style: AppText.title(size: 20)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.outline,
                          width: 2.5,
                        ),
                      ),
                      child: Text(
                        '${profile.rp} RP',
                        style: AppText.label(
                          size: 11,
                          color: AppColors.outline,
                        ),
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
                  unselectedLabelColor: AppColors.cream.withValues(alpha: 0.55),
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

// ---------------------------------------------------------------- shared

/// "Not enough RP" feedback, in one place so all three tabs say the same
/// thing the same way.
void _denied(BuildContext context, int cost) {
  SoundService.instance.denied();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Not enough RP! Need $cost RP.',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      backgroundColor: AppColors.hit,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// The EQUIPPED / TAP TO EQUIP / «cost» RP pill every card carries.
///
/// Colour follows the design's own table: green once equipped, blue for
/// something owned but not worn, gold for something affordable, and flat
/// ink for something out of reach — so "can I have this?" is answerable
/// from the colour alone, before reading a number.
Widget _statusPill({
  required bool owned,
  required bool equipped,
  required bool affordable,
  required int cost,
  double size = 9,
}) {
  final bg = equipped
      ? AppColors.green
      : owned
      ? AppColors.blue
      : (affordable ? AppColors.gold : AppColors.inkSoft);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(9),
      color: bg,
      border: Border.all(color: AppColors.outline, width: 2),
    ),
    child: Text(
      equipped
          ? 'EQUIPPED'
          : owned
          ? 'TAP TO EQUIP'
          : '$cost RP',
      style: AppText.label(
        size: size,
        color: (!owned && affordable) ? AppColors.outline : AppColors.cream,
      ),
    ),
  );
}

BoxDecoration _cardBox({required bool equipped, Color? fill}) => BoxDecoration(
  borderRadius: BorderRadius.circular(18),
  color: fill ?? AppColors.cream,
  border: Border.all(
    color: equipped ? AppColors.green : AppColors.outline,
    width: equipped ? 4 : 3,
  ),
  boxShadow: const [BoxShadow(color: Color(0x44000000), offset: Offset(0, 4))],
);

/// Divider + tap-to-open shelf for the original skins.
///
/// The design collapses them to a single row — "Nine original guns, kept
/// as one shelf. Owned ones stay owned." Kept literally, with one
/// addition: it opens by itself when the thing you currently have
/// equipped lives inside it, because a store that hides what you are
/// wearing is worse than a store with a long list.
class _LegacyShelf extends StatefulWidget {
  final String summary;
  final String note;
  final int ownedCount;
  final int total;

  /// True when the equipped item is one of these, which forces the shelf
  /// open on first build.
  final bool containsEquipped;

  final List<Widget> children;

  /// Laid out as a two-column grid (hulls) rather than a list (cannons,
  /// battlefields).
  final bool grid;

  const _LegacyShelf({
    required this.summary,
    required this.note,
    required this.ownedCount,
    required this.total,
    required this.containsEquipped,
    required this.children,
    this.grid = false,
  });

  @override
  State<_LegacyShelf> createState() => _LegacyShelfState();
}

class _LegacyShelfState extends State<_LegacyShelf> {
  late bool _open = widget.containsEquipped;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Divider(color: Color(0x661E2A36), thickness: 2),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'LEGACY — STILL EQUIPPABLE',
                style: AppText.label(size: 9.5, color: AppColors.navyDeep),
              ),
            ),
            const Expanded(
              child: Divider(color: Color(0x661E2A36), thickness: 2),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            SoundService.instance.click();
            setState(() => _open = !_open);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.cream.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.55),
                width: 3,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.summary,
                        style: AppText.heading(size: 13, color: AppColors.navy),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.note,
                        style: AppText.body(size: 11, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.blue,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.outline, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.ownedCount}/${widget.total} OWNED',
                        style: AppText.label(size: 9),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _open ? Icons.expand_less : Icons.expand_more,
                        size: 15,
                        color: AppColors.cream,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 12),
          if (widget.grid)
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.82,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: widget.children,
            )
          else
            ...widget.children,
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ SHIP HULLS

class _ShipsTab extends StatelessWidget {
  final ProfileStore profile;
  const _ShipsTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    final families = Catalog.shipSkins
        .where((s) => s.familyKey != null)
        .toList();
    final legacy = Catalog.shipSkins.where((s) => s.familyKey == null).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          // Taller than the legacy cards: these carry a large carrier AND
          // the four-class strip that proves the rest of the fleet
          // changes with it.
          childAspectRatio: 0.70,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final skin in families)
              _FamilyHullCard(profile: profile, skin: skin),
          ],
        ),
        _LegacyShelf(
          summary: 'Steel · Crimson · Midnight · six more',
          note:
              'The nine original hulls, kept as one shelf. '
              'Owned ones stay owned.',
          ownedCount: legacy.where((s) => profile.ownsShip(s.id)).length,
          total: legacy.length,
          containsEquipped: legacy.any((s) => s.id == profile.shipSkinId),
          grid: true,
          children: [
            for (final skin in legacy)
              _LegacyHullCard(profile: profile, skin: skin),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// A family hull: the carrier at size, then the other four classes.
class _FamilyHullCard extends StatelessWidget {
  final ProfileStore profile;
  final ShipSkin skin;

  const _FamilyHullCard({required this.profile, required this.skin});

  @override
  Widget build(BuildContext context) {
    final family = FleetFamilies.byKey(skin.familyKey)!;
    final owned = profile.ownsShip(skin.id);
    final equipped = profile.shipSkinId == skin.id;
    final affordable = profile.rp >= skin.cost;

    return GestureDetector(
      onTap: () {
        if (profile.equipShipSkin(skin)) {
          SoundService.instance.victory();
        } else {
          _denied(context, skin.cost);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: _cardBox(equipped: equipped),
        child: Column(
          children: [
            // The plate takes the family's own water and accent, so even
            // before you read the name the card is already the right
            // colour of sea to be looking at that fleet on.
            Container(
              margin: const EdgeInsets.fromLTRB(9, 9, 9, 5),
              height: 74,
              decoration: BoxDecoration(
                color: family.board.deck,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: family.accent, width: 2),
              ),
              child: Center(
                child: AnimatedShip(
                  spec: kFleet[0], // carrier — the largest silhouette
                  skin: skin,
                  width: 132,
                  height: 42,
                ),
              ),
            ),
            // The design's acceptance test, on the card: five classes,
            // five different shapes. A family that only changed the
            // carrier would be caught here by eye.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final spec in kFleet.skip(1))
                    AnimatedShip(
                      spec: spec,
                      skin: skin,
                      width: 7.0 * spec.size + 6,
                      height: 19,
                    ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                skin.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(size: 10, color: AppColors.navy),
              ),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _statusPill(
                owned: owned,
                equipped: equipped,
                affordable: affordable,
                cost: skin.cost,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the nine original hulls — one drawing, two tint colours, and
/// the card says exactly that by showing exactly that.
class _LegacyHullCard extends StatelessWidget {
  final ProfileStore profile;
  final ShipSkin skin;

  const _LegacyHullCard({required this.profile, required this.skin});

  @override
  Widget build(BuildContext context) {
    final owned = profile.ownsShip(skin.id);
    final equipped = profile.shipSkinId == skin.id;
    final affordable = profile.rp >= skin.cost;

    return GestureDetector(
      onTap: () {
        if (profile.equipShipSkin(skin)) {
          SoundService.instance.victory();
        } else {
          _denied(context, skin.cost);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: _cardBox(equipped: equipped),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.water,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cellBorder, width: 2),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label(size: 10, color: AppColors.navy),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _statusPill(
                owned: owned,
                equipped: equipped,
                affordable: affordable,
                cost: skin.cost,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- CANNONS

class _CannonsTab extends StatelessWidget {
  final ProfileStore profile;
  const _CannonsTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    final families = Catalog.cannonSkins
        .where((c) => c.familyKey != null)
        .toList();
    final legacy = Catalog.cannonSkins
        .where((c) => c.familyKey == null)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final cannon in families)
          _CannonCard(profile: profile, cannon: cannon),
        _LegacyShelf(
          summary: 'MK-I Standard · Tesla · Void · six more',
          note:
              'The nine original guns, kept as one shelf. '
              'Owned ones stay owned.',
          ownedCount: legacy.where((c) => profile.ownsCannon(c.id)).length,
          total: legacy.length,
          containsEquipped: legacy.any((c) => c.id == profile.cannonSkinId),
          children: [
            for (final cannon in legacy)
              _CannonCard(profile: profile, cannon: cannon),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _CannonCard extends StatelessWidget {
  final ProfileStore profile;
  final CannonSkin cannon;

  const _CannonCard({required this.profile, required this.cannon});

  @override
  Widget build(BuildContext context) {
    final family = FleetFamilies.byKey(cannon.familyKey);
    final owned = profile.ownsCannon(cannon.id);
    final equipped = profile.cannonSkinId == cannon.id;
    final affordable = profile.rp >= cannon.cost;

    return GestureDetector(
      onTap: () {
        if (profile.equipCannonSkin(cannon)) {
          SoundService.instance.victory();
        } else {
          _denied(context, cannon.cost);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: _cardBox(equipped: equipped),
        child: Row(
          children: [
            // The design's rule for this card: "the shell sits on the
            // disc beside its gun, so the pairing is visible before
            // purchase". A family cannon brings its own projectile, and
            // that is half of what you are buying — showing the gun
            // alone would hide it until the first shot. The disc takes
            // the family's own water and accent for the same reason.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: family?.board.deck ?? AppColors.water,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: family?.accent ?? AppColors.cellBorder,
                      width: 2,
                    ),
                  ),
                  child: CannonWidget(
                    skin: cannon,
                    cooldownFraction: 1,
                    enabled: false,
                    label: '',
                    size: 70,
                  ),
                ),
                if (family != null)
                  Positioned(
                    right: -8,
                    bottom: -4,
                    child: SizedBox(
                      width: 30,
                      height: 33,
                      child: CustomPaint(painter: _ShellPreviewPainter(family)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cannon.name,
                    style: AppText.heading(size: 13, color: AppColors.navy),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    cannon.description,
                    style: AppText.body(size: 11, color: AppColors.inkSoft),
                  ),
                  if (family != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      'FIRES THE ${family.shellName.toUpperCase()}',
                      style: AppText.label(size: 9, color: AppColors.inkSoft),
                    ),
                  ],
                  const SizedBox(height: 6),
                  _statusPill(
                    owned: owned,
                    equipped: equipped,
                    affordable: affordable,
                    cost: cannon.cost,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- GAMEPLAY

class _ThemesTab extends StatelessWidget {
  final ProfileStore profile;
  const _ThemesTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    final families = Catalog.gameplayThemes
        .where((t) => t.familyKey != null)
        .toList();
    final legacy = Catalog.gameplayThemes
        .where((t) => t.familyKey == null)
        .toList();
    // A set has nothing left to sell once all three of its pieces are
    // owned, so it drops off the list rather than sitting there quoting a
    // price for things you already have.
    final sets = FleetFamilies.all
        .where((f) => !profile.ownsFamilySet(f))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (sets.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'MATCHED SETS',
              style: AppText.label(size: 10, color: AppColors.navyDeep),
            ),
          ),
          for (final family in sets)
            _MatchedSetCard(profile: profile, family: family),
          const SizedBox(height: 6),
        ],
        for (final theme in families)
          _ThemeCard(profile: profile, theme: theme),
        _LegacyShelf(
          summary: 'Classic Deck · Arctic Front · Deep Sea · Sunset Siege',
          note:
              'The four original palettes, kept as one shelf. '
              'Owned ones stay owned.',
          ownedCount: legacy.where((t) => profile.ownsTheme(t.id)).length,
          total: legacy.length,
          containsEquipped: legacy.any((t) => t.id == profile.gameplayThemeId),
          children: [
            for (final theme in legacy)
              _ThemeCard(profile: profile, theme: theme),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// The design's one-tap matched set: board, cannon, shell and all five
/// hulls together, for less than the pieces bought singly.
///
/// It leads the GAMEPLAY tab rather than getting a tab of its own because
/// this is the one place you can see a whole family at once — the board
/// behind the gun that shoots over it. The quoted price discounts what
/// you are still missing, not what you already bought, so someone who
/// picked up the hull last week isn't asked to pay for it twice.
///
/// **Only the button buys.** This is the one card in the shop that
/// charges for three things at once, and it sits in a list of cards you
/// buy by tapping anywhere on them — with a big board preview on its left
/// that looks exactly like the battlefield cards below it. Tapping the
/// whole card was a trap: reach for what looks like one battlefield, pay
/// for a hull and a cannon too. The pieces it covers are spelled out
/// beneath the price for the same reason.
class _MatchedSetCard extends StatelessWidget {
  final ProfileStore profile;
  final FleetFamily family;

  const _MatchedSetCard({required this.profile, required this.family});

  @override
  Widget build(BuildContext context) {
    final price = profile.setPriceFor(family);
    final saving = profile.setSavingFor(family);
    final affordable = profile.rp >= price;
    final key = 'f_${family.key}';
    final ink = family.board.deck.computeLuminance() > 0.5
        ? AppColors.outline
        : AppColors.cream;

    // What this set would actually add. A piece already owned is not
    // charged for again, so it is listed as already yours rather than
    // silently dropped — otherwise the price looks arbitrary.
    final parts = <String>[
      if (!profile.ownsShip(key)) 'hull',
      if (!profile.ownsCannon(key)) 'cannon',
      if (!profile.ownsTheme(key)) 'battlefield',
    ];
    final owns = <String>[
      if (profile.ownsShip(key)) 'hull',
      if (profile.ownsCannon(key)) 'cannon',
      if (profile.ownsTheme(key)) 'battlefield',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: family.board.deck,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold, width: 4),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'MATCHED SET',
                  style: AppText.label(size: 9, color: AppColors.outline),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  family.fleetName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.heading(size: 14, color: ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 86,
                  height: 86,
                  child: CustomPaint(
                    painter: _BoardPreviewPainter.family(family),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 44,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: CustomPaint(
                              painter: _CannonPreviewPainter(family),
                            ),
                          ),
                          SizedBox(
                            width: 24,
                            height: 27,
                            child: CustomPaint(
                              painter: _ShellPreviewPainter(family),
                            ),
                          ),
                          AnimatedShip(
                            spec: kFleet[1],
                            skin: Catalog.shipById(key),
                            width: 62,
                            height: 26,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Adds the ${parts.join(', ')} — all five hulls, '
                      'the gun with its shell and the board. '
                      'Saves $saving RP.',
                      style: AppText.body(
                        size: 10.5,
                        color: ink.withValues(alpha: 0.85),
                      ),
                    ),
                    if (owns.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'You already own the ${owns.join(' and ')} — '
                        'not charged again.',
                        style: AppText.label(
                          size: 9,
                          color: ink.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The button, and only the button. See the class note: this
          // is the one card that charges for three things at once, in a
          // list where every other card buys on a tap anywhere.
          GestureDetector(
            onTap: () {
              if (profile.buyFamilySet(family)) {
                SoundService.instance.victory();
              } else {
                _denied(context, price);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: affordable ? AppColors.gold : AppColors.inkSoft,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.outline, width: 2),
              ),
              child: Text(
                'EQUIP SET · $price RP',
                style: AppText.label(
                  size: 10,
                  color: affordable ? AppColors.outline : AppColors.cream,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final ProfileStore profile;
  final GameplayTheme theme;

  const _ThemeCard({required this.profile, required this.theme});

  @override
  Widget build(BuildContext context) {
    final owned = profile.ownsTheme(theme.id);
    final equipped = profile.gameplayThemeId == theme.id;
    final affordable = profile.rp >= theme.cost;
    // The card wears the theme's own deck colour, which now spans
    // near-black (Cinder Straits) to near-white (Rime Field), so the text
    // on it has to be chosen rather than assumed. Same luminance rule
    // `fleet_identity.dart` uses for fleet colours.
    final deckInk = theme.deck.computeLuminance() > 0.5
        ? AppColors.outline
        : AppColors.cream;

    return GestureDetector(
      onTap: () {
        if (profile.equipGameplayTheme(theme)) {
          SoundService.instance.victory();
        } else {
          _denied(context, theme.cost);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: _cardBox(equipped: equipped, fill: theme.deck),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: theme.grid,
                  border: Border.all(color: theme.gridLine, width: 2),
                ),
                child: CustomPaint(painter: _BoardPreviewPainter(theme)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theme.name,
                    style: AppText.heading(size: 15, color: deckInk),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    theme.description,
                    style: AppText.body(
                      size: 11,
                      color: deckInk.withValues(alpha: 0.82),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _statusPill(
                    owned: owned,
                    equipped: equipped,
                    affordable: affordable,
                    cost: theme.cost,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- PAINTERS

/// A battlefield preview.
///
/// "The store sells the design, not the swatch": a themed battlefield
/// previews as the REAL board — its own water, its own gridlines, its own
/// markers — rather than as four lines over a flat colour. What you are
/// buying is exactly what you see here. The four original palettes have
/// no board art of their own and fall back to the swatch treatment, which
/// is an honest description of what they are.
class _BoardPreviewPainter extends CustomPainter {
  final GameplayTheme? theme;
  final FleetFamily? forced;

  _BoardPreviewPainter(this.theme) : forced = null;

  /// For the matched-set card, which has a family in hand rather than a
  /// catalogue entry.
  _BoardPreviewPainter.family(FleetFamily family)
    : theme = null,
      forced = family;

  @override
  void paint(Canvas canvas, Size size) {
    final family = forced ?? FleetFamilies.byKey(theme?.familyKey);
    if (family != null) {
      paintFamilyBoard(canvas, size, family);
      final cell = size.width / 10;
      paintFamilyMiss(canvas, Offset(cell * 2.5, cell * 3.5), cell, family);
      paintFamilyMiss(canvas, Offset(cell * 7.5, cell * 6.5), cell, family);
      paintFamilyHit(canvas, Offset(cell * 5.5, cell * 4.5), cell, family);
      return;
    }
    final t = theme!;
    final line = Paint()
      ..color = t.gridLine.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    final cw = size.width / 5, ch = size.height / 4;
    for (var c = 1; c < 5; c++) {
      canvas.drawLine(Offset(c * cw, 0), Offset(c * cw, size.height), line);
    }
    for (var r = 1; r < 4; r++) {
      canvas.drawLine(Offset(0, r * ch), Offset(size.width, r * ch), line);
    }
    canvas.drawCircle(
      Offset(size.width * 0.64, size.height * 0.48),
      size.shortestSide * 0.13,
      Paint()..color = t.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPreviewPainter old) =>
      old.theme?.id != theme?.id || old.forced?.id != forced?.id;
}

/// The projectile a family cannon fires, shown on its store card.
class _ShellPreviewPainter extends CustomPainter {
  final FleetFamily family;
  const _ShellPreviewPainter(this.family);

  @override
  void paint(Canvas canvas, Size size) =>
      paintFamilyShell(canvas, size, family);

  @override
  bool shouldRepaint(covariant _ShellPreviewPainter old) =>
      old.family.id != family.id;
}

/// A family's gun, static, for the matched-set card — the same painter
/// the battle screen uses, so the set card can't show a gun that differs
/// from the one you'd actually fire.
class _CannonPreviewPainter extends CustomPainter {
  final FleetFamily family;
  const _CannonPreviewPainter(this.family);

  @override
  void paint(Canvas canvas, Size size) =>
      CannonPainter(accent: family.accent, family: family).paint(canvas, size);

  @override
  bool shouldRepaint(covariant _CannonPreviewPainter old) =>
      old.family.id != family.id;
}
