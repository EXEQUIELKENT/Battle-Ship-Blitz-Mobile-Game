import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Real sound effects via the audioplayers plugin.
///
/// Short synthesized WAV assets live in `assets/sfx/` (see
/// `tool/gen_sounds.dart`). A small pool of players lets overlapping
/// effects (fire + hit + splash) play simultaneously on Android & Web.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  bool enabled = true;

  static const _files = {
    'fire': 'sfx/fire.wav',
    'hit': 'sfx/hit.wav',
    'miss': 'sfx/miss.wav',
    'sunk': 'sfx/sunk.wav',
    'victory': 'sfx/victory.wav',
    'defeat': 'sfx/defeat.wav',
    'place': 'sfx/place.wav',
    'click': 'sfx/click.wav',
    'denied': 'sfx/denied.wav',
  };

  final Map<String, List<AudioPlayer>> _pool = {};
  final Map<String, int> _cursor = {};

  /// Pre-create a round-robin player pool per effect. Safe to call
  /// fire-and-forget from main().
  Future<void> init() async {
    for (final entry in _files.entries) {
      final players = <AudioPlayer>[];
      for (var i = 0; i < 3; i++) {
        final p = AudioPlayer();
        try {
          await p.setSource(AssetSource(entry.value));
          await p.setPlayerMode(PlayerMode.lowLatency);
          await p.setReleaseMode(ReleaseMode.stop);
        } catch (_) {/* cosmetic */}
        players.add(p);
      }
      _pool[entry.key] = players;
      _cursor[entry.key] = 0;
    }
  }

  void _play(String key) {
    if (!enabled) return;
    final players = _pool[key];
    if (players == null || players.isEmpty) return;
    final i = _cursor[key]! % players.length;
    _cursor[key] = i + 1;
    final p = players[i];
    try {
      p.stop();
      p.play(AssetSource(_files[key]!));
    } catch (_) {
      // Audio is cosmetic — ignore failures (e.g. web autoplay policy).
    }
  }

  void fire() {
    HapticFeedback.mediumImpact();
    _play('fire');
  }

  void hit() {
    HapticFeedback.heavyImpact();
    _play('hit');
  }

  void miss() {
    HapticFeedback.lightImpact();
    _play('miss');
  }

  void sunk() {
    HapticFeedback.heavyImpact();
    _play('sunk');
  }

  void victory() {
    HapticFeedback.heavyImpact();
    _play('victory');
  }

  void defeat() {
    _play('defeat');
  }

  void place() => _play('place');

  void click() => _play('click');

  void denied() => _play('denied');
}
