// Offline sound-effect generator for Battleship Blitz.
// Run: dart run tool/gen_sounds.dart
// Synthesizes cartoon-style SFX into assets/sfx/*.wav (16-bit PCM, mono).
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const int sr = 22050;
final Random rng = Random(7);

void writeWav(String path, Float64List samples) {
  final n = samples.length;
  final data = ByteData(44 + n * 2);
  void s(int off, String v) {
    for (var i = 0; i < v.length; i++) {
      data.setUint8(off + i, v.codeUnitAt(i));
    }
  }

  s(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  s(8, 'WAVE');
  s(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sr, Endian.little);
  data.setUint32(28, sr * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  s(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  File(path).writeAsBytesSync(data.buffer.asUint8List());
  stdout.writeln('wrote $path (${n / sr}s)');
}

Float64List buf(double seconds) => Float64List((seconds * sr).toInt());

void add(Float64List out, int start, Float64List part) {
  for (var i = 0; i < part.length && start + i < out.length; i++) {
    out[start + i] += part[i];
  }
}

/// Sine blip with optional pitch sweep and exponential decay.
Float64List tone(double seconds, double Function(double) freqAt,
    {double volume = 0.5, double decay = 6}) {
  final n = (seconds * sr).toInt();
  final out = Float64List(n);
  double phase = 0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final f = freqAt(t);
    phase += 2 * pi * f / sr;
    out[i] = sin(phase) * exp(-decay * t) * volume;
  }
  return out;
}

/// Harmonic tone for bells, chimes, and metallic instruments.
Float64List harmonicTone(
    double seconds, double fundamental, List<double> harmonicWeights,
    {double volume = 0.5, double decay = 6}) {
  final n = (seconds * sr).toInt();
  final out = Float64List(n);
  final phases = List<double>.filled(harmonicWeights.length, 0);
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    double sample = 0;
    for (var h = 0; h < harmonicWeights.length; h++) {
      final f = fundamental * (h + 1);
      phases[h] += 2 * pi * f / sr;
      sample += sin(phases[h]) * harmonicWeights[h];
    }
    out[i] = sample * exp(-decay * t) * volume;
  }
  return out;
}

/// Frequency modulation synthesis (lasers, plasma, sci-fi energy, electric arcs).
Float64List fmTone(double seconds, double Function(double) carrierAt,
    double modFreq, double modIndex,
    {double volume = 0.5, double decay = 6}) {
  final n = (seconds * sr).toInt();
  final out = Float64List(n);
  double carPhase = 0;
  double modPhase = 0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    modPhase += 2 * pi * modFreq / sr;
    final modVal = sin(modPhase) * modIndex;
    final carFreq = carrierAt(t) + modVal * modFreq;
    carPhase += 2 * pi * carFreq / sr;
    out[i] = sin(carPhase) * exp(-decay * t) * volume;
  }
  return out;
}

/// Filtered noise burst (explosions, splashes, hiss, bursts).
Float64List noise(double seconds,
    {double volume = 0.5, double decay = 6, double cutoff = 0.25}) {
  final n = (seconds * sr).toInt();
  final out = Float64List(n);
  double lp = 0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final w = rng.nextDouble() * 2 - 1;
    lp += cutoff * (w - lp);
    out[i] = lp * exp(-decay * t) * volume * 3;
  }
  return out;
}

/// Band-passed noise sweep (whooshes / whirs / jets / vents).
Float64List sweep(double seconds, double Function(double) cutoffAt,
    {double volume = 0.5, double decay = 3}) {
  final n = (seconds * sr).toInt();
  final out = Float64List(n);
  double lp = 0, lp2 = 0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final w = rng.nextDouble() * 2 - 1;
    final c = cutoffAt(t).clamp(0.02, 0.9);
    lp += c * (w - lp);
    lp2 += 0.5 * (lp - lp2);
    out[i] = (lp - lp2) * exp(-decay * t) * volume * 4;
  }
  return out;
}

void main() {
  Directory('assets/sfx').createSync(recursive: true);

  // =========================================================================
  // CORE UI & SYSTEM SFX
  // =========================================================================

  // ---- CLICK: crisp short UI tick. ----
  final click = buf(0.06);
  add(click, 0, tone(0.03, (t) => 1900 - 700 * t, volume: 0.38, decay: 70));
  add(click, 0, noise(0.018, volume: 0.18, decay: 90, cutoff: 0.6));
  writeWav('assets/sfx/click.wav', click);

  // ---- COUNT_BEEP: countdown tick, plays on each of 3..2..1. ----
  final countBeep = buf(0.13);
  add(countBeep, 0, tone(0.11, (t) => 880, volume: 0.55, decay: 17));
  add(countBeep, 0, tone(0.11, (t) => 1760, volume: 0.16, decay: 20));
  writeWav('assets/sfx/count_beep.wav', countBeep);

  // ---- COUNT_GO: brighter rising chime after final tick. ----
  final countGo = buf(0.30);
  add(countGo, 0, tone(0.10, (t) => 660, volume: 0.4, decay: 13));
  add(countGo, (0.06 * sr).toInt(),
      tone(0.22, (t) => 990, volume: 0.52, decay: 9));
  add(countGo, (0.06 * sr).toInt(),
      tone(0.22, (t) => 1980, volume: 0.16, decay: 11));
  writeWav('assets/sfx/count_go.wav', countGo);

  // ---- SUNK: a whole ship destroyed ----
  final sunk = buf(1.35);
  add(sunk, 0, noise(0.38, volume: 0.55, decay: 6, cutoff: 0.22));
  add(sunk, 0, tone(0.55, (t) => 95 - 45 * t, volume: 0.5, decay: 4.6));
  add(sunk, (0.04 * sr).toInt(),
      tone(0.09, (t) => 3000, volume: 0.09, decay: 55));
  add(sunk, (0.06 * sr).toInt(),
      noise(0.28, volume: 0.34, decay: 9, cutoff: 0.5));
  add(sunk, (0.4 * sr).toInt(),
      sweep(0.8, (t) => 0.32 - 0.26 * t, volume: 0.24, decay: 2.6));
  writeWav('assets/sfx/sunk.wav', sunk);

  // ---- VICTORY: triumphant fanfare ----
  final victory = buf(1.9);
  const vNotes = [392.00, 523.25, 659.25, 783.99];
  for (var k = 0; k < vNotes.length; k++) {
    final at = (k * 0.18 * sr).toInt();
    add(victory, at, tone(0.5, (t) => vNotes[k], volume: 0.42, decay: 3.2));
    add(victory, at,
        tone(0.5, (t) => vNotes[k] * 2, volume: 0.14, decay: 3.8));
  }
  final chordAt = (4 * 0.18 * sr).toInt();
  for (final f in [523.25, 659.25, 783.99]) {
    add(victory, chordAt, tone(0.9, (t) => f, volume: 0.22, decay: 2.0));
  }
  writeWav('assets/sfx/victory.wav', victory);

  // ---- DEFEAT: falling dirge ----
  final defeat = buf(1.3);
  const dNotes = [392.0, 311.13, 233.08, 174.61];
  for (var k = 0; k < dNotes.length; k++) {
    final at = (k * 0.22 * sr).toInt();
    add(defeat, at, tone(0.34, (t) => dNotes[k], volume: 0.4, decay: 4));
    add(defeat, at,
        tone(0.34, (t) => dNotes[k] / 2, volume: 0.16, decay: 4.5));
  }
  add(defeat, 0, noise(1.1, volume: 0.08, decay: 1.4, cutoff: 0.08));
  writeWav('assets/sfx/defeat.wav', defeat);

  // ---- PLACE: short high "pop" blip + low thunk ----
  final place = buf(0.16);
  add(place, 0, tone(0.09, (t) => 950 - 350 * t, volume: 0.55, decay: 34));
  add(place, 0, noise(0.03, volume: 0.28, decay: 60, cutoff: 0.55));
  add(place, (0.01 * sr).toInt(),
      tone(0.08, (t) => 180, volume: 0.22, decay: 40));
  writeWav('assets/sfx/place.wav', place);

  // ---- WHIR: screen transition whoosh ----
  final whir = buf(0.5);
  add(whir, 0, sweep(0.45, (t) => 0.08 + 0.5 * t, volume: 0.5, decay: 4));
  add(whir, (0.02 * sr).toInt(),
      sweep(0.4, (t) => 0.18 + 0.6 * t, volume: 0.22, decay: 5));
  add(whir, (0.38 * sr).toInt(),
      noise(0.08, volume: 0.2, decay: 20, cutoff: 0.6));
  writeWav('assets/sfx/whir.wav', whir);

  // ---- DENIED: two-note dissonant buzz ----
  final denied = buf(0.28);
  add(denied, 0, tone(0.11, (t) => 150, volume: 0.4, decay: 16));
  add(denied, (0.1 * sr).toInt(),
      tone(0.14, (t) => 120, volume: 0.4, decay: 14));
  add(denied, 0, tone(0.11, (t) => 156, volume: 0.16, decay: 16));
  writeWav('assets/sfx/denied.wav', denied);

  // =========================================================================
  // 1. CANNON FIRE SOUNDS (Default, Legacy, & Thematic Families)
  // =========================================================================

  // ---- CANNON FIRE: MK1 / Default classic naval boom ----
  final fireMk1 = buf(0.72);
  add(fireMk1, 0, noise(0.26, volume: 0.65, decay: 9, cutoff: 0.42));
  add(fireMk1, 0, tone(0.48, (t) => 170 - 110 * t, volume: 0.55, decay: 5.5));
  add(fireMk1, (0.015 * sr).toInt(),
      noise(0.40, volume: 0.45, decay: 7, cutoff: 0.20));
  writeWav('assets/sfx/cannon_fire.wav', fireMk1);
  writeWav('assets/sfx/cannon_fire_mk1.wav', fireMk1);

  // ---- CANNON FIRE: INFERNO (Flames & burning concussive roar) ----
  final fireInferno = buf(0.75);
  add(fireInferno, 0, noise(0.35, volume: 0.60, decay: 7, cutoff: 0.55));
  add(fireInferno, 0, sweep(0.6, (t) => 0.6 - 0.4 * t, volume: 0.45, decay: 5));
  add(fireInferno, 0, tone(0.45, (t) => 140 - 80 * t, volume: 0.50, decay: 6));
  add(fireInferno, (0.05 * sr).toInt(),
      noise(0.5, volume: 0.35, decay: 6, cutoff: 0.7)); // crackle
  writeWav('assets/sfx/cannon_fire_inferno.wav', fireInferno);

  // ---- CANNON FIRE: TESLA (High-voltage electrical discharge & zap) ----
  final fireTesla = buf(0.65);
  add(fireTesla, 0, fmTone(0.38, (t) => 900 - 650 * t, 180, 5.0, volume: 0.52, decay: 8));
  add(fireTesla, 0, noise(0.25, volume: 0.40, decay: 14, cutoff: 0.85)); // spark burst
  add(fireTesla, (0.02 * sr).toInt(),
      tone(0.4, (t) => 220 - 120 * t, volume: 0.45, decay: 7));
  writeWav('assets/sfx/cannon_fire_tesla.wav', fireTesla);

  // ---- CANNON FIRE: VENOM (Pneumatic acid canister pop & hiss) ----
  final fireVenom = buf(0.68);
  add(fireVenom, 0, tone(0.2, (t) => 380 - 240 * t, volume: 0.55, decay: 15));
  add(fireVenom, 0, noise(0.12, volume: 0.45, decay: 20, cutoff: 0.6));
  add(fireVenom, (0.04 * sr).toInt(),
      sweep(0.55, (t) => 0.75 - 0.5 * t, volume: 0.42, decay: 6)); // toxic gas hiss
  writeWav('assets/sfx/cannon_fire_venom.wav', fireVenom);

  // ---- CANNON FIRE: ROYAL (Gilded heavy artillery with deep brass ring) ----
  final fireRoyal = buf(0.85);
  add(fireRoyal, 0, noise(0.28, volume: 0.60, decay: 8, cutoff: 0.38));
  add(fireRoyal, 0, tone(0.55, (t) => 130 - 70 * t, volume: 0.58, decay: 5));
  add(fireRoyal, (0.03 * sr).toInt(),
      harmonicTone(0.7, 330, [0.3, 0.4, 0.2, 0.1], volume: 0.35, decay: 4)); // brass ring
  writeWav('assets/sfx/cannon_fire_royal.wav', fireRoyal);

  // ---- CANNON FIRE: PHANTOM (Electromagnetic railgun supersonic slug) ----
  final firePhantom = buf(0.70);
  add(firePhantom, 0, tone(0.15, (t) => 2400 - 1800 * t, volume: 0.55, decay: 25)); // crack
  add(firePhantom, 0, fmTone(0.45, (t) => 440 - 280 * t, 88, 3.5, volume: 0.48, decay: 7));
  add(firePhantom, (0.02 * sr).toInt(),
      noise(0.3, volume: 0.45, decay: 10, cutoff: 0.3));
  writeWav('assets/sfx/cannon_fire_phantom.wav', firePhantom);

  // ---- CANNON FIRE: KRAKEN (Deep abyssal hydrostatic pressure thump) ----
  final fireKraken = buf(0.85);
  add(fireKraken, 0, noise(0.45, volume: 0.65, decay: 5, cutoff: 0.18));
  add(fireKraken, 0, tone(0.65, (t) => 90 - 45 * t, volume: 0.60, decay: 4));
  add(fireKraken, (0.06 * sr).toInt(),
      sweep(0.6, (t) => 0.25 - 0.18 * t, volume: 0.35, decay: 4)); // water displacement
  writeWav('assets/sfx/cannon_fire_kraken.wav', fireKraken);

  // ---- CANNON FIRE: SUNFIRE (Solar beam pulse & intense plasma pop) ----
  final fireSunfire = buf(0.72);
  add(fireSunfire, 0, fmTone(0.35, (t) => 720 - 320 * t, 120, 4.0, volume: 0.52, decay: 9));
  add(fireSunfire, 0, harmonicTone(0.55, 440, [0.35, 0.25, 0.15], volume: 0.40, decay: 6));
  add(fireSunfire, (0.02 * sr).toInt(),
      noise(0.25, volume: 0.35, decay: 12, cutoff: 0.5));
  writeWav('assets/sfx/cannon_fire_sunfire.wav', fireSunfire);

  // ---- CANNON FIRE: VOID (Dark-matter gravitational implosion) ----
  final fireVoid = buf(0.80);
  add(fireVoid, 0, tone(0.25, (t) => 80 + 160 * t, volume: 0.40, decay: 3)); // reverse swell
  add(fireVoid, (0.12 * sr).toInt(),
      noise(0.4, volume: 0.65, decay: 6, cutoff: 0.16)); // dark boom
  add(fireVoid, (0.14 * sr).toInt(),
      fmTone(0.48, (t) => 160 - 90 * t, 45, 6.0, volume: 0.45, decay: 5));
  writeWav('assets/sfx/cannon_fire_void.wav', fireVoid);

  // ---- CANNON FIRE: PIRATE (Blackpowder broadside & creaking carriage) ----
  final firePirate = buf(0.82);
  add(firePirate, 0, noise(0.42, volume: 0.70, decay: 7, cutoff: 0.35));
  add(firePirate, 0, tone(0.50, (t) => 120 - 75 * t, volume: 0.55, decay: 5));
  add(firePirate, (0.05 * sr).toInt(),
      noise(0.20, volume: 0.25, decay: 18, cutoff: 0.7)); // blackpowder fizz
  writeWav('assets/sfx/cannon_fire_pirate.wav', firePirate);
  writeWav('assets/sfx/cannon_fire_f_pirate.wav', firePirate);

  // ---- CANNON FIRE: NAVAL (MK-IV Military autoloader sharp double-crack) ----
  final fireNaval = buf(0.70);
  add(fireNaval, 0, tone(0.12, (t) => 1800 - 1200 * t, volume: 0.60, decay: 30));
  add(fireNaval, (0.03 * sr).toInt(),
      noise(0.32, volume: 0.62, decay: 9, cutoff: 0.38));
  add(fireNaval, (0.03 * sr).toInt(),
      tone(0.45, (t) => 150 - 95 * t, volume: 0.52, decay: 6));
  writeWav('assets/sfx/cannon_fire_naval.wav', fireNaval);
  writeWav('assets/sfx/cannon_fire_f_naval.wav', fireNaval);

  // ---- CANNON FIRE: STEAM (Pressure battery boiler blast & piston slam) ----
  final fireSteam = buf(0.78);
  add(fireSteam, 0, noise(0.25, volume: 0.55, decay: 10, cutoff: 0.45));
  add(fireSteam, 0, tone(0.40, (t) => 160 - 90 * t, volume: 0.48, decay: 7));
  add(fireSteam, (0.02 * sr).toInt(),
      sweep(0.55, (t) => 0.85 - 0.4 * t, volume: 0.48, decay: 5)); // high-pressure steam
  writeWav('assets/sfx/cannon_fire_steam.wav', fireSteam);
  writeWav('assets/sfx/cannon_fire_f_steam.wav', fireSteam);

  // ---- CANNON FIRE: ARCTIC (Icebreaker mortar frost blast) ----
  final fireArctic = buf(0.74);
  add(fireArctic, 0, noise(0.28, volume: 0.58, decay: 9, cutoff: 0.4));
  add(fireArctic, 0, tone(0.42, (t) => 180 - 110 * t, volume: 0.50, decay: 6));
  add(fireArctic, (0.02 * sr).toInt(),
      tone(0.35, (t) => 1400 - 700 * t, volume: 0.28, decay: 12)); // crystal shatter
  writeWav('assets/sfx/cannon_fire_arctic.wav', fireArctic);
  writeWav('assets/sfx/cannon_fire_f_arctic.wav', fireArctic);

  // ---- CANNON FIRE: VOLCANIC (Magma bombard molten rock detonation) ----
  final fireVolcanic = buf(0.88);
  add(fireVolcanic, 0, noise(0.50, volume: 0.70, decay: 5, cutoff: 0.22));
  add(fireVolcanic, 0, tone(0.60, (t) => 110 - 55 * t, volume: 0.60, decay: 4));
  add(fireVolcanic, (0.08 * sr).toInt(),
      noise(0.45, volume: 0.40, decay: 6, cutoff: 0.5)); // basalt rumble
  writeWav('assets/sfx/cannon_fire_volcanic.wav', fireVolcanic);
  writeWav('assets/sfx/cannon_fire_f_volcanic.wav', fireVolcanic);

  // ---- CANNON FIRE: SCIFI (Helios Drift ion particle cannon) ----
  final fireScifi = buf(0.68);
  add(fireScifi, 0, fmTone(0.32, (t) => 1200 - 800 * t, 160, 4.5, volume: 0.58, decay: 10));
  add(fireScifi, 0, tone(0.40, (t) => 260 - 140 * t, volume: 0.45, decay: 7));
  add(fireScifi, (0.04 * sr).toInt(),
      sweep(0.4, (t) => 0.6 - 0.2 * t, volume: 0.32, decay: 8));
  writeWav('assets/sfx/cannon_fire_scifi.wav', fireScifi);
  writeWav('assets/sfx/cannon_fire_f_scifi.wav', fireScifi);

  // =========================================================================
  // 2. CANNON RELOAD / READY SOUNDS (Default, Legacy, & Thematic Families)
  // =========================================================================

  // ---- CANNON READY: Default / MK1 (Breech-block lock & click) ----
  final readyMk1 = buf(0.30);
  add(readyMk1, 0, tone(0.06, (t) => 95, volume: 0.42, decay: 22));
  add(readyMk1, 0, noise(0.05, volume: 0.22, decay: 45, cutoff: 0.7));
  add(readyMk1, (0.04 * sr).toInt(),
      sweep(0.16, (t) => 0.5 - 0.35 * t, volume: 0.16, decay: 14));
  writeWav('assets/sfx/cannon_ready.wav', readyMk1);
  writeWav('assets/sfx/cannon_ready_mk1.wav', readyMk1);

  // ---- CANNON READY: INFERNO (Furnace door clank & flame hiss) ----
  final readyInferno = buf(0.34);
  add(readyInferno, 0, tone(0.08, (t) => 110, volume: 0.40, decay: 20));
  add(readyInferno, (0.03 * sr).toInt(),
      sweep(0.24, (t) => 0.65 - 0.3 * t, volume: 0.30, decay: 10)); // flame vent
  writeWav('assets/sfx/cannon_ready_inferno.wav', readyInferno);

  // ---- CANNON READY: TESLA (Capacitor charge sweep & spark snap) ----
  final readyTesla = buf(0.32);
  add(readyTesla, 0, tone(0.18, (t) => 400 + 800 * t, volume: 0.32, decay: 6));
  add(readyTesla, (0.16 * sr).toInt(),
      tone(0.06, (t) => 2200, volume: 0.35, decay: 45)); // spark
  writeWav('assets/sfx/cannon_ready_tesla.wav', readyTesla);

  // ---- CANNON READY: VENOM (Chemical valve click & canister bubble) ----
  final readyVenom = buf(0.32);
  add(readyVenom, 0, tone(0.05, (t) => 1400 - 800 * t, volume: 0.38, decay: 35));
  add(readyVenom, (0.04 * sr).toInt(),
      tone(0.18, (t) => 320 + 200 * sin(t * 50), volume: 0.28, decay: 12)); // gurgle
  writeWav('assets/sfx/cannon_ready_venom.wav', readyVenom);

  // ---- CANNON READY: ROYAL (Ornate clockwork gear tick & bell chime) ----
  final readyRoyal = buf(0.38);
  add(readyRoyal, 0, tone(0.04, (t) => 1600, volume: 0.30, decay: 50));
  add(readyRoyal, (0.05 * sr).toInt(),
      harmonicTone(0.28, 660, [0.35, 0.25], volume: 0.35, decay: 8));
  writeWav('assets/sfx/cannon_ready_royal.wav', readyRoyal);

  // ---- CANNON READY: PHANTOM (Magnetic coil charge & confirm beep) ----
  final readyPhantom = buf(0.32);
  add(readyPhantom, 0, tone(0.20, (t) => 600 + 1200 * t, volume: 0.30, decay: 5));
  add(readyPhantom, (0.18 * sr).toInt(),
      tone(0.10, (t) => 1760, volume: 0.40, decay: 20));
  writeWav('assets/sfx/cannon_ready_phantom.wav', readyPhantom);

  // ---- CANNON READY: KRAKEN (Deep-sea pressure latch & sonar blip) ----
  // BUGFIX (the Kraken reload "never played"): the original clip was two
  // PURE SINE tones at 180 Hz and 140 Hz — sub-200 Hz content phone and
  // laptop speakers physically cannot reproduce. The file played fine;
  // it was simply inaudible on real hardware. The deep character is kept
  // below, but every layer now carries audible harmonics over the thump.
  final readyKraken = buf(0.42);
  // Abyssal thump — low fundamental, but with 2nd/3rd partials so small
  // speakers still have something to push out.
  add(readyKraken, 0,
      harmonicTone(0.20, 130, [0.55, 0.35, 0.20], volume: 0.50, decay: 14));
  // Suction latch — a wet, band-passed hiss as the seal closes.
  add(readyKraken, (0.10 * sr).toInt(),
      sweep(0.12, (t) => 0.80 - 0.40 * t, volume: 0.40, decay: 16));
  // Bronze porthole clang the instant the latch seats.
  add(readyKraken, (0.14 * sr).toInt(),
      harmonicTone(0.22, 660, [0.50, 0.30, 0.20, 0.10], volume: 0.38, decay: 12));
  // Sonar blip rising out of the deep — the "locked in" confirmation.
  add(readyKraken, (0.24 * sr).toInt(),
      fmTone(0.16, (t) => 880 + 240 * t, 90, 1.5, volume: 0.38, decay: 10));
  writeWav('assets/sfx/cannon_ready_kraken.wav', readyKraken);

  // ---- CANNON READY: SUNFIRE (Solar collector focus hum & chime) ----
  final readySunfire = buf(0.35);
  add(readySunfire, 0, fmTone(0.18, (t) => 500 + 300 * t, 60, 2.0, volume: 0.30, decay: 6));
  add(readySunfire, (0.12 * sr).toInt(),
      harmonicTone(0.20, 880, [0.3, 0.2], volume: 0.35, decay: 10));
  writeWav('assets/sfx/cannon_ready_sunfire.wav', readySunfire);

  // ---- CANNON READY: VOID (Gravitational warp hum & dimensional lock) ----
  final readyVoid = buf(0.38);
  add(readyVoid, 0, tone(0.22, (t) => 120 - 40 * t, volume: 0.40, decay: 6));
  add(readyVoid, (0.10 * sr).toInt(),
      fmTone(0.22, (t) => 220, 30, 4.0, volume: 0.32, decay: 8));
  writeWav('assets/sfx/cannon_ready_void.wav', readyVoid);

  // ---- CANNON READY: PIRATE (Wooden carriage brake & rammer thud) ----
  final readyPirate = buf(0.34);
  add(readyPirate, 0, tone(0.08, (t) => 130 - 50 * t, volume: 0.45, decay: 20));
  add(readyPirate, 0, noise(0.06, volume: 0.25, decay: 30, cutoff: 0.5));
  writeWav('assets/sfx/cannon_ready_pirate.wav', readyPirate);
  writeWav('assets/sfx/cannon_ready_f_pirate.wav', readyPirate);

  // ---- CANNON READY: NAVAL (Hydraulic autoloader rammer slide & slam) ----
  final readyNaval = buf(0.32);
  add(readyNaval, 0, tone(0.07, (t) => 800 - 300 * t, volume: 0.35, decay: 25));
  add(readyNaval, (0.06 * sr).toInt(),
      tone(0.12, (t) => 120, volume: 0.50, decay: 20)); // steel slam
  writeWav('assets/sfx/cannon_ready_naval.wav', readyNaval);
  writeWav('assets/sfx/cannon_ready_f_naval.wav', readyNaval);

  // ---- CANNON READY: STEAM (Boiler steam release & gear ratchet) ----
  final readySteam = buf(0.35);
  add(readySteam, 0, sweep(0.20, (t) => 0.6 - 0.3 * t, volume: 0.32, decay: 8)); // steam puff
  add(readySteam, (0.08 * sr).toInt(),
      tone(0.12, (t) => 1200 - 600 * t, volume: 0.35, decay: 30)); // ratchet
  writeWav('assets/sfx/cannon_ready_steam.wav', readySteam);
  writeWav('assets/sfx/cannon_ready_f_steam.wav', readySteam);

  // ---- CANNON READY: ARCTIC (Frost crystallizing ping & ice clamp) ----
  final readyArctic = buf(0.32);
  add(readyArctic, 0, harmonicTone(0.20, 1100, [0.35, 0.2], volume: 0.35, decay: 12));
  add(readyArctic, (0.05 * sr).toInt(),
      tone(0.10, (t) => 180, volume: 0.38, decay: 22));
  writeWav('assets/sfx/cannon_ready_arctic.wav', readyArctic);
  writeWav('assets/sfx/cannon_ready_f_arctic.wav', readyArctic);

  // ---- CANNON READY: VOLCANIC (Heavy basalt grind & ember snap) ----
  final readyVolcanic = buf(0.36);
  add(readyVolcanic, 0, noise(0.12, volume: 0.40, decay: 16, cutoff: 0.3));
  add(readyVolcanic, (0.04 * sr).toInt(),
      tone(0.16, (t) => 90, volume: 0.45, decay: 14));
  writeWav('assets/sfx/cannon_ready_volcanic.wav', readyVolcanic);
  writeWav('assets/sfx/cannon_ready_f_volcanic.wav', readyVolcanic);

  // ---- CANNON READY: SCIFI (Servo sweep & digital lock tone) ----
  final readyScifi = buf(0.30);
  add(readyScifi, 0, tone(0.12, (t) => 800 + 400 * t, volume: 0.32, decay: 10));
  add(readyScifi, (0.10 * sr).toInt(),
      tone(0.15, (t) => 1480, volume: 0.42, decay: 18));
  writeWav('assets/sfx/cannon_ready_scifi.wav', readyScifi);
  writeWav('assets/sfx/cannon_ready_f_scifi.wav', readyScifi);

  // =========================================================================
  // 3. CANNON HIT SOUNDS (Default, Legacy, & Thematic Families)
  // =========================================================================

  // ---- HIT: Default / MK1 (Hull punch & steel thud) ----
  final hitMk1 = buf(0.42);
  add(hitMk1, 0, noise(0.09, volume: 0.5, decay: 28, cutoff: 0.5));
  add(hitMk1, 0, tone(0.16, (t) => 190 - 70 * t, volume: 0.48, decay: 16));
  add(hitMk1, (0.02 * sr).toInt(),
      tone(0.11, (t) => 2200, volume: 0.13, decay: 50));
  writeWav('assets/sfx/hit.wav', hitMk1);
  writeWav('assets/sfx/hit_mk1.wav', hitMk1);

  // ---- HIT: INFERNO (Explosive flame strike & searing scorch) ----
  final hitInferno = buf(0.45);
  add(hitInferno, 0, noise(0.18, volume: 0.55, decay: 18, cutoff: 0.6));
  add(hitInferno, 0, tone(0.20, (t) => 160 - 80 * t, volume: 0.45, decay: 12));
  add(hitInferno, (0.04 * sr).toInt(),
      sweep(0.35, (t) => 0.6 - 0.3 * t, volume: 0.35, decay: 8)); // burn sizzle
  writeWav('assets/sfx/hit_inferno.wav', hitInferno);

  // ---- HIT: TESLA (Electrical arc explosion & metal shock) ----
  final hitTesla = buf(0.42);
  add(hitTesla, 0, fmTone(0.25, (t) => 1100 - 700 * t, 220, 6.0, volume: 0.50, decay: 14));
  add(hitTesla, 0, noise(0.15, volume: 0.40, decay: 22, cutoff: 0.8));
  add(hitTesla, (0.02 * sr).toInt(),
      tone(0.22, (t) => 180, volume: 0.40, decay: 15));
  writeWav('assets/sfx/hit_tesla.wav', hitTesla);

  // ---- HIT: VENOM (Corrosive acid strike & sizzling metal melt) ----
  final hitVenom = buf(0.46);
  add(hitVenom, 0, noise(0.12, volume: 0.45, decay: 25, cutoff: 0.55));
  add(hitVenom, 0, tone(0.18, (t) => 240 - 120 * t, volume: 0.42, decay: 16));
  add(hitVenom, (0.03 * sr).toInt(),
      sweep(0.38, (t) => 0.7 - 0.35 * t, volume: 0.40, decay: 8)); // acid sizzle
  writeWav('assets/sfx/hit_venom.wav', hitVenom);

  // ---- HIT: ROYAL (Heavy golden cannonball & loud resonant bell gong) ----
  final hitRoyal = buf(0.55);
  add(hitRoyal, 0, noise(0.14, volume: 0.52, decay: 20, cutoff: 0.45));
  add(hitRoyal, 0, tone(0.25, (t) => 150 - 60 * t, volume: 0.50, decay: 10));
  add(hitRoyal, (0.02 * sr).toInt(),
      harmonicTone(0.45, 440, [0.4, 0.3, 0.15], volume: 0.38, decay: 6)); // bell
  writeWav('assets/sfx/hit_royal.wav', hitRoyal);

  // ---- HIT: PHANTOM (Armor-piercing hypervelocity kinetic strike) ----
  final hitPhantom = buf(0.40);
  add(hitPhantom, 0, tone(0.10, (t) => 3200 - 2000 * t, volume: 0.60, decay: 35)); // sharp crack
  add(hitPhantom, 0, noise(0.18, volume: 0.45, decay: 18, cutoff: 0.65));
  add(hitPhantom, (0.015 * sr).toInt(),
      tone(0.24, (t) => 280 - 140 * t, volume: 0.42, decay: 12));
  writeWav('assets/sfx/hit_phantom.wav', hitPhantom);

  // ---- HIT: KRAKEN (Deep sea crushing blow & hull fracture) ----
  final hitKraken = buf(0.52);
  add(hitKraken, 0, noise(0.28, volume: 0.65, decay: 10, cutoff: 0.25));
  add(hitKraken, 0, tone(0.35, (t) => 110 - 50 * t, volume: 0.55, decay: 8));
  add(hitKraken, (0.05 * sr).toInt(),
      noise(0.22, volume: 0.35, decay: 14, cutoff: 0.6)); // hull splinter
  writeWav('assets/sfx/hit_kraken.wav', hitKraken);

  // ---- HIT: SUNFIRE (Searing solar plasma blast & vaporizing metal) ----
  final hitSunfire = buf(0.44);
  add(hitSunfire, 0, fmTone(0.22, (t) => 850 - 450 * t, 140, 5.0, volume: 0.52, decay: 12));
  add(hitSunfire, 0, noise(0.16, volume: 0.42, decay: 20, cutoff: 0.6));
  add(hitSunfire, (0.03 * sr).toInt(),
      harmonicTone(0.32, 550, [0.3, 0.2], volume: 0.32, decay: 9));
  writeWav('assets/sfx/hit_sunfire.wav', hitSunfire);

  // ---- HIT: VOID (Dark energy spatial crush & distortion) ----
  final hitVoid = buf(0.48);
  add(hitVoid, 0, tone(0.15, (t) => 70 + 120 * t, volume: 0.45, decay: 6));
  add(hitVoid, (0.06 * sr).toInt(),
      noise(0.25, volume: 0.60, decay: 12, cutoff: 0.2));
  add(hitVoid, (0.08 * sr).toInt(),
      fmTone(0.32, (t) => 180 - 90 * t, 40, 5.0, volume: 0.40, decay: 8));
  writeWav('assets/sfx/hit_void.wav', hitVoid);

  // ---- HIT: PIRATE (Wooden timber splintering crunch) ----
  final hitPirate = buf(0.48);
  add(hitPirate, 0, noise(0.20, volume: 0.60, decay: 16, cutoff: 0.45));
  add(hitPirate, 0, tone(0.22, (t) => 140 - 60 * t, volume: 0.50, decay: 12));
  add(hitPirate, (0.03 * sr).toInt(),
      noise(0.25, volume: 0.42, decay: 14, cutoff: 0.75)); // wood crack
  writeWav('assets/sfx/hit_pirate.wav', hitPirate);
  writeWav('assets/sfx/hit_f_pirate.wav', hitPirate);

  // ---- HIT: NAVAL (Heavy steel bulkhead penetration) ----
  final hitNaval = buf(0.44);
  add(hitNaval, 0, tone(0.12, (t) => 1600 - 900 * t, volume: 0.58, decay: 28));
  add(hitNaval, 0, noise(0.20, volume: 0.55, decay: 15, cutoff: 0.42));
  add(hitNaval, (0.02 * sr).toInt(),
      tone(0.28, (t) => 160 - 80 * t, volume: 0.48, decay: 10));
  writeWav('assets/sfx/hit_naval.wav', hitNaval);
  writeWav('assets/sfx/hit_f_naval.wav', hitNaval);

  // ---- HIT: STEAM (Brass plate dent & steam rupture) ----
  final hitSteam = buf(0.46);
  add(hitSteam, 0, noise(0.15, volume: 0.52, decay: 20, cutoff: 0.5));
  add(hitSteam, 0, tone(0.20, (t) => 220 - 100 * t, volume: 0.46, decay: 14));
  add(hitSteam, (0.03 * sr).toInt(),
      sweep(0.35, (t) => 0.8 - 0.4 * t, volume: 0.40, decay: 9)); // steam hiss
  writeWav('assets/sfx/hit_steam.wav', hitSteam);
  writeWav('assets/sfx/hit_f_steam.wav', hitSteam);

  // ---- HIT: ARCTIC (Thick ice armor shatter) ----
  final hitArctic = buf(0.45);
  add(hitArctic, 0, tone(0.14, (t) => 2600 - 1400 * t, volume: 0.45, decay: 25)); // ice crack
  add(hitArctic, 0, noise(0.18, volume: 0.50, decay: 16, cutoff: 0.45));
  add(hitArctic, (0.02 * sr).toInt(),
      tone(0.25, (t) => 170 - 70 * t, volume: 0.44, decay: 12));
  writeWav('assets/sfx/hit_arctic.wav', hitArctic);
  writeWav('assets/sfx/hit_f_arctic.wav', hitArctic);

  // ---- HIT: VOLCANIC (Hardened magma rock crunch & cinder burst) ----
  final hitVolcanic = buf(0.52);
  add(hitVolcanic, 0, noise(0.26, volume: 0.62, decay: 12, cutoff: 0.28));
  add(hitVolcanic, 0, tone(0.30, (t) => 120 - 50 * t, volume: 0.52, decay: 9));
  add(hitVolcanic, (0.04 * sr).toInt(),
      noise(0.22, volume: 0.35, decay: 15, cutoff: 0.6));
  writeWav('assets/sfx/hit_volcanic.wav', hitVolcanic);
  writeWav('assets/sfx/hit_f_volcanic.wav', hitVolcanic);

  // ---- HIT: SCIFI (Energy shield deflection & composite spark) ----
  final hitScifi = buf(0.42);
  add(hitScifi, 0, fmTone(0.20, (t) => 1400 - 600 * t, 180, 5.0, volume: 0.55, decay: 16));
  add(hitScifi, 0, noise(0.12, volume: 0.40, decay: 24, cutoff: 0.75));
  add(hitScifi, (0.02 * sr).toInt(),
      tone(0.22, (t) => 240 - 100 * t, volume: 0.42, decay: 12));
  writeWav('assets/sfx/hit_scifi.wav', hitScifi);
  writeWav('assets/sfx/hit_f_scifi.wav', hitScifi);

  // =========================================================================
  // 4. CANNON MISS / WATER SPLASH SOUNDS (Decks & Projectiles)
  // =========================================================================

  // ---- MISS: Default / Classic Deck (Water splash & bloop) ----
  final missClassic = buf(0.60);
  add(missClassic, 0, tone(0.03, (t) => 1400, volume: 0.18, decay: 45));
  add(missClassic, 0, tone(0.16, (t) => 620 - 380 * t, volume: 0.42, decay: 12));
  add(missClassic, (0.05 * sr).toInt(),
      sweep(0.42, (t) => 0.55 - 0.25 * t, volume: 0.30, decay: 7));
  add(missClassic, (0.14 * sr).toInt(),
      tone(0.22, (t) => 260 - 90 * t, volume: 0.22, decay: 9));
  writeWav('assets/sfx/miss.wav', missClassic);
  writeWav('assets/sfx/miss_classic.wav', missClassic);

  // ---- MISS: ARCTIC (Freezing splash with tinkling ice shards) ----
  final missArctic = buf(0.62);
  add(missArctic, 0, tone(0.04, (t) => 2200 - 1200 * t, volume: 0.24, decay: 35));
  add(missArctic, 0, tone(0.18, (t) => 720 - 450 * t, volume: 0.38, decay: 13));
  add(missArctic, (0.04 * sr).toInt(),
      harmonicTone(0.35, 1400, [0.3, 0.2, 0.1], volume: 0.25, decay: 10)); // ice tinkle
  add(missArctic, (0.08 * sr).toInt(),
      sweep(0.40, (t) => 0.6 - 0.3 * t, volume: 0.28, decay: 8));
  writeWav('assets/sfx/miss_arctic.wav', missArctic);
  writeWav('assets/sfx/miss_f_arctic.wav', missArctic);

  // ---- MISS: DEEP SEA / KRAKEN (Deep underwater plunge & heavy echo) ----
  final missDeep = buf(0.70);
  add(missDeep, 0, noise(0.25, volume: 0.45, decay: 10, cutoff: 0.25));
  add(missDeep, 0, tone(0.30, (t) => 380 - 260 * t, volume: 0.45, decay: 8));
  add(missDeep, (0.08 * sr).toInt(),
      sweep(0.55, (t) => 0.35 - 0.15 * t, volume: 0.35, decay: 5)); // deep wash
  writeWav('assets/sfx/miss_deep.wav', missDeep);
  writeWav('assets/sfx/miss_kraken.wav', missDeep);

  // ---- MISS: SUNSET (Warm ocean surf & frothing spray) ----
  final missSunset = buf(0.62);
  add(missSunset, 0, tone(0.14, (t) => 580 - 340 * t, volume: 0.40, decay: 14));
  add(missSunset, (0.03 * sr).toInt(),
      sweep(0.48, (t) => 0.5 - 0.2 * t, volume: 0.34, decay: 6));
  writeWav('assets/sfx/miss_sunset.wav', missSunset);

  // ---- MISS: PIRATE (Heavy cannonball sea splash & roaring wave) ----
  final missPirate = buf(0.65);
  add(missPirate, 0, noise(0.20, volume: 0.50, decay: 12, cutoff: 0.45));
  add(missPirate, 0, tone(0.22, (t) => 500 - 320 * t, volume: 0.42, decay: 10));
  add(missPirate, (0.06 * sr).toInt(),
      sweep(0.50, (t) => 0.65 - 0.3 * t, volume: 0.38, decay: 6));
  writeWav('assets/sfx/miss_pirate.wav', missPirate);
  writeWav('assets/sfx/miss_f_pirate.wav', missPirate);

  // ---- MISS: NAVAL (High-velocity water displacement geyser) ----
  final missNaval = buf(0.60);
  add(missNaval, 0, tone(0.08, (t) => 1200 - 800 * t, volume: 0.35, decay: 22));
  add(missNaval, 0, tone(0.18, (t) => 650 - 420 * t, volume: 0.44, decay: 12));
  add(missNaval, (0.04 * sr).toInt(),
      sweep(0.45, (t) => 0.7 - 0.35 * t, volume: 0.35, decay: 7));
  writeWav('assets/sfx/miss_naval.wav', missNaval);
  writeWav('assets/sfx/miss_f_naval.wav', missNaval);

  // ---- MISS: STEAM (Boiling geothermal water & steam hiss) ----
  final missSteam = buf(0.64);
  add(missSteam, 0, tone(0.16, (t) => 560 - 360 * t, volume: 0.38, decay: 13));
  add(missSteam, (0.04 * sr).toInt(),
      sweep(0.52, (t) => 0.85 - 0.45 * t, volume: 0.42, decay: 6)); // steam eruption
  writeWav('assets/sfx/miss_steam.wav', missSteam);
  writeWav('assets/sfx/miss_f_steam.wav', missSteam);

  // ---- MISS: VOLCANIC (Lava-water vapor explosion & violent sizzle) ----
  final missVolcanic = buf(0.68);
  add(missVolcanic, 0, noise(0.22, volume: 0.55, decay: 10, cutoff: 0.35));
  add(missVolcanic, 0, tone(0.20, (t) => 420 - 240 * t, volume: 0.42, decay: 11));
  add(missVolcanic, (0.05 * sr).toInt(),
      sweep(0.55, (t) => 0.75 - 0.4 * t, volume: 0.45, decay: 6)); // boiling sizzle
  writeWav('assets/sfx/miss_volcanic.wav', missVolcanic);
  writeWav('assets/sfx/miss_f_volcanic.wav', missVolcanic);

  // ---- MISS: SCIFI (Ionized plasma water displacement pulse) ----
  final missScifi = buf(0.62);
  add(missScifi, 0, fmTone(0.20, (t) => 900 - 500 * t, 120, 3.5, volume: 0.45, decay: 14));
  add(missScifi, 0, tone(0.18, (t) => 600 - 380 * t, volume: 0.38, decay: 12));
  add(missScifi, (0.04 * sr).toInt(),
      sweep(0.48, (t) => 0.6 - 0.25 * t, volume: 0.30, decay: 7));
  writeWav('assets/sfx/miss_scifi.wav', missScifi);
  writeWav('assets/sfx/miss_f_scifi.wav', missScifi);

  // Additional projectile misses
  writeWav('assets/sfx/miss_inferno.wav', missVolcanic);
  writeWav('assets/sfx/miss_tesla.wav', missScifi);
  writeWav('assets/sfx/miss_venom.wav', missSteam);
  writeWav('assets/sfx/miss_phantom.wav', missNaval);
  writeWav('assets/sfx/miss_sunfire.wav', missScifi);
  writeWav('assets/sfx/miss_void.wav', missDeep);

  // =========================================================================
  // 5. TURN PASS / YOUR TURN SOUNDS (Decks & Thematic Families)
  // =========================================================================

  // ---- TURN PASS: Default / Classic (Friendly dual-bell chime C5-E5) ----
  final passClassic = buf(0.55);
  const cNotes = [523.25, 659.25];
  for (var k = 0; k < cNotes.length; k++) {
    final at = (k * 0.14 * sr).toInt();
    add(passClassic, at, tone(0.32, (t) => cNotes[k], volume: 0.32, decay: 7));
    add(passClassic, at,
        tone(0.24, (t) => cNotes[k] * 2, volume: 0.10, decay: 10));
  }
  writeWav('assets/sfx/turn_pass.wav', passClassic);
  writeWav('assets/sfx/turn_pass_classic.wav', passClassic);

  // ---- TURN PASS: ARCTIC (Crystal bell chime with frosty echo) ----
  final passArctic = buf(0.65);
  const aNotes = [587.33, 880.00]; // D5, A5
  for (var k = 0; k < aNotes.length; k++) {
    final at = (k * 0.16 * sr).toInt();
    add(passArctic, at,
        harmonicTone(0.42, aNotes[k], [0.35, 0.25, 0.15], volume: 0.35, decay: 6));
  }
  writeWav('assets/sfx/turn_pass_arctic.wav', passArctic);
  writeWav('assets/sfx/turn_pass_f_arctic.wav', passArctic);

  // ---- TURN PASS: DEEP SEA (Submarine sonar ping in the deep) ----
  final passDeep = buf(0.75);
  add(passDeep, 0, tone(0.45, (t) => 880, volume: 0.42, decay: 5));
  add(passDeep, 0, tone(0.30, (t) => 1760, volume: 0.12, decay: 8));
  add(passDeep, (0.08 * sr).toInt(),
      tone(0.40, (t) => 880, volume: 0.16, decay: 4)); // echo
  writeWav('assets/sfx/turn_pass_deep.wav', passDeep);

  // ---- TURN PASS: SUNSET (Warm maritime brass ship horn) ----
  final passSunset = buf(0.65);
  const sNotes = [392.00, 523.25]; // G4, C5
  for (var k = 0; k < sNotes.length; k++) {
    final at = (k * 0.16 * sr).toInt();
    add(passSunset, at,
        harmonicTone(0.40, sNotes[k], [0.4, 0.3, 0.2], volume: 0.38, decay: 5));
  }
  writeWav('assets/sfx/turn_pass_sunset.wav', passSunset);

  // ---- TURN PASS: PIRATE (Double ship's bell ring) ----
  final passPirate = buf(0.68);
  const pNotes = [659.25, 659.25]; // E5, E5 double tap
  for (var k = 0; k < pNotes.length; k++) {
    final at = (k * 0.18 * sr).toInt();
    add(passPirate, at,
        harmonicTone(0.40, pNotes[k], [0.4, 0.35, 0.2, 0.1], volume: 0.40, decay: 6));
  }
  writeWav('assets/sfx/turn_pass_pirate.wav', passPirate);
  writeWav('assets/sfx/turn_pass_f_pirate.wav', passPirate);

  // ---- TURN PASS: NAVAL (Military bridge telegraph bell) ----
  final passNaval = buf(0.55);
  const nNotes = [783.99, 1046.50]; // G5, C6
  for (var k = 0; k < nNotes.length; k++) {
    final at = (k * 0.12 * sr).toInt();
    add(passNaval, at,
        harmonicTone(0.32, nNotes[k], [0.45, 0.3], volume: 0.38, decay: 8));
  }
  writeWav('assets/sfx/turn_pass_naval.wav', passNaval);
  writeWav('assets/sfx/turn_pass_f_naval.wav', passNaval);

  // ---- TURN PASS: STEAM (Steampunk brass chime & whistle toot) ----
  final passSteam = buf(0.62);
  add(passSteam, 0,
      harmonicTone(0.30, 523.25, [0.35, 0.25], volume: 0.32, decay: 8));
  add(passSteam, (0.12 * sr).toInt(),
      sweep(0.38, (t) => 0.7 - 0.3 * t, volume: 0.28, decay: 7)); // whistle
  add(passSteam, (0.12 * sr).toInt(),
      tone(0.35, (t) => 880 + 20 * sin(t * 30), volume: 0.30, decay: 6));
  writeWav('assets/sfx/turn_pass_steam.wav', passSteam);
  writeWav('assets/sfx/turn_pass_f_steam.wav', passSteam);

  // ---- TURN PASS: VOLCANIC (Deep bronze volcanic temple gong) ----
  final passVolcanic = buf(0.85);
  add(passVolcanic, 0, noise(0.10, volume: 0.35, decay: 15, cutoff: 0.4));
  add(passVolcanic, 0,
      harmonicTone(0.75, 196.00, [0.45, 0.35, 0.2, 0.15], volume: 0.50, decay: 3.5)); // G3 gong
  writeWav('assets/sfx/turn_pass_volcanic.wav', passVolcanic);
  writeWav('assets/sfx/turn_pass_f_volcanic.wav', passVolcanic);

  // ---- TURN PASS: SCIFI (Futuristic tactical radar interface chime) ----
  final passScifi = buf(0.55);
  const sciNotes = [587.33, 880.00, 1174.66]; // D5, A5, D6 arpeggio
  for (var k = 0; k < sciNotes.length; k++) {
    final at = (k * 0.09 * sr).toInt();
    add(passScifi, at,
        fmTone(0.30, (t) => sciNotes[k], 120, 2.0, volume: 0.35, decay: 8));
  }
  writeWav('assets/sfx/turn_pass_scifi.wav', passScifi);
  writeWav('assets/sfx/turn_pass_f_scifi.wav', passScifi);

  stdout.writeln('All Battleship Blitz sound effects generated successfully.');
}
