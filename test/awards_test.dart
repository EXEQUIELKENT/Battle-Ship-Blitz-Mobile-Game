import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void _recordWin(ProfileStore p, DateTime day,
    {int hits = 12, int shots = 15, int sinks = 5, int cards = 0}) {
  p.wins++;
  p.streak++;
  p.recordMatchForAwards(
    won: true,
    now: day,
    hitsThisMatch: hits,
    shotsThisMatch: shots,
    sinksThisMatch: sinks,
    cardsUsed: cards,
    sunkCarrier: true,
    isGhostWin: false,
    counted: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first win unlocks a batch, never pays twice', () {
    final p = ProfileStore();
    final before = p.doubloons;
    _recordWin(p, DateTime(2026, 6, 1));
    expect(p.achievements,
        containsAll(['first_blood', 'ship_sinker', 'fleet_destroyer']));
    final paid = p.doubloons - before;
    expect(paid, greaterThan(0));
    final notes = p.lastAwardNotes.length;
    expect(notes, greaterThan(0));
    // Same again — achievements stay silent, no double pay. The only
    // newcomer is Demolisher: 5 + 5 career sinks hits its threshold.
    // first_blood, ship_sinker, fleet_destroyer, sharpshooter,
    // carrier_killer, flawless, annihilator, demolisher.
    _recordWin(p, DateTime(2026, 6, 1));
    expect(p.achievements.length, 8);
    final again = p.lastAwardNotes.where((n) => n.name == 'First Blood');
    expect(again, isEmpty);
  });

  test('sharpshooter needs 60%+ over 10+ shots', () {
    final p = ProfileStore();
    p.recordMatchForAwards(
      won: true,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 5,
      shotsThisMatch: 12,
      sinksThisMatch: 1,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(p.achievements, isNot(contains('sharpshooter')));
  });

  test('demolisher fires at 10 career sinks', () {
    final p = ProfileStore();
    p.recordMatchForAwards(
      won: false,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 3,
      shotsThisMatch: 10,
      sinksThisMatch: 9,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(p.achievements, isNot(contains('demolisher')));
    p.recordMatchForAwards(
      won: false,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 1,
      shotsThisMatch: 5,
      sinksThisMatch: 1,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(p.achievements, contains('demolisher'));
    expect(p.totalSinks, 10);
  });

  test('uncounted matches progress nothing', () {
    final p = ProfileStore();
    p.recordMatchForAwards(
      won: true,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 12,
      shotsThisMatch: 15,
      sinksThisMatch: 5,
      cardsUsed: 0,
      sunkCarrier: true,
      isGhostWin: false,
      counted: false,
    );
    expect(p.achievements, isEmpty);
    expect(p.lastAwardNotes, isEmpty);
    expect(p.totalSinks, 0);
  });

  test('daily quests are seeded per day and pay once', () {
    final a = ProfileStore.dailyQuestIds(DateTime(2026, 6, 1));
    final b = ProfileStore.dailyQuestIds(DateTime(2026, 6, 1));
    expect(a.map((q) => q.id).toList(), b.map((q) => q.id).toList());
    expect(a.length, 3);

    final p = ProfileStore();
    final day = DateTime(2026, 6, 1);
    final before = p.doubloons;
    // A big win: completes win_1/play_1 progress and possibly more.
    p.wins++;
    p.streak++;
    p.recordMatchForAwards(
      won: true,
      now: day,
      hitsThisMatch: 8,
      shotsThisMatch: 10,
      sinksThisMatch: 2,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(p.doubloons, greaterThan(before));
    final doneCount = p.questDone.length;
    expect(doneCount, greaterThan(0));
    // Next day rolls progress over.
    p.recordMatchForAwards(
      won: false,
      now: DateTime(2026, 6, 2),
      hitsThisMatch: 0,
      shotsThisMatch: 1,
      sinksThisMatch: 0,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(p.questDate, ProfileStore.dailyPuzzleKey(DateTime(2026, 6, 2)));
  });

  test('puzzle solve unlocks its medal once', () {
    final p = ProfileStore();
    final day = DateTime(2026, 6, 1);
    p.claimDailyPuzzleReward(solved: true, now: day);
    expect(p.achievements, contains('puzzle_solver'));
  });

  test('flawless needs a win with zero hulls lost', () {
    verifyWin(ownLost: 0, won: true, expectFlawless: true);
    verifyWin(ownLost: 1, won: true, expectFlawless: false);
    verifyWin(ownLost: 0, won: false, expectFlawless: false);
  });

  test('single-match volume medals gate on their thresholds', () {
    final p = ProfileStore();
    p.recordMatchForAwards(
      won: true,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 15,
      shotsThisMatch: 20,
      sinksThisMatch: 5,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(p.achievements, contains('annihilator'));
    expect(p.achievements, contains('brawler'));
    // Just under the lines: nothing.
    final q = ProfileStore();
    q.recordMatchForAwards(
      won: true,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 14,
      shotsThisMatch: 20,
      sinksThisMatch: 4,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(q.achievements, isNot(contains('annihilator')));
    expect(q.achievements, isNot(contains('brawler')));
  });

  test('against_all_odds needs a win after losing 4 hulls', () {
    verifyWin(ownLost: 4, won: true, expectOdds: true);
    verifyWin(ownLost: 4, won: false, expectOdds: false);
    verifyWin(ownLost: 3, won: true, expectOdds: false);
  });

  test('streak tiers fire at 3 and 5', () {
    final p = ProfileStore()..streak = 3;
    p.recordMatchForAwards(
      won: true,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 1,
      shotsThisMatch: 2,
      sinksThisMatch: 0,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(p.achievements, contains('hot_streak'));
    expect(p.achievements, isNot(contains('unstoppable')));
    final r = ProfileStore()..streak = 5;
    r.recordMatchForAwards(
      won: true,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 1,
      shotsThisMatch: 2,
      sinksThisMatch: 0,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(r.achievements, contains('unstoppable'));
  });

  test('career tiers fire at 25 sinks and 50 matches', () {
    final p = ProfileStore();
    p.recordMatchForAwards(
      won: false,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 0,
      shotsThisMatch: 1,
      sinksThisMatch: 25,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(p.achievements, contains('abyssal'));
    final r = ProfileStore()
      ..wins = 49
      ..losses = 1;
    r.recordMatchForAwards(
      won: false,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 0,
      shotsThisMatch: 1,
      sinksThisMatch: 0,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(r.achievements, contains('legend'));
  });

  test('mode wins unlock their own medals only', () {
    final p = ProfileStore();
    p.wins++;
    p.recordMatchForAwards(
      won: true,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 3,
      shotsThisMatch: 5,
      sinksThisMatch: 1,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
      lanMode: LanBattleMode.salvo,
    );
    expect(p.achievements, contains('win_salvo'));
    expect(p.achievements, isNot(contains('win_phantom')));
    // A loss in another mode unlocks nothing new.
    p.recordMatchForAwards(
      won: false,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 1,
      shotsThisMatch: 5,
      sinksThisMatch: 0,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
      lanMode: LanBattleMode.phantom,
    );
    expect(p.achievements, isNot(contains('win_phantom')));
    // Classic turns and ghost ride on their existing medals.
    final q = ProfileStore();
    q.wins++;
    q.recordMatchForAwards(
      won: true,
      now: DateTime(2026, 6, 1),
      hitsThisMatch: 3,
      shotsThisMatch: 5,
      sinksThisMatch: 1,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
      lanMode: LanBattleMode.turns,
    );
    expect(q.achievements, isNot(contains('win_salvo')));
  });

  test('new daily quests progress and uniqueness holds', () {
    expect(ProfileStore.questPool.length, 9);
    final p = ProfileStore();
    final day = DateTime(2026, 6, 1);
    p.wins += 2;
    p.streak += 2;
    p.recordMatchForAwards(
      won: true,
      now: day,
      hitsThisMatch: 15,
      shotsThisMatch: 20,
      sinksThisMatch: 4,
      cardsUsed: 0,
      sunkCarrier: false,
      isGhostWin: false,
      counted: true,
    );
    expect(p.questProgress['wins_2'], 1);
    expect(p.questProgress['hits_15'], 15);
    expect(p.questProgress['sinks_4'], 4);
    // All icons unique across medals and quests.
    final icons = [
      for (final a in ProfileStore.achievementDefs) a.icon,
      for (final q in ProfileStore.questPool) q.icon,
    ];
    expect(icons.toSet().length, icons.length);
  });

  test('puzzle streak medal fires on the third straight solve', () {
    final p = ProfileStore();
    p.claimDailyPuzzleReward(solved: true, now: DateTime(2026, 6, 1));
    p.claimDailyPuzzleReward(solved: true, now: DateTime(2026, 6, 2));
    expect(p.achievements, isNot(contains('puzzle_streak_3')));
    p.claimDailyPuzzleReward(solved: true, now: DateTime(2026, 6, 3));
    expect(p.achievements, contains('puzzle_streak_3'));
  });
}

void verifyWin({required int ownLost, required bool won, bool? expectFlawless, bool? expectOdds}) {
  final p = ProfileStore();
  if (won) {
    p.wins++;
    p.streak++;
  } else {
    p.losses++;
    p.streak = 0;
  }
  p.recordMatchForAwards(
    won: won,
    now: DateTime(2026, 6, 1),
    hitsThisMatch: 5,
    shotsThisMatch: 8,
    sinksThisMatch: 1,
    cardsUsed: 0,
    sunkCarrier: false,
    isGhostWin: false,
    counted: true,
    ownShipsLost: ownLost,
  );
  if (expectFlawless != null) {
    expect(p.achievements.contains('flawless'), expectFlawless);
  }
  if (expectOdds != null) {
    expect(p.achievements.contains('against_all_odds'), expectOdds);
  }
}
