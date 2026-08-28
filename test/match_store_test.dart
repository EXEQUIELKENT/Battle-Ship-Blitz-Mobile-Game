import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/match_store.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';

Future<GameController> _newHotspotController({bool host = true}) async {
  final profile = ProfileStore();
  await profile.load();
  final net = NetworkService();
  net.setMatchHost(host);
  net.mode = NetMode.hotspot;
  final c = GameController(profile: profile, network: net);
  c.mode = GameMode.hotspot; // GameController.hasRemotePeer keys off THIS
  return c;
}

/// A harmless, out-of-the-way enemy fleet — an empty `Board()` is a trap
/// for `Board.allSunk` (vacuously true), which would immediately end the
/// match the instant any hit registers.
Board _harmlessEnemyBoard() => Board()..place(kFleet.first, 9, 5, true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<MatchStore> newStore() async {
    final store = MatchStore();
    await store.load();
    return store;
  }

  group('MatchStore — nothing saved yet', () {
    test('saved is null before anything writes', () async {
      final store = await newStore();
      expect(store.saved, isNull);
    });
  });

  group('MatchStore — the cadence', () {
    test('beginBattle triggers an immediate flush, no debounce wait',
        () async {
      final store = await newStore();
      final c = await _newHotspotController();
      store.attach(c, c.network);

      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      // `flushNow()` itself is async (a real `SharedPreferences` write),
      // fired off with `unawaited` from the listener — one microtask is
      // enough for a MOCKED store, but it is still a real await, not
      // something that lands synchronously inside `notifyListeners`.
      await pumpEventQueue();

      final saved = store.saved;
      expect(saved, isNotNull);
      expect(saved!['transport'], NetMode.hotspot.index);
      expect(saved['iAmHost'], isTrue);
    });

    test('a plain notifyListeners with nothing meaningfully changed does '
        'not write', () async {
      final store = await newStore();
      final c = await _newHotspotController();
      store.attach(c, c.network);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      await pumpEventQueue();
      final firstSavedAt = store.saved!['savedAt'];

      // `cooldownTick` changes constantly and deliberately does NOT call
      // notifyListeners (see its own doc) — but even a a bare touch()
      // with stateSeq/peerHasTurn unchanged must not re-trigger a write.
      c.touch();
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(store.saved!['savedAt'], firstSavedAt,
          reason: 'nothing that matters actually changed');
    });

    test('a shot fired writes after the debounce, not before', () async {
      final store = await newStore();
      final c = await _newHotspotController();
      store.attach(c, c.network);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      await pumpEventQueue();
      final afterBegin = store.saved!['savedAt'];

      c.attachNetwork();
      // The outgoing 'fire' alone bumps nothing — `stateSeq` only moves
      // once `_registerShot` runs, which happens for OUR OWN shot when
      // its 'result' comes back. There is no real peer here to echo one,
      // so it's fed in directly — the same level `ghost_mode_test.dart`/
      // `power_play_test.dart` already drive this protocol at.
      c.network.handleIncomingForTest(
          {'type': 'result', 'r': 0, 'c': 0, 'res': ShotResult.miss.index});
      await pumpEventQueue();

      // Immediately after the result lands, still within the debounce
      // window.
      expect(store.saved!['savedAt'], afterBegin,
          reason: 'the 1.5s debounce has not elapsed yet');

      await Future<void>.delayed(const Duration(milliseconds: 1700));
      expect(store.saved!['savedAt'], isNot(afterBegin),
          reason: 'the debounced write must have landed by now');
    });

    test('finishing the match clears the save', () async {
      final store = await newStore();
      final c = await _newHotspotController();
      store.attach(c, c.network);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      await pumpEventQueue();
      expect(store.saved, isNotNull);

      c.abandonMatch();
      await pumpEventQueue();
      expect(store.saved, isNull);
    });
  });

  group('MatchStore — only ever for a real remote peer', () {
    test('a vs-AI match is never persisted', () async {
      final store = await newStore();
      final profile = ProfileStore();
      await profile.load();
      final c = GameController(profile: profile, network: NetworkService());
      c.mode = GameMode.vsAI;
      store.attach(c, c.network);

      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      await pumpEventQueue();

      expect(store.saved, isNull);
    });

    test('detach stops writing anything further', () async {
      final store = await newStore();
      final c = await _newHotspotController();
      store.attach(c, c.network);
      c.boards[0] = Board()..place(kFleet.last, 0, 0, true);
      c.beginBattle(enemyBoard: _harmlessEnemyBoard());
      await pumpEventQueue();
      expect(store.saved, isNotNull);

      await store.clear();
      store.detach();
      c.attachNetwork();
      c.network.handleIncomingForTest(
          {'type': 'result', 'r': 1, 'c': 1, 'res': ShotResult.miss.index});
      await Future<void>.delayed(const Duration(milliseconds: 1700));

      expect(store.saved, isNull,
          reason: 'a detached store must not react to further changes');
    });
  });

  group('MatchStore — staleness', () {
    test('an old hotspot save reads as absent', () async {
      SharedPreferences.setMockInitialValues({
        'match.saved': '''
        {"transport": ${NetMode.hotspot.index}, "iAmHost": true,
         "savedAt": ${DateTime.now().subtract(const Duration(hours: 3)).millisecondsSinceEpoch}}
        ''',
      });
      final store = await newStore();
      expect(store.saved, isNull,
          reason: 'older than kHotspotStaleAfter (2h)');
    });

    test('the same age is still fine for an online save', () async {
      SharedPreferences.setMockInitialValues({
        'match.saved': '''
        {"transport": ${NetMode.online.index}, "iAmHost": true,
         "savedAt": ${DateTime.now().subtract(const Duration(hours: 3)).millisecondsSinceEpoch}}
        ''',
      });
      final store = await newStore();
      expect(store.saved, isNotNull,
          reason: 'well under kOnlineStaleAfter (24h)');
    });

    test('a corrupt saved value is treated as absent, not a crash', () async {
      SharedPreferences.setMockInitialValues({'match.saved': 'not json {{{'});
      final store = await newStore();
      expect(store.saved, isNull);
    });
  });
}
