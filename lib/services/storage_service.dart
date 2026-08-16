import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A ship hull skin.
class ShipSkin {
  final String id;
  final String name;
  final Color hull;
  final Color trim;
  final int cost; // RP cost; 0 = free

  const ShipSkin(this.id, this.name, this.hull, this.trim, this.cost);
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

  const CannonSkin(this.id, this.name, this.barrel, this.projectile,
      this.description, this.cooldownFactor, this.cost);
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

  const GameplayTheme(this.id, this.name, this.description, this.deck, this.deckAccent, this.grid, this.gridLine, this.miss, this.accent, this.cost);
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
  ];

  static const List<CannonSkin> cannonSkins = [
    CannonSkin('mk1', 'MK-I Standard', Color(0xFF64748B), Color(0xFFFFB454),
        'Reliable naval artillery.', 1.0, 0),
    CannonSkin('inferno', 'Inferno Cannon', Color(0xFF7C2D12), Color(0xFFEF4444),
        'Blazing fire shells.', 1.0, 300),
    CannonSkin('tesla', 'Tesla Coilgun', Color(0xFF0E7490), Color(0xFF22D3EE),
        'Electric plasma bolts.', 1.0, 300),
    CannonSkin('venom', 'Venom Launcher', Color(0xFF365314), Color(0xFF84CC16),
        'Toxic green warheads.', 1.0, 300),
    CannonSkin('royal', 'Royal Broadside', Color(0xFF78350F), Color(0xFFFBBF24),
        'Gold-plated heavy guns.', 1.0, 600),
    CannonSkin('phantom', 'Phantom Railgun', Color(0xFF312E81), Color(0xFFC084FC),
        'Experimental railgun. 15% faster reload!', 0.85, 1000),
    CannonSkin('kraken', 'Kraken Cannon', Color(0xFF0F766E), Color(0xFF5EEAD4), 'Deep-sea siege cannon with a crushing pulse.', 0.95, 1200),
    CannonSkin('sunfire', 'Sunfire Battery', Color(0xFFB45309), Color(0xFFFDE047), 'High-energy golden shell launcher.', 0.90, 1400),
    CannonSkin('void', 'Void Annihilator', Color(0xFF111827), Color(0xFFEC4899), 'Dark-matter launcher. 10% faster reload!', 0.90, 1800),
  ];

  static const List<GameplayTheme> gameplayThemes = [
    GameplayTheme('classic','Classic Deck','Warm cartoon navy battle deck.',Color(0xFFE68A6E),Color(0xFFFDB9A4),Color(0xFF4A789A),Color(0xFF6D9DB8),Color(0xFF7A8A96),Color(0xFFFFB739),0),
    GameplayTheme('arctic','Arctic Front','Cold ice-water battlefield with bright sonar.',Color(0xFF9ED8E8),Color(0xFFD6F5FF),Color(0xFF3F7FA0),Color(0xFF8CCFE8),Color(0xFF9AB9C7),Color(0xFF7DD3FC),900),
    GameplayTheme('deep','Deep Sea','Dark ocean tones for a tactical match.',Color(0xFF173A4D),Color(0xFF2A607D),Color(0xFF214E63),Color(0xFF4A879C),Color(0xFF6B8792),Color(0xFF22D3EE),1200),
    GameplayTheme('sunset','Sunset Siege','Warm orange water and gold targeting effects.',Color(0xFFB8664F),Color(0xFFF5B48F),Color(0xFF4B718A),Color(0xFFD99D68),Color(0xFF8E9EAA),Color(0xFFFFD166),1500),
  ];

  static ShipSkin shipById(String id) =>
      shipSkins.firstWhere((s) => s.id == id, orElse: () => shipSkins.first);

  static CannonSkin cannonById(String id) =>
      cannonSkins.firstWhere((c) => c.id == id, orElse: () => cannonSkins.first);

  static GameplayTheme gameplayThemeById(String id) =>
      gameplayThemes.firstWhere((t) => t.id == id, orElse: () => gameplayThemes.first);
}

/// Persistent profile: RP, streaks, stats and customization.
class ProfileStore extends ChangeNotifier {
  static const _kRp = 'profile.rp';
  static const _kWins = 'profile.wins';
  static const _kLosses = 'profile.losses';
  static const _kStreak = 'profile.streak';
  static const _kBestStreak = 'profile.bestStreak';
  static const _kName = 'profile.name';
  static const _kSound = 'profile.sound';
  static const _kShipSkin = 'profile.shipSkin';
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
  String cannonSkinId = 'mk1';
  String gameplayThemeId = 'classic';
  Set<String> owned = {'steel', 'mk1', 'classic'};

  ShipSkin get shipSkin => Catalog.shipById(shipSkinId);
  CannonSkin get cannonSkin => Catalog.cannonById(cannonSkinId);
  GameplayTheme get gameplayTheme => Catalog.gameplayThemeById(gameplayThemeId);

  String get rankTitle {
    if (rp >= 2200) return 'FLEET ADMIRAL';
    if (rp >= 1800) return 'ADMIRAL';
    if (rp >= 1500) return 'COMMODORE';
    if (rp >= 1300) return 'CAPTAIN';
    if (rp >= 1150) return 'LIEUTENANT';
    return 'ENSIGN';
  }

  /// Streak bonus applied on top of base RP change.
  int get streakBonus => min(streak, 5) * 5;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    rp = p.getInt(_kRp) ?? 1000;
    wins = p.getInt(_kWins) ?? 0;
    losses = p.getInt(_kLosses) ?? 0;
    streak = p.getInt(_kStreak) ?? 0;
    bestStreak = p.getInt(_kBestStreak) ?? 0;
    playerName = p.getString(_kName) ?? 'Captain';
    soundOn = p.getBool(_kSound) ?? true;
    shipSkinId = p.getString(_kShipSkin) ?? 'steel';
    cannonSkinId = p.getString(_kCannonSkin) ?? 'mk1';
    gameplayThemeId = p.getString(_kGameplayTheme) ?? 'classic';
    owned = (p.getStringList(_kOwned) ?? ['steel', 'mk1', 'classic']).toSet();
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

  bool owns(String id) => owned.contains(id);

  /// Buys and/or equips a ship skin. Returns true when equipped.
  bool equipShipSkin(ShipSkin skin) {
    if (!owns(skin.id)) {
      if (rp < skin.cost) return false;
      rp -= skin.cost;
      owned.add(skin.id);
    }
    shipSkinId = skin.id;
    _save();
    notifyListeners();
    return true;
  }

  bool equipCannonSkin(CannonSkin skin) {
    if (!owns(skin.id)) {
      if (rp < skin.cost) return false;
      rp -= skin.cost;
      owned.add(skin.id);
    }
    cannonSkinId = skin.id;
    _save();
    notifyListeners();
    return true;
  }

  bool equipGameplayTheme(GameplayTheme theme) {
    if (!owns(theme.id)) {
      if (rp < theme.cost) return false;
      rp -= theme.cost;
      owned.add(theme.id);
    }
    gameplayThemeId = theme.id;
    _save();
    notifyListeners();
    return true;
  }
}
