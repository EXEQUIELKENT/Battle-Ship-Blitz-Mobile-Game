import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../art/fleet_family.dart';
import '../art/legacy_identity.dart';

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
  final int cost; // RP cost; 0 = free

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

  SharedPreferences? _prefs;

  int rp = 1000;
  int wins = 0;
  int losses = 0;
  int streak = 0;
  int bestStreak = 0;
  String playerName = 'Captain';
  bool soundOn = true;
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
    wins = p.getInt(_kWins) ?? 0;
    losses = p.getInt(_kLosses) ?? 0;
    streak = p.getInt(_kStreak) ?? 0;
    bestStreak = p.getInt(_kBestStreak) ?? 0;
    playerName = p.getString(_kName) ?? 'Captain';
    soundOn = p.getBool(_kSound) ?? true;
    shipSkinId = p.getString(_kShipSkin) ?? 'steel';
    shipSkinChosen = p.getBool(_kShipSkinChosen) ?? false;
    cannonSkinId = p.getString(_kCannonSkin) ?? 'mk1';
    gameplayThemeId = p.getString(_kGameplayTheme) ?? 'mk1';
    owned = (p.getStringList(_kOwned) ?? ['steel', 'mk1', 'mk1']).toSet();
    _migrateOwnership();
    notifyListeners();
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt(_kRp, rp);
    await p.setInt(_kWins, wins);
    await p.setInt(_kLosses, losses);
    await p.setInt(_kStreak, streak);
    await p.setInt(_kBestStreak, bestStreak);
    await p.setString(_kName, playerName);
    await p.setBool(_kSound, soundOn);
    await p.setString(_kShipSkin, shipSkinId);
    await p.setBool(_kShipSkinChosen, shipSkinChosen);
    await p.setString(_kCannonSkin, cannonSkinId);
    await p.setString(_kGameplayTheme, gameplayThemeId);
    await p.setStringList(_kOwned, owned.toList());
  }

  /// Records a finished match. Returns the RP delta.
  int recordResult({required bool won}) {
    int delta;
    if (won) {
      wins++;
      streak++;
      bestStreak = max(bestStreak, streak);
      delta = 25 + streakBonus;
    } else {
      losses++;
      streak = 0;
      delta = -15;
    }
    rp = max(0, rp + delta);
    _save();
    notifyListeners();
    return delta;
  }

  Future<void> setName(String name) async {
    playerName = name.trim().isEmpty ? 'Captain' : name.trim();
    await _save();
    notifyListeners();
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
  bool equipShipSkin(ShipSkin skin) {
    if (!ownsShip(skin.id)) {
      if (rp < skin.cost) return false;
      rp -= skin.cost;
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
      if (rp < skin.cost) return false;
      rp -= skin.cost;
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
    if (price > rp) return false;
    rp -= price;
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
      if (rp < theme.cost) return false;
      rp -= theme.cost;
      owned.add(_ownKey('theme', theme.id));
    }
    gameplayThemeId = theme.id;
    _save();
    notifyListeners();
    return true;
  }
}
