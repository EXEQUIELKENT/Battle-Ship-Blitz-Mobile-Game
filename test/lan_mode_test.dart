import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/game_controller.dart';
import 'package:battleship_blitz/services/network_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';

/// Coverage for the LAN pre-match game-mode vote and the match-shape flags
/// it feeds. The vote's whole job is to leave BOTH devices in the same
/// mode, so the rules that guard that — a vote can be changed right up
/// until it locks, and never after — are what's pinned down here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LAN game-mode vote', () {
    test('casting a vote records it and leaves the peer slot alone', () {
      final net = NetworkService();
      expect(net.myVote, isNull);
      expect(net.bothVoted, isFalse);

      var notifications = 0;
      net.addListener(() => notifications++);

      net.castVote(LanBattleMode.chaos);
      expect(net.myVote, LanBattleMode.chaos);
      expect(net.peerVote, isNull);
      expect(net.bothVoted, isFalse);
      expect(notifications, 1);
    });

    test('a player can change their pick, and re-tapping it is a no-op', () {
      final net = NetworkService();
      var notifications = 0;
      net.addListener(() => notifications++);

      net.castVote(LanBattleMode.turns);
      net.castVote(LanBattleMode.chaos); // changed their mind
      expect(net.myVote, LanBattleMode.chaos);
      expect(notifications, 2);

      // Tapping the mode you already picked must not churn the wire or
      // the UI — it's the same vote.
      net.castVote(LanBattleMode.chaos);
      expect(net.myVote, LanBattleMode.chaos);
      expect(notifications, 2);
    });

    test('votes are frozen once the mode has locked in', () {
      final net = NetworkService();
      net.castVote(LanBattleMode.turns);
      net.lockedMode = LanBattleMode.turns;

      // Past this point the peer has already been told which mode the
      // match is in, so a late vote change here would put the two devices
      // into DIFFERENT modes.
      net.castVote(LanBattleMode.chaos);
      expect(net.myVote, LanBattleMode.turns);
      expect(net.lockedMode, LanBattleMode.turns);
    });

    test('bothVoted only once both sides have picked', () {
      final net = NetworkService();
      expect(net.bothVoted, isFalse);
      net.castVote(LanBattleMode.chaos);
      expect(net.bothVoted, isFalse);
      net.peerVote = LanBattleMode.turns;
      expect(net.bothVoted, isTrue);
    });

    test('resetLanVote clears everything so picks cannot leak forward', () {
      final net = NetworkService();
      net.castVote(LanBattleMode.chaos);
      net.peerVote = LanBattleMode.chaos;
      net.voteCountdown = 3;
      net.lockedMode = LanBattleMode.chaos;

      net.resetLanVote();
      expect(net.myVote, isNull);
      expect(net.peerVote, isNull);
      expect(net.voteCountdown, isNull);
      expect(net.lockedMode, isNull);
    });
  });

  _resumeTests();
  _manoeuvreTests();

  group('chaos-mode flag', () {
    Future<GameController> newController() async {
      SharedPreferences.setMockInitialValues({});
      final profile = ProfileStore();
      await profile.load();
      return GameController(profile: profile, network: NetworkService());
    }

    test('defaults to turn-based', () async {
      final controller = await newController();
      expect(controller.lanBattleMode, LanBattleMode.turns);
      expect(controller.isChaosBattle, isFalse);
    });

    test('only network matches can be chaos matches', () async {
      final controller = await newController();
      controller.lanBattleMode = LanBattleMode.chaos;

      // The vote only exists in LAN play, so a stale chaos pick must never
      // leak into a vs-AI or pass-and-play match and switch off their turn
      // order.
      controller.mode = GameMode.vsAI;
      expect(controller.isChaosBattle, isFalse);
      controller.mode = GameMode.local;
      expect(controller.isChaosBattle, isFalse);

      controller.mode = GameMode.hotspot;
      expect(controller.isChaosBattle, isTrue);
      controller.mode = GameMode.online;
      expect(controller.isChaosBattle, isTrue);

      controller.lanBattleMode = LanBattleMode.turns;
      expect(controller.isChaosBattle, isFalse);
    });

    test('BLITZ is chaos AND manoeuvre, not a third thing', () async {
      // The mode is defined as its two parents combined, so the test is
      // that it behaves as both — no turn order, and hulls can still run.
      // Anything that special-cased CHAOS or MANOEUVRE by name rather
      // than by property would fail exactly one of these.
      final controller = await newController();
      controller.mode = GameMode.hotspot;

      controller.lanBattleMode = LanBattleMode.blitz;
      expect(controller.isChaosBattle, isTrue);
      expect(controller.isManoeuvreBattle, isTrue);

      controller.lanBattleMode = LanBattleMode.chaos;
      expect(controller.isChaosBattle, isTrue);
      expect(controller.isManoeuvreBattle, isFalse);

      controller.lanBattleMode = LanBattleMode.rearrange;
      expect(controller.isChaosBattle, isFalse);
      expect(controller.isManoeuvreBattle, isTrue);

      controller.lanBattleMode = LanBattleMode.turns;
      expect(controller.isChaosBattle, isFalse);
      expect(controller.isManoeuvreBattle, isFalse);
    });

    test('BLITZ never leaks into a non-network match', () async {
      final controller = await newController();
      controller.lanBattleMode = LanBattleMode.blitz;
      for (final mode in [GameMode.vsAI, GameMode.local]) {
        controller.mode = mode;
        expect(controller.isChaosBattle, isFalse);
        expect(controller.isManoeuvreBattle, isFalse);
      }
    });

    test('every mode has its own label, tagline and blurb', () {
      // Two modes sharing a description is the failure that made
      // MANOEUVRE and TURN BASED read as the same card, and BLITZ sits
      // between two existing modes so it is the likeliest to be
      // described as one of them by accident.
      final labels = LanBattleMode.values.map((m) => m.label).toSet();
      final taglines = LanBattleMode.values.map((m) => m.tagline).toSet();
      final blurbs = LanBattleMode.values.map((m) => m.blurb).toSet();
      expect(labels.length, LanBattleMode.values.length);
      expect(taglines.length, LanBattleMode.values.length);
      expect(blurbs.length, LanBattleMode.values.length);
    });

    test('mode indices are stable, because they go over the wire', () {
      // A vote and a resume snapshot both send `LanBattleMode.index`. If
      // a new mode were inserted rather than appended, an in-flight match
      // against an older build would silently change rules.
      expect(LanBattleMode.chaos.index, 0);
      expect(LanBattleMode.turns.index, 1);
      expect(LanBattleMode.rearrange.index, 2);
      expect(LanBattleMode.blitz.index, 3);
      expect(LanBattleMode.ghost.index, 4);
      expect(LanBattleMode.powerPlay.index, 5);
      expect(LanBattleMode.phantom.index, 6);
    });
  });

  group('match chat', () {
    test('a sent line is kept locally and counts as read', () {
      final net = NetworkService();
      net.sendChat('  taking the left flank  ');
      expect(net.chat, hasLength(1));
      expect(net.chat.single.text, 'taking the left flank');
      expect(net.chat.single.mine, isTrue);
      // Your own message is not something you need told about.
      expect(net.unreadChat, 0);
    });

    test('blank messages are not sent', () {
      final net = NetworkService();
      net.sendChat('   ');
      net.sendChat('');
      expect(net.chat, isEmpty);
    });

    test('an over-long line is capped rather than refused', () {
      final net = NetworkService();
      net.sendChat('x' * 500);
      expect(net.chat.single.text.length, NetworkService.kChatMaxChars);
    });

    test('the log is bounded, oldest dropped first', () {
      final net = NetworkService();
      for (var i = 0; i < NetworkService.kChatMaxLines + 20; i++) {
        net.sendChat('line $i');
      }
      expect(net.chat, hasLength(NetworkService.kChatMaxLines));
      expect(net.chat.last.text, 'line ${NetworkService.kChatMaxLines + 19}');
      // The first twenty are gone, not the newest twenty.
      expect(net.chat.first.text, 'line 20');
    });

    test('unread counts only the opponent, and clears on read', () {
      final net = NetworkService();
      net.handleIncomingForTest({'type': 'chat', 'm': 'hello'});
      net.handleIncomingForTest({'type': 'chat', 'm': 'ready?'});
      net.sendChat('one moment');
      expect(net.unreadChat, 2);
      net.markChatRead();
      expect(net.unreadChat, 0);
    });

    test('an over-long line from the peer is capped on arrival too', () {
      // Length is enforced at the sender, but the sender is the other
      // device — not something to take on trust.
      final net = NetworkService();
      net.handleIncomingForTest({'type': 'chat', 'm': 'y' * 9000});
      expect(net.chat.single.text.length, NetworkService.kChatMaxChars);
    });

    test('an empty line from the peer is dropped', () {
      final net = NetworkService();
      net.handleIncomingForTest({'type': 'chat', 'm': '   '});
      net.handleIncomingForTest({'type': 'chat'});
      expect(net.chat, isEmpty);
      expect(net.unreadChat, 0);
    });

    test('stopping clears the conversation', () async {
      // A chat log that survived into the next match would show one
      // opponent's words under another opponent's name.
      final net = NetworkService();
      net.sendChat('gg');
      await net.stop();
      expect(net.chat, isEmpty);
      expect(net.unreadChat, 0);
    });
  });
}

/// The reconnect path: a player who drops mid-match gets a snapshot from
/// the survivor and has to come back to the SAME position — same fleets,
/// same damage, same shot history, same side, same turn. Anything less
/// and reconnecting is worse than not reconnecting at all.
void _resumeTests() {
  Future<GameController> newController({bool host = false}) async {
    SharedPreferences.setMockInitialValues({});
    final profile = ProfileStore();
    await profile.load();
    final net = NetworkService();
    net.setMatchHost(host);
    final c = GameController(profile: profile, network: net);
    c.mode = GameMode.hotspot;
    c.lanBattleMode = LanBattleMode.turns;
    return c;
  }

  group('resume snapshot', () {
    test('restores fleets, damage, shot history, side and turn', () async {
      // ---- The surviving player's match state ----
      final survivor = await newController(host: true);
      final own = Board()
        ..place(kFleet[4], 0, 0, true) // destroyer, 2 cells at (0,0)-(0,1)
        ..place(kFleet[2], 5, 5, false); // cruiser, 3 cells down from (5,5)
      final theirs = Board()
        ..place(kFleet[4], 9, 8, true)
        ..place(kFleet[2], 2, 2, false);
      survivor.boards[0] = own;
      survivor.beginBattle(enemyBoard: theirs);

      // Survivor lands a hit and a miss on the opponent.
      survivor.myShots[2][2] = 2; // hit on their cruiser
      survivor.myShots[7][1] = 1; // miss
      // Opponent has sunk the survivor's destroyer and missed once.
      survivor.boards[0].receiveShot(0, 0);
      survivor.boards[0].receiveShot(0, 1);
      survivor.boards[0].receiveShot(4, 4);
      survivor.p2Shots[0][0] = 2;
      survivor.p2Shots[0][1] = 2;
      survivor.p2Shots[4][4] = 1;
      survivor.peerHasTurn = true; // it was the returning player's turn

      final snapshot = survivor.buildResumeSnapshot();

      // ---- The returning player rebuilds from it ----
      final returner = await newController();
      returner.network.setMatchHost(snapshot['youAreHost'] == true);
      returner.restoreFromSnapshot(snapshot);

      // Side and rules survived the round trip.
      expect(returner.network.isHost, isFalse,
          reason: 'survivor was the host, so the returner is the joiner');
      expect(returner.lanBattleMode, LanBattleMode.turns);
      expect(returner.phase, BattlePhase.battling);

      // Their own fleet is back, with the damage the survivor recorded.
      final myDestroyer = returner.boards[0].shipOfKind(ShipKind.destroyer);
      final myCruiser = returner.boards[0].shipOfKind(ShipKind.cruiser);
      expect(myDestroyer, isNotNull);
      expect(myDestroyer!.row, 9);
      expect(myDestroyer.col, 8);
      expect(myCruiser!.hitIndices, {0},
          reason: 'the survivor hit their cruiser once, at its first cell');

      // The enemy fleet is back, with ITS damage.
      final enemyDestroyer = returner.boards[1].shipOfKind(ShipKind.destroyer);
      expect(enemyDestroyer!.isSunk, isTrue,
          reason: 'they had sunk the survivor\'s destroyer before dropping');

      // Shot grids are mirrored: what the survivor fired is what the
      // returner has taken, and vice versa.
      expect(returner.myShots[0][0], 2);
      expect(returner.myShots[4][4], 1);
      expect(returner.p2Shots[2][2], 2);
      expect(returner.p2Shots[7][1], 1);

      // Cells already fired at stay off-limits for a fresh shot.
      expect(returner.boards[0].alreadyShot(2, 2), isTrue);
      expect(returner.boards[1].alreadyShot(0, 0), isTrue);

      // The turn came back to the right player.
      expect(returner.peerHasTurn, isFalse,
          reason: 'the survivor recorded it as the returner\'s turn');

      // Every past shot shows as an already-landed marker rather than
      // replaying a match worth of cannon fire.
      expect(returner.events, isNotEmpty);
      expect(returner.events.every((e) => e.impactAt != null), isTrue);
      expect(returner.events.length, 5);

      returner.reset();
      survivor.reset();
    });

    test('an abandoned match records no win, no loss and no RP', () async {
      final controller = await newController(host: true);
      final profile = controller.profile;
      final wins = profile.wins;
      final losses = profile.losses;
      final rp = profile.rp;

      controller.boards[0] = Board()..place(kFleet.first, 0, 0, true);
      controller.beginBattle(enemyBoard: Board()..place(kFleet.last, 4, 4, true));
      controller.abandonMatch();

      expect(controller.phase, BattlePhase.finished);
      expect(controller.matchAbandoned, isTrue);
      expect(controller.rpDelta, 0);
      expect(profile.wins, wins);
      expect(profile.losses, losses);
      expect(profile.rp, rp);
      controller.reset();
    });

    // BUGFIX regression: `flipSnapshot`/`restoreFromOwnSnapshot` exist so
    // a device can rehydrate from a snapshot it wrote about ITSELF (see
    // `MatchStore`'s self-persistence path, used when there is no live
    // opponent left to ask for a fresh snapshot). `flipSnapshot` has to
    // be an involution for that to work: flipping the same snapshot
    // twice must return to exactly where it started.
    test('flipSnapshot is an involution', () async {
      final c = await newController(host: true);
      c.boards[0] = Board()..place(kFleet[4], 0, 0, true);
      c.beginBattle(enemyBoard: Board()..place(kFleet[2], 5, 5, true));
      c.myShots[1][1] = 2;
      c.p2Shots[2][2] = 1;
      c.peerHasTurn = true;

      final snapshot = c.buildResumeSnapshot();
      final flippedTwice = c.flipSnapshot(c.flipSnapshot(snapshot));

      for (final key in [
        'yourBoard',
        'myBoard',
        'shotsByYou',
        'shotsByMe',
        'yourTurn',
        'yourFireSeq',
        'yourLastPeerFireSeq',
      ]) {
        expect(flippedTwice[key], snapshot[key],
            reason: 'flipping twice must restore "$key" exactly');
      }
      c.reset();
    });
  });
}

/// MANOEUVRE mode's two rules: damaged hulls are pinned, and no ship may
/// hide in water the enemy has already fired at.
void _manoeuvreTests() {
  group('manoeuvre rules', () {
    test('an undamaged ship can move to clear water', () {
      final b = Board()..place(kFleet[4], 0, 0, true); // destroyer
      expect(b.relocate(ShipKind.destroyer, 5, 5, true), isTrue);
      final ship = b.shipOfKind(ShipKind.destroyer)!;
      expect(ship.row, 5);
      expect(ship.col, 5);
    });

    test('a ship that has been hit is pinned for the rest of the match', () {
      final b = Board()..place(kFleet[4], 0, 0, true);
      b.receiveShot(0, 0); // one hit is enough
      expect(b.canRelocate(b.shipOfKind(ShipKind.destroyer)!), isFalse);
      expect(b.relocate(ShipKind.destroyer, 5, 5, true), isFalse);
      expect(b.shipOfKind(ShipKind.destroyer)!.row, 0,
          reason: 'a rejected move must not disturb the ship');
    });

    test('a ship cannot hide in water already fired at', () {
      final b = Board()..place(kFleet[4], 0, 0, true);
      b.receiveShot(5, 6); // a known miss — that cell is public knowledge
      expect(b.relocate(ShipKind.destroyer, 5, 5, true), isFalse,
          reason: 'the 2-cell hull would cover the known-empty (5,6)');
      expect(b.relocate(ShipKind.destroyer, 5, 7, true), isTrue,
          reason: 'clear of it, the same move is fine');
    });

    test('ships cannot be stacked on each other', () {
      final b = Board()
        ..place(kFleet[4], 0, 0, true)
        ..place(kFleet[2], 4, 4, true);
      expect(b.relocate(ShipKind.destroyer, 4, 4, true), isFalse);
      expect(b.relocate(ShipKind.destroyer, 9, 9, true), isFalse,
          reason: 'a 2-cell hull at column 9 runs off the board');
    });
  });

  // `findNearestRotationAnchor` is the shared search behind BOTH rotate
  // paths — deployment's tap-to-rotate (backed by `Board.canPlace`) and
  // the in-battle version used by MANOEUVRE, BLITZ and (once it exists)
  // GHOST FLEET (backed by `Board.canRelocateTo`, which additionally
  // refuses cells the enemy has already fired at). One set of tests
  // against the pure function, plus the specific `canRelocateTo` shape,
  // covers every mode a rotate can happen in without needing a separate
  // suite per mode.
  group('rotation always finds somewhere to turn', () {
    test('the nearest legal anchor wins, not the first one scanned', () {
      // The search scans row-major (top-left to bottom-right), so a
      // naive "first legal cell" implementation would return (0,0) here
      // even though (4,5) is far closer to where the turn was actually
      // attempted. Two clear cells planted on purpose: one that scans
      // first but is far away, one that scans later but is close.
      final occupied = <String>{
        for (var c = 0; c < 10; c++)
          if (c != 0) '0,$c', // row 0 blocked except the far corner
        for (var r = 1; r < 10; r++)
          for (var c = 0; c < 10; c++)
            if (!(r == 4 && c == 5)) '$r,$c',
      };
      final found = findNearestRotationAnchor(
        size: 1,
        horizontal: true,
        anchorRow: 4,
        anchorCol: 4,
        canPlaceAt: (r, c) => !occupied.contains('$r,$c'),
      );
      expect(found, (row: 4, col: 5));
    });

    test('an exact match at distance zero short-circuits the search', () {
      // The attempted anchor itself is legal — the search must return
      // exactly that spot, not scan past it looking for something
      // "better" (nothing WOULD be, since distance zero is optimal, but
      // this pins the early-exit path rather than just the outcome).
      final found = findNearestRotationAnchor(
        size: 3,
        horizontal: true,
        anchorRow: 2,
        anchorCol: 2,
        canPlaceAt: (r, c) => true,
      );
      expect(found, (row: 2, col: 2));
    });

    test('an orientation longer than the board can hold returns null '
        'immediately', () {
      // Guards the `maxRow < 0 || maxCol < 0` short-circuit — a search
      // that didn't have it would scan a negative range and either loop
      // zero times (harmless here) or, for a hypothetically larger
      // board size mismatch, behave unpredictably. Never reachable with
      // this game's own fleet (nothing is longer than the 10-cell
      // board), but the function is shared and shouldn't assume that.
      final found = findNearestRotationAnchor(
        size: 11,
        horizontal: true,
        anchorRow: 0,
        anchorCol: 0,
        canPlaceAt: (r, c) => true,
      );
      expect(found, isNull);
    });

    test('genuinely nowhere to turn returns null, not a wrong answer', () {
      // Every cell refused — the case that has to fail closed rather
      // than silently returning some anchor `canPlaceAt` never actually
      // approved.
      final found = findNearestRotationAnchor(
        size: 2,
        horizontal: true,
        anchorRow: 5,
        anchorCol: 5,
        canPlaceAt: (r, c) => false,
      );
      expect(found, isNull);
    });

    test('canRelocateTo: a hull rotates around a shot-up late-match board',
        () {
      // The realistic MANOEUVRE/BLITZ shape: the direct anchor is
      // blocked because the enemy has been shooting at that stretch of
      // water, but the rest of the board still has room.
      //
      // The destroyer sits horizontally at (3,3)-(3,4). Turning it
      // vertical at the same anchor would need (3,3) and (4,3) — (3,3)
      // is the ship's OWN current cell, so only (4,3) is shot here:
      // shooting (3,3) instead would hit the ship itself and pin it
      // outright (the separate, already-covered rule), which is not
      // the case this test is for.
      final b = Board()..place(kFleet[4], 3, 3, true); // 2-cell destroyer
      b.receiveShot(4, 3);
      final ship = b.shipOfKind(ShipKind.destroyer)!;
      expect(ship.hitIndices, isEmpty,
          reason: 'the ship itself must still be undamaged for this test');
      expect(b.canRelocateTo(ship, 3, 3, false), isFalse,
          reason: 'the direct vertical anchor needs the shot-up (4,3)');

      final found = findNearestRotationAnchor(
        size: 2,
        horizontal: false,
        anchorRow: 3,
        anchorCol: 3,
        canPlaceAt: (r, c) => b.canRelocateTo(ship, r, c, false),
      );
      expect(found, isNotNull);
      expect(b.canRelocateTo(ship, found!.row, found.col, false), isTrue);
      expect(b.relocate(ShipKind.destroyer, found.row, found.col, false),
          isTrue);
    });

    test(
        'canRelocateTo: null once every legal cell for the orientation '
        'has been fired at — the exact case the "NO ROOM TO TURN" notice '
        'exists for', () {
      // A single undamaged destroyer with the ENTIRE rest of the board
      // shot up: nowhere legally holds either orientation any more.
      final b = Board()..place(kFleet[4], 0, 0, true);
      for (var r = 0; r < 10; r++) {
        for (var c = 0; c < 10; c++) {
          if (r == 0 && (c == 0 || c == 1)) continue; // the ship's own cells
          b.receiveShot(r, c);
        }
      }
      final ship = b.shipOfKind(ShipKind.destroyer)!;
      final found = findNearestRotationAnchor(
        size: 2,
        horizontal: false,
        anchorRow: 0,
        anchorCol: 0,
        canPlaceAt: (r, c) => b.canRelocateTo(ship, r, c, false),
      );
      expect(found, isNull);
      // This is precisely `battle_screen.dart`'s `noRoomToTurn` flag: the
      // direct anchor already failed (asserted above via the shot board)
      // AND the search found nothing either.
      expect(b.canRelocateTo(ship, 0, 0, false), isFalse);
    });
  });

  group('joining by room code', () {
    // Everything `roomByCode` needs is already parsed into `foundRooms` by
    // `scanRooms` — these tests set that list directly rather than binding
    // a real UDP socket, exactly the level `NetworkService`'s own vote
    // tests above operate at.
    test('resolves a code to the room that advertised it', () {
      final net = NetworkService();
      net.foundRooms = const [
        RoomInfo(code: 'WXYZ', host: '192.168.1.5', playerName: 'Kim'),
      ];
      final found = net.roomByCode('wxyz'); // lower-case, as typed
      expect(found?.host, '192.168.1.5');
    });

    test('an unknown code resolves to nothing', () {
      final net = NetworkService();
      net.foundRooms = const [
        RoomInfo(code: 'WXYZ', host: '192.168.1.5', playerName: 'Kim'),
      ];
      expect(net.roomByCode('AAAA'), isNull);
      expect(net.roomByCode(''), isNull);
    });

    test(
        'a host with two interfaces beacons the same code twice — prefer '
        'the address on OUR OWN subnet', () {
      final net = NetworkService();
      net.foundRooms = const [
        RoomInfo(code: 'WXYZ', host: '10.0.0.9', playerName: 'Kim'), // mobile data, unreachable
        RoomInfo(code: 'WXYZ', host: '192.168.43.1', playerName: 'Kim'), // hotspot, reachable
      ];
      final found = net.roomByCode('WXYZ', myIps: const ['192.168.43.7']);
      expect(found?.host, '192.168.43.1');
    });

    test(
        'falls back to the first match when no candidate is on a '
        'reachable subnet', () {
      final net = NetworkService();
      net.foundRooms = const [
        RoomInfo(code: 'WXYZ', host: '10.0.0.9', playerName: 'Kim'),
        RoomInfo(code: 'WXYZ', host: '10.0.0.9', playerName: 'Kim'),
      ];
      final found = net.roomByCode('WXYZ', myIps: const ['192.168.1.2']);
      expect(found?.host, '10.0.0.9');
    });
  });

  group('scanning — folding a beacon into foundRooms', () {
    // Coverage for `NetworkService._ingestRoom` (exercised via
    // `ingestRoomForTest`, mirroring `handleIncomingForTest`): the real
    // beacon parsing lives inside a raw UDP socket listener and isn't
    // reachable from a plain unit test, but the dedupe DECISION it feeds
    // is pulled out into its own method precisely so it can be.
    test('a brand new code is simply added', () {
      final net = NetworkService();
      net.ingestRoomForTest(
          const RoomInfo(code: 'WXYZ', host: '192.168.1.5', playerName: 'Kim'));
      expect(net.foundRooms, hasLength(1));
      expect(net.foundRooms.single.host, '192.168.1.5');
    });

    test('the same host repeating its beacon is not duplicated', () {
      final net = NetworkService();
      net.ingestRoomForTest(
          const RoomInfo(code: 'WXYZ', host: '192.168.1.5', playerName: 'Kim'));
      net.ingestRoomForTest(
          const RoomInfo(code: 'WXYZ', host: '192.168.1.5', playerName: 'Kim'));
      expect(net.foundRooms, hasLength(1));
    });

    test(
        'a second interface beaconing the SAME code collapses into ONE '
        'room, not two', () {
      final net = NetworkService();
      net.localIps = const ['192.168.43.7']; // our own hotspot address
      net.ingestRoomForTest(
          const RoomInfo(code: 'WXYZ', host: '10.0.0.9', playerName: 'Kim'));
      net.ingestRoomForTest(const RoomInfo(
          code: 'WXYZ', host: '192.168.43.1', playerName: 'Kim'));
      expect(net.foundRooms, hasLength(1),
          reason: 'one logical room, even though it beaconed from two '
              'addresses under the same code');
      expect(net.foundRooms.single.host, '192.168.43.1',
          reason: 'upgraded to the address actually reachable from us');
    });

    test('an unreachable second address never displaces a reachable one',
        () {
      final net = NetworkService();
      net.localIps = const ['192.168.43.7'];
      net.ingestRoomForTest(const RoomInfo(
          code: 'WXYZ', host: '192.168.43.1', playerName: 'Kim'));
      net.ingestRoomForTest(
          const RoomInfo(code: 'WXYZ', host: '10.0.0.9', playerName: 'Kim'));
      expect(net.foundRooms.single.host, '192.168.43.1');
    });

    test('a different code from the same host is a distinct room', () {
      final net = NetworkService();
      net.ingestRoomForTest(
          const RoomInfo(code: 'WXYZ', host: '192.168.1.5', playerName: 'Kim'));
      net.ingestRoomForTest(
          const RoomInfo(code: 'ABCD', host: '192.168.1.5', playerName: 'Kim'));
      expect(net.foundRooms, hasLength(2));
    });
  });

  group('board_cancel — retracting a saved fleet', () {
    // Coverage for the CANCEL button on the "WAITING FOR OPPONENT…"
    // dialog (`placement_screen.dart`'s `_waitForPeerBoard`). The button
    // sends `board_cancel`; the peer's `NetworkService` must drop whatever
    // board it was holding so a stale fleet can never be handed to
    // `beginBattle`, and the message must still reach a listener on the
    // `messages` stream so the placement screen can pop its own dialog.
    test('sendBoardCancel puts a board_cancel message on the wire', () {
      final net = NetworkService();
      net.sendBoardCancel();
      expect(net.sentForTest.any((m) => m['type'] == 'board_cancel'), isTrue);
    });

    test('clears a board already retained via takePeerBoard', () {
      final net = NetworkService();
      net.handleIncomingForTest({'type': 'board', 'b': 'placeholder'});
      expect(net.takePeerBoard(), isNotNull);

      // A second board arrives, then the sender changes their mind.
      net.handleIncomingForTest({'type': 'board', 'b': 'placeholder2'});
      net.handleIncomingForTest({'type': 'board_cancel'});
      expect(net.takePeerBoard(), isNull,
          reason: 'a cancelled board must not be handed to beginBattle');
    });

    test('is forwarded on the messages stream for a waiting listener', () async {
      final net = NetworkService();
      final received = <Map<String, dynamic>>[];
      final sub = net.messages.listen(received.add);

      net.handleIncomingForTest({'type': 'board_cancel'});
      await Future<void>.delayed(Duration.zero);

      expect(received.any((m) => m['type'] == 'board_cancel'), isTrue);
      await sub.cancel();
    });
  });
}
