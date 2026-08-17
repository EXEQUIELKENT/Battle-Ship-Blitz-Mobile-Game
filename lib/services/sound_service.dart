import 'dart:async';
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

  /// Effects actually played through the pooled `_play()` path (see the
  /// methods below — victory/defeat/place/denied/whir/turnPass/
  /// cannonReady). Everything else (cannon_fire, hit, miss, sunk, click,
  /// count_beep, count_go) is fired via `_playOneShot`, which spins up
  /// its own disposable player and never touches the pool.
  ///
  /// BUGFIX (slow startup / music needing a tap to start): `init()` used
  /// to build a pool for EVERY entry in `_files`, including the
  /// one-shot-only effects above, with some of them (cannon_fire, hit,
  /// miss, click) given an inflated pool of 4-5 players each. That meant
  /// ~49 `AudioPlayer`s were created and awaited one-by-one before
  /// `runApp()` even ran, needlessly stretching cold start — and the
  /// longer that takes, the more likely it is that the menu music's
  /// autoplay attempt (fired on the home screen's very first frame)
  /// lands well outside any residual browser "user activation" window,
  /// making it look like music "only starts after you tap something".
  /// Only building pools for the effects that actually use them cuts
  /// that down to ~21 players and removes the dead pool entirely for the
  /// rest.
  static const _pooledEffects = {
    'victory',
    'defeat',
    'place',
    'denied',
    'whir',
    'turn_pass',
    'cannon_ready',
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

  /// Whether menu music is *supposed* to be playing right now (set by
  /// [startMenuMusic], cleared by [stopMenuMusic]) — independent of
  /// whether the play attempt actually succeeded. Used by
  /// [notifyUserGesture] to know whether it should retry.
  bool _menuMusicWanted = false;

  /// Pre-create a round-robin player pool per effect that actually uses
  /// the pool (see `_pooledEffects`). Safe to call fire-and-forget from
  /// main().
  Future<void> init() async {
    for (final entry in _files.entries) {
      if (!_pooledEffects.contains(entry.key)) continue;
      final size = _defaultPoolSize;
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

  Timer? _menuMusicRetryTimer;
  static const _menuMusicAutoRetries = 6;
  static const _menuMusicRetryGap = Duration(milliseconds: 500);

  /// BUGFIX (background music "only plays after I tap something"): two
  /// distinct causes were bundled under this one symptom, and only one of
  /// them actually needs a tap to fix.
  ///
  /// 1. On Web (and some WebView-based embeds), browsers refuse to play
  ///    ANY audio — even a fresh `AudioPlayer`, even muted-then-unmuted —
  ///    until the page has seen a real user gesture. That genuinely can't
  ///    be worked around without a gesture, so [notifyUserGesture] (wired
  ///    up in `main.dart` to fire on the very first tap/pointer-down
  ///    ANYWHERE in the app, not just a sound-producing button) retries
  ///    the instant one happens — the earliest a browser will allow it.
  /// 2. On native Android/iOS there is no such policy — nothing there
  ///    *requires* a gesture — but `main()` fires `SoundService.init()`
  ///    unawaited at the same moment this runs, spinning up ~21 pooled
  ///    `AudioPlayer`s for sound effects concurrently with this looping
  ///    track's own first `play()` call. That contention can make the
  ///    very first attempt silently land on a not-yet-ready platform
  ///    audio session. Previously the only retry path was
  ///    [notifyUserGesture], so on native the music only ever came back
  ///    to life by accident, whenever the player happened to tap a
  ///    button — exactly the "only after I tap something" symptom, on a
  ///    platform where a tap was never actually required.
  ///
  /// Fixed by keeping the gesture retry (still needed for case 1) AND
  /// adding a short, self-driven retry burst that needs no gesture at
  /// all (fixes case 2 — and also helps case 1 slightly, on browsers
  /// that don't block a plain retry once the page itself has settled).
  Future<void> startMenuMusic() async {
    if (!enabled) return;
    final alreadyWanted = _menuMusicWanted;
    _menuMusicWanted = true;
    await _attemptMenuMusicPlay();
    if (!alreadyWanted) {
      // Only kick off a fresh retry burst for a brand-new request — a
      // request that was already wanted (e.g. a gesture-triggered retry)
      // just makes its one attempt above and leaves any burst already in
      // flight alone.
      _scheduleMenuMusicAutoRetry();
    }
  }

  Future<void> _attemptMenuMusicPlay() async {
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
      // Left `_menuMusicWanted = true` so a retry (gesture-triggered or
      // the auto-retry burst below) picks it back up.
    }
  }

  void _scheduleMenuMusicAutoRetry() {
    _menuMusicRetryTimer?.cancel();
    var attempt = 0;
    _menuMusicRetryTimer = Timer.periodic(_menuMusicRetryGap, (t) {
      attempt++;
      final player = _menuMusicPlayer;
      final playing = player != null && player.state == PlayerState.playing;
      if (!_menuMusicWanted || playing || attempt >= _menuMusicAutoRetries) {
        t.cancel();
        return; // Either it's already playing, no longer wanted, or
                // we've made a reasonable number of attempts — beyond
                // this point only notifyUserGesture (the genuine
                // browser-autoplay-block case) should keep retrying.
      }
      _attemptMenuMusicPlay();
    });
  }

  Future<void> stopMenuMusic() async {
    _menuMusicWanted = false;
    _menuMusicRetryTimer?.cancel();
    _menuMusicRetryTimer = null;
    final player = _menuMusicPlayer;
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {}
    _menuMusicPlayer = null;
  }

  /// Call on every pointer-down/tap anywhere in the app (wired up once,
  /// globally, in `main.dart`). Cheap no-op unless menu music was wanted
  /// but isn't actually playing — see the bugfix note on
  /// [startMenuMusic].
  void notifyUserGesture() {
    if (!_menuMusicWanted) return;
    final player = _menuMusicPlayer;
    if (player != null && player.state == PlayerState.playing) return;
    startMenuMusic();
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
