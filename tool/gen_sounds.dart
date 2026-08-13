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

/// Filtered noise burst (explosions, splashes).
Float64List noise(double seconds,
    {double volume = 0.5, double decay = 6, double cutoff = 0.25}) {
  final n = (seconds * sr).toInt();
  final out = Float64List(n);
  double lp = 0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final w = rng.nextDouble() * 2 - 1;
    lp += cutoff * (w - lp); // crude low-pass for a "boom" body
    out[i] = lp * exp(-decay * t) * volume * 3;
  }
  return out;
}

/// Band-passed noise sweep (whooshes / whirs).
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
    lp2 += 0.5 * (lp - lp2); // second stage = rough band-pass
    out[i] = (lp - lp2) * exp(-decay * t) * volume * 4;
  }
  return out;
}

void main() {
  Directory('assets/sfx').createSync(recursive: true);

  // NOTE: fire.wav, hit.wav, sunk.wav, victory.wav, click.wav,
  // count_beep.wav and count_go.wav are REAL clips extracted from the
  // reference gameplay video (see docs). This tool (re)generates only
  // the synthesized effects below so it never clobbers the real ones.

  // ---- MISS: water splash — higher "bloop" + airy "shh", no bass ----
  final miss = buf(0.55);
  add(miss, 0, tone(0.16, (t) => 620 - 380 * t, volume: 0.42, decay: 12));
  add(miss, (0.05 * sr).toInt(),
      sweep(0.42, (t) => 0.55 - 0.25 * t, volume: 0.30, decay: 7));
  writeWav('assets/sfx/miss.wav', miss);

  // ---- DEFEAT: falling dirge ----
  final defeat = buf(1.2);
  const dNotes = [392.0, 311.13, 233.08, 174.61];
  for (var k = 0; k < dNotes.length; k++) {
    add(defeat, (k * 0.22 * sr).toInt(),
        tone(0.34, (t) => dNotes[k], volume: 0.4, decay: 4));
  }
  writeWav('assets/sfx/defeat.wav', defeat);

  // ---- PLACE: short high "pop" blip (matches video's placement taps) ----
  final place = buf(0.12);
  add(place, 0, tone(0.09, (t) => 950 - 350 * t, volume: 0.55, decay: 34));
  add(place, 0, noise(0.03, volume: 0.28, decay: 60, cutoff: 0.55));
  writeWav('assets/sfx/place.wav', place);

  // ---- WHIR: screen/turn transition whoosh (rising band-pass sweep) ----
  final whir = buf(0.5);
  add(whir, 0, sweep(0.45, (t) => 0.08 + 0.5 * t, volume: 0.5, decay: 4));
  writeWav('assets/sfx/whir.wav', whir);

  // ---- DENIED: dull buzz ----
  writeWav('assets/sfx/denied.wav',
      tone(0.16, (t) => 130, volume: 0.4, decay: 12));
}
