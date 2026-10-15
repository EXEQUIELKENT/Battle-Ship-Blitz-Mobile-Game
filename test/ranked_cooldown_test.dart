import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<GameController> _controller(GameMode mode) async {
  SharedPreferences.setMockInitialValues({});
  final profile = ProfileStore();
  await profile.load();
  profile.cannonSkinId = 'phantom'; // 0.85 factor — the pay-to-win case
  final c = GameController(profile: profile, network: NetworkService());
  c.mode = mode;
  if (mode == GameMode.hotspot || mode == GameMode.online) {
    c.lanBattleMode = LanBattleMode.turns;
  }
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('effectiveCooldownFactor: ranked is always standard', () {
    const gun = CannonSkin('x', 'X', Color(0xFF000000), Color(0xFFFFFFFF),
        'd', 0.85, 0);
    expect(gun.effectiveCooldownFactor(ranked: true), 1.0);
    expect(gun.effectiveCooldownFactor(ranked: false), 0.85);
  });

  test('ranked battle normalizes a bought fast cannon', () async {
    final c = await _controller(GameMode.hotspot);
    expect(c.isRankedBattle, isTrue);
    c.beginBattle(enemyBoard: Board()..place(kFleet.first, 9, 5, true));
    expect(c.cooldownMax1, kCooldownSeconds.toDouble());
    c.dispose();
  });

  test('online battle normalizes too', () async {
    final c = await _controller(GameMode.online);
    expect(c.isRankedBattle, isTrue);
    c.beginBattle(enemyBoard: Board()..place(kFleet.first, 9, 5, true));
    expect(c.cooldownMax1, kCooldownSeconds.toDouble());
    c.dispose();
  });

  test('casual vs-AI keeps the skin perk', () async {
    final c = await _controller(GameMode.vsAI);
    expect(c.isRankedBattle, isFalse);
    c.beginBattle(enemyBoard: Board()..place(kFleet.first, 9, 5, true));
    expect(c.cooldownMax1,
        closeTo(kCooldownSeconds * 0.85, 0.0001));
    c.dispose();
  });

  test('local pass-and-play keeps per-seat perks', () async {
    final c = await _controller(GameMode.local);
    c.resetLocalLoadouts();
    c.setLocalLoadout(0, const Loadout(cannonSkinId: 'phantom'));
    c.setLocalLoadout(1, const Loadout(cannonSkinId: 'mk1'));
    c.beginBattle(enemyBoard: Board()..place(kFleet.first, 9, 5, true));
    expect(c.cooldownMax1, closeTo(kCooldownSeconds * 0.85, 0.0001));
    expect(c.cooldownMax2, kCooldownSeconds.toDouble());
    c.dispose();
  });
}
