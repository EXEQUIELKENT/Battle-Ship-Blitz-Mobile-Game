import 'package:flutter/material.dart';

import 'fleet_family.dart';

/// The nine legacy identities' own short name + accent colour, ported
/// verbatim from `uploads/New Design/Adjustments/*.dart` (a naming/colour
/// manifest, not new geometry — every file there is a `skin`/`accent`
/// stub with the actual shape left to whatever already draws that piece).
///
/// Each entry's [id] is the shared legacy cannon/gameplay-theme id (see
/// `GameplayTheme.legacy`); [shipSkinId] is the matching legacy ship skin
/// — the two live in different id namespaces (`mk1` vs `steel`), paired
/// by the same `exhaustId`-style convention the design's own asset
/// filenames use throughout (`steel-fire-reload_cannon_fx.dart` names
/// `exhaustId = 'mk1'` inside it, and so on for all nine).
///
/// [accent] is this identity's single "pop" colour — the crosshair
/// reticle, the hit/miss glow, the deck's accent decorations, and the
/// cannon ring's own accent ring all read from it. Consumed by
/// `legacy_cannon_art.dart`/`legacy_board_art.dart`/
/// `legacy_crosshair_art.dart` for the recolour pass, and by
/// `Catalog.legacySets` (`storage_service.dart`) for the gear-dialog set
/// chips — one source for both.
class LegacyIdentity {
  final String id;
  final String shipSkinId;
  final String name;
  final Color accent;

  const LegacyIdentity(this.id, this.shipSkinId, this.name, this.accent);
}

const List<LegacyIdentity> legacyIdentities = [
  LegacyIdentity('mk1', 'steel', 'Steel', Color(0xFF94A3B8)),
  LegacyIdentity('inferno', 'crimson', 'Crimson', Color(0xFFEF4444)),
  LegacyIdentity('kraken', 'emerald', 'Emerald', Color(0xFF34D399)),
  LegacyIdentity('royal', 'gold', 'Gold', Color(0xFFFBBF24)),
  LegacyIdentity('phantom', 'abyss', 'Abyss', Color(0xFF7C6BC4)),
  LegacyIdentity('tesla', 'arctic', 'Arctic', Color(0xFF7FB8D6)),
  LegacyIdentity('sunfire', 'coral', 'Coral', Color(0xFFE0715A)),
  LegacyIdentity('void', 'midnight', 'Midnight', Color(0xFF4B72A8)),
  LegacyIdentity('venom', 'toxic', 'Toxic', Color(0xFFA3E635)),
];

LegacyIdentity legacyIdentityFor(String cannonId) => legacyIdentities.firstWhere(
      (l) => l.id == cannonId,
      orElse: () => legacyIdentities.first,
    );

/// Where an identity sits in the GAMEPLAY row: the nine legacy identities
/// in [legacyIdentities] order, then the six families in
/// [FleetFamilies.all] order. [id] is an identity's own id (a cannon or a
/// deck) or its ship skin's — one lookup serves all three catalogues.
///
/// FEEDBACK ("make the cannon, deck and ship rows follow the gameplay
/// row's sequence"): each catalogue had grown its own order and none of
/// them fully agreed. Hulls happened to match the sets row, but cannons
/// and decks ran `…tesla, venom, royal, phantom, kraken…` against the
/// sets' `…kraken, royal, phantom, tesla…`, and the family tails
/// disagreed too (hulls put Rime before Brass, the others the reverse).
/// So one identity sat in a different place in every row, and assembling a
/// matching set by hand meant re-finding it three times. Sorting the rows
/// through this lines them up without disturbing the catalogues, which are
/// also the shop's own order.
int gearRank(String? familyKey, String? id) {
  if (familyKey != null) {
    final family = FleetFamilies.byKey(familyKey);
    final i = family == null ? -1 : FleetFamilies.all.indexOf(family);
    return legacyIdentities.length + (i < 0 ? FleetFamilies.all.length : i);
  }
  final i = legacyIdentities.indexWhere((l) => l.id == id || l.shipSkinId == id);
  return i < 0 ? legacyIdentities.length : i;
}
