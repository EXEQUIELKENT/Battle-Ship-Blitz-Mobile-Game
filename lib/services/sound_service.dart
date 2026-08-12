import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Retro-style synthesized sound effects.
///
/// Short PCM blips are synthesized in memory, painted into a picture
/// and decoded so playback goes through Flutter's engine channel —
/// no external audio packages needed and fully Web-compatible.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  bool enabled = true;
  bool _ready = false;

  final Random _rng = Random();

  static const int _sampleRate = 22050;

  Future<void> init() async {
    _ready = true;
  }

  Float32List _tone(
    double seconds,
    double Function(double t) freqAt, {
    double volume = 0.4,
    bool noise = false,
    double decay = 4.0,
  }) {
    final n = (seconds * _sampleRate).toInt();
    final out = Float32List(n);
    double phase = 0;
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      final env = exp(-decay * t);
      double sample;
      if (noise) {
        sample = (_rng.nextDouble() * 2 - 1) * env * volume;
      } else {
        final f = freqAt(t);
        phase += 2 * pi * f / _sampleRate;
        sample = sin(phase) * env * volume;
      }
      out[i] = sample;
    }
    return out;
  }

  Future<void> _play(Float32List samples) async {
    if (!enabled || !_ready) return;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()..color = const ui.Color(0xFF000000);
      final n = samples.length;
      final path = ui.Path();
      for (var i = 0; i < n; i++) {
        final x = i.toDouble();
        final y = samples[i].clamp(-1.0, 1.0).toDouble();
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
      final picture = recorder.endRecording();
      final image = await picture.toImage(n, 1);
      final byteData = await image.toByteData();
      if (byteData == null) return;
      await SystemChannels.platform.invokeMethod(
        'SystemSound.playRaw',
        byteData.buffer.asUint8List(),
      );
    } catch (_) {
      // Audio is cosmetic — silently ignore failures (e.g. on web).
    }
  }

  void fire() {
    HapticFeedback.mediumImpact();
    _play(_tone(0.18, (t) => 320 - 900 * t, volume: 0.5, decay: 10));
  }

  void hit() {
    HapticFeedback.heavyImpact();
    _play(_tone(0.35, (t) => 90, volume: 0.6, noise: true, decay: 6));
  }

  void miss() {
    HapticFeedback.lightImpact();
    _play(_tone(0.25, (t) => 220 - 400 * t, volume: 0.3, decay: 7));
  }

  void sunk() {
    HapticFeedback.heavyImpact();
    _play(_tone(0.6, (t) => 160 - 180 * t, volume: 0.55, decay: 4));
  }

  void victory() {
    HapticFeedback.heavyImpact();
    final seq = Float32List((_sampleRate * 0.9).toInt());
    final notes = [523.25, 659.25, 783.99, 1046.5];
    final seg = (_sampleRate * 0.2).toInt();
    for (var nIdx = 0; nIdx < notes.length; nIdx++) {
      final tone = _tone(0.22, (t) => notes[nIdx], volume: 0.4, decay: 5);
      final start = nIdx * seg;
      for (var i = 0; i < tone.length && start + i < seq.length; i++) {
        seq[start + i] += tone[i];
      }
    }
    _play(seq);
  }

  void defeat() {
    final seq = Float32List((_sampleRate * 0.9).toInt());
    final notes = [392.0, 311.13, 233.08, 174.61];
    final seg = (_sampleRate * 0.2).toInt();
    for (var nIdx = 0; nIdx < notes.length; nIdx++) {
      final tone = _tone(0.24, (t) => notes[nIdx], volume: 0.35, decay: 4);
      final start = nIdx * seg;
      for (var i = 0; i < tone.length && start + i < seq.length; i++) {
        seq[start + i] += tone[i];
      }
    }
    _play(seq);
  }

  void place() {
    _play(_tone(0.1, (t) => 500 + 300 * t, volume: 0.3, decay: 12));
  }

  void click() {
    _play(_tone(0.06, (t) => 700, volume: 0.25, decay: 20));
  }

  void denied() {
    _play(_tone(0.15, (t) => 140, volume: 0.4, decay: 8));
  }
}
