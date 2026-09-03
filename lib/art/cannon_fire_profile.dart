import 'dart:math' as math;

import 'package:flutter/animation.dart';

import '../services/storage_service.dart';

/// Each gun's own recoil "personality" — ported from the design's
/// `*-fire-reload_cannon_fx.dart` snippets (one per legacy cannon and per
/// family, keyed there by `exhaustId`, matching `CannonSkin.id`/
/// `.familyKey` exactly). Before this, every gun — legacy or family —
/// shared one fixed 260ms linear recoil; these are what make MK-I's
/// crisp "snap" read differently from Kraken's slow tentacled "sway" or
/// Void's inward-pulling "suck".
enum RecoilCharacter { snap, jitter, sway, ghost, wobble, slow, suck }

class CannonFireProfile {
  /// How long the recoil kick takes to reach full extension and settle
  /// back — was a single fixed 260ms for every gun.
  final Duration recoilDuration;

  /// How long the muzzle-smoke cloud drifts and fades for.
  final Duration muzzleFxDuration;
  final RecoilCharacter character;

  /// Scales the widget-level kick/lateral offset (see [shapeRecoil]) and
  /// the barrel's own pull-into-the-mount distance.
  final double kickMultiplier;

  /// Scales the widget-level squash.
  final double squashMultiplier;

  const CannonFireProfile({
    required this.recoilDuration,
    required this.muzzleFxDuration,
    required this.character,
    required this.kickMultiplier,
    required this.squashMultiplier,
  });
}

const CannonFireProfile _defaultProfile = CannonFireProfile(
  recoilDuration: Duration(milliseconds: 260),
  muzzleFxDuration: Duration(milliseconds: 850),
  character: RecoilCharacter.snap,
  kickMultiplier: 1,
  squashMultiplier: 1,
);

const Map<String, CannonFireProfile> _legacyProfiles = {
  'mk1': _defaultProfile,
  'inferno': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 190),
    muzzleFxDuration: Duration(milliseconds: 650),
    character: RecoilCharacter.snap,
    kickMultiplier: 1.6,
    squashMultiplier: 1.5,
  ),
  'kraken': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 560),
    muzzleFxDuration: Duration(milliseconds: 1100),
    character: RecoilCharacter.sway,
    kickMultiplier: 0.75,
    squashMultiplier: 0.8,
  ),
  'phantom': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 320),
    muzzleFxDuration: Duration(milliseconds: 900),
    character: RecoilCharacter.ghost,
    kickMultiplier: 0.55,
    squashMultiplier: 0.55,
  ),
  'royal': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 360),
    muzzleFxDuration: Duration(milliseconds: 950),
    character: RecoilCharacter.wobble,
    kickMultiplier: 0.8,
    squashMultiplier: 0.85,
  ),
  'sunfire': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 230),
    muzzleFxDuration: Duration(milliseconds: 500),
    character: RecoilCharacter.snap,
    kickMultiplier: 1.3,
    squashMultiplier: 1.3,
  ),
  'tesla': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 150),
    muzzleFxDuration: Duration(milliseconds: 380),
    character: RecoilCharacter.jitter,
    kickMultiplier: 1,
    squashMultiplier: 1.05,
  ),
  'venom': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 520),
    muzzleFxDuration: Duration(milliseconds: 1000),
    character: RecoilCharacter.slow,
    kickMultiplier: 0.85,
    squashMultiplier: 1.05,
  ),
  'void': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 440),
    muzzleFxDuration: Duration(milliseconds: 900),
    character: RecoilCharacter.suck,
    kickMultiplier: 1,
    squashMultiplier: 1.3,
  ),
};

const Map<String, CannonFireProfile> _familyProfiles = {
  'pirate': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 300),
    muzzleFxDuration: Duration(milliseconds: 800),
    character: RecoilCharacter.jitter,
    kickMultiplier: 1.1,
    squashMultiplier: 1,
  ),
  'naval': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 240),
    muzzleFxDuration: Duration(milliseconds: 550),
    character: RecoilCharacter.snap,
    kickMultiplier: 1,
    squashMultiplier: 1,
  ),
  'steam': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 420),
    muzzleFxDuration: Duration(milliseconds: 1050),
    character: RecoilCharacter.wobble,
    kickMultiplier: 0.9,
    squashMultiplier: 1.1,
  ),
  'arctic': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 340),
    muzzleFxDuration: Duration(milliseconds: 700),
    character: RecoilCharacter.ghost,
    kickMultiplier: 0.8,
    squashMultiplier: 0.9,
  ),
  'volcanic': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 220),
    muzzleFxDuration: Duration(milliseconds: 600),
    character: RecoilCharacter.snap,
    kickMultiplier: 1.5,
    squashMultiplier: 1.4,
  ),
  'scifi': CannonFireProfile(
    recoilDuration: Duration(milliseconds: 300),
    muzzleFxDuration: Duration(milliseconds: 500),
    character: RecoilCharacter.suck,
    kickMultiplier: 0.7,
    squashMultiplier: 0.7,
  ),
};

/// A family gun reads its profile by [CannonSkin.familyKey]; a legacy gun
/// (no family) reads it by its own [CannonSkin.id]. Either way, an
/// unrecognised id falls back to MK-I's plain "snap".
CannonFireProfile fireProfileFor(CannonSkin skin) {
  final familyKey = skin.familyKey;
  if (familyKey != null) return _familyProfiles[familyKey] ?? _defaultProfile;
  return _legacyProfiles[skin.id] ?? _defaultProfile;
}

/// Shapes the recoil controller's raw 0→1 (attack) / 1→0 (release) value
/// into [character]'s own motion:
///  * `vertical` drives the existing squash/kick/barrel-pull, in the same
///    0-ish..1-ish range those already expect (a character may over/
///    undershoot slightly — `wobble`/`snap` overshoot past 1, `suck` dips
///    below 0 — callers should clamp before using it as an alpha).
///  * `lateral` is an extra sideways offset, 0 for every character except
///    the two shake-based ones.
///  * `opacity` fades the whole gun, 1 for every character except `ghost`.
({double vertical, double lateral, double opacity}) shapeRecoil(
  RecoilCharacter character,
  double t,
) {
  switch (character) {
    case RecoilCharacter.snap:
      return (vertical: Curves.easeOutBack.transform(t), lateral: 0, opacity: 1);
    case RecoilCharacter.wobble:
      return (vertical: Curves.elasticOut.transform(t), lateral: 0, opacity: 1);
    case RecoilCharacter.slow:
      return (vertical: Curves.easeOutQuint.transform(t), lateral: 0, opacity: 1);
    case RecoilCharacter.ghost:
      final v = Curves.easeInOut.transform(t);
      return (vertical: v, lateral: 0, opacity: 1 - v * 0.35);
    case RecoilCharacter.suck:
      final v = t < 0.4
          ? -0.3 * Curves.easeIn.transform(t / 0.4)
          : -0.3 + 1.3 * Curves.easeOutCubic.transform((t - 0.4) / 0.6);
      return (vertical: v, lateral: 0, opacity: 1);
    case RecoilCharacter.jitter:
      final env = 4 * t * (1 - t);
      return (
        vertical: Curves.easeOut.transform(t),
        lateral: math.sin(t * 26) * env,
        opacity: 1,
      );
    case RecoilCharacter.sway:
      final env = 4 * t * (1 - t);
      return (
        vertical: Curves.easeInOutSine.transform(t),
        lateral: math.sin(t * 8) * env,
        opacity: 1,
      );
  }
}
