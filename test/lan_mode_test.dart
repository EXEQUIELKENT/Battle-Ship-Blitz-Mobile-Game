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
  });
}
