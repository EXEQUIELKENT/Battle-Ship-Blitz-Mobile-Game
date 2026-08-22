import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../art/family_board_art.dart';
import '../art/family_shell_art.dart';
import '../art/fleet_family.dart';
import '../art/legacy_shell_art.dart';
import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_notification.dart';
import '../widgets/cannon_widget.dart';
import '../widgets/ocean_background.dart';
import '../widgets/ship_painter.dart';

/// Shipyard — unlock & equip ship hulls, cannons, decks and matched
/// gameplay sets with RP.
///
/// **The store sells the design, not the swatch.** That line from the
/// "Skin system architecture" design is the whole brief for this screen,
/// and the shell around it is deliberately unchanged — navy header, gold
/// RP pill, four tabs, cream cards. What changed is what a card is
/// allowed to show.
///
/// The old cards were honest about the old skins: one hull drawing in a
/// pair of tint colours, so a single battleship silhouette said
/// everything there was to say. A family is not that. It is five bespoke
/// hull classes, a gun that arrives with its own shell, and a battlefield
/// deck that replaces the grid rather than recolouring it — and none of
/// that survives being reduced to one ship on a blue square. So:
///
///  * a hull card shows the carrier large and the other four classes as a
///    strip beneath it, which is the design's own acceptance test made
///    visible: the card proves all five change;
///  * a cannon card carries its shell on the disc beside it, so the
///    pairing is visible before purchase rather than at the first shot;
///  * a DECK card previews the real board, its own markers included;
///  * and the matched set — hull, cannon and deck together — now has a
///    tab of its own: GAMEPLAY, buyable in one tap.
///
/// The matched set used to lead the old GAMEPLAY tab alongside the deck
/// cards, which made "buy the whole family" and "buy just the board"
/// read as the same kind of thing. Splitting them into DECK (the board
/// alone) and GAMEPLAY (the bundle) keeps the one-tap set from getting
/// lost among the boards it also happens to sell.
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
    _tab = TabController(length: 4, vsync: this);
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
                  // Scrollable so long labels are never clipped — but
                  // with [TabAlignment.center] the row sits centred while
                  // it fits and only becomes swipeable once it actually
                  // overflows. (Fixed-width mode split the bar into even
                  // quarters, which cut these labels off mid-word.)
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  tabs: const [
                    Tab(text: 'SHIP HULLS'),
                    Tab(text: 'CANNONS'),
                    Tab(text: 'DECK'),
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
                    _DeckTab(profile: profile),
                    _GameplayTab(profile: profile),
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
  AppNotification.show(
    context,
    'Not enough RP! Need $cost RP.',
    type: AppNoticeType.error,
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
        // Same skeleton as [_LegacyHullCard]: the preview area soaks up
        // whatever height the grid hands this card, and the name + pill
        // stay pinned just above a modest fixed bottom padding. (A
        // trailing `Spacer` used to collect ALL the slack under the
        // status pill instead, which read as a big dead margin at the
        // bottom of every family card.)
        child: Column(
          children: [
            // The plate takes the family's own water and accent, so even
            // before you read the name the card is already the right
            // colour of sea to be looking at that fleet on.
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(9, 9, 9, 5),
                constraints: const BoxConstraints(minHeight: 74),
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
            ),
            // The design's acceptance test, on the card: five classes,
            // five different shapes. A family that only changed the
            // carrier would be caught here by eye.
            //
            // Two rows of two rather than one row of four: four hulls
            // squeezed across this card's width left almost no breathing
            // room between them. Splitting battleship+cruiser from
            // submarine+destroyer gives every silhouette its own space
            // while keeping the same "five classes, five shapes" proof.
            //
            // `spaceEvenly` used to stretch the gap between each pair to
            // fill the whole row, which read as two tiny hulls stranded
            // at the edges. Centering the pair with a fixed gap keeps
            // them grouped together, and the bigger size multiplier
            // gives each hull enough width to actually read as its
            // silhouette instead of a sliver.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final spec in kFleet.skip(1).take(2)) ...[
                        if (spec != kFleet[1]) const SizedBox(width: 14),
                        AnimatedShip(
                          spec: spec,
                          skin: skin,
                          width: 9.5 * spec.size + 10,
                          height: 22,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final spec in kFleet.skip(3)) ...[
                        if (spec != kFleet[3]) const SizedBox(width: 14),
                        AnimatedShip(
                          spec: spec,
                          skin: skin,
                          width: 9.5 * spec.size + 10,
                          height: 22,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // A small fixed gap instead of a flex `Spacer` here — that
            // Spacer used to swallow all of the card's leftover height,
            // shoving the name well below the hull previews. Any height
            // left over once the name/pill are laid out is now absorbed
            // by the `Spacer` AFTER the pill instead, so the name sits
            // right under the previews and the slack shows up as a bit of
            // breathing room at the bottom of the card rather than a gap
            // in the middle.
            const SizedBox(height: 8),
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

/// A cannon exactly as it behaves on the battle screen — idle bob, ground
/// shadow, reload sweep and muzzle flash/smoke — looping on its own so the
/// store shows the gun the way it will actually be fired, not a flat
/// render of it. `CannonWidget` already draws all of this; the only reason
/// the shop cards didn't have it is that they drove it with a cannon
/// permanently `enabled: false` at a fixed `cooldownFraction: 1`, which is
/// the one state combination where none of that ever plays. This drives
/// the same widget through a real reload cycle instead: charge from
/// empty, sit at "ready" long enough for the idle pulse to read, fire,
/// smoke, repeat.
class _LiveCannonPreview extends StatefulWidget {
  final CannonSkin skin;
  final double size;

  const _LiveCannonPreview({required this.skin, required this.size});

  @override
  State<_LiveCannonPreview> createState() => _LiveCannonPreviewState();
}

class _LiveCannonPreviewState extends State<_LiveCannonPreview>
    with SingleTickerProviderStateMixin {
  // Charge for 1.6s, then hold "ready" (idle pulse visible) for 0.9s
  // before firing and starting over — long enough to actually see the
  // reload sweep travel, not just flicker past.
  static const _charge = Duration(milliseconds: 1600);
  static const _hold = Duration(milliseconds: 900);

  late final AnimationController _cycle;
  final _fire = StreamController<void>.broadcast();
  final _ready = StreamController<void>.broadcast();
  Timer? _fireTimer;

  @override
  void initState() {
    super.initState();
    // Stagger each card's cycle a little off the others (keyed off the
    // skin id) so a whole list of cards doesn't visibly fire in lockstep.
    final jitter = (widget.skin.id.hashCode % 400);
    _cycle = AnimationController(vsync: this, duration: _charge)
      ..addStatusListener(_onStatus);
    Future.delayed(Duration(milliseconds: jitter), () {
      if (mounted) _cycle.forward();
    });
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _ready.add(null);
    _fireTimer = Timer(_hold, () {
      if (!mounted) return;
      _fire.add(null);
      _cycle.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _fireTimer?.cancel();
    _cycle.dispose();
    _fire.close();
    _ready.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _cycle,
      builder: (context, _) => CannonWidget(
        skin: widget.skin,
        cooldownFraction: _cycle.value,
        enabled: true,
        label: '',
        size: widget.size,
        fireTrigger: _fire.stream,
        readyTrigger: _ready.stream,
      ),
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
            SizedBox(
              // Fixed disc footprint — matches the design's 86×86 badge so
              // every card in the tab lines up, family gun or legacy gun.
              width: 86,
              height: 86,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      color: family?.board.deck ?? AppColors.water,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: family?.accent ?? AppColors.cellBorder,
                        width: 2,
                      ),
                    ),
                  ),
                  if (family != null)
                    // A family gun is drawn end to end — mount, barrel and
                    // muzzle — at its own authored proportions, which read
                    // bigger than the 86px badge behind it. The design
                    // deliberately lets it overflow the disc (see
                    // `ThemedCannon` at size 66 sitting in an 86 badge,
                    // offset left -8.85/top -26.8) rather than squeezing
                    // the whole gun down to fit inside — a barrel shrunk
                    // to stay inside its own badge stopped reading as the
                    // actual weapon on the battle screen.
                    Positioned(
                      left: -8.85,
                      top: -26.8,
                      child: _LiveCannonPreview(skin: cannon, size: 104),
                    )
                  else
                    // The nine original guns were authored to fit their
                    // badge exactly, so they stay centred and contained.
                    Center(
                      child: _LiveCannonPreview(skin: cannon, size: 70),
                    ),
                  if (family != null)
                    Positioned(
                      right: -10,
                      bottom: -6,
                      child: SizedBox(
                        width: 34,
                        height: 37,
                        child:
                            CustomPaint(painter: _ShellPreviewPainter(family)),
                      ),
                    )
                  else
                    // The nine originals never had a shell to show here —
                    // they were nine barrel recolours firing one shared
                    // iron ball, so a card advertising "Blazing fire
                    // shells" or "Dark-matter launcher" showed neither.
                    // Same badge, same corner, as the family guns above:
                    // the pairing is the point, not just a family perk.
                    Positioned(
                      right: -10,
                      bottom: -6,
                      child: SizedBox(
                        width: 34,
                        height: 37,
                        child: CustomPaint(
                            painter: _LegacyShellPreviewPainter(cannon.id)),
                      ),
                    ),
                ],
              ),
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

// ------------------------------------------------------------------ DECK

/// The battlefield boards on their own shelf — no matched-set pitch
/// mixed in. Buying just a deck used to sit in the same list as buying
/// a whole family, which made the one-tap bundle read like one more
/// board among the boards. See GAMEPLAY, below, for the bundle.
class _DeckTab extends StatelessWidget {
  final ProfileStore profile;
  const _DeckTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    final families = Catalog.gameplayThemes
        .where((t) => t.familyKey != null)
        .toList();
    final legacy = Catalog.gameplayThemes
        .where((t) => t.familyKey == null)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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

// -------------------------------------------------------------- GAMEPLAY

/// The one-tap matched sets, on a tab of their own.
///
/// This used to lead the DECK tab, ahead of the boards it also happens
/// to sell — which made "buy the whole family" and "buy just the board"
/// read as the same kind of purchase. Giving it its own tab is the fix:
/// GAMEPLAY is where you buy a family whole, DECK is where you buy a
/// board.
class _GameplayTab extends StatelessWidget {
  final ProfileStore profile;
  const _GameplayTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    // A set has nothing left to sell once all three of its pieces are
    // owned, so it drops off the list rather than sitting there quoting a
    // price for things you already have.
    final sets = FleetFamilies.all
        .where((f) => !profile.ownsFamilySet(f))
        .toList();

    if (sets.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.workspace_premium, color: AppColors.gold, size: 48),
          const SizedBox(height: 12),
          Text(
            'Every matched set is already yours — hull, cannon and deck, '
            'for every family.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 13, color: AppColors.cream),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'MATCHED SETS',
            style: AppText.label(size: 10, color: AppColors.navyDeep),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Hull, cannon and deck together, in one tap, for less than '
            'buying the three pieces apart.',
            style: AppText.body(size: 11, color: AppColors.navyDeep),
          ),
        ),
        for (final family in sets)
          _MatchedSetCard(profile: profile, family: family),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// The design's one-tap matched set: board, cannon, shell and all five
/// hulls together, for less than the pieces bought singly.
///
/// It has its own GAMEPLAY tab, separate from DECK, because this is the
/// one place you can see a whole family at once — the board behind the
/// gun that shoots over it — and that is a different purchase than
/// picking a single board. The quoted price discounts what you are
/// still missing, not what you already bought, so someone who picked up
/// the hull last week isn't asked to pay for it twice.
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
                  // Matches the design's 104×104 board preview — was 86,
                  // which made the set's own battlefield read smaller than
                  // the single-board cards further down the same tab.
                  width: 104,
                  height: 104,
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
                      height: 56,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Same "gun bigger than its slot" treatment as
                          // the CANNONS tab: the design draws this at
                          // size 56 (≈88×86) inside a 62×56 slot, offset
                          // left -14/top -22, rather than squashing the
                          // whole gun down to fit flush.
                          SizedBox(
                            width: 62,
                            height: 56,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: -14,
                                  top: -22,
                                  child: SizedBox(
                                    width: 88,
                                    height: 86,
                                    child: CustomPaint(
                                      painter: _CannonPreviewPainter(family),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 30,
                            height: 33,
                            child: CustomPaint(
                              painter: _ShellPreviewPainter(family),
                            ),
                          ),
                          AnimatedShip(
                            spec: kFleet[1],
                            skin: Catalog.shipById(key),
                            width: 72,
                            height: 30,
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

/// The projectile one of the nine original cannons fires, shown on its
/// store card — the LEGACY-shelf counterpart to [_ShellPreviewPainter].
/// Keyed off the cannon's own id rather than a [FleetFamily] since the
/// originals never had one; see `legacy_shell_art.dart`.
class _LegacyShellPreviewPainter extends CustomPainter {
  final String cannonId;
  const _LegacyShellPreviewPainter(this.cannonId);

  @override
  void paint(Canvas canvas, Size size) =>
      paintLegacyShell(canvas, size, cannonId);

  @override
  bool shouldRepaint(covariant _LegacyShellPreviewPainter old) =>
      old.cannonId != cannonId;
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