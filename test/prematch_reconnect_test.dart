// PRE-BATTLE RECONNECT — a dropped opponent during the mode VOTE or the
// DEPLOY screen gets the same "lost connection" grace window a mid-battle
// drop does, and a returning player is told where the match stands (the
// VOTE screen still up, or DEPLOY with the locked mode) so they can walk
// back into the same state instead of a fresh lobby join.
//
// `NetworkService.preMatch` (set by `LanModeScreen`/`PlacementScreen` via
// `beginPreMatch`) is what makes `_openGraceWindow` treat a drop here as
// real as a mid-battle one; the `'prematch'` message (built by
// `_preMatchSignalPayload`, read back via `takePreMatchSignal`) is what
// tells the returner which screen to rebuild. Both are pure `NetworkService`
// state — this file drives them directly with `handleIncomingForTest`,
// the same level `reconnect_test.dart` covers the mid-battle grace window
// at.
import 'package:flutter_test/flutter_test.dart';

import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/network_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    NetworkService.graceTickIntervalForTest = const Duration(seconds: 1);
  });

  group('a drop on the vote/deploy screen opens the same grace window', () {
    test('preMatch alone is enough — inMatch is never set here', () {
      final net = NetworkService();
      net.beginPreMatch();
      expect(net.preMatch, isTrue);
      expect(net.inMatch, isFalse);

      net.openGraceWindowForTest();
      expect(net.peerLost, isTrue,
          reason: 'the vote/deploy screens are a real match too');
      expect(net.graceSecondsLeft, NetworkService.kReconnectGraceSeconds);
    });

    test('neither flag set is still a no-op, same as an ordinary failed '
        'lobby attempt', () {
      final net = NetworkService();
      net.openGraceWindowForTest();
      expect(net.peerLost, isFalse);
    });
  });

  group('the survivor tells a returner where the match stands', () {
    test('mid-VOTE: stage is "vote", no mode', () async {
      final net = NetworkService();
      net.setMatchHost(true);
      net.beginPreMatch();
      net.openGraceWindowForTest();
      expect(net.lockedMode, isNull, reason: 'still voting');

      net.handleIncomingForTest(
          {'type': 'hello', 'name': 'Returner', 'rejoin': 1});
      await pumpEventQueue();

      expect(net.peerLost, isFalse, reason: 'the rejoin closed the window');
      final sent = net.sentForTest.where((m) => m['type'] == 'prematch');
      expect(sent, hasLength(1));
      expect(sent.single['stage'], 'vote');
      expect(sent.single['mode'], isNull);
      expect(sent.single['host'], isTrue);
    });

    test('mid-DEPLOY: stage is "deploy", carries the locked mode', () async {
      final net = NetworkService();
      net.setMatchHost(false); // the joiner can hold the seat too
      net.beginPreMatch();
      net.lockedMode = LanBattleMode.blitz; // the vote already resolved
      net.openGraceWindowForTest();

      net.handleIncomingForTest(
          {'type': 'hello', 'name': 'Returner', 'rejoin': 1});
      await pumpEventQueue();

      final sent = net.sentForTest.where((m) => m['type'] == 'prematch');
      expect(sent, hasLength(1));
      expect(sent.single['stage'], 'deploy');
      expect(sent.single['mode'], LanBattleMode.blitz.index);
      expect(sent.single['host'], isFalse,
          reason: 'the survivor tells the returner their OWN role, so the '
              'returner can restore the opposite one');
    });

    test('a rejoin mid-vote re-broadcasts our own pick, so the returner\'s '
        'peerVote is current the instant they land', () async {
      final net = NetworkService();
      net.setMatchHost(true);
      net.beginPreMatch();
      net.castVote(LanBattleMode.rearrange);
      net.sentForTest.clear();
      net.openGraceWindowForTest();

      net.handleIncomingForTest(
          {'type': 'hello', 'name': 'Returner', 'rejoin': 1});
      await pumpEventQueue();

      final votes = net.sentForTest.where((m) => m['type'] == 'vote');
      expect(votes, hasLength(1));
      expect(votes.single['m'], LanBattleMode.rearrange.index);
    });

    test('once locked, a rejoin does NOT re-send a vote — there is '
        'nothing left to agree on', () async {
      final net = NetworkService();
      net.setMatchHost(true);
      net.beginPreMatch();
      net.castVote(LanBattleMode.rearrange);
      net.lockedMode = LanBattleMode.rearrange;
      net.sentForTest.clear();
      net.openGraceWindowForTest();

      net.handleIncomingForTest(
          {'type': 'hello', 'name': 'Returner', 'rejoin': 1});
      await pumpEventQueue();

      expect(net.sentForTest.where((m) => m['type'] == 'vote'), isEmpty);
    });
  });

  group('the returning side: takePreMatchSignal', () {
    test('a "prematch" message is only accepted while genuinely rejoining',
        () async {
      final net = NetworkService();
      net.joiningResumable = true;

      net.handleIncomingForTest(
          {'type': 'prematch', 'stage': 'deploy', 'host': true, 'mode': 2});
      await pumpEventQueue();

      final signal = net.takePreMatchSignal();
      expect(signal, isNotNull);
      expect(signal!['stage'], 'deploy');
      expect(signal['host'], isTrue);
      expect(signal['mode'], 2);
      expect(net.joiningResumable, isFalse,
          reason: 'consumed — a stray duplicate must not re-trigger this');
    });

    test('taking it clears it — a second read gets nothing', () async {
      final net = NetworkService();
      net.joiningResumable = true;
      net.handleIncomingForTest(
          {'type': 'prematch', 'stage': 'vote', 'host': false});
      await pumpEventQueue();

      expect(net.takePreMatchSignal(), isNotNull);
      expect(net.takePreMatchSignal(), isNull);
    });

    test('ignored outside a genuine rejoin — a stray message cannot '
        'hijack a brand-new lobby join', () async {
      final net = NetworkService();
      net.joiningResumable = false; // an ordinary fresh join

      net.handleIncomingForTest(
          {'type': 'prematch', 'stage': 'deploy', 'host': true, 'mode': 0});
      await pumpEventQueue();

      expect(net.takePreMatchSignal(), isNull);
    });
  });

  group('giving up: the seat is released like any other abandoned match',
      () {
    test('the grace window fully expiring during vote/deploy sets '
        'peerGone', () async {
      NetworkService.graceTickIntervalForTest = Duration.zero;
      final net = NetworkService();
      net.beginPreMatch();
      net.openGraceWindowForTest();

      await Future<void>.delayed(const Duration(seconds: 3));
      expect(net.peerGone, isTrue);
      expect(net.peerLost, isFalse);
    });
  });
}
