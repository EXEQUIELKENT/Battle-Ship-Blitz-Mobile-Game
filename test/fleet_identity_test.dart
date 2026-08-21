import 'package:battleship_blitz/core/fleet_identity.dart';
import 'package:battleship_blitz/core/theme.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fleet identity', () {
    test('a captain who never picked a hull sails their side colour', () {
      final red = fleetLook(
        isRedSide: true,
        equippedShipSkinId: 'steel',
        chosen: false,
      );
      final blue = fleetLook(
        isRedSide: false,
        equippedShipSkinId: 'steel',
        chosen: false,
      );

      expect(red.skin.hull, AppColors.shipRed);
      expect(blue.skin.hull, AppColors.shipBlue);
      expect(red.skinned, isFalse);
      expect(red.label, 'RED FLEET');
      expect(blue.label, 'BLUE FLEET');
    });

    test('two untouched profiles stay visibly different sides', () {
      // The regression this whole flag exists to prevent: treating the
      // starter hull as "a skin" put both captains in the same grey and
      // threw away the only thing telling them apart.
      final host = fleetLook(
          isRedSide: true, equippedShipSkinId: 'steel', chosen: false);
      final guest = fleetLook(
          isRedSide: false, equippedShipSkinId: 'steel', chosen: false);
      expect(host.color, isNot(guest.color));
    });

    test('equipping Steel Fleet on purpose actually shows Steel Fleet', () {
      // The other half of the same problem: steel is BOTH the default and
      // a real, choosable skin, so a player who deliberately picked it
      // must not be silently overruled back to a side colour.
      final look = fleetLook(
        isRedSide: true,
        equippedShipSkinId: 'steel',
        chosen: true,
      );
      expect(look.skinned, isTrue);
      expect(look.skin.id, 'steel');
      expect(look.skin.hull, Catalog.shipById('steel').hull);
      expect(look.label, 'STEEL FLEET');
    });

    test('an equipped skin overrides the side colour and names itself', () {
      final look = fleetLook(
        isRedSide: true,
        equippedShipSkinId: 'emerald',
        chosen: true,
      );
      expect(look.skin.hull, Catalog.shipById('emerald').hull);
      expect(look.label, 'EMERALD TIDE');
      // Still knows which side it is, for anything that needs the raw role.
      expect(look.isRedSide, isTrue);
    });

    test('skins are ignored where they do not apply', () {
      final look = fleetLook(
        isRedSide: false,
        equippedShipSkinId: 'gold',
        chosen: true,
        skinsApply: false,
      );
      expect(look.skin.hull, AppColors.shipBlue);
      expect(look.skinned, isFalse);
    });

    test('ink stays readable on every hull in the catalogue', () {
      for (final skin in Catalog.shipSkins) {
        final look = fleetLook(
          isRedSide: true,
          equippedShipSkinId: skin.id,
          chosen: true,
        );
        final contrast = _contrastRatio(look.ink, look.color);
        expect(
          contrast,
          greaterThan(4.0),
          reason: '${skin.name} label contrast is only '
              '${contrast.toStringAsFixed(2)}:1',
        );
      }
    });

    test('the palest and darkest hulls get opposite ink', () {
      // Arctic Storm is near-white and Midnight Ops near-black; a fixed
      // cream label would be invisible on the first.
      final arctic = fleetLook(
          isRedSide: true, equippedShipSkinId: 'arctic', chosen: true);
      final midnight = fleetLook(
          isRedSide: true, equippedShipSkinId: 'midnight', chosen: true);
      expect(arctic.ink, AppColors.outline);
      expect(midnight.ink, AppColors.cream);
    });
  });

  group('per-seat loadouts', () {
    test('a loadout copied from a profile carries the chosen flag', () {
      final profile = ProfileStore()
        ..shipSkinId = 'coral'
        ..shipSkinChosen = true
        ..cannonSkinId = 'tesla'
        ..gameplayThemeId = 'deep';

      final lo = Loadout.of(profile);
      expect(lo.shipSkinId, 'coral');
      expect(lo.shipChosen, isTrue);
      expect(lo.cannonSkin.id, 'tesla');
      expect(lo.theme.id, 'deep');
    });

    test('copyWith changes one field and leaves the rest alone', () {
      const base = Loadout(
        shipSkinId: 'gold',
        cannonSkinId: 'royal',
        themeId: 'sunset',
        shipChosen: true,
      );
      final next = base.copyWith(cannonSkinId: 'venom');
      expect(next.cannonSkinId, 'venom');
      expect(next.shipSkinId, 'gold');
      expect(next.themeId, 'sunset');
      expect(next.shipChosen, isTrue);
    });

    test('a fresh loadout defaults to the unchosen starter gear', () {
      const lo = Loadout();
      expect(lo.shipSkinId, 'steel');
      expect(lo.shipChosen, isFalse);
      expect(lo.cannonSkinId, 'mk1');
      expect(lo.themeId, 'classic');
    });
  });
}

/// WCAG relative-luminance contrast ratio, so the readability assertion
/// above is a real measurement rather than a guess about which colours
/// "look fine".
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
