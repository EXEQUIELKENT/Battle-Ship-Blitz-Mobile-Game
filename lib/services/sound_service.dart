import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Real sound effects via the audioplayers plugin.
///
/// Short synthesized WAV assets live in `assets/sfx/` (see
/// `tool/gen_sounds.dart`). A small pool of players per effect lets
/// overlapping effects (fire + hit + splash) play simultaneously on
/// Android & Web.
///
/// BUGFIX (sound effects sometimes disappearing): the old code called
/// `player.stop()` and then IMMEDIATELY `player.play(...)` without
/// awaiting the stop. On Flutter Web this races the underlying HTML
/// `<audio>` element — a `play()` issued while a `pause()`/reset from the
/// previous `stop()` is still in flight throws (browsers report this as
/// "play() request was interrupted"), and the old code's blanket
/// `catch (_) {}` swallowed that silently, so the sound just never played.
/// It also only kept a pool of 3 players per effect, so any 4th
/// near-simultaneous trigger of the SAME sound (e.g. several quick misses)
/// forced a busy player to be interrupted, which is exactly when that race
/// was likeliest to bite. Fixed by (1) preferring an already-idle player
/// instead of interrupting a busy one, (2) properly awaiting `stop()`
/// before replaying a still-busy player, (3) falling back to a disposable
/// one-off player if every pooled player is busy or a play attempt throws,
/// and (4) logging failures in debug builds instead of eating them
/// silently, so a regression here is visible again instead of just
/// "sometimes the sound doesn't happen".
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  bool enabled = true;
  final _rng = math.Random();

  static const _files = {
    'cannon_fire': 'sfx/cannon_fire.wav',
    'hit': 'sfx/hit.wav',
    'miss': 'sfx/miss.wav',
    'sunk': 'sfx/sunk.wav',
    'victory': 'sfx/victory.wav',
    'defeat': 'sfx/defeat.wav',
    'place': 'sfx/place.wav',
    'click': 'sfx/click.wav',
    'denied': 'sfx/denied.wav',
    'whir': 'sfx/whir.wav',
    'turn_pass': 'sfx/turn_pass.wav',
    'cannon_ready': 'sfx/cannon_ready.wav',
    'count_beep': 'sfx/count_beep.wav',
    'count_go': 'sfx/count_go.wav',
  };

  /// How many pooled players to keep per effect. Effects that can fire in
  /// rapid bursts (cannon fire, hits, misses, UI clicks) get a bigger pool
  /// so a burst is far less likely to need to interrupt a still-playing
  /// player at all.
  static const _poolSizes = {
    'cannon_fire': 5,
    'hit': 5,
    'miss': 5,
    'click': 4,
  };
  static const _defaultPoolSize = 3;

  /// Effects that get a tiny random pitch/rate wobble each play so rapid
  /// repeats (several misses in a row, etc.) don't sound like a stuck
  /// robot repeating the exact same clip.
  static const _variedPitch = {'cannon_fire', 'hit', 'miss', 'click'};

  final Map<String, List<AudioPlayer>> _pool = {};
  final Map<String, int> _cursor = {};

  static const _menuMusicAsset = 'sfx/menu_music.wav';
  AudioPlayer? _menuMusicPlayer;
  final Set<AudioPlayer> _oneShots = <AudioPlayer>{};

  /// Pre-create a round-robin player pool per effect. Safe to call
  /// fire-and-forget from main().
  Future<void> init() async {
    for (final entry in _files.entries) {
      final size = _poolSizes[entry.key] ?? _defaultPoolSize;
      final players = <AudioPlayer>[];
      for (var i = 0; i < size; i++) {
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

  Future<void> _play(String key) async {
    if (!enabled) return;
    final players = _pool[key];
    final asset = _files[key];
    if (players == null || players.isEmpty || asset == null) return;

    final rate = _variedPitch.contains(key)
        ? 0.94 + _rng.nextDouble() * 0.12 // ~±6% pitch/speed wobble
        : 1.0;

    // Prefer a player that's already idle — avoids interrupting (and
    // racing) a player that's mid-playback at all.
    AudioPlayer? target;
    for (final p in players) {
      if (p.state != PlayerState.playing) {
        target = p;
        break;
      }
    }

    if (target != null) {
      await _fire(target, asset, rate);
      return;
    }

    // Every pooled player is busy: round-robin-steal one, but AWAIT the
    // stop before replaying it so we don't race the previous playback.
    final i = _cursor[key]! % players.length;
    _cursor[key] = i + 1;
    final p = players[i];
    try {
      await p.stop();
    } catch (_) {
      // Ignore — we'll still attempt to play below.
    }
    final ok = await _fire(p, asset, rate);
    if (!ok) {
      // Last resort: a disposable one-shot player, so a single stuck
      // pooled player can never fully silence an effect.
      await _fireOneShot(asset, rate);
    }
  }

  Future<bool> _fire(AudioPlayer p, String asset, double rate) async {
    try {
      await p.setPlaybackRate(rate);
      await p.play(AssetSource(asset));
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SoundService: play failed for $asset ($e)');
      }
      return false;
    }
  }

  Future<void> _fireOneShot(String asset, double rate) async {
    try {
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.release);
      await p.setPlaybackRate(rate);
      await p.play(AssetSource(asset));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SoundService: one-shot fallback failed for $asset ($e)');
      }
    }
  }

  Future<void> startMenuMusic() async {
    if (!enabled) return;
    final existing = _menuMusicPlayer;
    if (existing != null && existing.state == PlayerState.playing) return;

    final player = existing ?? AudioPlayer();
    _menuMusicPlayer = player;
    try {
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(0.82);
      await player.play(AssetSource(_menuMusicAsset), volume: 0.82);
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService: menu music play failed ($e)');
    }
  }

  Future<void> stopMenuMusic() async {
    final player = _menuMusicPlayer;
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {}
    _menuMusicPlayer = null;
  }

  void refreshMenuMusic(bool onMenu) {
    if (onMenu) {
      startMenuMusic();
    } else {
      stopMenuMusic();
    }
  }

  void cannonFire() {
    HapticFeedback.mediumImpact();
    _playOneShot('cannon_fire', volume: 1.0);
  }

  void hit() {
    HapticFeedback.heavyImpact();
    _playOneShot('hit', volume: 1.0);
  }

  void miss() {
    HapticFeedback.lightImpact();
    _playOneShot('miss', volume: 1.0);
  }

  void sunk() {
    HapticFeedback.heavyImpact();
    _playOneShot('sunk', volume: 1.0);
  }

  void victory() {
    HapticFeedback.heavyImpact();
    _play('victory');
  }

  void defeat() {
    _play('defeat');
  }

  void place() => _play('place');

  /// UI click uses a dedicated one-shot player instead of the pooled
  /// low-latency players. This makes menu clicks reliable on Flutter Web
  /// even when the shared effect pool is still initializing.
  void click() => _playOneShot('click', volume: 0.9);

  Future<void> _playOneShot(String key, {double volume = 1.0}) async {
    final asset = _files[key];
    if (!enabled || asset == null) return;

    final player = AudioPlayer();
    _oneShots.add(player);
    var released = false;
    Future<void> cleanup() async {
      if (released) return;
      released = true;
      _oneShots.remove(player);
      try { await player.dispose(); } catch (_) {}
    }

    try {
      await player.setReleaseMode(ReleaseMode.release);
      player.onPlayerComplete.first.then((_) => cleanup());
      await player.play(
        AssetSource(asset),
        volume: volume.clamp(0.0, 1.0),
      );
    } catch (e) {
      await cleanup();
      if (kDebugMode) {
        debugPrint('SoundService: one-shot sound failed for $asset ($e)');
      }
    }
  }

  void denied() => _play('denied');

  /// Screen/turn transition whoosh.
  void whir() => _play('whir');

  /// Distinct "turn passed to the other player" cue — plays alongside
  /// [whir] at handoff so a turn change is unmistakable even with sound
  /// as the only cue (e.g. eyes on the board, not the turn badge).
  void turnPass() => _play('turn_pass');

  /// Mechanical "locked in" clunk — synced to the cannon's ready-flash,
  /// right as it settles into the middle of its grid.
  void cannonReady() => _play('cannon_ready');

  /// Countdown warning beep (plays each tick: 3..2..1).
  void countBeep() => _playOneShot('count_beep', volume: 1.0);

  /// Higher "GO!" chime after the final countdown tick.
  void countGo() => _playOneShot('count_go', volume: 1.0);

  Future<void> dispose() async {
    await stopMenuMusic();
    for (final players in _pool.values) {
      for (final player in players) {
        try { await player.dispose(); } catch (_) {}
      }
    }
    _pool.clear();
    _cursor.clear();
    for (final p in List<AudioPlayer>.from(_oneShots)) {
      try { await p.dispose(); } catch (_) {}
    }
    _oneShots.clear();
  }
}
