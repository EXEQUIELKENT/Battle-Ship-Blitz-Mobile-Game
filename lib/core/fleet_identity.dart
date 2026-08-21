import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import 'theme.dart';

// One place that decides what colour a captain's fleet is, so the
// deployment screen, the mode vote and the battle grid can never
// disagree with each other.
//
// The rule, in one sentence: a captain who has actually been to the
// shipyard and equipped a hull sails that hull; a captain who never
// picked one sails their SIDE's colour — red for the host / Player 1,
// blue for the challenger / Player 2.
//
// Why the "actually picked one" part needs its own flag rather than
// just comparing against the catalogue's first entry: Steel Fleet is
// both the free starter hull AND a real, equippable skin. Treating "is
// steel equipped" as "never chose anything" meant a captain who
// deliberately picked Steel Fleet was silently overruled and handed a
// side colour instead. Treating it as "chose steel" instead put two
// untouched profiles into two identical grey fleets and threw away the
// only thing telling the sides apart. Neither is right, because the two
// cases are genuinely different states that the equipped id alone
// cannot distinguish — so [ProfileStore.shipSkinChosen] records which
// one it is.


/// The flat red hull a captain sails when they have not picked a skin.
const ShipSkin kRedFleetSkin = ShipSkin(
  'side.red',
  'Red Fleet',
  AppColors.shipRed,
  AppColors.shipRedDark,
  0,
);

/// The flat blue hull, likewise.
const ShipSkin kBlueFleetSkin = ShipSkin(
  'side.blue',
  'Blue Fleet',
  AppColors.shipBlue,
  AppColors.shipBlueDark,
  0,
);

/// Everything about how one captain's fleet reads on screen: the hull it
/// is painted in, the colour that stands for them in UI chrome, and ink
/// that stays legible on top of it.
class FleetLook {
  /// The hull skin the ships are actually drawn with.
  final ShipSkin skin;

  /// Whether this look came from an equipped skin (true) or fell back to
  /// the plain red/blue side colour (false).
  final bool skinned;

  /// True when this captain is on the red side, whether or not they are
  /// currently wearing a skin. Kept so callers that still want the raw
  /// side identity (the remaining-ships badge, for one) can ask.
  final bool isRedSide;

  const FleetLook({
    required this.skin,
    required this.skinned,
    required this.isRedSide,
  });

  /// The captain's colour anywhere outside the ships themselves —
  /// highlight borders, name chips, vote badges.
  Color get color => skin.hull;

  /// Secondary tone of the same identity, for trim and shadows.
  Color get trim => skin.trim;

  /// Text/icon colour that stays readable on top of [color].
  ///
  /// Hull colours span the full range from Midnight Ops (near black) to
  /// Arctic Storm (near white), so a fixed cream label is invisible on
  /// roughly a third of the catalogue. Picking the ink from the hull's
  /// own luminance keeps every name chip and vote badge readable no
  /// matter what either captain turns up wearing.
  Color get ink =>
      skin.hull.computeLuminance() > 0.5 ? AppColors.outline : AppColors.cream;

  /// Softer version of [ink] for the secondary line inside a chip.
  Color get inkSoft => ink.withValues(alpha: 0.78);

  /// What to call this fleet in the UI: the skin's own name once one is
  /// equipped, otherwise the side colour. Telling a captain in Emerald
  /// Tide that they command the "RED FLEET" would just be wrong.
  String get label =>
      (skinned ? skin.name : (isRedSide ? 'Red Fleet' : 'Blue Fleet'))
          .toUpperCase();

  /// Border colour that keeps a very pale hull from vanishing into a
  /// light background.
  Color get border => AppColors.outline;
}

/// Resolves a captain's look from their side and their equipped loadout.
///
/// [skinsApply] is false for the one place ship skins deliberately do not
/// show up — local pass-and-play before either player has picked, and any
/// screen where both fleets belong to the same person — in which case the
/// plain side colour is always used.
FleetLook fleetLook({
  required bool isRedSide,
  required String equippedShipSkinId,
  required bool chosen,
  bool skinsApply = true,
}) {
  final sideSkin = isRedSide ? kRedFleetSkin : kBlueFleetSkin;
  if (!skinsApply || !chosen) {
    return FleetLook(skin: sideSkin, skinned: false, isRedSide: isRedSide);
  }
  return FleetLook(
    skin: Catalog.shipById(equippedShipSkinId),
    skinned: true,
    isRedSide: isRedSide,
  );
}
