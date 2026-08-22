// End-to-end test of online play against a REAL running server.
//
// Drives the actual client code — OnlineApi and RelayLink — through the
// actual PHP backend: two accounts register, befriend each other, one
// invites the other, and then both ends exchange the real game protocol
// over the relay and check every message arrives, in order, on the other
// side.
//
// SKIPS ITSELF when no server is reachable, so `flutter test` stays green
// on a machine with Apache and MySQL switched off. Point it somewhere
// else with:
//
//   flutter test --dart-define=BBZ_SERVER=http://host/path/server
//
import 'package:battleship_blitz/services/online_api.dart';
import 'package:battleship_blitz/services/relay_link.dart';
import 'package:battleship_blitz/services/server_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

const _serverUrl = String.fromEnvironment(
  'BBZ_SERVER',
  defaultValue: 'http://localhost/Battle-Ship-Blitz-Mobile-Game/server',
);

Future<bool> _serverUp() async {
  try {
    final api = OnlineApi()..baseUrl = _serverUrl;
    await api.call('ping',
        authed: false, timeout: const Duration(seconds: 3));
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  late bool up;

  setUpAll(() async {
    up = await _serverUp();
    if (!up) {
      // ignore: avoid_print
      print('online relay tests skipped — no server at $_serverUrl');
    }
  });

  group('online play, end to end', () {
    late OnlineApi alice;
    late OnlineApi bob;
    late int aliceId;
    late int bobId;
    late int matchId;

    setUp(() async {
      if (!up) return;
      alice = OnlineApi()..baseUrl = _serverUrl;
      bob = OnlineApi()..baseUrl = _serverUrl;

      final a = await alice
          .call('register', args: {'name': 'Test Alice'}, authed: false);
      final b = await bob
          .call('register', args: {'name': 'Test Bob'}, authed: false);
      alice.token = a['token'] as String;
      bob.token = b['token'] as String;
      aliceId = (a['id'] as num).toInt();
      bobId = (b['id'] as num).toInt();

      // Befriend, invite, accept — the whole lobby path, because a match
      // id is only obtainable by walking it.
      await alice.call('request', args: {'tag': b['tag']});
      await bob.call('respond', args: {'playerId': aliceId, 'accept': true});
      final inv = await alice.call('invite', args: {'playerId': bobId});
      matchId = (inv['matchId'] as num).toInt();
      await bob
          .call('invite_respond', args: {'matchId': matchId, 'accept': true});
    });

    test('friends see each other with live stats and presence', () async {
      if (!up) return;
      final poll = await alice.call('poll');
      final friends = poll['friends'] as List;
      expect(friends, hasLength(1));
      final bobRow = friends.first as Map;
      expect(bobRow['name'], 'Test Bob');
      expect(bobRow['online'], isTrue);
      expect(bobRow['rp'], 1000);
    });

    test('the inviter hosts, and so takes the red fleet', () async {
      if (!up) return;
      final a = await alice.call('poll');
      final b = await bob.call('poll');
      expect((a['match'] as Map)['youAreHost'], isTrue);
      expect((b['match'] as Map)['youAreHost'], isFalse);
      expect((a['match'] as Map)['status'], 'active');
    });

    test('synced stats show up on the friend\'s side', () async {
      if (!up) return;
      await bob.call('sync', args: {
        'name': 'Admiral Bob',
        'rp': 1850,
        'wins': 12,
        'losses': 3,
        'bestStreak': 5,
        'ship': 'arctic',
        'shipChosen': true,
        'cannon': 'phantom',
        'theme': 'deep',
      });
      final poll = await alice.call('poll');
      final bobRow = (poll['friends'] as List).first as Map;
      expect(bobRow['name'], 'Admiral Bob');
      expect(bobRow['rp'], 1850);
      expect(bobRow['wins'], 12);
      expect(bobRow['ship'], 'arctic');
      // The flag that decides whether they sail their skin or their side
      // colour has to survive the trip — see fleet_identity.dart.
      expect(bobRow['shipChosen'], isTrue);
    });

    test('the relay carries the game protocol both ways', () async {
      if (!up) return;
      final aIn = <Map<String, dynamic>>[];
      final bIn = <Map<String, dynamic>>[];
      final aLink = RelayLink(api: alice, matchId: matchId);
      final bLink = RelayLink(api: bob, matchId: matchId);
      aLink.messages.listen(aIn.add);
      bLink.messages.listen(bIn.add);

      aLink.send({'type': 'hello', 'name': 'Test Alice', 'ship': 'crimson'});
      bLink.send({'type': 'hello', 'name': 'Test Bob', 'ship': 'steel'});
      await _until(() => aIn.isNotEmpty && bIn.isNotEmpty);

      expect(aIn.first['name'], 'Test Bob');
      expect(bIn.first['name'], 'Test Alice');
      // The loadout rides along with the greeting, which is how each
      // device knows what to paint the other fleet in.
      expect(aIn.first['ship'], 'steel');
      expect(bIn.first['ship'], 'crimson');

      await aLink.close();
      await bLink.close();
    });

    test('a burst of shots arrives complete and in order', () async {
      if (!up) return;
      // The ordering guarantee a socket gives for free and the relay's
      // outbox has to reproduce: eight sends in one tick, no awaits.
      final bIn = <Map<String, dynamic>>[];
      final aLink = RelayLink(api: alice, matchId: matchId);
      final bLink = RelayLink(api: bob, matchId: matchId);
      bLink.messages.listen(bIn.add);

      for (var i = 0; i < 8; i++) {
        aLink.send({'type': 'fire', 'r': i, 'c': i * 2});
      }
      await _until(() => bIn.length >= 8);

      expect(bIn, hasLength(8));
      for (var i = 0; i < 8; i++) {
        expect(bIn[i]['r'], i);
        expect(bIn[i]['c'], i * 2);
      }

      await aLink.close();
      await bLink.close();
    });

    test('a full resume snapshot survives the round trip', () async {
      if (!up) return;
      // The largest thing the protocol ever sends — a reconnecting player
      // gets the whole match state in one message.
      final aIn = <Map<String, dynamic>>[];
      final aLink = RelayLink(api: alice, matchId: matchId);
      final bLink = RelayLink(api: bob, matchId: matchId);
      aLink.messages.listen(aIn.add);

      bLink.send({
        'type': 'resume',
        'youAreHost': true,
        'yourTurn': false,
        'log': List.generate(60, (i) => 'shell $i splashed down'),
        'myBoard': {
          'ships': List.generate(
              5, (i) => {'k': i, 'r': i, 'c': 0, 'h': true, 'x': [0]}),
          'shots': ['1,1', '2,2'],
        },
      });
      await _until(() => aIn.any((m) => m['type'] == 'resume'));

      final snap = aIn.firstWhere((m) => m['type'] == 'resume');
      expect((snap['log'] as List), hasLength(60));
      expect(((snap['myBoard'] as Map)['ships'] as List), hasLength(5));
      expect(((snap['myBoard'] as Map)['shots'] as List), contains('2,2'));

      await aLink.close();
      await bLink.close();
    });

    test('ending the match closes both links', () async {
      if (!up) return;
      var aClosed = false;
      var bClosed = false;
      final aLink =
          RelayLink(api: alice, matchId: matchId, onClosed: () => aClosed = true);
      final bLink =
          RelayLink(api: bob, matchId: matchId, onClosed: () => bClosed = true);

      await alice.call('match_end', args: {'matchId': matchId});
      await _until(() => aClosed && bClosed,
          timeout: const Duration(seconds: 30));

      expect(aClosed, isTrue, reason: 'host link should have closed');
      expect(bClosed, isTrue, reason: 'guest link should have closed');

      await aLink.close();
      await bLink.close();
    });

    test('a stranger cannot read or write another pair\'s match', () async {
      if (!up) return;
      final mallory = OnlineApi()..baseUrl = _serverUrl;
      final m = await mallory
          .call('register', args: {'name': 'Mallory'}, authed: false);
      mallory.token = m['token'] as String;

      await expectLater(
        mallory.call('relay_poll', args: {'matchId': matchId, 'since': 0}),
        throwsA(isA<OnlineError>()),
      );
      await expectLater(
        mallory.call('relay_send',
            args: {'matchId': matchId, 'lines': ['{"type":"fire"}']}),
        throwsA(isA<OnlineError>()),
      );
    });

    test('you can only invite an actual friend', () async {
      if (!up) return;
      final stranger = OnlineApi()..baseUrl = _serverUrl;
      final s = await stranger
          .call('register', args: {'name': 'Stranger'}, authed: false);
      stranger.token = s['token'] as String;

      await expectLater(
        stranger.call('invite', args: {'playerId': aliceId}),
        throwsA(isA<OnlineError>()),
      );
    });

    test('a bad token is refused', () async {
      if (!up) return;
      final forged = OnlineApi()
        ..baseUrl = _serverUrl
        ..token = 'not-a-real-token';
      await expectLater(
        forged.call('poll'),
        throwsA(isA<OnlineError>()),
      );
    });

    group('matchmaking — find a match, both must accept', () {
      // A searcher left standing in the queue stays "online" for half a
      // minute and would steal the next test's pairing — this suite has
      // been bitten by exactly that. Clear the seats whatever happens.
      Future<void> clearSeats() async {
        for (final api in [alice, bob]) {
          try {
            await api.call('queue_leave');
          } on OnlineError catch (_) {
            // Not queued / nothing to decline — that is fine too.
          }
        }
      }

      setUp(() async {
        if (!up) return;
        await clearSeats();
        await alice.call('match_end', args: {'matchId': matchId});
      });

      tearDown(clearSeats);

      test('one searcher alone just waits', () async {
        if (!up) return;
        final r = await alice.call('queue_join');
        expect(r['searching'], isTrue);
        expect(r['match'], isNull);
        final poll = await alice.call('poll');
        expect(poll['searching'], isTrue);
      });

      test('two searchers pair; the relay opens only on the SECOND yes',
          () async {
        if (!up) return;
        final w = await alice.call('queue_join');
        expect(w['searching'], isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 150));

        final r = await bob.call('queue_join');
        expect(r['searching'], isFalse,
            reason: 'bob should be paired the moment he asks');
        final m = r['match'] as Map;
        expect(m['status'], 'found');
        // Whoever waited first hosts — red fleet, opening shot.
        expect(m['youAreHost'], isFalse);

        final pairingId = (m['id'] as num).toInt();

        // Guard against a stray third captain stealing the pairing: what
        // bob sees must be THE match alice is sitting in.
        final a = await alice.call('poll');
        expect(a['searching'], isFalse);
        expect((a['match'] as Map)['status'], 'found');
        expect((a['match'] as Map)['id'], pairingId);
        expect((a['match'] as Map)['youAreHost'], isTrue);

        // One yes alone must NOT open the relay.
        final first =
            await alice.call('accept_match', args: {'matchId': pairingId});
        expect(first['status'], 'found');

        final bMid = await bob.call('poll');
        expect((bMid['match'] as Map)['peerAccepted'], isTrue);
        expect((bMid['match'] as Map)['youAccepted'], isFalse);

        // ...the second one does, for both players.
        final second =
            await bob.call('accept_match', args: {'matchId': pairingId});
        expect(second['status'], 'active');

        final aFinal = await alice.call('poll');
        expect((aFinal['match'] as Map)['status'], 'active');
      });

      test('declining releases both players back out of matchmaking',
          () async {
        if (!up) return;
        await alice.call('queue_join');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final r = await bob.call('queue_join');
        final pairingId = ((r['match'] as Map)['id'] as num).toInt();

        // bob says no thanks.
        await bob.call('queue_leave');

        final a = await alice.call('poll');
        expect(a['searching'], isFalse,
            reason: 'pairing took alice out of the queue');
        expect(a['match'], isNull,
            reason: 'the decline dissolved the pairing');
        expect(pairingId, isPositive);
      });
    });

    group('finding captains by name', () {
      // Dedicated accounts whose names are unique per RUN: the database
      // accumulates a "Test Bob" per suite run, and a bare prefix search
      // capped at twelve results cannot be relied on to surface today's.
      late OnlineApi seeker;
      late OnlineApi target;
      late int seekerId;
      late int targetId;
      late String runName;

      setUp(() async {
        if (!up) return;
        final run = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
        runName = run;
        seeker = OnlineApi()..baseUrl = _serverUrl;
        target = OnlineApi()..baseUrl = _serverUrl;

        final s = await seeker
            .call('register', args: {'name': 'Seeker$run'}, authed: false);
        seeker.token = s['token'] as String;
        seekerId = (s['id'] as num).toInt();

        final t = await target.call('register',
            args: {'name': 'Findable$run'}, authed: false);
        target.token = t['token'] as String;
        targetId = (t['id'] as num).toInt();
      });

      test('a name prefix finds the captain', () async {
        if (!up) return;
        // The full per-run prefix: a bare 'Findable' search competes with
        // every Findable… account past suite runs for the twelve slots.
        final r = await seeker.call('find', args: {'q': 'Findable$runName'});
        final players = (r['players'] as List).cast<Map>();
        expect(players.map((p) => p['id']), contains(targetId));
      });

      test('a friend request can be sent straight from a search result',
          () async {
        if (!up) return;
        final r =
            await seeker.call('find', args: {'q': 'Findable$runName'});
        final hit = (r['players'] as List)
            .cast<Map>()
            .firstWhere((p) => p['id'] == targetId);
        await seeker.call('request', args: {'playerId': hit['id']});

        final poll = await target.call('poll');
        expect(
          (poll['incoming'] as List)
              .cast<Map>()
              .map((p) => p['id']),
          contains(seekerId),
        );
      });

      test('an empty search is refused politely', () async {
        if (!up) return;
        await expectLater(
          seeker.call('find', args: {'q': ''}),
          throwsA(isA<OnlineError>()),
        );
      });
    });
  });

  group('server auto-discovery', () {
    test('finds the running server with nothing to go on', () async {
      if (!up) return;
      final found = await ServerDiscovery().discover();
      expect(found, isNotNull);
      // Whichever alias answered (localhost, 127.0.0.1, …), what matters
      // is that it genuinely speaks this game's protocol.
      final api = OnlineApi()..baseUrl = found!;
      await api.call('ping', authed: false);
    });

    test('a stale remembered address does not stick — the real '
        'server is still found behind it', () async {
      if (!up) return;
      final found = await ServerDiscovery()
          .discover(known: 'http://127.0.0.1/definitely-not-here');
      expect(found, isNotNull);
      expect(found, isNot(contains('/definitely-not-here')));
      final api = OnlineApi()..baseUrl = found!;
      await api.call('ping', authed: false);
    });
  });
}

/// Polls [condition] until it holds or the timeout lapses — so a fast
/// server isn't waited on needlessly and a slow one still gets its chance.
Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
