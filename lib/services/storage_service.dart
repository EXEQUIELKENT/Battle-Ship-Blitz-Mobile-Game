import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../art/fleet_family.dart';
import '../art/impact_fx.dart';
import '../art/legacy_identity.dart';
import '../models/game_models.dart';
import 'sound_service.dart';

/// A ship hull skin.
///
/// Two generations live side by side here. The original nine are a pair
/// of tint colours applied to one shared hull drawing. The six added from
/// the "Skin system architecture" design carry a [familyKey] instead, and
/// that key selects an entirely different set of five hull shapes — a
/// pirate galleon and a sci-fi catamaran are not the same ship recoloured.
/// [hull] and [trim] are still filled in for family skins so anything
/// that only wants a representative colour (a chip, a swatch, a badge)
/// keeps working without knowing which generation it is looking at.
class ShipSkin {
  final String id;
  final String name;
  final Color hull;
  final Color trim;
  final int cost; // Doubloons cost; 0 = free

  /// Non-null for the thematic families — see `lib/art/fleet_family.dart`.
  final String? familyKey;

  const ShipSkin(this.id, this.name, this.hull, this.trim, this.cost,
      {this.familyKey});
}

/// A cannon skin (barrel color + projectile style + cooldown modifier).
class CannonSkin {
  final String id;
  final String name;
  final Color barrel;
  final Color projectile;
  final String description;
  final double cooldownFactor; // < 1.0 means faster reload
  final int cost;

  /// Non-null for the thematic families. A family cannon brings its own
  /// silhouette, its own shell AND its own muzzle geometry — the barrel
  /// length is what the battle screen reads to place the shot, so a long
  /// naval autoloader genuinely fires from further out than a stubby
  /// magma mortar.
  final String? familyKey;

  const CannonSkin(this.id, this.name, this.barrel, this.projectile,
      this.description, this.cooldownFactor, this.cost, {this.familyKey});

  /// Reload factor actually used for a match. Ranked play (real humans
  /// over hotspot/online — see `GameController.isRankedBattle`) always
  /// fires at the standard rate so a bought cannon is never a fire-rate
  /// advantage where Elo is on the line; casual modes (vs-AI, local)
  /// keep the skin's own factor as a fun progression perk.
  double effectiveCooldownFactor({required bool ranked}) =>
      ranked ? 1.0 : cooldownFactor;
}

/// A gameplay theme changes the battlefield palette without changing rules.
class GameplayTheme {
  final String id;
  final String name;
  final String description;
  final Color deck;
  final Color deckAccent;
  final Color grid;
  final Color gridLine;
  final Color miss;
  final Color accent;
  final int cost;

  /// Non-null for the thematic families. A family battlefield replaces
  /// the flat cells and printed gridlines wholesale — ice floes, basalt
  /// slabs, riveted plate — and brings its own hit and miss markers with
  /// it. Coordinates, cell count and tap targets are untouched: a marker
  /// is still one cell, drawn differently.
  final String? familyKey;

  /// True for the nine legacy battlefields — one matching illustrated
  /// deck per legacy cannon skin (`id` is that same cannon's id), ported
  /// from `uploads/New Design/Deck/dk-*.svg`. Like a family battlefield
  /// this replaces the flat cells and printed gridlines wholesale (see
  /// `paintLegacyBoard`), but it is bought and equipped on its own —
  /// legacy skins are still sold a la carte, never bundled — and it keeps
  /// the existing legacy hit/miss marks (themed by the shooter's cannon,
  /// not the board) rather than bringing its own.
  final bool legacy;

  const GameplayTheme(this.id, this.name, this.description, this.deck, this.deckAccent, this.grid, this.gridLine, this.miss, this.accent, this.cost, {this.familyKey, this.legacy = false});
}

/// A legacy "gameplay set" — the hull/gun/board trio a legacy identity's
/// ship skin and matching cannon (also its gameplay theme id, per
/// `GameplayTheme.legacy`) form together, mirroring what a [FleetFamily]
/// is for the six thematic families. Unlike a family, this is NOT a
/// purchasable bundle — every piece is still bought a la carte — it only
/// exists as a "you already own all three, here's the shortcut" shortcut
/// in the gear dialog (see `_GearDialogState` in `placement_screen.dart`).
class LegacySet {
  /// The shared legacy cannon / gameplay-theme id, e.g. `'mk1'`.
  final String id;

  /// The matching legacy ship skin id, e.g. `'steel'` — a different id
  /// namespace from [id], unlike a family where all three share one id.
  final String shipSkinId;
  final String name;
  final Color accent;

  const LegacySet(this.id, this.shipSkinId, this.name, this.accent);
}

/// Full customization catalog.
class Catalog {
  Catalog._();

  static const List<ShipSkin> shipSkins = [
    ShipSkin('steel', 'Steel Fleet', Color(0xFF64748B), Color(0xFF94A3B8), 0),
    ShipSkin('crimson', 'Crimson Armada', Color(0xFF991B1B), Color(0xFFEF4444), 250),
    ShipSkin('emerald', 'Emerald Tide', Color(0xFF065F46), Color(0xFF34D399), 250),
    ShipSkin('gold', 'Golden Armada', Color(0xFF92400E), Color(0xFFFBBF24), 500),
    ShipSkin('abyss', 'Abyss Ghost', Color(0xFF1E1B4B), Color(0xFF818CF8), 500),
    ShipSkin('arctic', 'Arctic Storm', Color(0xFFE2E8F0), Color(0xFF7DD3FC), 750),
    ShipSkin('coral', 'Coral Raiders', Color(0xFF9F3B46), Color(0xFFFF9A8B), 850),
    ShipSkin('midnight', 'Midnight Ops', Color(0xFF0F172A), Color(0xFF38BDF8), 1100),
    ShipSkin('toxic', 'Toxic Wreckers', Color(0xFF365314), Color(0xFFA3E635), 1250),
    // ---- Thematic families: five bespoke hull classes each ----
    // Priced ABOVE every legacy hull (top out at Toxic Wreckers, 1250):
    // five distinct hull classes and a real board to match are worth
    // more than a shared silhouette in a second tint, and the price tag
    // should say so rather than undercut it.
    ShipSkin('f_pirate', 'Blackpowder Fleet', Color(0xFF8A5A2B),
        Color(0xFFC98A3E), 1500, familyKey: 'pirate'),
    ShipSkin('f_naval', 'Iron Pact', Color(0xFF5A6B78), Color(0xFF8CA0AD),
        1750, familyKey: 'naval'),
    ShipSkin('f_arctic', 'Rime Wardens', Color(0xFFC8DCE6), Color(0xFF8FC3D8),
        2000, familyKey: 'arctic'),
    ShipSkin('f_steam', 'Brass Consortium', Color(0xFF7A5A34),
        Color(0xFFC99A3F), 2400, familyKey: 'steam'),
    ShipSkin('f_volcanic', 'Cinder Hold', Color(0xFF3A3438), Color(0xFF514247),
        2900, familyKey: 'volcanic'),
    ShipSkin('f_scifi', 'Helios Drift', Color(0xFF1B2138), Color(0xFF6E8FD8),
        3600, familyKey: 'scifi'),
  ];

  static const List<CannonSkin> cannonSkins = [
    CannonSkin('mk1', 'MK-I Standard', Color(0xFF64748B), Color(0xFFFFB454),
        'Reliable naval artillery.', 1.0, 0),
    CannonSkin('inferno', 'Inferno Cannon', Color(0xFF7C2D12), Color(0xFFEF4444),
        'Blazing fire shells.', 1.0, 300),
    CannonSkin('tesla', 'Arctic Coilgun', Color(0xFF0E7490), Color(0xFF22D3EE),
        'Electric plasma bolts.', 1.0, 300),
    CannonSkin('venom', 'Venom Launcher', Color(0xFF365314), Color(0xFF84CC16),
        'Toxic green warheads.', 1.0, 300),
    CannonSkin('royal', 'Royal Broadside', Color(0xFF78350F), Color(0xFFFBBF24),
        'Gold-plated heavy guns.', 1.0, 600),
    CannonSkin('phantom', 'Abyss Railgun', Color(0xFF312E81), Color(0xFFC084FC),
        'Experimental railgun. 15% faster reload!', 0.85, 1000),
    CannonSkin('kraken', 'Emerald Cannon', Color(0xFF0F766E), Color(0xFF5EEAD4), 'Deep-sea siege cannon with a crushing pulse.', 0.95, 1200),
    // FEEDBACK ("rename the Sunfire Battery to a coral name and match its
    // projectile to the gun"): this gun's ART was re-imported as the design's
    // CORAL identity (`uploads/New Design/New Cannons/coral-fire-reload…`) —
    // a terracotta body with salmon highlights — but its CATALOGUE entry was
    // never brought along, so the name still said Sunfire and both colours
    // here were still the old amber/yellow. `projectile` is the gun's pop
    // colour everywhere it is read (the painter's ready accent, the gear
    // dialog's cannon chip), which is why a coral cannon was firing a
    // canary-yellow shell. Both now come straight off the cannon's own
    // markup: body `#C1543F`, highlight `#FF9E7A`. The id stays `sunfire` —
    // it is a save-file key, and every owned copy would be forgotten by
    // renaming it (see `legacyIdentities`, which pairs it with `coral`).
    CannonSkin('sunfire', 'Coral Battery', Color(0xFFC1543F), Color(0xFFFF9E7A), 'High-energy coral shell launcher.', 0.90, 1400),
    CannonSkin('void', 'Void Annihilator', Color(0xFF111827), Color(0xFFEC4899), 'Dark-matter launcher. 10% faster reload!', 0.90, 1800),
    // ---- Thematic families: each gun ships with its own shell ----
    // Priced ABOVE every legacy cannon (top out at Void Annihilator,
    // 1800): a gun with its own silhouette, shell AND muzzle geometry is
    // worth more than a recoloured MK-I, and used to cost less than half
    // of one.
    CannonSkin('f_pirate', 'Bell-Mouth Broadside', Color(0xFF8A5A2B),
        Color(0xFF4A4038), 'Timber carriage, bronze bell muzzle. Round shot.',
        1.0, 2000, familyKey: 'pirate'),
    CannonSkin('f_naval', 'MK-IV Autoloader', Color(0xFF5A6B78),
        Color(0xFF6B7A87), 'Long barrel, muzzle brake. Finned sabot shell.',
        0.95, 2200, familyKey: 'naval'),
    CannonSkin('f_steam', 'Pressure Battery', Color(0xFF7A5A34),
        Color(0xFFC99A3F), 'Three boiler drums and a bypass pipe. Gear sphere.',
        1.0, 2450, familyKey: 'steam'),
    CannonSkin('f_arctic', 'Icebreaker Mortar', Color(0xFFC8DCE6),
        Color(0xFFBBDCEA), 'Two-stage barrel behind a collar of crystal.',
        0.95, 2700, familyKey: 'arctic'),
    CannonSkin('f_volcanic', 'Magma Bombard', Color(0xFF3A3438),
        Color(0xFF332B2E), 'Rock-slab mortar. Ember slug, crater impact.',
        0.90, 3100, familyKey: 'volcanic'),
    CannonSkin('f_scifi', 'Ion Lance', Color(0xFF2B3550), Color(0xFF232B45),
        'Floating segments, forked emitter. 15% faster reload!', 0.85, 3800,
        familyKey: 'scifi'),
  ];

  static const List<GameplayTheme> gameplayThemes = [
    // ---- Legacy battlefields: one illustrated deck per legacy cannon ----
    // Each of the nine originals now ships a matching battlefield —
    // gridlines, corner dressing and a scatter of thematic detail replacing
    // the flat palette swaps above. Still bought and equipped a la carte
    // like every other legacy piece (no bundling), so priced on the same
    // ladder as the flat palettes (900–1500) rather than the family tier
    // (1700+), scaled roughly with the matching cannon's own price.
    GameplayTheme('mk1', 'Iron Standard',
        'Plain steel-blue water, riveted corner braces.',
        Color(0xFF6FA3C4), Color(0xFFEAF2F8), Color(0xFF4A789A),
        Color(0xFF6FA3C4), Color(0xFFEAF2F8), Color(0xFFEAF2F8), 0, legacy: true),
    GameplayTheme('inferno', 'Ember Field',
        'Scorched black water, drifting embers and heat-haze wisps.',
        Color(0xFF7A2E14), Color(0xFFFF8A4A), Color(0xFF2B0F0A),
        Color(0xFF7A2E14), Color(0xFFFFD9BF), Color(0xFFFF6A2B), 500, legacy: true),
    GameplayTheme('tesla', 'Storm Circuit',
        'Dashed conduit lines and a live current band across the deck.',
        Color(0xFF16505E), Color(0xFF7FE7FF), Color(0xFF0B2432),
        Color(0xFF16505E), Color(0xFFE0FBFF), Color(0xFF7FB8D6), 500, legacy: true),
    GameplayTheme('venom', 'Toxic Marsh',
        'Sickly green water with sunken toxic-barrel wreckage.',
        Color(0xFF3A5220), Color(0xFFD4F98A), Color(0xFF1F2E0D),
        Color(0xFF3A5220), Color(0xFFD4F98A), Color(0xFFA3E635), 500, legacy: true),
    GameplayTheme('royal', 'Gilded Waters',
        'Navy and gold parade ground with a compass badge at every corner.',
        Color(0xFFC98A3E), Color(0xFFFFF3C4), Color(0xFF1A2E4A),
        Color(0xFFC98A3E), Color(0xFFFFF3C4), Color(0xFFFBBF24), 800, legacy: true),
    GameplayTheme('phantom', 'Shadow Veil',
        'Ghostly violet water with slow concentric ripple rings.',
        Color(0xFF333A66), Color(0xFFF1E3FF), Color(0xFF14162B),
        Color(0xFF333A66), Color(0xFFF1E3FF), Color(0xFF7C6BC4), 1100, legacy: true),
    GameplayTheme('kraken', 'Abyssal Depths',
        'Deep teal trench water with drifting tentacle trails.',
        Color(0xFF175A52), Color(0xFFB6FFF1), Color(0xFF0A2E2C),
        Color(0xFF175A52), Color(0xFFB6FFF1), Color(0xFF34D399), 1300, legacy: true),
    GameplayTheme('sunfire', 'Solar Flats',
        'Sun-scorched amber sands with radiant corner sigils.',
        Color(0xFF8A5A20), Color(0xFFFFF8D6), Color(0xFF3A2408),
        Color(0xFF8A5A20), Color(0xFFFFF8D6), Color(0xFFE0715A), 1500, legacy: true),
    GameplayTheme('void', 'Event Horizon',
        'Dark-matter water warped around a hollow gravity well.',
        Color(0xFF1C2A44), Color(0xFFFBCFE8), Color(0xFF070A14),
        Color(0xFF1C2A44), Color(0xFFFBCFE8), Color(0xFF4B72A8), 1600, legacy: true),
    // ---- Thematic families: a whole battlefield, not a palette ----
    // Priced ABOVE every legacy battlefield (top out at Event Horizon,
    // 1600): a family board replaces the tiles, gridlines AND hit/miss
    // markers wholesale, so it should never be the cheaper pick next to
    // a legacy board's a la carte price.
    GameplayTheme('f_pirate', 'Pirate Seas',
        'Brine cells, rope grid, drifting swell.', Color(0xFF1F3B3C),
        Color(0xFF2C5A5C), Color(0xFF2C5A5C), Color(0xFF8FAE8A),
        Color(0xFFBEE3D8), Color(0xFFC98A3E), 1700, familyKey: 'pirate'),
    GameplayTheme('f_naval', 'Fleet Command',
        'Steel cells, range rings, row ticks.', Color(0xFF2A3843),
        Color(0xFF3B4E5C), Color(0xFF305064), Color(0xFF7FB2CC),
        Color(0xFF9FB6C4), Color(0xFFCFE0EA), 1900, familyKey: 'naval'),
    GameplayTheme('f_arctic', 'Rime Field',
        'Floes over open water. Snowfall, aurora band.', Color(0xFFCFE6EE),
        Color(0xFFEAF7FC), Color(0xFF4E86A6), Color(0xFFDFF4FC),
        Color(0xFFEAFBFF), Color(0xFFBDF1FF), 2100, familyKey: 'arctic'),
    GameplayTheme('f_steam', 'Brass Works',
        'Riveted quarter-plates with bolted seams.', Color(0xFF4A3927),
        Color(0xFF6B5537), Color(0xFF57432E), Color(0xFFB89056),
        Color(0xFFC99A3F), Color(0xFFC99A3F), 2300, familyKey: 'steam'),
    GameplayTheme('f_volcanic', 'Cinder Straits',
        'Basalt slabs, molten seams, rising embers.', Color(0xFF241B1B),
        Color(0xFF3A2A26), Color(0xFF33262A), Color(0xFF7A6A62),
        Color(0xFF8A8079), Color(0xFFFF6A2B), 2700, familyKey: 'volcanic'),
    GameplayTheme('f_scifi', 'Helios Grid',
        'Lattice, corner ticks, travelling scan band.', Color(0xFF0E1428),
        Color(0xFF1B2138), Color(0xFF16223E), Color(0xFF3A5A9E),
        Color(0xFF6FE7FF), Color(0xFF6FE7FF), 3300, familyKey: 'scifi'),
  ];

  /// The nine legacy identities' own hull+gun+board pairing — see
  /// [LegacySet]'s own doc. Sourced from `legacy_identity.dart` (the same
  /// data the recolour pass in `legacy_cannon_art.dart`/
  /// `legacy_board_art.dart`/`legacy_crosshair_art.dart` reads), not
  /// duplicated here.
  static final List<LegacySet> legacySets = [
    for (final l in legacyIdentities) LegacySet(l.id, l.shipSkinId, l.name, l.accent),
  ];

  static ShipSkin shipById(String id) =>
      shipSkins.firstWhere((s) => s.id == id, orElse: () => shipSkins.first);

  static CannonSkin cannonById(String id) =>
      cannonSkins.firstWhere((c) => c.id == id, orElse: () => cannonSkins.first);

  static GameplayTheme gameplayThemeById(String id) =>
      gameplayThemes.firstWhere((t) => t.id == id, orElse: () => gameplayThemes.first);
}

/// One captain's chosen look: hull, gun and battlefield.
///
/// The [ProfileStore] holds exactly one of these (the device owner's),
/// which is all a network match ever needs — the opponent's arrives over
/// the wire. Local pass-and-play is the case that needs the concept
/// separated out from the profile: two people share one device and one
/// saved profile, but each still gets to sail their own purchased gear,
/// so the controller keeps one [Loadout] per seat (see
/// `GameController.localLoadouts`).
class Loadout {
  final String shipSkinId;
  final String cannonSkinId;
  final String themeId;

  /// See [ProfileStore.shipSkinChosen] — same meaning, per seat.
  final bool shipChosen;

  const Loadout({
    this.shipSkinId = 'steel',
    this.cannonSkinId = 'mk1',
    this.themeId = 'mk1',
    this.shipChosen = false,
  });

  /// The device owner's own equipped gear.
  factory Loadout.of(ProfileStore p) => Loadout(
        shipSkinId: p.shipSkinId,
        cannonSkinId: p.cannonSkinId,
        themeId: p.gameplayThemeId,
        shipChosen: p.shipSkinChosen,
      );

  /// A loadout drawn independently at random — one ship skin, one cannon
  /// skin, one gameplay theme — from everything [p] actually owns. Used
  /// to give an AI opponent a real, varied appearance instead of always
  /// sailing the plain starter gear: every catalogue always has at least
  /// its free starter entry owned, so none of the three pools is ever
  /// empty. [rng] is injectable for deterministic tests.
  factory Loadout.randomOwned(ProfileStore p, {Random? rng}) {
    final r = rng ?? Random();
    T pick<T>(List<T> owned) => owned[r.nextInt(owned.length)];
    final ship = pick(Catalog.shipSkins.where((s) => p.ownsShip(s.id)).toList());
    final cannon =
        pick(Catalog.cannonSkins.where((c) => p.ownsCannon(c.id)).toList());
    final theme =
        pick(Catalog.gameplayThemes.where((t) => p.ownsTheme(t.id)).toList());
    return Loadout(
      shipSkinId: ship.id,
      shipChosen: true,
      cannonSkinId: cannon.id,
      themeId: theme.id,
    );
  }

  ShipSkin get shipSkin => Catalog.shipById(shipSkinId);
  CannonSkin get cannonSkin => Catalog.cannonById(cannonSkinId);
  GameplayTheme get theme => Catalog.gameplayThemeById(themeId);

  Loadout copyWith({
    String? shipSkinId,
    String? cannonSkinId,
    String? themeId,
    bool? shipChosen,
  }) =>
      Loadout(
        shipSkinId: shipSkinId ?? this.shipSkinId,
        cannonSkinId: cannonSkinId ?? this.cannonSkinId,
        themeId: themeId ?? this.themeId,
        shipChosen: shipChosen ?? this.shipChosen,
      );
}

/// The rank a given RP total earns.
///
/// A free function rather than a method on [ProfileStore] because it is
/// also needed for OTHER players — a friend's rank on the friends list
/// comes from their synced RP, and there is no profile object for them.
String rankTitleForRp(int rp) {
  if (rp >= 2200) return 'FLEET ADMIRAL';
  if (rp >= 1800) return 'ADMIRAL';
  if (rp >= 1500) return 'COMMODORE';
  if (rp >= 1300) return 'CAPTAIN';
  if (rp >= 1150) return 'LIEUTENANT';
  return 'ENSIGN';
}

/// Persistent profile: RP, streaks, stats and customization.

/// How much visual flourish the battle screen spends per frame.
///
/// A real knob, not a label: each step switches off specific work that
/// costs real milliseconds on a mid-range phone — see
/// `GraphicsQualityX` for exactly what each one changes.
enum GraphicsQuality { low, balanced, high }

extension GraphicsQualityX on GraphicsQuality {
  String get label => switch (this) {
        GraphicsQuality.low => 'PERFORMANCE',
        GraphicsQuality.balanced => 'BALANCED',
        GraphicsQuality.high => 'MAXIMUM',
      };

  String get blurb => switch (this) {
        GraphicsQuality.low =>
          'Fewer impact particles, no screen shake. Smoothest frame rate '
              'on older phones.',
        GraphicsQuality.balanced =>
          'The full impact effects and screen shake. What the game is '
              'tuned for.',
        GraphicsQuality.high =>
          'Everything in BALANCED plus denser particles and longer '
              'shell trails.',
      };

  /// Multiplier on how many particles an impact effect draws. Read by
  /// `impact_fx.dart`, which is where the per-frame cost actually is.
  double get fxDensity => switch (this) {
        GraphicsQuality.low => 0.5,
        GraphicsQuality.balanced => 1.0,
        GraphicsQuality.high => 1.35,
      };

  /// Whether an impact is allowed to shake the screen.
  bool get screenShake => this != GraphicsQuality.low;

  /// How many motion-trail ghosts follow a shell.
  int get shellTrails => switch (this) {
        GraphicsQuality.low => 0,
        GraphicsQuality.balanced => 2,
        GraphicsQuality.high => 3,
      };
}
class ProfileStore extends ChangeNotifier {
  /// Testing/build-time override: every hull, cannon and battlefield
  /// reads as owned everywhere in the app, release APKs included. On by
  /// default so a debug build or a build shipped for testers never gates
  /// content behind RP. Flip off for a real release with
  /// `--dart-define=BBZ_UNLOCK_ALL=false`.
  static const bool _unlockAllDefault =
      bool.fromEnvironment('BBZ_UNLOCK_ALL', defaultValue: true);

  /// Lets a test flip the flag without a separate dart-define per run —
  /// e.g. the shop/purchase-flow tests that specifically exercise real
  /// ownership rules. `null` defers to [_unlockAllDefault].
  @visibleForTesting
  static bool? debugUnlockAllOverride;

  static bool get _unlockAll => debugUnlockAllOverride ?? _unlockAllDefault;

  static const _kRp = 'profile.rp';
  static const _kDoubloons = 'profile.doubloons';
  static const _kRookieWins = 'profile.rookieWins';
  static const _kWins = 'profile.wins';
  static const _kLosses = 'profile.losses';
  static const _kStreak = 'profile.streak';
  static const _kBestStreak = 'profile.bestStreak';
  static const _kName = 'profile.name';
  static const _kSound = 'profile.sound';
  static const _kShipSkin = 'profile.shipSkin';
  static const _kShipSkinChosen = 'profile.shipSkinChosen';
  static const _kCannonSkin = 'profile.cannonSkin';
  static const _kOwned = 'profile.owned';
  static const _kGameplayTheme = 'profile.gameplayTheme';
  static const _kSfxVol = 'profile.sfxVolume';
  static const _kMusicVol = 'profile.musicVolume';
  static const _kGraphics = 'profile.graphics';
  static const _kCinematic = 'profile.cinematicFinish';
  static const _kDailyClaim = 'profile.dailyPuzzleClaim';
  static const _kDailyStreak = 'profile.dailyPuzzleStreak';
  static const _kDailySolved = 'profile.dailyPuzzleSolved';
  static const _kAch = 'profile.achievements';
  static const _kQuestDate = 'profile.questDate';
  static const _kQuestProg = 'profile.questProgress';
  static const _kQuestDone = 'profile.questDone';
  static const _kTotalSinks = 'profile.totalSinks';

  SharedPreferences? _prefs;

  /// Rank Points — moved ONLY by match results, never by purchases.
  /// This is the number `rankTitle` reads.
  int rp = 1000;

  /// Spendable soft currency ("Doubloons") — earned by playing (win or
  /// loss), spent by every shop purchase. Spending never lowers rank.
  int doubloons = 1000;

  /// Last match's doubloon gain, for the result screen. Set by
  /// [recordResult] alongside its int (RP delta) return.
  int lastDoubloonsDelta = 0;

  /// Consecutive vs-AI Rookie wins — drives diminishing returns so
  /// farming the easiest difficulty stalls out instead of ranking up.
  int consecutiveRookieWins = 0;

  int wins = 0;
  int losses = 0;
  int streak = 0;
  int bestStreak = 0;
  String playerName = 'Captain';
  bool soundOn = true;

  /// Master effect volume, 0..1. Multiplied into every cue's own level —
  /// see `SoundService.sfxVolume`.
  double sfxVolume = 1.0;

  /// Menu-music volume, 0..1. 0.82 is the level the music always played
  /// at before it became adjustable, so an untouched profile sounds
  /// exactly as it did.
  double musicVolume = 0.82;

  /// How much visual flourish the battle screen spends — see
  /// [GraphicsQuality].
  GraphicsQuality graphics = GraphicsQuality.balanced;

  /// The slow, close-up finish on the shot that sinks a fleet's last
  /// hull. OFF by default: it is a deliberate interruption of the pace,
  /// and a player who has not asked for it should not have their match
  /// paused for a camera move.
  bool cinematicFinish = false;
  String shipSkinId = 'steel';

  /// Whether the player has ever actually equipped a hull in the
  /// shipyard, as opposed to still sailing the one every profile starts
  /// with. Steel Fleet is both the free starter hull AND a real,
  /// equippable skin, so the equipped id alone cannot tell "I chose
  /// steel" apart from "I never chose anything" — and multiplayer wants
  /// different fleet colours for those two states. See
  /// `lib/core/fleet_identity.dart` for what each one looks like.
  bool shipSkinChosen = false;

  String cannonSkinId = 'mk1';
  String gameplayThemeId = 'mk1';
  Set<String> owned = {'ship:steel', 'cannon:mk1', 'theme:mk1'};

  ShipSkin get shipSkin => Catalog.shipById(shipSkinId);
  CannonSkin get cannonSkin => Catalog.cannonById(cannonSkinId);
  GameplayTheme get gameplayTheme => Catalog.gameplayThemeById(gameplayThemeId);

  String get rankTitle => rankTitleForRp(rp);

  // ------------------------------------------------- AWARDS (achievements + daily quests) ---
  //
  // Local-only retention: one-time achievement milestones and three
  // seeded daily quests, all paying Doubloons (never rank). Progress is
  // recorded only for counted matches (see `recordMatchForAwards`) so
  // local pass-and-play can't farm them.

  /// One-time milestones: id → (icon, name, description, reward).
  /// Icons are unique across medals and quests.
  static const List<
      ({String id, String icon, String name, String desc, int reward})>
      achievementDefs = [
    (id: 'first_blood', icon: '🩸', name: 'First Blood', desc: 'Score a hit.', reward: 10),
    (id: 'ship_sinker', icon: '⚓', name: 'Ship Sinker', desc: 'Sink a ship.', reward: 15),
    (
      id: 'fleet_destroyer',
      icon: '💥',
      name: 'Fleet Destroyer',
      desc: 'Win a match.',
      reward: 25
    ),
    (
      id: 'sharpshooter',
      icon: '🎯',
      name: 'Sharpshooter',
      desc: 'Win with 60%+ accuracy (10+ shots).',
      reward: 40
    ),
    (
      id: 'hot_streak',
      icon: '🔥',
      name: 'Hot Streak',
      desc: 'Reach a 3-win streak.',
      reward: 30
    ),
    (
      id: 'carrier_killer',
      icon: '🛩️',
      name: 'Carrier Killer',
      desc: 'Sink an Aircraft Carrier.',
      reward: 20
    ),
    (
      id: 'demolisher',
      icon: '💀',
      name: 'Demolisher',
      desc: 'Sink 10 ships (career).',
      reward: 50
    ),
    (
      id: 'veteran',
      icon: '🎖️',
      name: 'Veteran',
      desc: 'Complete 10 matches.',
      reward: 30
    ),
    (
      id: 'ghost_hunter',
      icon: '👻',
      name: 'Ghost Hunter',
      desc: 'Win a Ghost Fleet match.',
      reward: 30
    ),
    (
      id: 'power_player',
      icon: '🃏',
      name: 'Power Player',
      desc: 'Use 3 cards in one match.',
      reward: 25
    ),
    (
      id: 'puzzle_solver',
      icon: '🧩',
      name: 'Puzzle Solver',
      desc: 'Solve a daily puzzle.',
      reward: 20
    ),
    (
      id: 'flawless',
      icon: '🛡️',
      name: 'Flawless Victory',
      desc: 'Win without losing a hull.',
      reward: 40
    ),
    (
      id: 'annihilator',
      icon: '☠️',
      name: 'Annihilator',
      desc: 'Sink 5 ships in one match.',
      reward: 35
    ),
    (
      id: 'brawler',
      icon: '🔨',
      name: 'Brawler',
      desc: 'Score 15 hits in one match.',
      reward: 30
    ),
    (
      id: 'against_all_odds',
      icon: '🌊',
      name: 'Against All Odds',
      desc: 'Win having lost 4 of your hulls.',
      reward: 45
    ),
    (
      id: 'unstoppable',
      icon: '🚀',
      name: 'Unstoppable',
      desc: 'Reach a 5-win streak.',
      reward: 60
    ),
    (
      id: 'abyssal',
      icon: '🐙',
      name: 'Abyssal Terror',
      desc: 'Sink 25 ships (career).',
      reward: 75
    ),
    (
      id: 'legend',
      icon: '👑',
      name: 'Living Legend',
      desc: 'Complete 50 matches.',
      reward: 100
    ),
    (
      id: 'puzzle_streak_3',
      icon: '📅',
      name: 'Puzzle Devotee',
      desc: 'Solve the daily puzzle 3 days in a row.',
      reward: 30
    ),
    (
      id: 'win_chaos',
      icon: '⛈️',
      name: 'Storm Rider',
      desc: 'Win a Chaos match.',
      reward: 25
    ),
    (
      id: 'win_rearrange',
      icon: '🧭',
      name: 'Master Maneuverist',
      desc: 'Win a Manoeuvre match.',
      reward: 25
    ),
    (
      id: 'win_blitz',
      icon: '⚡',
      name: 'Blitzkrieg',
      desc: 'Win a Blitz match.',
      reward: 25
    ),
    (
      id: 'win_powerplay',
      icon: '🎴',
      name: 'Card Shark',
      desc: 'Win a Power Play match.',
      reward: 25
    ),
    (
      id: 'win_phantom',
      icon: '🌫️',
      name: 'Phantom Menace',
      desc: 'Win a Phantom match.',
      reward: 30
    ),
    (
      id: 'win_salvo',
      icon: '🔱',
      name: 'Salvo Striker',
      desc: 'Win a Salvo match.',
      reward: 30
    ),
  ];

  /// Daily-quest pool: id → (icon, name, description, target, reward).
  /// Three are dealt per day by seed (see [dailyQuestIds]). Icons are
  /// unique across quests and medals.
  static const List<
      ({String id, String icon, String name, String desc, int target, int reward})>
      questPool = [
    (id: 'play_2', icon: '⛵', name: 'Sail Out', desc: 'Complete 2 matches.', target: 2, reward: 15),
    (id: 'win_1', icon: '🏆', name: 'Victorious', desc: 'Win 1 match.', target: 1, reward: 30),
    (
      id: 'hits_8',
      icon: '🔫',
      name: 'Gunnery Practice',
      desc: 'Score 8 hits.',
      target: 8,
      reward: 20
    ),
    (
      id: 'sinks_2',
      icon: '💣',
      name: 'Shipbreaker',
      desc: 'Sink 2 ships.',
      target: 2,
      reward: 25
    ),
    (
      id: 'streak_2',
      icon: '🎲',
      name: 'On a Roll',
      desc: 'Win 2 matches in a row.',
      target: 1,
      reward: 35
    ),
    (
      id: 'accuracy_50',
      icon: '🔭',
      name: 'Deadeye',
      desc: 'Win with 50%+ accuracy.',
      target: 1,
      reward: 25
    ),
    (
      id: 'wins_2',
      icon: '⚔️',
      name: 'Double Victory',
      desc: 'Win 2 matches.',
      target: 2,
      reward: 40
    ),
    (
      id: 'hits_15',
      icon: '🧨',
      name: 'Broadside Barrage',
      desc: 'Score 15 hits.',
      target: 15,
      reward: 30
    ),
    (
      id: 'sinks_4',
      icon: '🌀',
      name: 'Wrecker',
      desc: 'Sink 4 ships.',
      target: 4,
      reward: 35
    ),
  ];

  /// Career ships sunk — feeds the Demolisher achievement.
  int totalSinks = 0;

  /// Unlocked achievement ids.
  Set<String> achievements = {};

  /// Active daily-quest date key (see [dailyPuzzleKey]).
  String questDate = '';

  /// Progress for the active date's quests: quest id → count.
  Map<String, int> questProgress = {};

  /// Claimed (completed + paid) quest ids for the active date.
  Set<String> questDone = {};

  /// Awards from the latest match/event, for the result screen to
  /// announce. Reset on every recording call — never persisted.
  List<({String icon, String name, int reward})> lastAwardNotes = [];

  /// The three quest defs dealt for [now]'s date. Deterministic per
  /// day, same on every device.
  static List<
      ({String id, String icon, String name, String desc, int target, int reward})>
      dailyQuestIds(DateTime now) {
    final pool = List.of(questPool);
    pool.shuffle(
        Random(dailyPuzzleSeed(DateTime(now.year, now.month, now.day))));
    return pool.take(3).toList();
  }

  /// Medal id → its def, or null for unknown ids.
  static ({String id, String icon, String name, String desc, int reward})?
      medalById(String id) {
    for (final a in achievementDefs) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Mode-win medal for a network battle mode, or null when the mode
  /// has no medal (classic turns ride on Fleet Destroyer; Ghost Fleet
  /// has Ghost Hunter).
  static String? modeMedalId(LanBattleMode mode) => switch (mode) {
        LanBattleMode.chaos => 'win_chaos',
        LanBattleMode.rearrange => 'win_rearrange',
        LanBattleMode.blitz => 'win_blitz',
        LanBattleMode.powerPlay => 'win_powerplay',
        LanBattleMode.phantom => 'win_phantom',
        LanBattleMode.salvo => 'win_salvo',
        _ => null,
      };

  void _grant({required String icon, required String name, required int reward}) {
    doubloons += reward;
    lastAwardNotes.add((icon: icon, name: name, reward: reward));
  }

  void _unlock(String id) {
    if (achievements.contains(id)) return;
    final def = medalById(id);
    if (def == null) return;
    achievements.add(id);
    _grant(icon: def.icon, name: def.name, reward: def.reward);
  }

  /// Records a finished match for awards. Call AFTER [recordResult] so
  /// streak/wins are current. [counted] mirrors the RP guard (no local,
  /// abandoned, or headless games) so unranked play can't farm.
  /// [ownShipsLost] is this fleet's sunk count; [lanMode] is set for
  /// hotspot/online matches (drives the mode-win medals).
  void recordMatchForAwards({
    required bool won,
    required DateTime now,
    required int hitsThisMatch,
    required int shotsThisMatch,
    required int sinksThisMatch,
    required int cardsUsed,
    required bool sunkCarrier,
    required bool isGhostWin,
    required bool counted,
    int ownShipsLost = 0,
    LanBattleMode? lanMode,
  }) {
    lastAwardNotes = [];
    if (!counted) {
      _save();
      notifyListeners();
      return;
    }
    totalSinks += sinksThisMatch;
    final acc = shotsThisMatch == 0
        ? 0.0
        : hitsThisMatch / shotsThisMatch;

    if (hitsThisMatch >= 1) _unlock('first_blood');
    if (sinksThisMatch >= 1) _unlock('ship_sinker');
    if (won) _unlock('fleet_destroyer');
    if (won && shotsThisMatch >= 10 && acc >= 0.6) {
      _unlock('sharpshooter');
    }
    if (streak >= 3) _unlock('hot_streak');
    if (streak >= 5) _unlock('unstoppable');
    if (sunkCarrier) _unlock('carrier_killer');
    if (totalSinks >= 10) _unlock('demolisher');
    if (totalSinks >= 25) _unlock('abyssal');
    if (wins + losses >= 10) _unlock('veteran');
    if (wins + losses >= 50) _unlock('legend');
    if (isGhostWin) _unlock('ghost_hunter');
    if (cardsUsed >= 3) _unlock('power_player');
    if (won && shotsThisMatch > 0 && ownShipsLost == 0) {
      _unlock('flawless');
    }
    if (sinksThisMatch >= 5) _unlock('annihilator');
    if (hitsThisMatch >= 15) _unlock('brawler');
    if (won && ownShipsLost >= 4) _unlock('against_all_odds');
    if (won && lanMode != null) {
      final modeMedal = modeMedalId(lanMode);
      if (modeMedal != null) _unlock(modeMedal);
    }

    // Daily quests for today's date (roll over first).
    final key = dailyPuzzleKey(now);
    if (questDate != key) {
      questDate = key;
      questProgress = {};
      questDone = {};
    }
    void bump(String id, int n) {
      if (questDone.contains(id)) return;
      questProgress[id] = (questProgress[id] ?? 0) + n;
    }

    bump('play_2', 1);
    if (won) {
      bump('win_1', 1);
      bump('wins_2', 1);
    }
    bump('hits_8', hitsThisMatch);
    bump('hits_15', hitsThisMatch);
    bump('sinks_2', sinksThisMatch);
    bump('sinks_4', sinksThisMatch);
    if (streak >= 2) questProgress['streak_2'] = 1;
    if (won && acc >= 0.5) questProgress['accuracy_50'] = 1;

    for (final q in dailyQuestIds(now)) {
      if (questDone.contains(q.id)) continue;
      if ((questProgress[q.id] ?? 0) >= q.target) {
        questDone.add(q.id);
        _grant(icon: q.icon, name: q.name, reward: q.reward);
      }
    }
    _save();
    notifyListeners();
  }

  // -------------------------------------------------- DAILY PUZZLE ---
  //
  // One reward per calendar day (local time): solving pays 25 + 5 per
  // streak day (cap 50), failing still pays 5 for showing up. Replays
  // are free but pay nothing — the claim date is what enforces that,
  // not the screen, so no UI path can double-pay.

  /// Date key this device last claimed a daily-puzzle reward on.
  String dailyPuzzleClaim = '';

  /// Consecutive solved days. Resets on a fail or a skipped day.
  int dailyPuzzleStreak = 0;

  /// Date key of the last SOLVED day (drives the streak above).
  String dailyPuzzleLastSolved = '';

  static String dailyPuzzleKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static int dailyPuzzleSeed(DateTime d) =>
      d.year * 10000 + d.month * 100 + d.day;

  bool dailyPuzzleRewardAvailable(DateTime now) =>
      dailyPuzzleClaim != dailyPuzzleKey(now);

  int claimDailyPuzzleReward({required bool solved, required DateTime now}) {
    final key = dailyPuzzleKey(now);
    if (dailyPuzzleClaim == key) return 0;
    dailyPuzzleClaim = key;
    lastAwardNotes = [];
    int reward;
    if (solved) {
      final yesterday =
          dailyPuzzleKey(now.subtract(const Duration(days: 1)));
      dailyPuzzleStreak =
          (dailyPuzzleLastSolved == yesterday) ? dailyPuzzleStreak + 1 : 1;
      dailyPuzzleLastSolved = key;
      reward = 25 + 5 * min(dailyPuzzleStreak, 5);
      _unlock('puzzle_solver');
      if (dailyPuzzleStreak >= 3) _unlock('puzzle_streak_3');
    } else {
      dailyPuzzleStreak = 0;
      reward = 5;
    }
    doubloons += reward;
    _save();
    notifyListeners();
    return reward;
  }

  /// Streak bonus applied on top of base RP change.
  int get streakBonus => min(streak, 5) * 5;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // The platform's local preferences store failed to load — most
      // likely a previous run's write was interrupted (crash, forced
      // kill, disk hiccup) and left the on-disk file truncated or
      // malformed. `_prefs` stays null; `_save` already no-ops without
      // one, so this device just plays a session that can't persist
      // instead of refusing to start at all.
      _prefs = null;
    }
    final p = _prefs;
    if (p == null) {
      notifyListeners();
      return;
    }
    rp = p.getInt(_kRp) ?? 1000;
    // Migration: Doubloons did not exist before the RP/currency split.
    // Preserve purchasing power by seeding from the current RP once.
    if (p.containsKey(_kDoubloons)) {
      doubloons = p.getInt(_kDoubloons) ?? 1000;
    } else {
      doubloons = rp;
    }
    consecutiveRookieWins = p.getInt(_kRookieWins) ?? 0;
    dailyPuzzleClaim = p.getString(_kDailyClaim) ?? '';
    dailyPuzzleStreak = p.getInt(_kDailyStreak) ?? 0;
    dailyPuzzleLastSolved = p.getString(_kDailySolved) ?? '';
    achievements = (p.getStringList(_kAch) ?? const []).toSet();
    questDate = p.getString(_kQuestDate) ?? '';
    questProgress = {
      for (final e in (p.getStringList(_kQuestProg) ?? const []))
        if (e.contains('='))
          e.substring(0, e.indexOf('=')):
              int.tryParse(e.substring(e.indexOf('=') + 1)) ?? 0,
    };
    questDone = (p.getStringList(_kQuestDone) ?? const []).toSet();
    totalSinks = p.getInt(_kTotalSinks) ?? 0;
    wins = p.getInt(_kWins) ?? 0;
    losses = p.getInt(_kLosses) ?? 0;
    streak = p.getInt(_kStreak) ?? 0;
    bestStreak = p.getInt(_kBestStreak) ?? 0;
    playerName = p.getString(_kName) ?? 'Captain';
    soundOn = p.getBool(_kSound) ?? true;
    sfxVolume = (p.getDouble(_kSfxVol) ?? 1.0).clamp(0.0, 1.0);
    musicVolume = (p.getDouble(_kMusicVol) ?? 0.82).clamp(0.0, 1.0);
    graphics = GraphicsQuality.values[(p.getInt(_kGraphics) ?? GraphicsQuality.balanced.index).clamp(0, GraphicsQuality.values.length - 1)];
    cinematicFinish = p.getBool(_kCinematic) ?? false;
    shipSkinId = p.getString(_kShipSkin) ?? 'steel';
    shipSkinChosen = p.getBool(_kShipSkinChosen) ?? false;
    cannonSkinId = p.getString(_kCannonSkin) ?? 'mk1';
    gameplayThemeId = p.getString(_kGameplayTheme) ?? 'mk1';
    owned = (p.getStringList(_kOwned) ?? ['steel', 'mk1', 'mk1']).toSet();
    _migrateOwnership();
    // The sound service and the effect painters read these as globals;
    // this is what makes a restored profile sound and draw the way it
    // was left rather than at the compiled-in defaults.
    SoundService.instance.sfxVolume = sfxVolume;
    SoundService.instance.musicVolume = musicVolume;
    applyGraphics();
    notifyListeners();
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt(_kRp, rp);
    await p.setInt(_kDoubloons, doubloons);
    await p.setInt(_kRookieWins, consecutiveRookieWins);
    await p.setString(_kDailyClaim, dailyPuzzleClaim);
    await p.setInt(_kDailyStreak, dailyPuzzleStreak);
    await p.setString(_kDailySolved, dailyPuzzleLastSolved);
    await p.setStringList(_kAch, achievements.toList());
    await p.setString(_kQuestDate, questDate);
    await p.setStringList(
        _kQuestProg, [for (final e in questProgress.entries) '${e.key}=${e.value}']);
    await p.setStringList(_kQuestDone, questDone.toList());
    await p.setInt(_kTotalSinks, totalSinks);
    await p.setInt(_kWins, wins);
    await p.setInt(_kLosses, losses);
    await p.setInt(_kStreak, streak);
    await p.setInt(_kBestStreak, bestStreak);
    await p.setString(_kName, playerName);
    await p.setBool(_kSound, soundOn);
    await p.setDouble(_kSfxVol, sfxVolume);
    await p.setDouble(_kMusicVol, musicVolume);
    await p.setInt(_kGraphics, graphics.index);
    await p.setBool(_kCinematic, cinematicFinish);
    await p.setString(_kShipSkin, shipSkinId);
    await p.setBool(_kShipSkinChosen, shipSkinChosen);
    await p.setString(_kCannonSkin, cannonSkinId);
    await p.setString(_kGameplayTheme, gameplayThemeId);
    await p.setStringList(_kOwned, owned.toList());
  }

  /// Records a finished match. Returns the RP (rank) delta.
  ///
  /// Rank and currency are separate: RP moves here (Elo-style online,
  /// difficulty-scaled vs-AI, symmetric otherwise) while Doubloons are
  /// always earned (never lost) so playing funds the shop without ever
  /// lowering rank. The doubloon gain is exposed via
  /// [lastDoubloonsDelta] for the result screen.
  ///
  /// - [opponentRp]: set for ranked online/hotspot play. Elo K=32 with a
  ///   ±8..32 clamp, so equal players trade ±16 (50% break-even).
  /// - [aiDifficulty]: set for vs-AI. Rookie pays least and diminishes
  ///   with consecutive Rookie wins; Admiral pays full.
  int recordResult({
    required bool won,
    int? opponentRp,
    AIDifficulty? aiDifficulty,
  }) {
    int delta;
    double currencyScale = 1.0;
    if (opponentRp != null) {
      // Elo-style ranked gain.
      const k = 32;
      final expected =
          1 / (1 + pow(10, (opponentRp - rp) / 400));
      if (won) {
        wins++;
        streak++;
        bestStreak = max(bestStreak, streak);
        delta = (k * (1 - expected)).round().clamp(8, 32).toInt();
        // Small streak kicker on top of Elo, capped so it can't farm.
        delta = (delta + min(streak, 3)).clamp(8, 36).toInt();
        consecutiveRookieWins = 0;
      } else {
        losses++;
        streak = 0;
        delta = (k * (0 - expected)).round().clamp(-32, -8).toInt();
        consecutiveRookieWins = 0;
      }
    } else if (aiDifficulty != null) {
      final scale = switch (aiDifficulty) {
        AIDifficulty.easy => 0.4,
        AIDifficulty.normal => 0.7,
        AIDifficulty.hard => 1.0,
      };
      currencyScale = switch (aiDifficulty) {
        AIDifficulty.easy => 0.5,
        AIDifficulty.normal => 0.8,
        AIDifficulty.hard => 1.0,
      };
      if (won) {
        wins++;
        streak++;
        bestStreak = max(bestStreak, streak);
        var base = (25 * scale).round() + (streakBonus * scale).round();
        if (aiDifficulty == AIDifficulty.easy) {
          // Diminishing returns: 1x, ~0.57x, 0.4x, ... floored at 2 RP.
          final denom = 1 + 0.75 * consecutiveRookieWins;
          base = max(2, (base / denom).round());
          consecutiveRookieWins++;
        } else {
          consecutiveRookieWins = 0;
        }
        delta = base;
      } else {
        losses++;
        streak = 0;
        consecutiveRookieWins = 0;
        delta = switch (aiDifficulty) {
          AIDifficulty.easy => -5,
          AIDifficulty.normal => -10,
          AIDifficulty.hard => -15,
        };
      }
    } else {
      // Unranked / unknown opponent (e.g. hotspot without RP handshake):
      // symmetric ± so break-even is 50%, not 37.5%.
      if (won) {
        wins++;
        streak++;
        bestStreak = max(bestStreak, streak);
        delta = 16 + min(streak, 5) * 2;
        consecutiveRookieWins = 0;
      } else {
        losses++;
        streak = 0;
        delta = -16;
        consecutiveRookieWins = 0;
      }
    }
    rp = max(0, rp + delta);
    // Doubloons: always a gain, scaled like the match, rookie-farmed
    // gains diminish with the same denominator.
    int coins;
    if (won) {
      coins = (20 * currencyScale).round() + min(streak, 5) * 3;
      if (aiDifficulty == AIDifficulty.easy && opponentRp == null) {
        final denom = 1 + 0.75 * (consecutiveRookieWins - 1).clamp(0, 99);
        coins = max(2, (coins / denom).round());
      }
    } else {
      coins = (8 * currencyScale).round().clamp(2, 99).toInt();
    }
    lastDoubloonsDelta = coins;
    doubloons += coins;
    _save();
    notifyListeners();
    return delta;
  }

  Future<void> setName(String name) async {
    playerName = name.trim().isEmpty ? 'Captain' : name.trim();
    await _save();
    notifyListeners();
  }


  /// Applies a settings change and pushes it at whatever actually acts on
  /// it. Kept as one method per setting rather than a single "save
  /// everything" so a slider dragged across the screen writes once per
  /// change and never has to guess what else moved.
  Future<void> setSfxVolume(double v) async {
    sfxVolume = v.clamp(0.0, 1.0);
    SoundService.instance.sfxVolume = sfxVolume;
    await _save();
    notifyListeners();
  }

  Future<void> setMusicVolume(double v) async {
    musicVolume = v.clamp(0.0, 1.0);
    SoundService.instance.musicVolume = musicVolume;
    await _save();
    notifyListeners();
  }

  Future<void> setGraphics(GraphicsQuality q) async {
    graphics = q;
    applyGraphics();
    await _save();
    notifyListeners();
  }

  Future<void> setCinematicFinish(bool on) async {
    cinematicFinish = on;
    await _save();
    notifyListeners();
  }

  /// Pushes the audio and graphics settings at the systems that read them
  /// as plain globals rather than through this store — the sound service,
  /// and the impact-effect painters in `lib/art/`. Called on load so a
  /// restored profile sounds and draws the way it was left, and again
  /// from each setter.
  void applyGraphics() {
    fxDensity = graphics.fxDensity;
    // These two were declared on `GraphicsQuality` and then never read by
    // anything — see the note on `screenShakeEnabled`. Pushed out here
    // with the density so one call applies the whole setting.
    screenShakeEnabled = graphics.screenShake;
    shellTrailCount = graphics.shellTrails;
  }
  Future<void> toggleSound() async {
    soundOn = !soundOn;
    await _save();
    notifyListeners();
  }

  /// Ownership keys are scoped by what KIND of item they are.
  ///
  /// BUGFIX: they used not to be, and `owned` is one flat set shared by
  /// hulls, cannons and battlefields — so an id appearing in two
  /// catalogues was silently the same purchase. That was already live:
  /// buying the **Arctic Front** battlefield (900 RP) handed you the
  /// **Arctic Storm** hull (750 RP) for nothing, because both are id
  /// `arctic`. Adding six families across all three catalogues would have
  /// turned one collision into eighteen.
  ///
  /// [_migrateOwnership] converts old saves, deliberately generously —
  /// see the note there.
  static String _ownKey(String kind, String id) => '$kind:$id';

  bool ownsShip(String id) =>
      _unlockAll || owned.contains(_ownKey('ship', id));
  bool ownsCannon(String id) =>
      _unlockAll || owned.contains(_ownKey('cannon', id));
  bool ownsTheme(String id) =>
      _unlockAll || owned.contains(_ownKey('theme', id));

  /// Untyped lookup, kept for callers that only have an id. Prefer the
  /// typed variants — this one cannot tell an `arctic` hull from an
  /// `arctic` battlefield and answers true for either.
  bool owns(String id) =>
      ownsShip(id) || ownsCannon(id) || ownsTheme(id) || owned.contains(id);

  /// Brings a pre-scoping save up to date.
  ///
  /// Every bare id is expanded into a typed key for **each** catalogue
  /// that contains it. That is intentionally generous: under the old
  /// build a player with `arctic` in their set really could equip both
  /// the hull and the battlefield, so scoping it strictly now would take
  /// away something they had been using. Nobody should be charged for a
  /// bug on our side.
  void _migrateOwnership() {
    if (owned.any((k) => k.contains(':'))) return; // already scoped
    final scoped = <String>{};
    for (final id in owned) {
      if (Catalog.shipSkins.any((s) => s.id == id)) {
        scoped.add(_ownKey('ship', id));
      }
      if (Catalog.cannonSkins.any((c) => c.id == id)) {
        scoped.add(_ownKey('cannon', id));
      }
      if (Catalog.gameplayThemes.any((t) => t.id == id)) {
        scoped.add(_ownKey('theme', id));
      }
    }
    // The three starters are free and must survive any odd save state.
    scoped.addAll([
      _ownKey('ship', 'steel'),
      _ownKey('cannon', 'mk1'),
      _ownKey('theme', 'mk1'),
    ]);
    owned = scoped;
  }

  /// Buys and/or equips a ship skin. Returns true when equipped.
  /// Costs Doubloons — rank (RP) is never spent.
  bool equipShipSkin(ShipSkin skin) {
    if (!ownsShip(skin.id)) {
      if (doubloons < skin.cost) return false;
      doubloons -= skin.cost;
      owned.add(_ownKey('ship', skin.id));
    }
    shipSkinId = skin.id;
    // Equipping ANY hull — Steel Fleet very much included — is the player
    // making a choice, and from here on that is what they sail in
    // multiplayer instead of their side's plain red/blue.
    shipSkinChosen = true;
    _save();
    notifyListeners();
    return true;
  }

  /// Steps back out of skins entirely: sail your side's plain red/blue.
  ///
  /// The counterpart to [equipShipSkin], which can only ever say "a hull
  /// was chosen" — the GEAR dialog's RED/BLUE FLEET chip needs a way to
  /// UN-choose, and without this it silently re-equipped whatever hull id
  /// was still lying around (Steel, usually) with the chosen flag forced
  /// back on. That is exactly the "I pick Red Fleet and it reverts to
  /// Steel" bug.
  void clearShipSkinChoice() {
    shipSkinChosen = false;
    _save();
    notifyListeners();
  }



  bool equipCannonSkin(CannonSkin skin) {
    if (!ownsCannon(skin.id)) {
      if (doubloons < skin.cost) return false;
      doubloons -= skin.cost;
      owned.add(_ownKey('cannon', skin.id));
    }
    cannonSkinId = skin.id;
    _save();
    notifyListeners();
    return true;
  }

  /// The design's one-tap matched set: a family's hull, gun and
  /// battlefield together, for less than the three bought separately.
  ///
  /// Returns false and changes nothing if it can't be afforded, so a
  /// half-bought set is impossible. Pieces already owned are charged for
  /// again by design — the discount is on the bundle, and refunding
  /// against past purchases would let someone buy the two cheap pieces
  /// first and take the expensive one at a fraction of its price.
  /// [setDiscountFor] is what the card actually quotes, and it only
  /// discounts what is still missing.
  bool buyFamilySet(FleetFamily family) {
    final price = setPriceFor(family);
    if (price > doubloons) return false;
    doubloons -= price;
    owned.add(_ownKey('ship', 'f_${family.key}'));
    owned.add(_ownKey('cannon', 'f_${family.key}'));
    owned.add(_ownKey('theme', 'f_${family.key}'));
    shipSkinId = 'f_${family.key}';
    shipSkinChosen = true;
    cannonSkinId = 'f_${family.key}';
    gameplayThemeId = 'f_${family.key}';
    _save();
    notifyListeners();
    return true;
  }

  /// What this player would pay for [family]'s set right now: 80% of the
  /// pieces they don't already have. Someone who bought the hull last
  /// week still gets the bundle price on the rest rather than paying for
  /// it twice.
  int setPriceFor(FleetFamily family) {
    final key = 'f_${family.key}';
    var full = 0;
    if (!ownsShip(key)) full += Catalog.shipById(key).cost;
    if (!ownsCannon(key)) full += Catalog.cannonById(key).cost;
    if (!ownsTheme(key)) full += Catalog.gameplayThemeById(key).cost;
    return (full * 0.8).round();
  }

  /// RP saved by taking the set instead of the remaining pieces singly.
  int setSavingFor(FleetFamily family) {
    final key = 'f_${family.key}';
    var full = 0;
    if (!ownsShip(key)) full += Catalog.shipById(key).cost;
    if (!ownsCannon(key)) full += Catalog.cannonById(key).cost;
    if (!ownsTheme(key)) full += Catalog.gameplayThemeById(key).cost;
    return full - (full * 0.8).round();
  }

  /// True once all three pieces of [family] are owned — the point at
  /// which its set card has nothing left to sell.
  bool ownsFamilySet(FleetFamily family) {
    final key = 'f_${family.key}';
    return ownsShip(key) && ownsCannon(key) && ownsTheme(key);
  }

  /// True once all three pieces of [set] are owned — a legacy set has no
  /// bundle price to sell (every piece is still a la carte), so this only
  /// gates whether its gear-dialog shortcut chip appears.
  bool ownsLegacySet(LegacySet set) =>
      ownsShip(set.shipSkinId) && ownsCannon(set.id) && ownsTheme(set.id);

  bool equipGameplayTheme(GameplayTheme theme) {
    if (!ownsTheme(theme.id)) {
      if (doubloons < theme.cost) return false;
      doubloons -= theme.cost;
      owned.add(_ownKey('theme', theme.id));
    }
    gameplayThemeId = theme.id;
    _save();
    notifyListeners();
    return true;
  }
}
