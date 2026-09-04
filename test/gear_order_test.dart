import 'package:battleship_blitz/art/fleet_family.dart';
import 'package:battleship_blitz/art/legacy_identity.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The deploy screen's GEAR dialog sorts its HULL, CANNON and DECK rows
/// through [gearRank] so the same identity sits in the same place in each.
/// Before that, every catalogue had its own order and none fully agreed.
void main() {
  List<String> ranked<T>(List<T> items, String? Function(T) family,
          String? Function(T) id) =>
      (items.toList()
            ..sort((a, b) =>
                gearRank(family(a), id(a)).compareTo(gearRank(family(b), id(b)))))
          .map((e) => '${gearRank(family(e), id(e))}')
          .toList();

  test('every catalogue fills each gear slot exactly once', () {
    final hulls = ranked(Catalog.shipSkins, (s) => s.familyKey, (s) => s.id);
    final cannons =
        ranked(Catalog.cannonSkins, (c) => c.familyKey, (c) => c.id);
    final decks =
        ranked(Catalog.gameplayThemes, (t) => t.familyKey, (t) => t.id);

    expect(cannons, hulls);
    expect(decks, hulls);
    // The real property: each catalogue maps onto the slots one-to-one —
    // nine legacy identities then six families, with nothing colliding or
    // falling off the end into the catch-all rank. That is what makes the
    // three sorted rows line up; the sorting itself is one call per row in
    // the dialog.
    expect(
      hulls,
      List.generate(legacyIdentities.length + FleetFamilies.all.length,
          (i) => '$i'),
    );
  });

  test('legacy identities come before families', () {
    for (final l in legacyIdentities) {
      expect(gearRank(null, l.id), lessThan(legacyIdentities.length));
      expect(gearRank(null, l.shipSkinId), gearRank(null, l.id),
          reason: '${l.shipSkinId} must rank with its own ${l.id}');
    }
    for (final f in FleetFamilies.all) {
      expect(gearRank(f.key, null),
          greaterThanOrEqualTo(legacyIdentities.length));
    }
  });
}
