import 'dart:math';
import 'dart:ui' as ui;

import 'package:battleship_blitz/art/cannon_fire_profile.dart';
import 'package:battleship_blitz/art/fleet_family.dart';
import 'package:battleship_blitz/art/legacy_board_art.dart';
import 'package:battleship_blitz/art/legacy_cannon_art.dart';
import 'package:battleship_blitz/art/legacy_crosshair_art.dart';
import 'package:battleship_blitz/art/legacy_ship_art.dart';
import 'package:battleship_blitz/art/ship_damage_art.dart';
import 'package:battleship_blitz/art/ship_damage_svg.dart';
import 'package:battleship_blitz/art/svg_replay.dart';
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:battleship_blitz/widgets/ship_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _legacyShipIds = [
  'steel', 'crimson', 'emerald', 'gold', 'abyss',
  'arctic', 'coral', 'midnight', 'toxic',
];

const _legacyCannonIds = [
  'mk1', 'inferno', 'kraken', 'phantom', 'royal',
  'sunfire', 'tesla', 'venom', 'void',
];

const _familyCrosshairIds = [
  'f_arctic', 'f_naval', 'f_pirate', 'f_scifi', 'f_steam', 'f_volcanic',
];

void main() {
  // The "unlock everything for testing" flag defaults on (see
  // `fleet_family_test.dart`'s own setup) so the AI-randomisation and
  // legacy-sets tests below — which check REAL ownership gating — need it
  // off for this file. Nothing else here cares either way.
  setUpAll(() => ProfileStore.debugUnlockAllOverride = false);
  tearDownAll(() => ProfileStore.debugUnlockAllOverride = null);

  group('legacy ship hulls', () {
    test('every legacy skin renders for every ship kind', () {
      for (final id in _legacyShipIds) {
        final skin = Catalog.shipById(id);
        for (final kind in ShipKind.values) {
          final rec = ui.PictureRecorder();
          final canvas = Canvas(rec);
          paintLegacyShip(canvas, const Size(300, 100), skin, kind);
          expect(rec.endRecording().approximateBytesUsed,
              greaterThan(_emptyPictureBytes),
              reason: '$id/${kind.name} drew nothing');
        }
      }
    });

    test('every legacy skin has its own ink colour', () {
      final inks = _legacyShipIds.map(legacyShipInk).toSet();
      expect(inks, hasLength(_legacyShipIds.length));
    });
  });

  group('hulls fill their footprint', () {
    // FEEDBACK: the nine legacy yards are authored in one shared 300x100
    // box that almost none of them fills — every yard's destroyer starts
    // roughly a fifth of the way in from the stern edge. Mapping the box
    // rather than the art handed that margin to the screen: a destroyer
    // that stopped short of its own two cells on the board, and hulls
    // that sat small and off-centre in the preview rows.
    test('every legacy hull reports real, non-empty bounds', () {
      for (final id in _legacyShipIds) {
        final skin = Catalog.shipById(id);
        for (final kind in ShipKind.values) {
          final b = hullBounds(skin, kind);
          expect(b.width, greaterThan(0), reason: '$id/${kind.name} width');
          expect(b.height, greaterThan(0), reason: '$id/${kind.name} height');
          expect(b.isFinite, isTrue, reason: '$id/${kind.name} finite');
        }
      }
    });

    test('the shared box really is bigger than what a destroyer draws', () {
      // If this ever stops being true the normalisation is a no-op and
      // the test below is passing for the wrong reason.
      final b = hullBounds(Catalog.shipById('steel'), ShipKind.destroyer);
      expect(b.width, lessThan(280),
          reason: 'a destroyer that already filled the 300-wide box would '
              'mean there was never a gap to close');
    });

    // The real guard, measured in pixels rather than in coordinates: a
    // hull painted into its own footprint has to actually reach both
    // ends of it.
    test('every legacy hull paints all the way to both ends of its box',
        () async {
      const w = 240;
      const h = 60;
      for (final id in _legacyShipIds) {
        final skin = Catalog.shipById(id);
        for (final kind in ShipKind.values) {
          final rec = ui.PictureRecorder();
          ShipPainter(spec: kFleet.firstWhere((s) => s.kind == kind), skin: skin)
              .paint(Canvas(rec), Size(w.toDouble(), h.toDouble()));
          final img = await rec.endRecording().toImage(w, h);
          final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          int alphaAt(int x, int y) => data!.getUint8((y * w + x) * 4 + 3);
          bool columnPainted(int x) {
            for (var y = 0; y < h; y++) {
              if (alphaAt(x, y) > 8) return true;
            }
            return false;
          }

          var first = 0;
          while (first < w && !columnPainted(first)) {
            first++;
          }
          var last = w - 1;
          while (last > first && !columnPainted(last)) {
            last--;
          }
          // A few pixels of slack at each end: `measuredBounds` outsets by
          // half an ink weight so an outline is not clipped, and a pointed
          // bow or stern fades out over a pixel or two of antialiasing.
          // The gap this test exists to catch was a fifth of the hull.
          const slack = 0.03 * w;
          expect(first, lessThan(slack),
              reason: '$id/${kind.name}: $first px of dead space at the stern');
          expect(w - 1 - last, lessThan(slack),
              reason: '$id/${kind.name}: ${w - 1 - last} px of dead space at the bow');
        }
      }
    });
  });

  group('ShipPreviewBox', () {
    // FEEDBACK: the deploy screen's dock tray and the battle screen's
    // fleet strip each carried their OWN copy of this sizing formula, and
    // the dock tray's copy silently never got updated when the formula
    // was fixed — it kept sizing a destroyer into a near-square box long
    // after the fleet strip (right next to it, in the same match) did
    // not. `ShipPreviewBox` exists so both rows read off ONE definition
    // instead of two that can drift apart unnoticed; this locks that
    // definition down so a future change to it is deliberate.
    test('a hull with more cells never gets a narrower box', () {
      const unit = 11.0;
      // kFleet is listed carrier(5) down to destroyer(2), with cruiser and
      // submarine tied at 3 — so this is non-decreasing, not strictly
      // increasing; the tie itself is asserted separately below.
      final widths = [
        for (final spec in kFleet) ShipPreviewBox.width(spec, unit)
      ];
      for (var i = 1; i < widths.length; i++) {
        expect(widths[i], lessThanOrEqualTo(widths[i - 1]),
            reason: '${kFleet[i].kind.name} should not be wider than '
                '${kFleet[i - 1].kind.name}');
      }
    });

    test('two classes with the same cell count get the same width', () {
      const unit = 11.0;
      final cruiser = kFleet.firstWhere((s) => s.kind == ShipKind.cruiser);
      final submarine = kFleet.firstWhere((s) => s.kind == ShipKind.submarine);
      expect(cruiser.size, submarine.size, reason: 'test assumption');
      expect(ShipPreviewBox.width(cruiser, unit),
          ShipPreviewBox.width(submarine, unit));
    });

    test('the shortest hull still gets a non-square box', () {
      const unit = 11.0;
      final destroyer = kFleet.reduce((a, b) => a.size < b.size ? a : b);
      final w = ShipPreviewBox.width(destroyer, unit);
      final h = ShipPreviewBox.beam(unit);
      expect(w / h, greaterThan(1.5),
          reason: 'a near-square box is exactly what squashed the '
              'destroyer\'s art before');
    });

    test('beam scales with the same unit the width does', () {
      expect(ShipPreviewBox.beam(20), 2 * ShipPreviewBox.beam(10));
    });
  });

  group('ship damage flourishes', () {
    test('every legacy skin resolves its own damage style', () {
      final styles = _legacyShipIds.map(damageStyleForShipSkin).toSet();
      expect(styles, hasLength(_legacyShipIds.length),
          reason: 'each legacy skin should read as its own hit, not a shared default');
    });

    test('every family resolves its own damage style', () {
      final styles = FleetFamilyId.values.map(damageStyleForFamily).toSet();
      expect(styles, hasLength(FleetFamilyId.values.length));
    });

    test('every style has authored artwork and renders', () {
      // A style with no entry in `shipDamageSvg` would silently draw
      // NOTHING at all — `paintShipDamage` returns early — so a hit
      // would land with no visible mark. Checked per style rather than
      // by map length so the failure names the missing one.
      for (final style in DamageStyle.values) {
        expect(shipDamageSvg.containsKey(style), isTrue,
            reason: '${style.name} has no authored SVG');
        final rec = ui.PictureRecorder();
        paintShipDamage(Canvas(rec), const Offset(50, 50), 15, style);
        expect(rec.endRecording().approximateBytesUsed,
            greaterThan(_emptyPictureBytes),
            reason: '${style.name} drew nothing');
      }
    });

    test('no two projectiles share the same artwork', () {
      expect(shipDamageSvg.values.toSet(), hasLength(DamageStyle.values.length),
          reason: 'two projectiles leaving an identical wound is the bug '
              'this whole variant set exists to avoid');
    });
  });

  group('svg replay', () {
    // ROOT-CAUSE REGRESSION (the "missing circle detail in the middle of
    // the MK-I"): `<g>` merged its attributes into the running style and
    // `</g>` restored only the canvas, so a group's opacity leaked into
    // everything drawn after it. Every legacy cannon ends its ring markup
    // with a rivet group at opacity 0.55 — and MK-I adds a second at 0.28
    // — so the mount collar and rivets that follow were drawn at 55% and
    // 15% alpha respectively. Measured in pixels, because the whole
    // failure mode was "the markup is right and the screen is wrong".
    test('a group does not leak its opacity past its own closing tag',
        () async {
      const w = 40, h = 20;
      final rec = ui.PictureRecorder();
      paintSvgFragment(
        Canvas(rec),
        '<g fill="#000000" opacity="0.1">'
        '<circle cx="10" cy="10" r="4"></circle>'
        '</g>'
        '<circle cx="30" cy="10" r="8" fill="#FF0000"></circle>',
      );
      final img = await rec.endRecording().toImage(w, h);
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      int at(int x, int y, int channel) =>
          data!.getUint8(((y * w + x) * 4) + channel);
      expect(at(30, 10, 3), 255,
          reason: 'the circle AFTER the group should be fully opaque');
      expect(at(30, 10, 0), 255, reason: 'and still its own red');
    });

    test('polygon points are drawn', () async {
      // The design's ship-damage SVGs draw most of their crater geometry
      // as <polygon>, which the replayer used to ignore outright.
      final rec = ui.PictureRecorder();
      paintSvgFragment(Canvas(rec),
          '<polygon points="2,2 38,2 38,18 2,18" fill="#FF0000"></polygon>');
      final img = await rec.endRecording().toImage(40, 20);
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data!.getUint8(((10 * 40 + 20) * 4) + 3), 255,
          reason: 'polygon interior should be filled');
    });
  });

  group('legacy cannons', () {
    test('every legacy cannon body renders and returns a muzzle tip', () {
      for (final id in _legacyCannonIds) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        final tip = paintLegacyCannon(canvas, const Offset(50, 50), 24, id);
        expect(tip, isNot(const Offset(50, 50)),
            reason: '$id: muzzle tip should not sit exactly on the mount centre');
        expect(rec.endRecording().approximateBytesUsed,
            greaterThan(_emptyPictureBytes),
            reason: '$id drew nothing');
      }
    });

    test('legacy cannons are not all pinned to one shared muzzle fraction', () {
      // REDESIGN: the nine originals used to share one fixed constant.
      // Each now reads its own turret's real tip position — most differ,
      // though a couple of very different silhouettes (e.g. phantom and
      // mk1) can legitimately land on the same y by coincidence.
      final fractions = _legacyCannonIds.map(legacyMuzzleFractionOf).toSet();
      expect(fractions.length, greaterThan(1));
      expect(legacyMuzzleFractionOf('inferno'),
          isNot(legacyMuzzleFractionOf('mk1')));
    });

    test('hit and miss marks render for every legacy cannon', () {
      for (final id in _legacyCannonIds) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        paintLegacyHit(canvas, const Offset(20, 20), 40, id);
        paintLegacyMiss(canvas, const Offset(60, 20), 40, id);
        expect(rec.endRecording().approximateBytesUsed,
            greaterThan(_emptyPictureBytes),
            reason: '$id hit/miss drew nothing');
      }
    });

    // FEEDBACK: the reload sweep is drawn between the ring plate and the
    // turret now, so the barrel sits on top of it — two nested save/
    // restore pairs where there used to be one, which is exactly the
    // kind of change that leaves a canvas unbalanced if it goes wrong.
    test('a reloading cannon still renders and leaves the canvas balanced', () {
      for (final id in _legacyCannonIds) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        canvas.save();
        final before = canvas.getSaveCount();
        final tip = paintLegacyCannon(canvas, const Offset(50, 50), 24, id,
            cooldown: 0.4, recoilPull: 3);
        expect(canvas.getSaveCount(), before,
            reason: '$id: reload path left the save stack unbalanced');
        expect(tip, isNot(const Offset(50, 50)));
        canvas.restore();
        expect(rec.endRecording().approximateBytesUsed,
            greaterThan(_emptyPictureBytes),
            reason: '$id drew nothing while reloading');
      }
    });

    test('a fully loaded cannon draws no reload sweep', () {
      // cooldown defaults to 1 and every non-battle caller (previews,
      // the transition overlay) relies on that meaning "no ring at all".
      int bytes(double cooldown) {
        final rec = ui.PictureRecorder();
        paintLegacyCannon(
            Canvas(rec), const Offset(50, 50), 24, 'mk1', cooldown: cooldown);
        return rec.endRecording().approximateBytesUsed;
      }

      expect(bytes(1.0), lessThan(bytes(0.5)));
      expect(bytes(1.0), bytes(0.9995));
    });
  });

  group('legacy and family crosshairs', () {
    test('every legacy and family crosshair renders', () {
      for (final id in [..._legacyCannonIds, ..._familyCrosshairIds]) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        paintLegacyCrosshair(canvas, const Size(40, 40), id);
        expect(rec.endRecording().approximateBytesUsed,
            greaterThan(_emptyPictureBytes),
            reason: '$id crosshair drew nothing');
      }
    });

    test('an unrecognised id falls back to mk1 rather than drawing nothing', () {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      paintLegacyCrosshair(canvas, const Size(40, 40), 'not_a_real_id');
      expect(rec.endRecording().approximateBytesUsed,
          greaterThan(_emptyPictureBytes));
    });
  });

  group('legacy battlefields', () {
    test('every legacy cannon has its own matching, purchasable battlefield', () {
      for (final id in _legacyCannonIds) {
        final theme = Catalog.gameplayThemes.where((t) => t.id == id);
        expect(theme, hasLength(1), reason: 'no legacy battlefield for $id');
        expect(theme.first.legacy, isTrue, reason: '$id battlefield not flagged legacy');
        expect(theme.first.familyKey, isNull,
            reason: 'a legacy battlefield must not also claim a family');
      }
    });

    test('every legacy battlefield renders', () {
      for (final id in _legacyCannonIds) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        paintLegacyBoard(canvas, const Size(400, 400), id);
        expect(rec.endRecording().approximateBytesUsed,
            greaterThan(_emptyPictureBytes),
            reason: '$id battlefield drew nothing');
      }
    });
  });

  group('cannon fire profiles', () {
    test('every legacy cannon has its own profile, not the fallback default', () {
      // mk1 legitimately IS the default, so it's excluded from the
      // "not shared with anything else" check below.
      final profiles = _legacyCannonIds
          .where((id) => id != 'mk1')
          .map((id) => fireProfileFor(Catalog.cannonById(id)))
          .toList();
      final characters = profiles.map((p) => p.character).toSet();
      expect(characters.length, greaterThan(1),
          reason: 'every legacy gun sharing one recoil character defeats the point');
    });

    test('every family has its own profile, resolved by familyKey not id', () {
      for (final f in FleetFamilies.all) {
        final skin = Catalog.cannonById('f_${f.key}');
        final profile = fireProfileFor(skin);
        // A family id (e.g. "f_pirate") must not accidentally fall through
        // to the legacy-id lookup and land on the mk1 default.
        expect(profile.recoilDuration, isNot(const Duration(milliseconds: 260)),
            reason: '${f.key}: looks like it fell through to the default profile');
      }
    });

    test('an unrecognised skin falls back to the default profile rather than throwing', () {
      const unknown = CannonSkin('not_real', 'x', Color(0xFF000000), Color(0xFF000000), '', 1, 0);
      expect(() => fireProfileFor(unknown), returnsNormally);
    });

    test('every recoil character stays finite across the whole 0..1 sweep', () {
      for (final character in RecoilCharacter.values) {
        for (var i = 0; i <= 10; i++) {
          final shape = shapeRecoil(character, i / 10);
          expect(shape.vertical.isFinite, isTrue, reason: '$character vertical');
          expect(shape.lateral.isFinite, isTrue, reason: '$character lateral');
          expect(shape.opacity, inInclusiveRange(0.0, 1.0), reason: '$character opacity');
        }
      }
    });

    test('only jitter and sway carry a lateral shake', () {
      for (final character in RecoilCharacter.values) {
        final midLateral = shapeRecoil(character, 0.5).lateral;
        final isShake =
            character == RecoilCharacter.jitter || character == RecoilCharacter.sway;
        expect(midLateral != 0, isShake, reason: '$character');
      }
    });
  });

  group('damage keyed by shooter', () {
    test('every legacy cannon resolves its own damage style', () {
      final styles = _legacyCannonIds.map(damageStyleForCannon).toSet();
      expect(styles.length, _legacyCannonIds.length,
          reason: 'every legacy gun should leave its own mark, not a shared default');
    });

    test('an unrecognised cannon id falls back rather than throwing', () {
      expect(() => damageStyleForCannon('not_real'), returnsNormally);
    });

    test('damageStyleForShooter resolves both legacy and family guns', () {
      for (final id in _legacyCannonIds) {
        expect(damageStyleForShooter(Catalog.cannonById(id)),
            damageStyleForCannon(id));
      }
      for (final f in FleetFamilies.all) {
        expect(damageStyleForShooter(Catalog.cannonById('f_${f.key}')),
            damageStyleForFamily(f.id));
      }
    });

    // FEEDBACK ("the ship damage is all the same on the cannons"): every
    // view that shows a damaged or sunk hull — the fleet strip's wrecked
    // previews, the ghost-fleet sinking hull, the board's wreck reveal —
    // used to leave `shooterCannonId` null and fall back to a style keyed
    // to the DEFENDER, so one board's worth of damage looked identical no
    // matter what had been firing at it. This is the painter-level
    // contract those call sites now rely on.
    test('one hull, two different shooters, two different wounds', () {
      int bytes(String? shooter) {
        final rec = ui.PictureRecorder();
        ShipPainter(
          spec: kFleet[1],
          skin: Catalog.shipById('steel'),
          sunk: true,
          hitCount: kFleet[1].size,
          shooterCannonId: shooter,
        ).paint(Canvas(rec), const Size(160, 40));
        return rec.endRecording().approximateBytesUsed;
      }

      // `royal` draws an eight-ray starburst, `void`'s flechette is a
      // single puncture and one hairline crack — the two ends of the
      // roster, so a shared fallback could not produce both sizes.
      expect(bytes('royal'), isNot(bytes('void')));
      // And the null fallback still works for the genuine preview callers
      // (shipyard, dock, drag ghost), which have no shooter at all.
      expect(bytes(null), greaterThan(_emptyPictureBytes));
    });
  });

  group('projectile wound colour', () {
    // FEEDBACK ("every cannon projectile has the same effects"): the
    // wound's shape was already keyed to the shooter, but at a battle
    // grid's cell size the shape is fine detail — what actually reads is
    // the colour, and that came from the struck hull plus a hardcoded
    // orange ember, identically for every gun.
    test('every projectile has its own accent, none shared', () {
      final accents = DamageStyle.values.map(damageAccentFor).toSet();
      expect(accents, hasLength(DamageStyle.values.length),
          reason: 'two projectiles sharing a colour is the bug this fixes');
    });

    test('a wound is coloured by the gun, not by the hull it lands on', () {
      // Same hull, same hits, two guns: the marks must differ.
      int bytesFor(String hull, String? shooter) {
        final rec = ui.PictureRecorder();
        ShipPainter(
          spec: kFleet[1],
          skin: Catalog.shipById(hull),
          hitCount: kFleet[1].size,
          shooterCannonId: shooter,
        ).paint(Canvas(rec), const Size(160, 40));
        return rec.endRecording().approximateBytesUsed;
      }

      expect(bytesFor('steel', 'venom'), isNot(bytesFor('steel', 'royal')));
      // ...and the same gun on two different hulls keeps its own colour,
      // which is the half that used to be backwards.
      expect(damageAccentFor(damageStyleForCannon('venom')),
          damageAccentFor(damageStyleForShooter(Catalog.cannonById('venom'))));
    });

    test('a family gun leaves its family shell mark, not the hull owner\'s', () {
      for (final f in FleetFamilies.all) {
        final gun = Catalog.cannonById('f_${f.key}');
        expect(damageAccentFor(damageStyleForShooter(gun)),
            damageAccentFor(damageStyleForFamily(f.id)));
      }
    });
  });

  group('legacy cannon names', () {
    // FEEDBACK: these three are named for their fleet identity now (see
    // `legacy_identity.dart`), not for the id they happen to carry.
    test('phantom, tesla and kraken read as Abyss, Arctic and Emerald', () {
      expect(Catalog.cannonById('phantom').name, 'Abyss Railgun');
      expect(Catalog.cannonById('tesla').name, 'Arctic Coilgun');
      expect(Catalog.cannonById('kraken').name, 'Emerald Cannon');
    });

    test('no two cannons share a display name', () {
      final names = Catalog.cannonSkins.map((c) => c.name).toSet();
      expect(names, hasLength(Catalog.cannonSkins.length));
    });
  });

  group('AI cosmetic randomisation', () {
    test('randomOwned only ever returns pieces the profile actually owns', () {
      final profile = ProfileStore()
        ..owned = {
          'ship:steel', 'ship:crimson',
          'cannon:mk1', 'cannon:inferno',
          'theme:mk1', 'theme:inferno',
        };
      final rng = Random(7);
      for (var i = 0; i < 50; i++) {
        final lo = Loadout.randomOwned(profile, rng: rng);
        expect(profile.ownsShip(lo.shipSkinId), isTrue, reason: lo.shipSkinId);
        expect(profile.ownsCannon(lo.cannonSkinId), isTrue, reason: lo.cannonSkinId);
        expect(profile.ownsTheme(lo.themeId), isTrue, reason: lo.themeId);
        expect(lo.shipChosen, isTrue,
            reason: 'a plain, un-chosen skin falls back to side colours — '
                'defeats the point of picking one');
      }
    });

    test('randomOwned never crashes on a bare starter profile', () {
      final profile = ProfileStore();
      expect(() => Loadout.randomOwned(profile), returnsNormally);
      final lo = Loadout.randomOwned(profile);
      expect(lo.shipSkinId, 'steel');
      expect(lo.cannonSkinId, 'mk1');
      expect(lo.themeId, 'mk1');
    });
  });

  group('legacy sets', () {
    test('nine legacy sets, each lining up with a real catalogue entry', () {
      expect(Catalog.legacySets, hasLength(9));
      for (final set in Catalog.legacySets) {
        expect(Catalog.shipSkins.map((s) => s.id), contains(set.shipSkinId));
        expect(Catalog.cannonSkins.map((c) => c.id), contains(set.id));
        expect(Catalog.gameplayThemes.map((t) => t.id), contains(set.id));
      }
    });

    test('ownsLegacySet is true only once all three pieces are owned', () {
      final set = Catalog.legacySets.firstWhere((s) => s.id == 'inferno');
      final p = ProfileStore()..owned = {};
      expect(p.ownsLegacySet(set), isFalse);
      p.owned = {'ship:crimson', 'cannon:inferno'};
      expect(p.ownsLegacySet(set), isFalse, reason: 'missing the board');
      p.owned = {'ship:crimson', 'cannon:inferno', 'theme:inferno'};
      expect(p.ownsLegacySet(set), isTrue);
    });
  });
}

/// Byte size of a recording with nothing drawn into it, so "did this
/// actually paint?" is measured against a real baseline instead of
/// against zero — an empty picture is not zero bytes.
final int _emptyPictureBytes = () {
  final rec = ui.PictureRecorder();
  Canvas(rec);
  return rec.endRecording().approximateBytesUsed;
}();
