import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Real sound effects via the audioplayers plugin.
///
/// Short synthesized WAV assets live in `assets/sfx/` (see
/// `tool/gen_sounds.dart`). A bounded pool of [AudioPlayer]s per effect
/// (see [_ManagedPool]) lets overlapping effects (fire + hit + splash) play
/// simultaneously on Android & Web without ever cutting each other off.
///
/// ROOT-CAUSE FIX (audio disappearing mid-match / cut off before finishing):
/// two compounding bugs were found here.
///
/// 1. **Audio-focus self-interruption.** `audioplayers`' Android backend
///    defaults every single `AudioPlayer` to request EXCLUSIVE audio focus
///    (`AudioManager.AUDIOFOCUS_GAIN`) the instant it starts playing. Since
///    this app plays many short, deliberately-OVERLAPPING effects (cannon
///    fire immediately followed by an impact sound, several rapid shots),
///    every new sound's own focus request silently steals focus from
///    whichever sibling player — from THIS SAME APP — was already
///    mid-clip, which native-pauses it. That pause happens entirely on the
///    native side; the Dart-side `AudioPlayer.state` is never told, so it
///    keeps reporting `playing` while the clip has actually gone dead —
///    exactly "cut off before the clip finishes", and exactly why it gets
///    worse as a match goes on (more overlapping shots quietly leave more
///    zombie paused players behind). Fixed by giving every player in this
///    service an explicit, non-exclusive [_sfxAudioContext]
///    (`AndroidAudioFocus.none` / iOS `mixWithOthers`) so our own effects
///    never fight each other — or themselves — for the OS audio focus
///    stack. See `audioplayers_android`'s `FocusManager`/`WrappedPlayer` if
///    this ever needs re-diagnosing.
///
/// 2. **Unbounded player creation.** `cannonFire()`, `hit()`, `miss()` and
///    `sunk()` — the four sounds fired on literally every shot — used to
///    spin up a brand-new disposable `AudioPlayer` on EVERY call via a
///    one-shot helper, never reusing one. A long match with many
///    consecutive shots means many dozens of native player objects created
///    over time; if a single one of them ever fails to fire its
///    `onPlayerComplete` event (which the interruption above made likely),
///    it leaked forever. That's the "excessive audio player creation /
///    resource exhaustion" and "one-shot player cleanup" failure modes
///    called out in review. Fixed by routing every gameplay effect —
///    including those four — through the same bounded [_ManagedPool]:
///    a small warm pool of reusable players per effect that only grows
///    (briefly, capped) under genuine simultaneous load and shrinks back
///    down afterward, with a timeout-based safety net so a stuck player
///    can never be lost for good.
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

  /// Warm (min) / cap (max) player counts per effect. Sized to how many
  /// times an effect can realistically overlap itself in this game — e.g.
  /// `cannon_fire`/`hit`/`miss` can stack a little (both sides' cannons,
  /// quick taps) so they get a bit more headroom than one-off cues like
  /// `victory`. These are hard caps: even under a pathological burst, a
  /// single effect can never spin up more than `max` native players, and
  /// the pool shrinks back down to something reasonable once the burst
  /// passes (see [_ManagedPool]).
  static const Map<String, (int min, int max)> _poolSizes = {
    'cannon_fire': (2, 4),
    'hit': (2, 4),
    'miss': (2, 4),
    'sunk': (1, 3),
    'victory': (1, 2),
    'defeat': (1, 2),
    'place': (1, 3),
    'click': (1, 3),
    'denied': (1, 2),
    'whir': (1, 2),
    'turn_pass': (1, 2),
    'cannon_ready': (1, 2),
    'count_beep': (1, 2),
    'count_go': (1, 2),
  };

  /// Effects that get a tiny random pitch/rate wobble each play so rapid
  /// repeats (several misses in a row, etc.) don't sound like a stuck
  /// robot repeating the exact same clip.
  static const _variedPitch = {'cannon_fire', 'hit', 'miss', 'click'};

  /// Non-exclusive audio context shared by every player this service
  /// creates (pooled effects AND menu music). `AndroidAudioFocus.none`
  /// means we never ask Android's `AudioManager` for focus at all — so our
  /// own overlapping sounds can never steal focus from (and silently
  /// native-pause) each other. `mixWithOthers` on iOS is the equivalent:
  /// this app's audio plays alongside whatever else is already playing
  /// instead of trying to take over the session. See the class doc above.
  static final AudioContext _sfxAudioContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {AVAudioSessionOptions.mixWithOthers},
    ),
  );

  final Map<String, _ManagedPool> _pools = {};

  static const _menuMusicAsset = 'sfx/menu_music.wav';
  AudioPlayer? _menuMusicPlayer;

  /// Whether menu music is *supposed* to be playing right now (set by
  /// [startMenuMusic], cleared by [stopMenuMusic]) — independent of
  /// whether the play attempt actually succeeded. Used by
  /// [notifyUserGesture] to know whether it should retry.
  bool _menuMusicWanted = false;

  /// Pre-create every effect's warm player pool. Safe to call
  /// fire-and-forget from main().
  Future<void> init() async {
    try {
      await AudioPlayer.global.setAudioContext(_sfxAudioContext);
    } catch (_) {/* best effort — per-player context below still applies */}
    await _buildPools();
  }

  Future<void> _buildPools() async {
    for (final entry in _files.entries) {
      final sizes = _poolSizes[entry.key];
      if (sizes == null) continue; // shouldn't happen — every key is sized
      final pool = _pools.putIfAbsent(
        entry.key,
        () => _ManagedPool(
          asset: entry.value,
          minPlayers: sizes.$1,
          maxPlayers: sizes.$2,
          audioContext: _sfxAudioContext,
        ),
      );
      await pool.warmUp();
    }
  }

  /// BUGFIX (all sound effects going silent mid-game on phones): nothing
  /// in the app previously observed `AppLifecycleState`, so SoundService
  /// never knew when it left or returned to the foreground. On Android,
  /// backgrounding the app (locking the screen, taking a call, swiping to
  /// another app, even just pulling down the notification shade) can make
  /// the OS reclaim the native SoundPool session backing the low-latency
  /// pooled players to free resources; iOS deactivates the shared
  /// AVAudioSession in the same situations. Either way the Dart-side
  /// `AudioPlayer` objects survive and still report a normal idle/
  /// completed state, so a pool happily keeps handing them out — but their
  /// underlying native sample is gone, so `play()` returns successfully
  /// and produces no sound at all for the rest of the match. Rebuilding
  /// every pool (reloading every asset into brand-new native players) the
  /// instant the app comes back to the foreground restores real audio
  /// immediately instead of leaving it dead until a full app restart.
  /// Menu music is nudged back to life the same way, since its player can
  /// be silently killed the same way (e.g. returning to the app from the
  /// home screen).
  Future<void> onAppResumed() async {
    if (_rebuildingPool) return;
    _rebuildingPool = true;
    try {
      for (final pool in _pools.values) {
        await pool.rebuild();
      }
      if (_menuMusicWanted) {
        await _attemptMenuMusicPlay();
        _scheduleMenuMusicAutoRetry();
      }
    } finally {
      _rebuildingPool = false;
    }
  }

  bool _rebuildingPool = false;

  /// Companion to [onAppResumed]: just stops the menu-music auto-retry
  /// burst (if one happens to be running) so it doesn't spin pointlessly
  /// while backgrounded. There's nothing else to proactively tear down —
  /// pooled players clean themselves up on completion regardless of
  /// lifecycle state, and [onAppResumed] fully rebuilds every pool anyway.
  void onAppPaused() {
    _menuMusicRetryTimer?.cancel();
  }

  Future<void> _play(String key, {double volume = 1.0}) async {
    if (!enabled) return;
    final pool = _pools[key];
    if (pool == null) return;
    final rate = _variedPitch.contains(key)
        ? 0.94 + _rng.nextDouble() * 0.12 // ~±6% pitch/speed wobble
        : 1.0;
    await pool.play(volume: volume, rate: rate);
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
  ///    unawaited at the same moment this runs, spinning up pooled
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
      await player.setAudioContext(_sfxAudioContext);
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
    _play('cannon_fire');
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

  /// UI click. Same pooled path as everything else now — no longer needs
  /// a special case to stay reliable while the pools are still warming up,
  /// since `_play` just no-ops safely if a pool isn't built yet.
  void click() => _play('click', volume: 0.9);

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
  void countBeep() => _play('count_beep');

  /// Higher "GO!" chime after the final countdown tick.
  void countGo() => _play('count_go');

  Future<void> dispose() async {
    await stopMenuMusic();
    for (final pool in _pools.values) {
      await pool.dispose();
    }
    _pools.clear();
  }
}

/// A bounded, self-healing pool of [AudioPlayer]s all loaded with the same
/// short sound effect — the "reliable audio-management strategy" this
/// service needed for gameplay SFX.
///
/// Design (deliberately conservative — see the class doc on
/// [SoundService] for the two bugs this replaces):
///  * [minPlayers] are created up front and kept warm/idle between plays.
///  * `play()` NEVER touches a player that's currently mid-clip — it only
///    ever hands out a player from the idle pool, or creates a fresh one
///    if every pooled player is busy (up to [maxPlayers] concurrently).
///    This is what guarantees overlapping sounds never cut each other off.
///  * A player is returned to the idle pool the instant its clip finishes
///    (`onPlayerComplete`). If the pool has grown past [maxPlayers] to
///    absorb a burst, the extra player is released instead of kept, so the
///    pool naturally shrinks back down afterward.
///  * A timeout-based safety net force-returns a player even if
///    `onPlayerComplete` never fires (e.g. an interruption the platform
///    plugin fails to report) — this is what prevents a player from ever
///    becoming permanently stuck/unusable.
///  * Only in the genuinely pathological case of [maxPlayers] simultaneous
///    copies of the SAME effect already playing does this fall back to
///    reusing the longest-running one (awaiting its `stop()` first, so it
///    can never race a still-in-flight play call).
class _ManagedPool {
  _ManagedPool({
    required this.asset,
    required this.minPlayers,
    required this.maxPlayers,
    required this.audioContext,
  });

  final String asset;
  final int minPlayers;
  final int maxPlayers;
  final AudioContext audioContext;

  final List<AudioPlayer> _idle = [];
  final Map<AudioPlayer, void Function()> _busy = {};

  static const _safetyTimeout = Duration(seconds: 6);

  Future<void> warmUp() async {
    if (_idle.isNotEmpty || _busy.isNotEmpty) return; // already built
    for (var i = 0; i < minPlayers; i++) {
      try {
        _idle.add(await _create());
      } catch (_) {/* best effort — play() will lazily create on demand */}
    }
  }

  Future<AudioPlayer> _create() async {
    final p = AudioPlayer();
    await p.setAudioContext(audioContext);
    await p.setSource(AssetSource(asset));
    await p.setPlayerMode(PlayerMode.lowLatency);
    await p.setReleaseMode(ReleaseMode.stop);
    return p;
  }

  Future<void> play({double volume = 1.0, double rate = 1.0}) async {
    AudioPlayer player;
    try {
      if (_idle.isNotEmpty) {
        player = _idle.removeLast();
      } else if (_busy.length < maxPlayers) {
        player = await _create();
      } else {
        // Every pooled player (up to the hard cap) is genuinely busy at
        // once — reuse the oldest, but AWAIT its stop before replaying it
        // so this can never race that still-in-flight playback. Detach it
        // from its OLD checkout directly (just unsubscribing/cancelling
        // that checkout's own listeners) rather than through that
        // checkout's normal completion path, which would incorrectly hand
        // it straight back to the idle pool at the same moment we're
        // about to reuse it right here — i.e. a player briefly sitting in
        // both `_idle` and `_busy` at once, which a concurrent play() call
        // could then also check out. That's exactly the "reuse while
        // still playing" race this whole pool exists to prevent.
        final oldest = _busy.keys.first;
        _busy.remove(oldest)?.call();
        try {
          await oldest.stop();
        } catch (_) {}
        player = oldest;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SoundService: could not obtain a player for $asset ($e)');
      }
      return;
    }

    late final StreamSubscription<void> sub;
    late final Timer safety;
    var released = false;
    Future<void> release() async {
      if (released) return;
      released = true;
      safety.cancel();
      await sub.cancel();
      _busy.remove(player);
      if (_idle.length < maxPlayers) {
        _idle.add(player);
      } else {
        // Pool already has enough idle players resident — this one was
        // only created to absorb a burst, so let it go instead of
        // growing the pool permanently.
        try {
          await player.dispose();
        } catch (_) {}
      }
    }

    sub = player.onPlayerComplete.listen((_) => release());
    safety = Timer(_safetyTimeout, release);
    // The busy-map entry only cancels this checkout's OWN listeners — see
    // the steal-path comment above for why it must not also perform
    // `release`'s idle-return side effect.
    _busy[player] = () {
      safety.cancel();
      sub.cancel();
    };

    try {
      await player.setVolume(volume.clamp(0.0, 1.0));
      // Resuming (rather than re-calling play(source)) reuses the already
      // -prepared native player instead of tearing it down and reloading
      // the asset on every single play — this is the low-latency path.
      await player.resume();
      // Playback rate can only be applied to the underlying native stream
      // once it has actually started (see SoundPool's per-stream setRate),
      // so this is set AFTER resume(), not before.
      if (rate != 1.0) await player.setPlaybackRate(rate);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SoundService: play failed for $asset ($e)');
      }
      await release();
    }
  }

  Future<void> dispose() async {
    for (final p in [..._idle, ..._busy.keys]) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _idle.clear();
    _busy.clear();
  }

  /// Tears down and recreates every player in this pool — see the bugfix
  /// note on [SoundService.onAppResumed] for why that's necessary after
  /// the app returns from the background.
  Future<void> rebuild() async {
    await dispose();
    await warmUp();
  }
}
