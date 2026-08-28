// The POWER PLAY deck: pure data (20 cards, weighted draw) and pure
// targeting-shape geometry. Nothing here touches `GameController` — the
// gameplay wiring (what each card actually DOES to a match) is covered
// in `test/power_play_test.dart`. This file is what's actually risky
// about a 20-card deck: the wrong card drawn, a shape that loses a cell
// at an edge, or a weight that quietly makes some card unreachable.
import 'dart:math';

import 'package:battleship_blitz/models/power_up.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the deck itself', () {
    test('exactly twenty cards, one definition each, no duplicates', () {
      expect(PowerUps.deck, hasLength(20));
      expect(PowerUps.deck.map((d) => d.card).toSet(), hasLength(20));
      expect(PowerUps.deck.map((d) => d.name).toSet(), hasLength(20),
          reason: 'every card needs its own name for the UI banner');
    });

    test('every card is reachable — PowerUps.of round-trips every card', () {
      for (final card in PowerUpCard.values) {
        expect(PowerUps.of(card).card, card);
      }
    });

    test('rarity is monotonic: common > uncommon > rare, strictly', () {
      final byRarity = <PowerUpRarity, List<int>>{};
      for (final d in PowerUps.deck) {
        (byRarity[d.rarity] ??= []).add(d.weight);
      }
      final commonMin = byRarity[PowerUpRarity.common]!.reduce(min);
      final uncommonMax = byRarity[PowerUpRarity.uncommon]!.reduce(max);
      final uncommonMin = byRarity[PowerUpRarity.uncommon]!.reduce(min);
      final rareMax = byRarity[PowerUpRarity.rare]!.reduce(max);
      expect(commonMin, greaterThan(uncommonMax));
      expect(uncommonMin, greaterThan(rareMax));
    });

    test('every card carries a positive weight', () {
      for (final d in PowerUps.deck) {
        expect(d.weight, greaterThan(0), reason: '${d.name} is unreachable');
      }
    });

    test('draw() only ever returns a card actually in the deck', () {
      final rng = Random(7);
      final seen = <PowerUpCard>{};
      for (var i = 0; i < 2000; i++) {
        seen.add(PowerUps.draw(rng));
      }
      expect(seen.length, 20, reason: '2000 draws should see every card');
    });

    test('draw() is weighted — commons come up far more than rares', () {
      final rng = Random(11);
      final counts = <PowerUpRarity, int>{
        for (final r in PowerUpRarity.values) r: 0,
      };
      const rounds = 20000;
      for (var i = 0; i < rounds; i++) {
        final rarity = PowerUps.of(PowerUps.draw(rng)).rarity;
        counts[rarity] = counts[rarity]! + 1;
      }
      // Loose bounds — this is checking the weighting is respected in
      // direction and rough proportion, not pinning an exact percentage
      // that would make the deck impossible to retune.
      expect(counts[PowerUpRarity.common]!,
          greaterThan(counts[PowerUpRarity.rare]! * 2));
    });
  });

  group('targeting shapes always cost their full size', () {
    // The risk with any "clamp to the board" logic is a shape losing a
    // cell at an edge — a SALVO flush against a wall must still be
    // three shots, not two.
    test('salvo is three cells, distinct, everywhere including corners',
        () {
      for (final r in [0, 4, 9]) {
        for (final c in [0, 4, 9]) {
          final shape = PowerUpShapes.salvo(r, c);
          expect(shape.toSet(), hasLength(3), reason: 'at ($r,$c)');
          for (final (row, col) in shape) {
            expect(row, inInclusiveRange(0, 9));
            expect(col, inInclusiveRange(0, 9));
          }
        }
      }
    });

    test('depth charge is a full 2×2 even in the bottom-right corner', () {
      final shape = PowerUpShapes.depthCharge(9, 9);
      expect(shape.toSet(), hasLength(4));
      for (final (row, col) in shape) {
        expect(row, inInclusiveRange(0, 9));
        expect(col, inInclusiveRange(0, 9));
      }
      // Flush against the corner: the block must have slid to (8,8)-(9,9).
      expect(shape.toSet(), {(8, 8), (8, 9), (9, 8), (9, 9)});
    });

    test('cross fire is five cells even tapped exactly on an edge', () {
      for (final r in [0, 9]) {
        for (final c in [0, 9]) {
          final shape = PowerUpShapes.crossFire(r, c);
          expect(shape.toSet(), hasLength(5), reason: 'at ($r,$c)');
          for (final (row, col) in shape) {
            expect(row, inInclusiveRange(0, 9));
            expect(col, inInclusiveRange(0, 9));
          }
        }
      }
    });

    test('an interior tap is centred exactly where tapped', () {
      // Away from every edge, clamping should be a no-op — this pins
      // that the shapes are centred/anchored as documented, not just
      // "some 3/4/5 cells somewhere near the tap".
      expect(PowerUpShapes.salvo(5, 5).toSet(),
          {(5, 4), (5, 5), (5, 6)});
      expect(PowerUpShapes.depthCharge(5, 5).toSet(),
          {(5, 5), (5, 6), (6, 5), (6, 6)});
      expect(PowerUpShapes.crossFire(5, 5).toSet(),
          {(5, 5), (4, 5), (6, 5), (5, 4), (5, 6)});
    });

    test('spray is exactly the two cells picked, in bounds by construction',
        () {
      final shape = PowerUpShapes.spray((0, 0), (9, 9));
      expect(shape, [(0, 0), (9, 9)]);
    });

    test('barrage draws four distinct cells, none of them avoided', () {
      final rng = Random(3);
      final avoid = <(int, int)>{
        for (var r = 0; r < 10; r++)
          for (var c = 0; c < 10; c++)
            if (!(r == 0 && c < 4)) (r, c),
      }; // only row 0, columns 0-3 remain open
      final shots = PowerUpShapes.barrage(rng, avoid);
      expect(shots.toSet(), hasLength(4));
      for (final cell in shots) {
        expect(avoid.contains(cell), isFalse);
      }
    });

    test('barrage degrades gracefully when fewer than four cells remain',
        () {
      final rng = Random(9);
      final avoid = <(int, int)>{
        for (var r = 0; r < 10; r++)
          for (var c = 0; c < 10; c++)
            if (!((r == 0 && c == 0) || (r == 0 && c == 1))) (r, c),
      }; // only two cells open
      final shots = PowerUpShapes.barrage(rng, avoid);
      expect(shots.length, lessThanOrEqualTo(2));
      expect(shots.toSet(), {(0, 0), (0, 1)});
    });
  });
}
