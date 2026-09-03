
import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import 'fleet_family.dart';
import 'ship_damage_svg.dart';
import 'svg_replay.dart';

/// Which projectile hit — ported from `Ship Damage Variants.dc.html`,
/// which names 15 hit "flourishes": the 6 already-named family shells
/// (see [MuzzleExhaust]) plus one new legacy shell per legacy ship skin.
/// Mirrors [MuzzleExhaust]'s own pattern: a shape picked by what fired,
/// never a duration or a base geometry — the shared crater
/// `ShipPainter._drawDamageMark` already draws is untouched by this at
/// all; only the accents layered on top of it vary.
enum DamageStyle {
  roundShot, // pirate — blunt splinter burst, no glow
  saboShell, // naval — clean through-puncture, ruler-straight fractures
  governorSphere, // steam — gear-tooth dent, vented steam curl
  rimeShard, // arctic (family) — fine frost spiderweb, loose ice chips
  emberSlug, // volcanic — molten cracks, climbing embers
  plasmaBolt, // scifi — no crater at all, a clean glowing burn ring
  apSlug, // steel — punched hole, rivet holes, one metal shaving
  spikeLance, // crimson — elongated barbed tear, blood-red drips
  thornPod, // emerald — jagged bloom, standing thorns, beading sap
  gildedOrb, // gold — full starburst, gem-cut shrapnel
  phantomRing, // abyss — no fill at all, hollow dashed rings
  glacierRound, // arctic (legacy) — blocky angular plate-crater
  barnacleShot, // coral — polyp bumps at the rim, rising bubbles
  flechetteDart, // midnight — one clean puncture, one hairline crack
  scrapSlug, // toxic — ragged sawtooth tear, dripping ooze
}

DamageStyle damageStyleForShipSkin(String skinId) => switch (skinId) {
      'steel' => DamageStyle.apSlug,
      'crimson' => DamageStyle.spikeLance,
      'emerald' => DamageStyle.thornPod,
      'gold' => DamageStyle.gildedOrb,
      'abyss' => DamageStyle.phantomRing,
      'arctic' => DamageStyle.glacierRound,
      'coral' => DamageStyle.barnacleShot,
      'midnight' => DamageStyle.flechetteDart,
      'toxic' => DamageStyle.scrapSlug,
      _ => DamageStyle.apSlug,
    };

DamageStyle damageStyleForFamily(FleetFamilyId id) => switch (id) {
      FleetFamilyId.pirate => DamageStyle.roundShot,
      FleetFamilyId.naval => DamageStyle.saboShell,
      FleetFamilyId.steam => DamageStyle.governorSphere,
      FleetFamilyId.arctic => DamageStyle.rimeShard,
      FleetFamilyId.volcanic => DamageStyle.emberSlug,
      FleetFamilyId.scifi => DamageStyle.plasmaBolt,
    };

/// FEEDBACK: a hit's flourish should read as "what gun fired this",
/// not "whose hull got hit" — the ship↔cannon pairing below is the same
/// one `Ship Damage Variants` and `Legacy Skin Assets` both use (each
/// legacy cannon id's matching legacy ship skin), so this reuses the
/// EXACT same 9 [DamageStyle] values [damageStyleForShipSkin] already
/// maps, just re-keyed from the struck ship's skin to the shooter's gun.
DamageStyle damageStyleForCannon(String cannonId) => switch (cannonId) {
      'mk1' => DamageStyle.apSlug,
      'inferno' => DamageStyle.spikeLance,
      'kraken' => DamageStyle.thornPod,
      'phantom' => DamageStyle.phantomRing,
      'royal' => DamageStyle.gildedOrb,
      'sunfire' => DamageStyle.barnacleShot,
      'tesla' => DamageStyle.glacierRound,
      'venom' => DamageStyle.scrapSlug,
      'void' => DamageStyle.flechetteDart,
      _ => DamageStyle.apSlug,
    };

/// Resolves whichever gun actually fired the shot — a family cannon by
/// its family, a legacy cannon by its own id — so callers don't need to
/// branch on [CannonSkin.familyKey] themselves.
DamageStyle damageStyleForShooter(CannonSkin shooter) {
  final family = FleetFamilies.byKey(shooter.familyKey);
  return family != null
      ? damageStyleForFamily(family.id)
      : damageStyleForCannon(shooter.id);
}

/// Each projectile's own accent colour, ported verbatim from `uploads/New
/// Design/Ship Damage/*_damage.dart` (each file's `static const Color
/// accent`, alongside the `projectile`/`fleet` labels the enum comments
/// above already carry).
///
/// FEEDBACK ("every cannon projectile has the same effect"): the wound's
/// SHAPE has been keyed to the shooter for a while, but its COLOUR was
/// not — the flourish was recoloured through the struck HULL's own
/// ink/trim, and the crater under it finished with a hardcoded orange
/// ember. On one board that meant every hit, from every gun, came out the
/// same two colours; the shape differences are fine detail at a battle
/// grid's cell size, so what a player actually saw was one identical
/// orange scorch mark for the whole match. This is the token that makes a
/// Toxic hit land green and a Gold hit land gold. `ink` is still the
/// struck hull's own dark tone, so the wound still reads as damage TO
/// that hull rather than a decal floating on top of it.
Color damageAccentFor(DamageStyle style) => switch (style) {
      DamageStyle.roundShot => const Color(0xFFF2B24C),
      DamageStyle.saboShell => const Color(0xFFCFE0EA),
      DamageStyle.governorSphere => const Color(0xFFE8A33D),
      DamageStyle.rimeShard => const Color(0xFFBDF1FF),
      DamageStyle.emberSlug => const Color(0xFFFF6A2B),
      DamageStyle.plasmaBolt => const Color(0xFF6FE7FF),
      DamageStyle.apSlug => const Color(0xFF94A3B8),
      DamageStyle.spikeLance => const Color(0xFFEF4444),
      DamageStyle.thornPod => const Color(0xFF34D399),
      DamageStyle.gildedOrb => const Color(0xFFFBBF24),
      DamageStyle.phantomRing => const Color(0xFFA78BFA),
      DamageStyle.glacierRound => const Color(0xFFBAE6FD),
      DamageStyle.barnacleShot => const Color(0xFFFF9E7A),
      DamageStyle.flechetteDart => const Color(0xFF8FB6E0),
      DamageStyle.scrapSlug => const Color(0xFFA3E635),
    };


/// Draws the whole wound [style] leaves at [center], replayed verbatim
/// from the design's own SVG for that projectile — see `ship_damage_svg
/// .dart`.
///
/// [r] is the wound's characteristic radius (`cellSize * 0.30` at every
/// call site). The design authors each wound in a 120×120 box centred on
/// (60,60) whose own halo sits at radius 36, so mapping design-36 onto
/// [r] keeps every wound exactly the size and position the hand-drawn
/// flourishes were — this swapped the artwork, not the layout.
///
/// The SVGs carry their own halo, crater and core, so unlike the
/// flourishes they replaced this is the ENTIRE mark: nothing should be
/// drawn underneath it (see `ShipPainter`, which used to add a generic
/// crater first). They also carry their own colours, keyed to the
/// projectile — which is what [damageAccentFor] was introduced to do by
/// hand, and now simply agrees with.
void paintShipDamage(Canvas canvas, Offset center, double r, DamageStyle style) {
  final markup = shipDamageSvg[style];
  if (markup == null) return;
  final scale = r / 36;
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.scale(scale);
  canvas.translate(-60, -60);
  paintSvgFragmentCached(canvas, markup);
  canvas.restore();
}
