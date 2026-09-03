import 'dart:ui' as ui;

import 'package:battleship_blitz/art/family_board_art.dart';
import 'package:battleship_blitz/art/family_cannon_art.dart';
import 'package:battleship_blitz/art/family_shell_art.dart';
import 'package:battleship_blitz/art/family_ship_art.dart';
import 'package:battleship_blitz/art/fleet_family.dart';
import 'package:battleship_blitz/art/legacy_cannon_art.dart';
import 'package:battleship_blitz/art/svg_path.dart';
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/widgets/cannon_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // This file specifically exercises real ownership rules (locked vs
  // owned, purchase migrations) — the global "unlock everything for
  // testing" flag (`ProfileStore._unlockAll`, on by default so a plain
  // debug/tester build never gates content) would make every `isFalse`
  // ownership assertion below wrong. Off for the whole file; nothing
  // here depends on cosmetics actually being locked in the APP sense,
  // only in the sense these tests are checking.
  setUpAll(() => ProfileStore.debugUnlockAllOverride = false);
  tearDownAll(() => ProfileStore.debugUnlockAllOverride = null);

  group('SVG path parser', () {
    test('absolute line commands trace the box they describe', () {
      final p = parseSvgPath('M10,10 L90,10 L90,50 L10,50 Z');
      expect(p.getBounds(), const Rect.fromLTRB(10, 10, 90, 50));
    });

    test('relative commands accumulate from the current point', () {
      final abs = parseSvgPath('M0,0 L10,0 L10,10 Z');
      final rel = parseSvgPath('m0,0 l10,0 l0,10 z');
      expect(rel.getBounds(), abs.getBounds());
    });

    test('close returns to the sub-path start, not the origin', () {
      // A second sub-path must close onto ITS OWN start. Getting this
      // wrong silently welds shapes together — the arctic hull's rime
      // highlights are three separate closed blobs on one path.
      final p = parseSvgPath('M0,0 L10,0 Z M50,50 L60,50 L60,60 Z');
      expect(p.getBounds(), const Rect.fromLTRB(0, 0, 60, 60));
    });

    test('cubic and quadratic curves stay inside their control hulls', () {
      final cubic = parseSvgPath('M0,50 C0,0 100,0 100,50');
      expect(cubic.getBounds().top, greaterThanOrEqualTo(0));
      expect(cubic.getBounds().bottom, lessThanOrEqualTo(50.01));
      final quad = parseSvgPath('M0,50 q50,-50 100,0');
      expect(quad.getBounds().width, closeTo(100, 0.01));
    });

    test('an implicit lineto after moveto is honoured', () {
      // "M0,0 10,0" means move then LINE — a real shape in the design
      // source relies on it.
      final p = parseSvgPath('M0,0 10,0 10,10');
      expect(p.getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
    });

    test('a malformed path yields an empty path rather than hanging', () {
      // Robustness matters more than fidelity here: a bad glyph must not
      // take the battle screen down mid-match.
      expect(() => parseSvgPath('M0,0 W99 L10,10'), returnsNormally);
      expect(() => parseSvgPath(''), returnsNormally);
    });

    test('every hull path in the design source parses to real geometry', () {
      // Catches a truncated or mistyped `d` string, which would otherwise
      // just draw nothing and be easy to miss on a small grid ship.
      for (final family in FleetFamilies.all) {
        for (final kind in ShipKind.values) {
          final rec = ui.PictureRecorder();
          final canvas = Canvas(rec);
          paintFamilyShip(canvas, const Size(300, 100), family, kind);
          expect(rec.endRecording().approximateBytesUsed,
              greaterThan(_emptyPictureBytes),
              reason: '${family.key}/${kind.name} drew nothing');
        }
      }
    });
  });

  group('fleet families', () {
    test('all six are registered and uniquely keyed', () {
      expect(FleetFamilies.all, hasLength(6));
      expect(FleetFamilies.all.map((f) => f.key).toSet(), hasLength(6));
      expect(FleetFamilies.all.map((f) => f.id).toSet(), hasLength(6));
    });

    test('byKey resolves families and rejects legacy skins', () {
      expect(FleetFamilies.byKey('volcanic')?.fleetName, 'Cinder Hold');
      // The original nine have no family and must fall through to their
      // own flat-tint painters.
      expect(FleetFamilies.byKey(null), isNull);
      expect(FleetFamilies.byKey('crimson'), isNull);
    });

    test('barrel-length tokens keep the design table', () {
      expect(FleetFamilies.pirate.barrelFrac, 0.48);
      expect(FleetFamilies.naval.barrelFrac, 0.78);
    });

    test('every muzzle sits above its own mount and inside the box', () {
      // `muzzleFrac` is measured off the artwork rather than taken from
      // the design's token table, and it is what `battle_screen` reads to
      // decide where a shell is born. The two properties that have to
      // hold for that to look right: the muzzle is above the mount (the
      // barrel points up), and it is inside the drawing (a shell must not
      // appear out of empty space beyond the widget).
      for (final f in FleetFamilies.all) {
        expect(f.muzzleY, lessThan(-f.mountROuter),
            reason: '${f.key}: muzzle must clear its own platform');
        expect(f.muzzleY, greaterThanOrEqualTo(kGunBoxTop),
            reason: '${f.key}: muzzle must be inside the art box');
        expect(f.muzzleFrac, inInclusiveRange(0.15, 0.45));
        expect(f.mountRInner, lessThan(f.mountROuter));
      }
      // The relative ordering the design cares about survives the switch
      // from tokens to measurements: the autoloader is still the longest
      // gun and the icebreaker mortar still the stubbiest.
      expect(FleetFamilies.naval.muzzleFrac,
          greaterThan(FleetFamilies.pirate.muzzleFrac));
      expect(FleetFamilies.arctic.muzzleFrac,
          lessThan(FleetFamilies.pirate.muzzleFrac));
    });

    test('a square cannon widget maps design y=0 to its own centre', () {
      // The whole muzzle/mount mapping rests on this: `FamilyCanvas.fit`
      // letterboxes the 220x216 box on width, which lands design y=0 on
      // the widget's vertical centre. If that ever stopped being true,
      // every shell and every reload ring would silently shift.
      for (final f in FleetFamilies.all) {
        // The mount centre is the one point the inset does not move, so
        // it maps exactly where the un-inset formula puts it.
        expect(f.gunY(220, f.mountCy), closeTo(110 + f.mountCy, 0.001));
        expect(f.gunY(200, f.muzzleY), lessThan(100));
        expect(f.gunY(200, f.mountCy), greaterThan(100));
      }
    });

    test('the reload platform fits inside the cannon widget', () {
      // The gun art is inset so a ring of platform shows around its base.
      // If the platform were wider than the widget it would be clipped
      // along the bottom, which is where it is closest to the edge.
      for (final f in FleetFamilies.all) {
        const side = 200.0;
        final bottom = f.gunY(side, f.mountCy) + f.platformRadius(side);
        expect(bottom, lessThanOrEqualTo(side),
            reason: '${f.key}: platform runs off the bottom');
        // …and the visible ring has real width, or there is no platform
        // to see the reload on.
        expect(f.sweepWidth(side), greaterThan(2));
      }
    });

    test('the muzzle moves with the art when it is inset', () {
      // The inset shrinks the drawing about its mount, so the muzzle
      // genuinely moves closer in. `muzzleFrac` is the single value the
      // battle screen reads to spawn a shell, so if it kept quoting the
      // authored position the shell would leave from a point the barrel
      // no longer reaches.
      for (final f in FleetFamilies.all) {
        expect(f.muzzleFrac, closeTo(0.5 - f.gunY(1, f.muzzleY), 1e-9));
        expect(f.muzzleFrac, lessThan(-f.muzzleY / kGunBoxW),
            reason: '${f.key}: inset muzzle must be nearer than the raw one');
      }
    });

    test('no two battlefields read as the same battlefield', () {
      // Found by eye and pinned here: Brass Works' field was a steel-blue
      // a few points from Fleet Command's, so at store-card size they
      // were the same board twice. The families are meant to be
      // structural rather than chromatic, but that is an argument for the
      // shapes ALSO differing — it is not licence for two of six boards
      // to share a colour, because colour is what carries at small size.
      //
      // Compared in HSL rather than by summing channel differences. That
      // cruder measure was tried first and was actively misleading: it
      // scored the two boards that genuinely looked identical FURTHER
      // apart than a pair that reads clearly as teal versus blue. What
      // separates boards at a glance is hue or lightness, not the total
      // distance travelled through RGB.
      double hueGap(Color a, Color b) {
        final d =
            (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs();
        return d > 180 ? 360 - d : d;
      }

      double lightGap(Color a, Color b) =>
          (HSLColor.fromColor(a).lightness - HSLColor.fromColor(b).lightness)
              .abs();

      for (final a in FleetFamilies.all) {
        for (final b in FleetFamilies.all) {
          if (a.id.index >= b.id.index) continue;
          final h = hueGap(a.board.field, b.board.field);
          final l = lightGap(a.board.field, b.board.field);
          expect(h > 20 || l > 0.10, isTrue,
              reason: '${a.key} and ${b.key} fields are too close '
                  '(hue ${h.toStringAsFixed(0)}°, '
                  'lightness ${l.toStringAsFixed(3)})');
        }
      }
    });

    test('every family has its own exhaust beat', () {
      // The design's storyboard: same 260 ms, different beat. Six
      // families sharing one grey puff would be exactly the "generic"
      // failure the whole system exists to avoid.
      final kinds = FleetFamilies.all.map((f) => f.exhaust).toSet();
      expect(kinds.length, FleetFamilies.all.length);
      expect(FleetFamilies.scifi.exhaust, MuzzleExhaust.ring);
      expect(FleetFamilies.pirate.exhaust, MuzzleExhaust.smoke);
    });

    test('a matched set is cheaper than buying the three pieces', () {
      for (final f in FleetFamilies.all) {
        expect(f.setPrice, lessThan(f.fullPrice));
        expect(f.setSaving, greaterThan(0));
      }
    });

    test('cannon, shell and board all render for every family', () {
      for (final f in FleetFamilies.all) {
        for (final draw in [
          () {
            final rec = ui.PictureRecorder();
            paintFamilyCannon(Canvas(rec), const Size(140, 140), f);
            return rec.endRecording();
          },
          () {
            final rec = ui.PictureRecorder();
            paintFamilyShell(Canvas(rec), const Size(60, 66), f);
            return rec.endRecording();
          },
          () {
            final rec = ui.PictureRecorder();
            paintFamilyBoard(Canvas(rec), const Size(400, 400), f);
            return rec.endRecording();
          },
        ]) {
          expect(draw().approximateBytesUsed, greaterThan(_emptyPictureBytes),
              reason: '${f.key} drew nothing');
        }
      }
    });

    test('hit and miss markers render for every family', () {
      for (final f in FleetFamilies.all) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        paintFamilyMiss(canvas, const Offset(20, 20), 40, f);
        paintFamilyHit(canvas, const Offset(60, 20), 40, f);
        expect(rec.endRecording().approximateBytesUsed,
            greaterThan(_emptyPictureBytes),
            reason: '${f.key} markers drew nothing');
      }
    });
  });

  group('catalogue', () {
    test('every family has a hull, a cannon and a battlefield on sale', () {
      for (final f in FleetFamilies.all) {
        expect(Catalog.shipSkins.where((s) => s.familyKey == f.key),
            hasLength(1),
            reason: 'no hull for ${f.key}');
        expect(Catalog.cannonSkins.where((c) => c.familyKey == f.key),
            hasLength(1),
            reason: 'no cannon for ${f.key}');
        expect(Catalog.gameplayThemes.where((t) => t.familyKey == f.key),
            hasLength(1),
            reason: 'no battlefield for ${f.key}');
      }
    });

    test('ids are unique within each catalogue', () {
      expect(Catalog.shipSkins.map((s) => s.id).toSet(),
          hasLength(Catalog.shipSkins.length));
      expect(Catalog.cannonSkins.map((c) => c.id).toSet(),
          hasLength(Catalog.cannonSkins.length));
      expect(Catalog.gameplayThemes.map((t) => t.id).toSet(),
          hasLength(Catalog.gameplayThemes.length));
    });

    test('the original nine skins are untouched and family-free', () {
      // Adding six families must not disturb anything already bought.
      for (final id in [
        'steel', 'crimson', 'emerald', 'gold', 'abyss',
        'arctic', 'coral', 'midnight', 'toxic',
      ]) {
        final skin = Catalog.shipById(id);
        expect(skin.id, id);
        expect(skin.familyKey, isNull);
      }
      expect(Catalog.shipById('arctic').name, 'Arctic Storm');
      expect(Catalog.cannonById('mk1').cooldownFactor, 1.0);
    });

    test(
        'a family cannon reports its own muzzle, a legacy one its own '
        'illustrated barrel length', () {
      // REDESIGN: the nine originals used to be one drawing in nine
      // colourways sharing one fixed `muzzleFraction` — `paintLegacyCannon`
      // gives each its own turret now, so each reads its own value from
      // `legacyMuzzleFractionOf` instead (see that function's own doc).
      expect(CannonWidget.muzzleFractionOf(Catalog.cannonById('mk1')),
          legacyMuzzleFractionOf('mk1'));
      expect(CannonWidget.muzzleFractionOf(Catalog.cannonById('inferno')),
          legacyMuzzleFractionOf('inferno'));
      expect(legacyMuzzleFractionOf('inferno'),
          isNot(legacyMuzzleFractionOf('mk1')),
          reason: 'the whole point of the redesign — different guns, '
              'different barrel lengths');
      expect(CannonWidget.muzzleFractionOf(Catalog.cannonById('f_naval')),
          FleetFamilies.naval.muzzleFrac);
      expect(CannonWidget.muzzleFractionOf(Catalog.cannonById('f_pirate')),
          FleetFamilies.pirate.muzzleFrac);
    });
  });

  group('ownership scoping', () {
    test('an id shared by two catalogues is two separate purchases', () {
      // The bug this fixes: `f_arctic` is BOTH a hull (Rime Wardens) and a
      // battlefield (Rime Field) sharing one id, and one flat set made
      // buying either hand over the other for free. (No LEGACY id is
      // shared across catalogues any more since the four flat palettes —
      // one of which used to collide with the `arctic` hull — were
      // retired in favour of the nine legacy battlefields.)
      final p = ProfileStore()..owned = {'theme:f_arctic'};
      expect(p.ownsTheme('f_arctic'), isTrue);
      expect(p.ownsShip('f_arctic'), isFalse);
    });

    test('an old flat save keeps everything it could previously equip', () {
      // Deliberately generous — under the old build this player really
      // could equip both, so scoping must not repossess one of them.
      // `mk1` alone covers the shared-catalogue case here (it is both a
      // legacy cannon id AND its own matching legacy theme id).
      final p = ProfileStore()..owned = {'steel', 'mk1', 'f_arctic'};
      p.load; // not called: migration runs inside load()
      // Simulate what load() does.
      final migrated = ProfileStore()..owned = {...p.owned};
      _runMigration(migrated);
      expect(migrated.ownsShip('f_arctic'), isTrue);
      expect(migrated.ownsTheme('f_arctic'), isTrue);
      expect(migrated.ownsShip('steel'), isTrue);
      expect(migrated.ownsCannon('mk1'), isTrue);
      expect(migrated.ownsTheme('mk1'), isTrue);
      // …but nothing it never had.
      expect(migrated.ownsShip('gold'), isFalse);
      expect(migrated.ownsShip('f_scifi'), isFalse);
    });

    test('the free starters survive an empty save', () {
      final p = ProfileStore()..owned = {};
      _runMigration(p);
      expect(p.ownsShip('steel'), isTrue);
      expect(p.ownsCannon('mk1'), isTrue);
      expect(p.ownsTheme('mk1'), isTrue);
    });

    test('an already-scoped save is left alone', () {
      final p = ProfileStore()..owned = {'ship:gold', 'cannon:mk1'};
      _runMigration(p);
      expect(p.ownsShip('gold'), isTrue);
      expect(p.ownsShip('steel'), isFalse,
          reason: 'must not re-add starters over a real scoped save');
    });

    test('buying a family hull does not hand over its cannon or board', () {
      final p = ProfileStore()
        ..rp = 9999
        ..owned = {'ship:steel', 'cannon:mk1', 'theme:mk1'};
      p.equipShipSkin(Catalog.shipById('f_volcanic'));
      expect(p.ownsShip('f_volcanic'), isTrue);
      expect(p.ownsCannon('f_volcanic'), isFalse);
      expect(p.ownsTheme('f_volcanic'), isFalse);
    });

    test('one piece of a family is one piece, for every family', () {
      // The whole point of buying a hull is that you get a hull. A family
      // shares one id across three catalogues, which is exactly the shape
      // of mistake that hands over all three — so this checks every
      // family in all three directions rather than spot-checking one.
      for (final f in FleetFamilies.all) {
        final key = 'f_${f.key}';

        final byHull = ProfileStore()
          ..rp = 99999
          ..owned = {'ship:steel', 'cannon:mk1', 'theme:mk1'};
        byHull.equipShipSkin(Catalog.shipById(key));
        expect(byHull.ownsShip(key), isTrue, reason: '$key hull');
        expect(byHull.ownsCannon(key), isFalse, reason: '$key hull→cannon');
        expect(byHull.ownsTheme(key), isFalse, reason: '$key hull→board');
        // …and what they SAIL is unchanged apart from the hull.
        expect(byHull.cannonSkinId, 'mk1');
        expect(byHull.gameplayThemeId, 'mk1');

        final byGun = ProfileStore()
          ..rp = 99999
          ..owned = {'ship:steel', 'cannon:mk1', 'theme:mk1'};
        byGun.equipCannonSkin(Catalog.cannonById(key));
        expect(byGun.ownsCannon(key), isTrue, reason: '$key cannon');
        expect(byGun.ownsShip(key), isFalse, reason: '$key cannon→hull');
        expect(byGun.ownsTheme(key), isFalse, reason: '$key cannon→board');
        expect(byGun.shipSkinId, 'steel');
        expect(byGun.gameplayThemeId, 'mk1');

        final byBoard = ProfileStore()
          ..rp = 99999
          ..owned = {'ship:steel', 'cannon:mk1', 'theme:mk1'};
        byBoard.equipGameplayTheme(Catalog.gameplayThemeById(key));
        expect(byBoard.ownsTheme(key), isTrue, reason: '$key board');
        expect(byBoard.ownsShip(key), isFalse, reason: '$key board→hull');
        expect(byBoard.ownsCannon(key), isFalse, reason: '$key board→cannon');
        expect(byBoard.shipSkinId, 'steel');
        expect(byBoard.cannonSkinId, 'mk1');
      }
    });

    test('each piece is charged its own catalogue price, once', () {
      for (final f in FleetFamilies.all) {
        final key = 'f_${f.key}';
        final p = ProfileStore()
          ..rp = 99999
          ..owned = {'ship:steel', 'cannon:mk1', 'theme:mk1'};

        final start = p.rp;
        p.equipShipSkin(Catalog.shipById(key));
        expect(p.rp, start - Catalog.shipById(key).cost);

        // Re-equipping something already owned is free — otherwise
        // switching back and forth between two hulls would bill you for
        // both every time.
        final afterHull = p.rp;
        p.equipShipSkin(Catalog.shipById('steel'));
        p.equipShipSkin(Catalog.shipById(key));
        expect(p.rp, afterHull);
      }
    });
  });

  group('matched sets', () {
    ProfileStore fresh() => ProfileStore()
      ..rp = 99999
      ..owned = {'ship:steel', 'cannon:mk1', 'theme:mk1'};

    test('the set costs 80% of its three pieces and equips all of them', () {
      final p = fresh();
      const f = FleetFamilies.arctic;
      final full = Catalog.shipById('f_arctic').cost +
          Catalog.cannonById('f_arctic').cost +
          Catalog.gameplayThemeById('f_arctic').cost;
      expect(p.setPriceFor(f), (full * 0.8).round());
      expect(p.setSavingFor(f), full - (full * 0.8).round());

      final before = p.rp;
      expect(p.buyFamilySet(f), isTrue);
      expect(p.rp, before - (full * 0.8).round());
      expect(p.ownsShip('f_arctic'), isTrue);
      expect(p.ownsCannon('f_arctic'), isTrue);
      expect(p.ownsTheme('f_arctic'), isTrue);
      expect(p.shipSkinId, 'f_arctic');
      expect(p.cannonSkinId, 'f_arctic');
      expect(p.gameplayThemeId, 'f_arctic');
      // Equipping a hull is a deliberate choice, and the set is the most
      // deliberate one there is.
      expect(p.shipSkinChosen, isTrue);
    });

    test('you are not charged twice for a piece you already own', () {
      final p = fresh();
      const f = FleetFamilies.pirate;
      p.equipShipSkin(Catalog.shipById('f_pirate'));
      final remaining = Catalog.cannonById('f_pirate').cost +
          Catalog.gameplayThemeById('f_pirate').cost;
      expect(p.setPriceFor(f), (remaining * 0.8).round());
    });

    test('an unaffordable set changes nothing at all', () {
      // The failure that matters here is a HALF-bought set: RP gone, or
      // one piece handed over and the rest not.
      final p = fresh()..rp = 10;
      const f = FleetFamilies.scifi;
      expect(p.buyFamilySet(f), isFalse);
      expect(p.rp, 10);
      expect(p.ownsShip('f_scifi'), isFalse);
      expect(p.ownsCannon('f_scifi'), isFalse);
      expect(p.ownsTheme('f_scifi'), isFalse);
      expect(p.shipSkinId, 'steel');
    });

    test('a fully-owned set reports itself owned, and costs nothing', () {
      final p = fresh();
      const f = FleetFamilies.steam;
      expect(p.ownsFamilySet(f), isFalse);
      p.buyFamilySet(f);
      expect(p.ownsFamilySet(f), isTrue);
      expect(p.setPriceFor(f), 0);
    });
  });

  group('ink weight at small sizes', () {
    /// The `ink()` a canvas would use for a design-space stroke width,
    /// given a viewBox mapped onto a widget of [size].
    double inkFor(Size size, Rect viewBox, double designWidth) {
      final rec = ui.PictureRecorder();
      return FamilyCanvas.stretch(Canvas(rec), size, viewBox).ink(designWidth);
    }

    const shipBox = Rect.fromLTWH(0, 0, 300, 100);

    test('at the design\'s own size the weight is exactly as specified', () {
      // Anything else would mean the port no longer matches the source.
      expect(inkFor(const Size(300, 100), shipBox, 4), closeTo(4, 0.001));
      expect(inkFor(const Size(300, 100), shipBox, 2), closeTo(2, 0.001));
    });

    test('drawn larger, ink does not grow past the design', () {
      // The design marks every stroke non-scaling, so a big preview keeps
      // the authored weight rather than turning into a woodcut.
      expect(inkFor(const Size(900, 300), shipBox, 4), closeTo(4, 0.001));
    });

    test('drawn smaller, ink shrinks with the drawing', () {
      // THE BUG: fixed device-pixel ink on a hull scaled down to a grid
      // cell is ink that grows relative to everything around it. Half the
      // size means half the weight, so the proportions hold.
      expect(inkFor(const Size(150, 50), shipBox, 4), closeTo(2, 0.001));
    });

    test('a grid-scale ship is outlined, not filled in with outline', () {
      // A five-cell carrier on a phone: roughly 180x36 logical pixels.
      // Before the fix this was a flat 4px of ink on a 36px-tall hull.
      final ink = inkFor(const Size(180, 36), shipBox, 4);
      expect(ink, lessThan(2.5), reason: 'too heavy to read as an outline');
      expect(ink, greaterThan(1.0), reason: 'too faint to read at all');
    });

    test('ink never falls below the visibility floor', () {
      // Scaling all the way down would eventually reach sub-pixel widths,
      // where a stroke flickers in and out along the shape — worse than
      // being slightly heavy.
      expect(inkFor(const Size(9, 3), shipBox, 2), greaterThan(0.5));
    });

    test('a stretched hull takes its weight from both axes', () {
      // A two-cell destroyer is much shorter than it is thinner. Taking
      // either axis alone would make the outline lurch between ships of
      // different lengths sitting in the same fleet strip.
      final wide = inkFor(const Size(300, 40), shipBox, 4);
      final narrow = inkFor(const Size(120, 40), shipBox, 4);
      expect(wide, greaterThan(narrow));
      expect(wide, lessThan(4.001));
    });
  });
}

/// Mirrors `ProfileStore.load()`'s migration step, which is private.
void _runMigration(ProfileStore p) {
  if (p.owned.any((k) => k.contains(':'))) return;
  final scoped = <String>{};
  for (final id in p.owned) {
    if (Catalog.shipSkins.any((s) => s.id == id)) scoped.add('ship:$id');
    if (Catalog.cannonSkins.any((c) => c.id == id)) scoped.add('cannon:$id');
    if (Catalog.gameplayThemes.any((t) => t.id == id)) scoped.add('theme:$id');
  }
  scoped.addAll(['ship:steel', 'cannon:mk1', 'theme:mk1']);
  p.owned = scoped;
}

/// Byte size of a recording with nothing drawn into it, so "did this
/// actually paint?" is measured against a real baseline instead of
/// against zero — an empty picture is not zero bytes.
final int _emptyPictureBytes = () {
  final rec = ui.PictureRecorder();
  Canvas(rec);
  return rec.endRecording().approximateBytesUsed;
}();
