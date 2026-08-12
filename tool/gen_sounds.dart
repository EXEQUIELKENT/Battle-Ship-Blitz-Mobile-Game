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

void main() {
  Directory('assets/sfx').createSync(recursive: true);

  // ---- CANNON FIRE: punchy low thump + crack ----
  final fire = buf(0.5);
  add(fire, 0, noise(0.18, volume: 0.55, decay: 16, cutoff: 0.5));
  add(fire, 0, tone(0.3, (t) => 140 - 260 * t, volume: 0.7, decay: 12));
  add(fire, (0.02 * sr).toInt(),
      noise(0.3, volume: 0.3, decay: 8, cutoff: 0.12));
  writeWav('assets/sfx/fire.wav', fire);

  // ---- HIT: heavy explosion boom + debris sizzle ----
  final hit = buf(0.7);
  add(hit, 0, noise(0.5, volume: 0.8, decay: 7, cutoff: 0.16));
  add(hit, 0, tone(0.4, (t) => 90 - 60 * t, volume: 0.6, decay: 8));
  add(hit, (0.08 * sr).toInt(),
      noise(0.4, volume: 0.25, decay: 5, cutoff: 0.6));
  writeWav('assets/sfx/hit.wav', hit);

  // ---- MISS: water splash (bloop + fizz) ----
  final miss = buf(0.6);
  add(miss, 0, tone(0.22, (t) => 500 - 700 * t, volume: 0.4, decay: 9));
  add(miss, (0.06 * sr).toInt(),
      noise(0.45, volume: 0.35, decay: 6, cutoff: 0.35));
  writeWav('assets/sfx/miss.wav', miss);

  // ---- SUNK: big explosion + sinking glissando ----
  final sunk = buf(1.3);
  add(sunk, 0, noise(0.6, volume: 0.8, decay: 6, cutoff: 0.14));
  add(sunk, 0, tone(0.5, (t) => 100 - 70 * t, volume: 0.6, decay: 6));
  add(sunk, (0.35 * sr).toInt(),
      tone(0.8, (t) => 320 - 260 * t, volume: 0.35, decay: 4));
  writeWav('assets/sfx/sunk.wav', sunk);

  // ---- VICTORY: rising fanfare ----
  final victory = buf(1.2);
  const vNotes = [523.25, 659.25, 783.99, 1046.5];
  for (var k = 0; k < vNotes.length; k++) {
    add(victory, (k * 0.18 * sr).toInt(),
        tone(0.3, (t) => vNotes[k], volume: 0.45, decay: 5));
  }
  writeWav('assets/sfx/victory.wav', victory);

  // ---- DEFEAT: falling dirge ----
  final defeat = buf(1.2);
  const dNotes = [392.0, 311.13, 233.08, 174.61];
  for (var k = 0; k < dNotes.length; k++) {
    add(defeat, (k * 0.22 * sr).toInt(),
        tone(0.34, (t) => dNotes[k], volume: 0.4, decay: 4));
  }
  writeWav('assets/sfx/defeat.wav', defeat);

  // ---- PLACE: wooden clunk ----
  final place = buf(0.2);
  add(place, 0, tone(0.12, (t) => 240 - 120 * t, volume: 0.5, decay: 22));
  add(place, 0, noise(0.05, volume: 0.3, decay: 40, cutoff: 0.4));
  writeWav('assets/sfx/place.wav', place);

  // ---- CLICK: UI tick ----
  writeWav('assets/sfx/click.wav',
      tone(0.06, (t) => 800, volume: 0.3, decay: 30));

  // ---- DENIED: dull buzz ----
  writeWav('assets/sfx/denied.wav',
      tone(0.16, (t) => 130, volume: 0.4, decay: 12));
}
