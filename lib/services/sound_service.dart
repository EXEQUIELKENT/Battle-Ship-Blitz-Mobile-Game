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
///    including those four — through the same [_ManagedPool]: a FIXED-SIZE
///    pool of reusable players per effect, every one of them created ONCE
///    up front and never again during gameplay (see the REGRESSION FIX
///    note on [_ManagedPool] for why on-demand growth was tried and made
///    things worse on real phones), with a timeout-based safety net so a
///    stuck player can never be lost for good.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  bool _enabled = true;
  bool get enabled => _enabled;

  /// ROOT-CAUSE FIX (main-menu sound toggle appearing to do nothing):
  /// this used to be a plain `bool` field. Every one-shot effect already
  /// checked it inside [_play], so gameplay SFX genuinely muted — but
  /// the looping menu-music player never did, because it is only ever
  /// gated at the moment it *starts* (see the guard in [startMenuMusic]).
  /// Flipping this flag while the track was already playing left it
  /// looping right through the "muted" state, which is the one sound
  /// most audible on the main menu — so the button looked completely
  /// broken even though effects were, in fact, being silenced. This
  /// setter now actively pauses/resumes the menu track to match,
  /// mirroring the existing app-lifecycle pause/resume pair
  /// ([onAppPaused]/[onAppResumed]) instead of leaving mute as a
  /// no-op flag.
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _muteMenuMusic();
    } else {
      unawaited(_unmuteMenuMusic());
    }
  }

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

  /// FIXED player count per effect — see the REGRESSION FIX note on
  /// [_ManagedPool] for why this is a single fixed size rather than a
  /// min/max range that grows on demand: growth-on-demand is exactly what
  /// caused a real-device-only regression (lag + audio glitches after a
  /// handful of shots) when a previous pass raised the max end of that
  /// range trying to fix a DIFFERENT bug (cut-off audio). Sized to how
  /// many times an effect can realistically overlap itself in this game —
  /// `cannon_fire`/`hit`/`miss` are the ones fired on every single shot,
  /// and a HIT grants an immediate extra shot, so a hit streak can chain
  /// several of each back-to-back — while one-off cues like `victory`
  /// only ever need one or two. Every player counted here is created ONCE
  /// up front (see [_ManagedPool.warmUp]) — nothing is ever created during
  /// actual gameplay.
  static const Map<String, int> _poolSizes = {
    'cannon_fire': 5,
    'hit': 5,
    'miss': 5,
    'sunk': 2,
    'victory': 1,
    'defeat': 1,
    'place': 2,
    'click': 2,
    'denied': 1,
    'whir': 1,
    'turn_pass': 1,
    'cannon_ready': 1,
    'count_beep': 1,
    'count_go': 1,
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
      final size = _poolSizes[entry.key];
      if (size == null) continue; // shouldn't happen — every key is sized
      final pool = _pools.putIfAbsent(
        entry.key,
        () => _ManagedPool(
          asset: entry.value,
          size: size,
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
      if (_menuMusicWanted && enabled) {
        // Coming back from a pause we did ourselves, resume rather than
        // replay: `play()` restarts an AssetSource from position zero, so
        // glancing at a notification would send the track back to its
        // opening bar every time. `resume()` picks it up mid-phrase where
        // the player left it. If it fails (the OS reclaimed the player
        // while we were away, which is exactly what the pool rebuild
        // above exists for) fall through to a normal play attempt.
        var resumed = false;
        if (_menuMusicPausedByLifecycle) {
          _menuMusicPausedByLifecycle = false;
          final player = _menuMusicPlayer;
          if (player != null) {
            try {
              await player.resume();
              resumed = player.state == PlayerState.playing;
            } catch (_) {/* fall through to a fresh play below */}
          }
        }
        if (!resumed) await _attemptMenuMusicPlay();
        _scheduleMenuMusicAutoRetry();
      }
    } finally {
      _rebuildingPool = false;
    }
  }

  bool _rebuildingPool = false;

  /// Companion to [onAppResumed], called the moment the app stops being
  /// the thing on screen — locked, switched away from, taking a call,
  /// notification shade pulled down.
  ///
  /// Silences the music for as long as the player isn't actually in the
  /// game. Our audio session is deliberately NON-exclusive
  /// (`AndroidAudioFocus.none` / `mixWithOthers` — see [_sfxAudioContext])
  /// so that our own overlapping sound effects can't native-pause each
  /// other. The flip side of never asking for audio focus is that the OS
  /// never takes it away either, so a looping menu track otherwise plays
  /// happily out of a backgrounded app, on top of whatever the player
  /// switched to. Pausing it here is what makes the music behave the way
  /// every other app's does.
  ///
  /// Pause, not stop: [onAppResumed] picks the track back up from the
  /// same position, so a two-second glance at a notification doesn't
  /// send it back to its opening bar.
  ///
  /// Sound EFFECTS need no equivalent — they're one-shots, and the
  /// longest of them rings out in well under a second.
  void onAppPaused() {
    _menuMusicRetryTimer?.cancel();
    final player = _menuMusicPlayer;
    if (player != null && player.state == PlayerState.playing) {
      _menuMusicPausedByLifecycle = true;
      unawaited(player.pause());
    }
  }

  /// Set only when [onAppPaused] is what stopped the music, so
  /// [onAppResumed] knows to RESUME rather than restart — and, just as
  /// importantly, so it never revives music that was stopped for an
  /// ordinary in-game reason like walking into a battle.
  bool _menuMusicPausedByLifecycle = false;

  /// Same idea as [_menuMusicPausedByLifecycle] but for the mute toggle
  /// instead of app backgrounding — kept as its own flag because the two
  /// can overlap (muting, then backgrounding the app, then unmuting
  /// before it's foregrounded again) and each needs to unwind on its own
  /// trigger without stepping on the other.
  bool _menuMusicMutedWhilePlaying = false;

  void _muteMenuMusic() {
    _menuMusicRetryTimer?.cancel();
    final player = _menuMusicPlayer;
    if (player != null && player.state == PlayerState.playing) {
      _menuMusicMutedWhilePlaying = true;
      unawaited(player.pause());
    }
  }

  Future<void> _unmuteMenuMusic() async {
    if (!_menuMusicWanted) return; // not on a screen that wants music
    if (_menuMusicMutedWhilePlaying) {
      _menuMusicMutedWhilePlaying = false;
      final player = _menuMusicPlayer;
      if (player != null) {
        try {
          await player.resume();
          if (player.state == PlayerState.playing) {
            _scheduleMenuMusicAutoRetry();
            return;
          }
        } catch (_) {/* fall through to a fresh attempt below */}
      }
    }
    await _attemptMenuMusicPlay();
    _scheduleMenuMusicAutoRetry();
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
    // Record intent BEFORE the enabled check (unlike before): a screen
    // that wants menu music still wants it even while muted, so that
    // unmuting later (via the [enabled] setter) knows to actually start
    // it rather than treating the request as never having happened.
    final alreadyWanted = _menuMusicWanted;
    _menuMusicWanted = true;
    if (!enabled) return;
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
      // Same per-frame `getCurrentPosition` polling as the pooled players —
      // see the root-cause note in `_ManagedPool._create`. The music track
      // loops and nothing reads its position, so turn the polling off here
      // too rather than leaving one more channel-spammer running for the
      // entire time the app is on a menu.
      player.positionUpdater = null;
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
    // Whatever the app-lifecycle pause was holding, it no longer applies:
    // this is a deliberate stop, and there is now no player to resume.
    _menuMusicPausedByLifecycle = false;
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
  ///
  /// RETRIGGER GUARD: buttons that play this from their own widget code
  /// (see [NeonButton]) are sometimes ALSO played again inside the handler
  /// they invoke, and nested pressables can fire a tap twice — so clicks
  /// landing within a tenth of a second of each other are treated as one
  /// gesture and played once. No human taps two different buttons within
  /// 100 ms; a double sound on every other press was what the guard is
  /// for.
  void click() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastClickAt < 100) return;
    _lastClickAt = now;
    _play('click', volume: 0.9);
  }

  int _lastClickAt = -1000;

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

/// A FIXED-SIZE, fully pre-warmed pool of [AudioPlayer]s all loaded with
/// the same short sound effect — the "reliable audio-management strategy"
/// this service needed for gameplay SFX.
///
/// REGRESSION FIX (real phones got WORSE — lag + audio glitching after
/// only 5-7 shots — after a previous pass raised these pools' dynamic
/// growth caps to fix cut-off audio): that diagnosis had it backwards.
/// The earlier design created just [size] `AudioPlayer`s up front and let
/// `play()` create MORE, lazily, up to a higher cap, whenever a burst
/// exceeded the warm supply. Each new player isn't free even though the
/// underlying decoded sample is shared — `_create()` is FOUR sequential
/// awaited platform-channel round trips
/// (`setAudioContext`/`setSource`/`setPlayerMode`/`setReleaseMode`) to
/// build the native wrapper object. Raising the cap didn't add headroom
/// for free — it made the pool reach for that expensive, mid-gameplay
/// player-creation path far MORE readily (a normal hit streak — HIT grants
/// an immediate extra shot — fires `cannonFire()`/`hit()` several times in
/// a row), and it grew the SHARED native SoundPool's own concurrent-stream
/// bookkeeping right along with it. On a real phone's platform thread that
/// shows up as exactly what got reported: janky frames and glitched/silent
/// audio, worse the more shots had already fired, i.e. "after 5-7 shots" —
/// right around where the pool had to start growing past its old, safer
/// ceiling for the first time.
///
/// Fixed by removing dynamic growth entirely: every player this pool will
/// ever use is created ONCE, up front (during [warmUp], off the gameplay
/// hot path — see [SoundService.init]), and `play()` never calls
/// `_create()` again. When every one of the fixed [size] players is
/// genuinely busy at once (rare — [size] is chosen for this game's actual
/// overlap, not a worst case), it falls back to reusing the
/// longest-running one instead of allocating a new native object mid-shot.
/// That reuse can occasionally cut off an already-playing copy of the
/// SAME effect in a truly extreme burst, which is a far smaller price than
/// stalling the platform thread (and destabilizing the one SHARED native
/// SoundPool every effect draws from) by creating players during active
/// play.
///
///  * A player is returned to idle the instant its clip finishes
///    (`onPlayerComplete`) — always back to idle, never disposed, since
///    the pool never holds more than [size] players in the first place.
///  * A timeout-based safety net force-returns a player even if
///    `onPlayerComplete` never fires (e.g. an interruption the platform
///    plugin fails to report) — this is what prevents a player from ever
///    becoming permanently stuck/unusable.
class _ManagedPool {
  _ManagedPool({
    required this.asset,
    required this.size,
    required this.audioContext,
  });

  final String asset;
  final int size;
  final AudioContext audioContext;

  final List<AudioPlayer> _idle = [];
  final Map<AudioPlayer, void Function()> _busy = {};

  /// How long a checked-out player is considered busy before it's forced
  /// back into the idle pool.
  ///
  /// This is the ONLY thing that ever returns a low-latency player to the
  /// pool: Android's SoundPool has no completion callback, so
  /// `onPlayerComplete` never fires for `PlayerMode.lowLatency` (the
  /// listener below is kept purely for the platforms where it does work).
  /// The old 6s value therefore pinned every player for 6 seconds after a
  /// 0.4s sound, so pools were almost permanently exhausted and nearly
  /// every play fell through to the steal-the-oldest path. Every gameplay
  /// clip in `assets/sfx/` is short (longest is victory at ~1.9s), so this
  /// comfortably outlasts any of them while letting a pool actually
  /// recycle between shots.
  static const _safetyTimeout = Duration(milliseconds: 2200);

  /// Creates every player this pool will ever hold. Called once from
  /// [SoundService.init] (fire-and-forget, well before any gameplay
  /// input) and again by [rebuild] after the app resumes from the
  /// background — never from the gameplay hot path in [play].
  Future<void> warmUp() async {
    if (_idle.isNotEmpty || _busy.isNotEmpty) return; // already built
    for (var i = 0; i < size; i++) {
      try {
        _idle.add(await _create());
      } catch (_) {/* best effort — a missing slot just means slightly
                      less overlap headroom for this one effect */}
    }
  }

  Future<AudioPlayer> _create() async {
    final p = AudioPlayer();
    // ROOT-CAUSE FIX (mobile jank + audio dying mid-match) — measured on a
    // real device with the Dart profiler: 99.4% of ALL UI-thread samples
    // were inside `AudioPlayer.getCurrentPosition` →
    // `MethodChannel.invokeMethod` → `sendPlatformMessage`.
    //
    // Nothing in this app ever asks for a playback position. The calls come
    // from audioplayers itself: `AudioPlayer`'s constructor installs a
    // `FramePositionUpdater`, which polls `getCurrentPosition()` over the
    // platform channel ONCE PER FRAME, PER PLAYER — forever, whether or not
    // that player is playing. This service keeps ~29 pooled players alive,
    // so that was ~29 × 60 = ~1,700 platform round trips per second, each
    // an async call allocating a Future/closure/suspend-state chain.
    //
    // Consequences, which match every symptom reported:
    //  * The UI thread saturates on channel traffic → frames took ~300ms
    //    (raster stayed a healthy 6-10ms — it was never a GPU problem,
    //    which is why earlier render-side optimizations changed nothing).
    //  * The async garbage accumulates faster than GC reclaims it — the
    //    Dart heap climbed ~1MB per shot, past 590MB, until Android
    //    OOM-killed the process. Longer match = bigger heap = longer GC
    //    pauses, i.e. "fine early, unplayable late".
    //  * That same saturated channel is what starves the actual play/stop
    //    commands, so effects drop out mid-to-late match.
    //
    // Setting `positionUpdater = null` disables the polling entirely. One
    // -shot SFX have no use for a position stream, so nothing is lost.
    p.positionUpdater = null;
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
      } else if (_busy.isNotEmpty) {
        // Every one of this pool's fixed players is genuinely busy at
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
        //
        // Deliberately NOT `_create()`-ing a fresh player here even
        // though one used to be an option — see the class doc: doing
        // that mid-gameplay is exactly what caused the real-device
        // regression this pool now avoids.
        final oldest = _busy.keys.first;
        _busy.remove(oldest)?.call();
        try {
          await oldest.stop();
        } catch (_) {}
        player = oldest;
      } else {
        // Only reachable if warmUp() never managed to create a single
        // player for this effect (e.g. the asset failed to load) — best
        // effort, since there's nothing pooled to fall back to.
        player = await _create();
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
    void release() {
      if (released) return;
      released = true;
      safety.cancel();
      sub.cancel();
      _busy.remove(player);
      // Always back to idle — this pool never exceeds `size` players, so
      // there's never a "grew past capacity, let this one go" case.
      _idle.add(player);
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
      // ROOT-CAUSE FIX (effects play once then go silent; menu clicks dead
      // after a match). Verified against audioplayers_android 5.2.1:
      //
      //   SoundPoolPlayer.start():
      //     if (streamId != null) soundPool.resume(streamId)   // stale!
      //     else                  streamId = soundPool.play(...)
      //
      // `streamId` is set on the first play and is ONLY ever cleared by
      // stop(). SoundPool has no completion callback, so after a clip
      // finishes naturally that id still points at a dead stream — every
      // later `resume()` resumes nothing and is SILENT. On top of that,
      // `WrappedPlayer.play()` is guarded by `if (!playing && !released)`,
      // and `playing` is likewise only cleared by pause()/stop() — so a
      // second `resume()` was frequently a no-op before it even reached
      // the native player.
      //
      // Net effect: each pooled player produced sound exactly ONCE, then
      // was mute for the rest of the app's lifetime. It looked random
      // ("sometimes it plays") only because a pool has several players and
      // the steal-the-oldest path happens to call stop(), briefly reviving
      // one. It also explains why menu clicks died after a match: those
      // pools were spent during the battle and never reset.
      //
      // `stop()` fixes BOTH preconditions in one call — it pauses (so
      // `playing` goes false) and seeks to 0, which routes to
      // SoundPoolPlayer.stop() and nulls `streamId` — so the next start()
      // takes the `soundPool.play(...)` branch and produces a real, fresh
      // stream every time. `prepared` stays true, so the already-loaded
      // sample is reused and this is still the low-latency path (no asset
      // reload).
      await player.stop();
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
      release();
    }
  }

  /// BUGFIX (some sound effects going silent specifically after
  /// backgrounding and returning to the app, rather than all of them):
  /// this used to dispose every player without first canceling the
  /// `onPlayerComplete` subscription / safety timer of any player still
  /// checked out ("busy") at the moment the app was backgrounded — e.g.
  /// whichever effect happened to be mid-playback right when the phone
  /// was locked or the app was switched away from.
  ///
  /// [rebuild] (called by [SoundService.onAppResumed]) runs this BEFORE
  /// [warmUp] repopulates `_idle` with brand-new players. Without the
  /// cancellation below, that old player's listener was still live: its
  /// `onPlayerComplete` event (already in flight over the platform
  /// channel) or its 2.2s safety timer could fire AFTER this method
  /// returned, running `play()`'s `release()` closure against the OLD,
  /// now-DISPOSED player — which pushes it straight into the SAME
  /// `_idle` list `warmUp` had just filled with working ones. The next
  /// `play()` for that effect could then hand out that stale, disposed
  /// player, whose `stop()`/`resume()` calls fail silently — exactly
  /// "this one effect went quiet" rather than the whole roster, since
  /// only effects that happened to be busy at the exact moment of
  /// backgrounding were ever at risk.
  Future<void> dispose() async {
    // Cancel every busy player's own listeners FIRST, so none of them can
    // fire mid- or post-disposal and reinsert a dead player into the pool
    // this method (and the `warmUp()` right after it, via [rebuild]) is
    // about to rebuild clean.
    for (final cancel in _busy.values) {
      cancel();
    }
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
