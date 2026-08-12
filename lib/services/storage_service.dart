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
  ];

  static ShipSkin shipById(String id) =>
      shipSkins.firstWhere((s) => s.id == id, orElse: () => shipSkins.first);

  static CannonSkin cannonById(String id) =>
      cannonSkins.firstWhere((c) => c.id == id, orElse: () => cannonSkins.first);
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
  Set<String> owned = {'steel', 'mk1'};

  ShipSkin get shipSkin => Catalog.shipById(shipSkinId);
  CannonSkin get cannonSkin => Catalog.cannonById(cannonSkinId);

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
    owned = (p.getStringList(_kOwned) ?? ['steel', 'mk1']).toSet();
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
}
