import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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
///
/// 3. **Reused-player race during fast-paced gameplay.** Even with (1) and
///    (2) fixed, effects were STILL reported as inconsistently cut off or
///    silent specifically during active play (hit streaks, multiple
///    LAN/BLITZ shooters) — i.e. exactly when a pool's fixed players get
///    reused most often. Two bugs compounded here too: every effect shared
///    ONE flat, worst-case-sized busy-timeout, so short/frequent effects
///    (`cannon_fire`, `hit`, `miss`) sat "busy" 3-5x longer than their
///    actual clip and hit the reuse path far more than their real overlap
///    needed; and reuse itself didn't wait for a still-in-flight previous
///    checkout's own `stop`/`resume` calls to finish before dispatching
///    its own on the same physical player, so two calls could genuinely
///    race on one player. Fixed by sizing each effect's busy-timeout to
///    its own clip length (see [SoundService._safetyTimeoutFor]) and by
///    serializing reuse behind a per-player "previous checkout finished"
///    gate (see the ROOT-CAUSE FIX note on [_ManagedPool.play]).
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
    // Cannon Fire variants:
    'cannon_fire_mk1': 'sfx/cannon_fire_mk1.wav',
    'cannon_fire_inferno': 'sfx/cannon_fire_inferno.wav',
    'cannon_fire_tesla': 'sfx/cannon_fire_tesla.wav',
    'cannon_fire_venom': 'sfx/cannon_fire_venom.wav',
    'cannon_fire_royal': 'sfx/cannon_fire_royal.wav',
    'cannon_fire_phantom': 'sfx/cannon_fire_phantom.wav',
    'cannon_fire_kraken': 'sfx/cannon_fire_kraken.wav',
    'cannon_fire_sunfire': 'sfx/cannon_fire_sunfire.wav',
    'cannon_fire_void': 'sfx/cannon_fire_void.wav',
    'cannon_fire_pirate': 'sfx/cannon_fire_pirate.wav',
    'cannon_fire_f_pirate': 'sfx/cannon_fire_f_pirate.wav',
    'cannon_fire_naval': 'sfx/cannon_fire_naval.wav',
    'cannon_fire_f_naval': 'sfx/cannon_fire_f_naval.wav',
    'cannon_fire_steam': 'sfx/cannon_fire_steam.wav',
    'cannon_fire_f_steam': 'sfx/cannon_fire_f_steam.wav',
    'cannon_fire_arctic': 'sfx/cannon_fire_arctic.wav',
    'cannon_fire_f_arctic': 'sfx/cannon_fire_f_arctic.wav',
    'cannon_fire_volcanic': 'sfx/cannon_fire_volcanic.wav',
    'cannon_fire_f_volcanic': 'sfx/cannon_fire_f_volcanic.wav',
    'cannon_fire_scifi': 'sfx/cannon_fire_scifi.wav',
    'cannon_fire_f_scifi': 'sfx/cannon_fire_f_scifi.wav',
    // Cannon Ready variants:
    'cannon_ready_mk1': 'sfx/cannon_ready_mk1.wav',
    'cannon_ready_inferno': 'sfx/cannon_ready_inferno.wav',
    'cannon_ready_tesla': 'sfx/cannon_ready_tesla.wav',
    'cannon_ready_venom': 'sfx/cannon_ready_venom.wav',
    'cannon_ready_royal': 'sfx/cannon_ready_royal.wav',
    'cannon_ready_phantom': 'sfx/cannon_ready_phantom.wav',
    'cannon_ready_kraken': 'sfx/cannon_ready_kraken.wav',
    'cannon_ready_sunfire': 'sfx/cannon_ready_sunfire.wav',
    'cannon_ready_void': 'sfx/cannon_ready_void.wav',
    'cannon_ready_pirate': 'sfx/cannon_ready_pirate.wav',
    'cannon_ready_f_pirate': 'sfx/cannon_ready_f_pirate.wav',
    'cannon_ready_naval': 'sfx/cannon_ready_naval.wav',
    'cannon_ready_f_naval': 'sfx/cannon_ready_f_naval.wav',
    'cannon_ready_steam': 'sfx/cannon_ready_steam.wav',
    'cannon_ready_f_steam': 'sfx/cannon_ready_f_steam.wav',
    'cannon_ready_arctic': 'sfx/cannon_ready_arctic.wav',
    'cannon_ready_f_arctic': 'sfx/cannon_ready_f_arctic.wav',
    'cannon_ready_volcanic': 'sfx/cannon_ready_volcanic.wav',
    'cannon_ready_f_volcanic': 'sfx/cannon_ready_f_volcanic.wav',
    'cannon_ready_scifi': 'sfx/cannon_ready_scifi.wav',
    'cannon_ready_f_scifi': 'sfx/cannon_ready_f_scifi.wav',
    // Hit variants:
    'hit_mk1': 'sfx/hit_mk1.wav',
    'hit_inferno': 'sfx/hit_inferno.wav',
    'hit_tesla': 'sfx/hit_tesla.wav',
    'hit_venom': 'sfx/hit_venom.wav',
    'hit_royal': 'sfx/hit_royal.wav',
    'hit_phantom': 'sfx/hit_phantom.wav',
    'hit_kraken': 'sfx/hit_kraken.wav',
    'hit_sunfire': 'sfx/hit_sunfire.wav',
    'hit_void': 'sfx/hit_void.wav',
    'hit_pirate': 'sfx/hit_pirate.wav',
    'hit_f_pirate': 'sfx/hit_f_pirate.wav',
    'hit_naval': 'sfx/hit_naval.wav',
    'hit_f_naval': 'sfx/hit_f_naval.wav',
    'hit_steam': 'sfx/hit_steam.wav',
    'hit_f_steam': 'sfx/hit_f_steam.wav',
    'hit_arctic': 'sfx/hit_arctic.wav',
    'hit_f_arctic': 'sfx/hit_f_arctic.wav',
    'hit_volcanic': 'sfx/hit_volcanic.wav',
    'hit_f_volcanic': 'sfx/hit_f_volcanic.wav',
    'hit_scifi': 'sfx/hit_scifi.wav',
    'hit_f_scifi': 'sfx/hit_f_scifi.wav',
    // Miss variants:
    'miss_classic': 'sfx/miss_classic.wav',
    'miss_arctic': 'sfx/miss_arctic.wav',
    'miss_f_arctic': 'sfx/miss_f_arctic.wav',
    'miss_deep': 'sfx/miss_deep.wav',
    'miss_kraken': 'sfx/miss_kraken.wav',
    'miss_sunset': 'sfx/miss_sunset.wav',
    'miss_pirate': 'sfx/miss_pirate.wav',
    'miss_f_pirate': 'sfx/miss_f_pirate.wav',
    'miss_naval': 'sfx/miss_naval.wav',
    'miss_f_naval': 'sfx/miss_f_naval.wav',
    'miss_steam': 'sfx/miss_steam.wav',
    'miss_f_steam': 'sfx/miss_f_steam.wav',
    'miss_volcanic': 'sfx/miss_volcanic.wav',
    'miss_f_volcanic': 'sfx/miss_f_volcanic.wav',
    'miss_scifi': 'sfx/miss_scifi.wav',
    'miss_f_scifi': 'sfx/miss_f_scifi.wav',
    'miss_mk1': 'sfx/miss_mk1.wav',
    'miss_royal': 'sfx/miss_royal.wav',
    'miss_inferno': 'sfx/miss_inferno.wav',
    'miss_tesla': 'sfx/miss_tesla.wav',
    'miss_venom': 'sfx/miss_venom.wav',
    'miss_phantom': 'sfx/miss_phantom.wav',
    'miss_sunfire': 'sfx/miss_sunfire.wav',
    'miss_void': 'sfx/miss_void.wav',
    // Turn Pass variants:
    // One per legacy battlefield. Before these, the only non-family
    // handoff cues belonged to the four flat themes that were deleted when
    // the illustrated legacy decks replaced them, so all nine legacy
    // boards — the default included — fell back to the generic chime.
    'turn_pass_mk1': 'sfx/turn_pass_mk1.wav',
    'turn_pass_inferno': 'sfx/turn_pass_inferno.wav',
    'turn_pass_tesla': 'sfx/turn_pass_tesla.wav',
    'turn_pass_venom': 'sfx/turn_pass_venom.wav',
    'turn_pass_royal': 'sfx/turn_pass_royal.wav',
    'turn_pass_phantom': 'sfx/turn_pass_phantom.wav',
    'turn_pass_kraken': 'sfx/turn_pass_kraken.wav',
    'turn_pass_sunfire': 'sfx/turn_pass_sunfire.wav',
    'turn_pass_void': 'sfx/turn_pass_void.wav',
    'turn_pass_classic': 'sfx/turn_pass_classic.wav',
    'turn_pass_arctic': 'sfx/turn_pass_arctic.wav',
    'turn_pass_f_arctic': 'sfx/turn_pass_f_arctic.wav',
    'turn_pass_deep': 'sfx/turn_pass_deep.wav',
    'turn_pass_sunset': 'sfx/turn_pass_sunset.wav',
    'turn_pass_pirate': 'sfx/turn_pass_pirate.wav',
    'turn_pass_f_pirate': 'sfx/turn_pass_f_pirate.wav',
    'turn_pass_naval': 'sfx/turn_pass_naval.wav',
    'turn_pass_f_naval': 'sfx/turn_pass_f_naval.wav',
    'turn_pass_steam': 'sfx/turn_pass_steam.wav',
    'turn_pass_f_steam': 'sfx/turn_pass_f_steam.wav',
    'turn_pass_volcanic': 'sfx/turn_pass_volcanic.wav',
    'turn_pass_f_volcanic': 'sfx/turn_pass_f_volcanic.wav',
    'turn_pass_scifi': 'sfx/turn_pass_scifi.wav',
    'turn_pass_f_scifi': 'sfx/turn_pass_f_scifi.wav',
    // Sunk (ship destroyed) variants — one per ship skin, legacy and
    // family alike. The destroyed hull's own skin picks it (see
    // `SoundService.sunk`).
    'sunk_steel': 'sfx/sunk_steel.wav',
    'sunk_crimson': 'sfx/sunk_crimson.wav',
    'sunk_emerald': 'sfx/sunk_emerald.wav',
    'sunk_gold': 'sfx/sunk_gold.wav',
    'sunk_abyss': 'sfx/sunk_abyss.wav',
    'sunk_arctic': 'sfx/sunk_arctic.wav',
    'sunk_coral': 'sfx/sunk_coral.wav',
    'sunk_midnight': 'sfx/sunk_midnight.wav',
    'sunk_toxic': 'sfx/sunk_toxic.wav',
    'sunk_f_pirate': 'sfx/sunk_f_pirate.wav',
    'sunk_f_naval': 'sfx/sunk_f_naval.wav',
    'sunk_f_arctic': 'sfx/sunk_f_arctic.wav',
    'sunk_f_steam': 'sfx/sunk_f_steam.wav',
    'sunk_f_volcanic': 'sfx/sunk_f_volcanic.wav',
    'sunk_f_scifi': 'sfx/sunk_f_scifi.wav',
    // Place (ship set down) variants — one per ship skin, played on the
    // deploy screen whenever a ship is placed, moved or rotated.
    'place_steel': 'sfx/place_steel.wav',
    'place_crimson': 'sfx/place_crimson.wav',
    'place_emerald': 'sfx/place_emerald.wav',
    'place_gold': 'sfx/place_gold.wav',
    'place_abyss': 'sfx/place_abyss.wav',
    'place_arctic': 'sfx/place_arctic.wav',
    'place_coral': 'sfx/place_coral.wav',
    'place_midnight': 'sfx/place_midnight.wav',
    'place_toxic': 'sfx/place_toxic.wav',
    'place_f_pirate': 'sfx/place_f_pirate.wav',
    'place_f_naval': 'sfx/place_f_naval.wav',
    'place_f_arctic': 'sfx/place_f_arctic.wav',
    'place_f_steam': 'sfx/place_f_steam.wav',
    'place_f_volcanic': 'sfx/place_f_volcanic.wav',
    'place_f_scifi': 'sfx/place_f_scifi.wav',
    // Drag/pickup variants — one per ship skin. The lighter partner to
    // the place sound: plays the moment a ship is picked up on the
    // deploy screen (off the dock, or grabbed on the grid).
    'move': 'sfx/move.wav',
    'move_steel': 'sfx/move_steel.wav',
    'move_crimson': 'sfx/move_crimson.wav',
    'move_emerald': 'sfx/move_emerald.wav',
    'move_gold': 'sfx/move_gold.wav',
    'move_abyss': 'sfx/move_abyss.wav',
    'move_arctic': 'sfx/move_arctic.wav',
    'move_coral': 'sfx/move_coral.wav',
    'move_midnight': 'sfx/move_midnight.wav',
    'move_toxic': 'sfx/move_toxic.wav',
    'move_f_pirate': 'sfx/move_f_pirate.wav',
    'move_f_naval': 'sfx/move_f_naval.wav',
    'move_f_arctic': 'sfx/move_f_arctic.wav',
    'move_f_steam': 'sfx/move_f_steam.wav',
    'move_f_volcanic': 'sfx/move_f_volcanic.wav',
    'move_f_scifi': 'sfx/move_f_scifi.wav',
  };

  /// Core effects warmed up immediately at start.
  static const _corePoolKeys = [
    'cannon_fire',
    'hit',
    'miss',
    'sunk',
    'victory',
    'defeat',
    'place',
    'click',
    'denied',
    'whir',
    'turn_pass',
    'cannon_ready',
    'count_beep',
    'count_go',
  ];

  /// How many players an effect keeps, i.e. how many copies of it can
  /// overlap before one has to be cut short.
  ///
  /// PERF: these were 3 and 2. Every player is a live native `MediaPlayer`
  /// with its own decoder, and a match had ~62 of them alive at once — the
  /// weight behind the frame stalls that appear only while sound is
  /// playing. Two things let the counts come down without costing overlap.
  /// A shot's two clips are DIFFERENT effects (`cannon_fire` then `hit`),
  /// so they never contend for the same pool; and on `mediaPlayer` a
  /// completion event actually arrives, so a player is free again the
  /// moment its clip ends rather than when a timeout says so — a 420ms hit
  /// frees in 420ms, where the old backend held it for 770ms and needed
  /// the third player to cover the gap.
  ///
  /// Two is what genuinely overlapping cases need: both guns firing on
  /// their own reload clocks in BLITZ/CHAOS, a sinking landing on top of a
  /// turn-pass cue.
  static int _poolSizeFor(String key) {
    if (key.startsWith('cannon_fire') ||
        key.startsWith('hit') ||
        key.startsWith('miss') ||
        key.startsWith('cannon_ready') ||
        key.startsWith('sunk')) {
      return 2;
    }
    return 1;
  }

  /// Measured length, in milliseconds, of each effect's `.wav` asset.
  static const Map<String, int> _clipMs = {
    'cannon_fire': 720,
    'hit': 420,
    'miss': 600,
    'sunk': 1350,
    'victory': 1900,
    'defeat': 1300,
    'place': 160,
    'click': 60,
    'denied': 280,
    'whir': 500,
    'turn_pass': 550,
    'cannon_ready': 300,
    'count_beep': 130,
    'count_go': 300,
    // No shared `move.wav` plays on its own, but every `move_<skin>` needs
    // this to resolve a window through [_baseEffectOf].
    'move': 150,
  };

  /// Padding added on top of a clip's measured length.
  static const _safetyMarginMs = 350;
  static const _minSafetyMs = 500;
  static const _fallbackSafetyMs = 2200;

  /// The effect a themed key belongs to — `hit_mk1` → `hit`,
  /// `cannon_fire_f_scifi` → `cannon_fire`, `turn_pass_classic` →
  /// `turn_pass`. Longest match wins, since the base names are not all
  /// one word (`cannon_fire` and `cannon_ready` share a prefix).
  static String? _baseEffectOf(String key) {
    String? best;
    for (final base in _clipMs.keys) {
      if (key != base && !key.startsWith('${base}_')) continue;
      if (best == null || base.length > best.length) best = base;
    }
    return best;
  }

  /// ROOT-CAUSE FIX (fire/hit/miss dropping out during a real match, while
  /// the menu was fine): [_clipMs] is keyed by the BASE effect names only,
  /// and every sound a battle actually plays is a THEMED variant —
  /// `cannon_fire_mk1`, `hit_inferno`, `miss_phantom`. None of those were
  /// in the map, so every one of them fell through to the 2200ms
  /// worst-case fallback instead of its own ~400-800ms clip length.
  ///
  /// That timeout was not cosmetic: under the SoundPool backend this file
  /// used at the time, it was the ONLY thing that ever returned a player
  /// to its pool (see [_ManagedPool.safetyTimeout], where it is now a
  /// backstop). Holding a 720ms cannon shot "busy" for 2.2 seconds means a
  /// 3-player pool sustains barely 1.4 shots a second before it has to
  /// start stealing players from clips that are still audible — and a
  /// steal cuts that clip off. Two guns firing on their own reload timers
  /// in CHAOS/BLITZ, or a hit streak granting extra shots, clears that bar
  /// easily. Traced on a real match: a `cannon_fire_mk1` player was still
  /// marked busy 2.1 seconds after its 720ms clip had finished.
  ///
  /// So the per-effect sizing the timeout was introduced for only ever
  /// applied to the 14 core pools, which are the ones a match barely
  /// touches. Resolving through the base effect gives every variant the
  /// right window; the variants measure within ~15% of their base (`hit`
  /// 420ms vs `hit_inferno` 449ms), comfortably inside the existing
  /// [_safetyMarginMs].
  /// Baked into the pool at creation instead of set per play. Only the
  /// UI click is quieter than full, and a volume that never changes has
  /// no business costing a platform round trip on every shot — see the
  /// note on [_ManagedPool.play].
  static double _volumeFor(String key) => key == 'click' ? 0.9 : 1.0;

  static Duration _safetyTimeoutFor(String key) {
    final base = _baseEffectOf(key);
    final clip = base == null ? null : _clipMs[base];
    if (clip == null) return const Duration(milliseconds: _fallbackSafetyMs);
    return Duration(milliseconds: math.max(_minSafetyMs, clip + _safetyMarginMs));
  }

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

  /// How a pool builds a player. Only ever swapped by tests, which stand a
  /// fake in for the real thing: `AudioPlayer`'s actual playback needs a
  /// platform plugin, and this service's hardest bugs have all been in the
  /// BOOKKEEPING around players (which one is idle, whose it is, whether a
  /// rebuild has retired it) rather than in playback itself — see
  /// [_ManagedPool._owner]. A fake makes exactly that testable.
  @visibleForTesting
  static AudioPlayer Function() playerFactory = AudioPlayer.new;

  /// Every player a pool is currently accounting for, idle or busy.
  /// Tests assert on this: a healthy pool holds exactly its own `size`,
  /// all of them live. Anything else means a checkout filed a player it
  /// should not have.
  @visibleForTesting
  List<AudioPlayer> poolPlayers(String key) => _pools[key]?.players ?? const [];

  /// Drops all pooled state so one test can't inherit another's players.
  /// The click bookkeeping goes with it: [click]'s retrigger guard is wall
  /// -clock based, so without this a test that clicks would silently
  /// suppress the click in whichever test ran within the next 100ms of
  /// real time — which is every one of them.
  @visibleForTesting
  void resetForTesting() {
    _pools.clear();
    _leftForeground = false;
    _rebuildingPool = false;
    _lastClickAt = -1000;
    _clickPending = false;
  }

  /// [_play], awaitable. The effect methods are all fire-and-forget, which
  /// is right for callers and useless for a test that needs to know when
  /// the play has actually finished dispatching.
  @visibleForTesting
  Future<void> playForTesting(String key) => _play(key);

  /// Whether an effect file is registered under exactly [key] — no
  /// fallback. Tests use it to assert that every catalogue id brings its
  /// OWN sound rather than quietly landing on the generic one.
  @visibleForTesting
  static bool hasVariantForTesting(String key) => _files.containsKey(key);

  /// How long a play of [key] holds its player. See [_safetyTimeoutFor] —
  /// on Android this is the only thing that ever frees one, so getting it
  /// wrong for the keys a match actually plays starves those pools.
  @visibleForTesting
  static Duration safetyTimeoutForTesting(String key) =>
      _safetyTimeoutFor(key);

  static const _menuMusicAsset = 'sfx/menu_music.wav';
  AudioPlayer? _menuMusicPlayer;
  bool _menuMusicWanted = false;

  /// Pre-create core warm player pools. Safe to call fire-and-forget from main().
  Future<void> init() async {
    try {
      await AudioPlayer.global.setAudioContext(_sfxAudioContext);
    } catch (_) {/* best effort */}
    await _buildCorePools();
  }

  Future<void> _buildCorePools() async {
    for (final key in _corePoolKeys) {
      final file = _files[key];
      if (file == null) continue;
      final pool = _pools.putIfAbsent(
        key,
        () => _ManagedPool(
          asset: file,
          size: _poolSizeFor(key),
          audioContext: _sfxAudioContext,
          safetyTimeout: _safetyTimeoutFor(key),
          volume: _volumeFor(key),
        ),
      );
      await pool.warmUp();
    }
  }

  _ManagedPool? _getPool(String key) {
    var pool = _pools[key];
    if (pool != null) return pool;
    final file = _files[key];
    if (file == null) return null;
    pool = _ManagedPool(
      asset: file,
      size: _poolSizeFor(key),
      audioContext: _sfxAudioContext,
      safetyTimeout: _safetyTimeoutFor(key),
      volume: _volumeFor(key),
    );
    _pools[key] = pool;
    // NOTE: deliberately NOT `unawaited(pool.warmUp())` here any more —
    // see `_play`, which now `await`s `ensureWarm()` instead. A
    // fire-and-forget warmup meant the very first play of a themed
    // effect (any purchased cannon/ship/deck) raced its own pool build:
    // `play()` found an empty pool and fell through to the expensive
    // mid-gameplay `_create()` path the pool design exists to avoid —
    // and on Windows, where `setSource` is loaded asynchronously on a
    // native thread, that race could make the sound come up SILENT.
    // That is why themed effects "didn't play consistently on different
    // skins" on both phone and Windows builds while the base effects
    // (pre-warmed in `init`) always did.
    return pool;
  }

  /// Pre-warms every themed pool a captain's loadout can ask for — the
  /// cannon's fire/reload/hit/miss, the ship skin's hit/sunk, and the
  /// deck's miss/turn-pass — so the FIRST shot, hit, miss, reload,
  /// sinking or ship move with a purchased skin never has to build its
  /// players on the gameplay hot path. Called for the equipped profile at
  /// app start (see `main.dart`), for both captains' loadouts the moment
  /// a battle screen opens, and for the seat's loadout on the deploy
  /// screen — all well before the first sound can be requested.
  void warmLoadout({
    required String cannonSkinId,
    required String shipSkinId,
    required String themeId,
  }) {
    final keys = <String>{
      'cannon_fire_$cannonSkinId',
      'cannon_ready_$cannonSkinId',
      'hit_$cannonSkinId',
      'miss_$cannonSkinId',
      'miss_$themeId',
      'turn_pass_$themeId',
      'hit_$shipSkinId',
      'sunk_$shipSkinId',
      'place_$shipSkinId',
      'move_$shipSkinId',
    };
    _warmSkinKeys(keys);
  }

  void _warmSkinKeys(Iterable<String> keys) {
    for (final key in keys) {
      final file = _files[key];
      if (file == null) continue;
      final pool = _pools.putIfAbsent(
        key,
        () => _ManagedPool(
          asset: file,
          size: _poolSizeFor(key),
          audioContext: _sfxAudioContext,
          safetyTimeout: _safetyTimeoutFor(key),
          volume: _volumeFor(key),
        ),
      );
      unawaited(pool.ensureFresh());
    }
  }

  /// BUGFIX (all sound effects going silent mid-game on phones): nothing
  /// in the app previously observed `AppLifecycleState`, so SoundService
  /// never knew when it left or returned to the foreground. On Android,
  /// backgrounding the app (locking the screen, taking a call, swiping to
  /// another app, even just pulling down the notification shade) can make
  /// the OS reclaim the native media session behind the pooled players to
  /// free resources; iOS deactivates the shared
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
      // PERF + FEEDBACK, in three passes, because the first two fixed the
      // shape of the problem but not the problem:
      //
      //  1. This rebuilt every pool in turn, fully awaiting one before
      //     starting the next. Each pool's own dispose/warmUp is already
      //     a chain of sequential platform-channel round trips, and a
      //     match underway has ~29 pooled players across every skin
      //     equipped this session, so a resume became one long serialized
      //     queue of platform calls — "lags for a bit, then it's fine".
      //     Batching them concurrently cut the wall-clock time a lot.
      //  2. All those replies still land on this same UI isolate, in the
      //     same window as the first frame the player sees on return, so
      //     that frame paid for them. Waiting for `endOfFrame` first kept
      //     the batch off the one frame where the cost is visible.
      //  3. Neither helped the other half of the report — audio silent
      //     for a beat or two after coming back — because `rebuild()`
      //     disposes before it warms, so EVERY pool was empty for the
      //     whole length of the batch and anything fired in that window
      //     had to wait the queue out before it could make a sound.
      //
      // Nothing is torn down here at all now. Every pool is only FLAGGED
      // stale, and [_ManagedPool.ensureFresh] — which every play already
      // goes through — rebuilds a pool the first time it is actually used
      // after a resume. The first shot back therefore waits on its own
      // pool alone (three players, a few ms) rather than on thirty. It is
      // still safe: the whole reason for rebuilding is that the OS may
      // have reclaimed a pool's native samples while the app was away,
      // and that only matters at the moment that pool next plays — which
      // is exactly when the refresh now happens.
      //
      //  4. A background pass was then added to walk the REST of the pools
      //     anyway, so later effects wouldn't each pay their own first-use
      //     rebuild — one pool per frame, `endOfFrame` between each. That
      //     quietly undid pass 3. A match has ~30 pools holding ~70
      //     players, and a rebuild is 5 platform round trips per player
      //     (one dispose, four to build its replacement), so every resume
      //     still queued ~350 of them; spreading that over 30-odd frames
      //     makes it a third of a second of dribbling channel traffic
      //     instead of one stall, but it is the same work, and it lands
      //     exactly while the player is looking at the screen again. That
      //     is the resume lag, back in a shape that is harder to see.
      //
      // The background pass is gone. Nothing is rebuilt on resume at all;
      // pools are only FLAGGED, and [_ManagedPool.ensureFresh] — which
      // every play already goes through — rebuilds a pool the first time
      // it is actually used. A resume now costs nothing, and the first
      // shot back waits on its own pool alone: three players, a handful of
      // platform calls, off the frame-critical path because it is a sound
      // being dispatched rather than a frame being built. Most pools are
      // never touched again on the screen the player returns to, so most
      // of that ~350-call bill is simply never incurred.
      //
      // It stays safe for the same reason as before: the point of a
      // rebuild is that the OS may have reclaimed a pool's native samples
      // while the app was away, and that only matters at the moment that
      // pool next plays — which is exactly when the refresh happens.
      //
      // FEEDBACK ("effects sometimes play and sometimes disappear"): the
      // deferred pass was also making that far worse, and dropping it is
      // half of that fix too. Every pool it walked was a pool being torn
      // down underneath whatever the player happened to be doing, and a
      // teardown that lands on a live checkout used to poison the rebuilt
      // pool with a stale player — see [_ManagedPool._owner], which is the
      // other half.
      //
      // Nothing invalidates on a transient `inactive` any more either (a
      // permission dialog, a peek at the notification shade, the start of
      // a recents gesture): the app never left, so its audio is fine, and
      // treating those as a backgrounding meant rebuilding every pool in
      // the app for an interruption the player may not even have noticed.
      // See [onAppPaused].
      if (_leftForeground) {
        _leftForeground = false;
        for (final pool in _pools.values) {
          pool.markStale();
        }
      }
      await SchedulerBinding.instance.endOfFrame;
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

  /// Whether the app genuinely left the foreground since the last resume —
  /// set only by a `paused`/`hidden`/`detached` transition, never by a
  /// bare `inactive`. See [onAppPaused] and [onAppResumed].
  bool _leftForeground = false;

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
  ///
  /// [leftForeground] separates the two very different things this one
  /// method is called for. `paused`/`hidden`/`detached` mean the app
  /// really is gone, which is what puts its pooled players at risk and so
  /// arms the invalidation in [onAppResumed]. A bare `inactive` does not:
  /// it fires for a permission dialog, a peek at the notification shade,
  /// the beginning of a recents swipe — the app is still there, its audio
  /// is still fine, and it is usually `resumed` again a moment later.
  /// Treating those as a backgrounding meant every such blip invalidated
  /// every pool in the app. Music still pauses either way, since that is
  /// about what the player can hear, not about what the OS reclaimed.
  void onAppPaused({bool leftForeground = true}) {
    if (leftForeground) _leftForeground = true;
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

  /// [key] is an effect name from [_files]. Volume is NOT a parameter: it
  /// belongs to the effect, not the call, and is baked into the pool's
  /// players when they are built (see [_ManagedPool.volume]) so an
  /// ordinary play costs one platform call instead of two.
  Future<void> _play(String key) async {
    // A specific cue supersedes the generic UI click raised by the same
    // gesture — see [click]. Must stay the first thing this method does:
    // it has to run synchronously, before the first `await` below hands
    // control back and lets the click's microtask through.
    if (key != 'click') _clickPending = false;
    if (!enabled) return;
    final pool = _getPool(key);
    if (pool == null) return;
    // A lazily-created pool (any themed variant) is guaranteed fully
    // built before its first play — see the note on `_getPool` for the
    // race this closes. `ensureWarm` caches its future, so concurrent
    // first-plays share one warmup and later plays await nothing.
    await pool.ensureFresh();
    await pool.play();
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

  bool _hasSound(String key) => _files.containsKey(key);

  void cannonFire({String? cannonSkinId}) {
    HapticFeedback.mediumImpact();
    if (cannonSkinId != null) {
      final k1 = 'cannon_fire_$cannonSkinId';
      if (_hasSound(k1)) {
        _play(k1);
        return;
      }
      final clean = cannonSkinId.replaceFirst('f_', '');
      final k2 = 'cannon_fire_$clean';
      if (_hasSound(k2)) {
        _play(k2);
        return;
      }
    }
    _play('cannon_fire');
  }

  void hit({String? cannonSkinId, String? shipSkinId}) {
    HapticFeedback.heavyImpact();
    if (cannonSkinId != null) {
      final k1 = 'hit_$cannonSkinId';
      if (_hasSound(k1)) {
        _play(k1);
        return;
      }
      final clean = cannonSkinId.replaceFirst('f_', '');
      final k2 = 'hit_$clean';
      if (_hasSound(k2)) {
        _play(k2);
        return;
      }
    }
    if (shipSkinId != null) {
      final k1 = 'hit_$shipSkinId';
      if (_hasSound(k1)) {
        _play(k1);
        return;
      }
      final clean = shipSkinId.replaceFirst('f_', '');
      final k2 = 'hit_$clean';
      if (_hasSound(k2)) {
        _play(k2);
        return;
      }
    }
    _play('hit');
  }

  /// FEEDBACK ("I use an MK-I cannon but the miss still registers as the
  /// opponent's lava theme"): the shooter's gun is asked FIRST now, and the
  /// target's board only as a fallback. This used to be the other way
  /// round, so a shot landing on any themed battlefield took that board's
  /// splash no matter what fired it — the audible half of the same bug the
  /// hit/miss MARKS had (see `_StaticGridPainter.paint`), and inconsistent
  /// with [hit] and [cannonFire], which have always been keyed to the gun.
  ///
  /// No sound becomes unreachable by the swap: a legacy board's id IS its
  /// matching legacy cannon's id, and a family board's id is its family
  /// cannon's, so the same fifteen files are still in play — they now
  /// follow the shell rather than the water it lands in.
  void miss({String? themeId, String? cannonSkinId}) {
    HapticFeedback.lightImpact();
    _play(_missKey(themeId: themeId, cannonSkinId: cannonSkinId));
  }

  /// The file a miss resolves to: the shooter's gun, else the target's
  /// board, else the shared splash. Split out so it is the one definition
  /// of that order — see [missKeyForTesting].
  String _missKey({String? themeId, String? cannonSkinId}) =>
      _variantKey('miss', cannonSkinId) ??
      _variantKey('miss', themeId) ??
      'miss';

  /// `<base>_<id>` if that exists, else `<base>_<id without its `f_`>`,
  /// else null — the same two-step every effect uses to fall from a themed
  /// variant back towards the shared one.
  String? _variantKey(String base, String? id) {
    if (id == null) return null;
    if (_hasSound('${base}_$id')) return '${base}_$id';
    final clean = id.replaceFirst('f_', '');
    return _hasSound('${base}_$clean') ? '${base}_$clean' : null;
  }

  @visibleForTesting
  static String missKeyForTesting({String? themeId, String? cannonSkinId}) =>
      instance._missKey(themeId: themeId, cannonSkinId: cannonSkinId);

  void sunk({String? shipSkinId}) {
    HapticFeedback.heavyImpact();
    if (shipSkinId != null) {
      final k1 = 'sunk_$shipSkinId';
      if (_hasSound(k1)) {
        _play(k1);
        return;
      }
      final clean = shipSkinId.replaceFirst('f_', '');
      final k2 = 'sunk_$clean';
      if (_hasSound(k2)) {
        _play(k2);
        return;
      }
    }
    _play('sunk');
  }

  void victory() {
    HapticFeedback.heavyImpact();
    _play('victory');
  }

  void defeat() {
    _play('defeat');
  }

  /// A ship set down on the deploy grid — placing from the dock, dragging
  /// a placed hull to new water, or rotating. Each equipped ship skin has
  /// its own set-down sound (see `tool/gen_sounds.dart`), falling back to
  /// the shared one for skins without a variant.
  void place({String? shipSkinId}) {
    if (shipSkinId != null) {
      final k1 = 'place_$shipSkinId';
      if (_hasSound(k1)) {
        _play(k1);
        return;
      }
      final clean = shipSkinId.replaceFirst('f_', '');
      final k2 = 'place_$clean';
      if (_hasSound(k2)) {
        _play(k2);
        return;
      }
    }
    _play('place');
  }

  /// The lighter partner to [place]: the tick that plays the moment a
  /// ship is PICKED UP on the deploy screen — grabbed off the dock tray,
  /// or seized on the grid to be dragged — keyed by that ship's skin so
  /// every fleet moves to its own sound.
  void shipMove({String? shipSkinId}) {
    if (shipSkinId != null) {
      final k1 = 'move_$shipSkinId';
      if (_hasSound(k1)) {
        _play(k1);
        return;
      }
      final clean = shipSkinId.replaceFirst('f_', '');
      final k2 = 'move_$clean';
      if (_hasSound(k2)) {
        _play(k2);
        return;
      }
    }
    _play('move');
  }

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
  ///
  /// FEEDBACK ("the button audio plays twice on the deploy screen too").
  /// The guard above only ever de-duplicated a click against ANOTHER
  /// click, and that is not the only way one press makes two sounds. Some
  /// buttons raise a cue of their own in the handler [NeonButton] invokes
  /// — measured on the device, RANDOM fires `click` and `whir` in the SAME
  /// millisecond, and SAVE fires `click` and the deployment fanfare — so
  /// the press lands as two overlapping effects where every other button
  /// in the app makes exactly one.
  ///
  /// So the generic click now yields to a specific one. It is deferred by
  /// a single microtask, which runs only once the whole tap handler has
  /// finished: any effect the handler raised on the way past cancels it
  /// (see the head of [_play]), and a button that raises nothing still
  /// clicks, a fraction of a millisecond later and inside the same frame.
  /// Deliberately microtask-scoped rather than timed: it can only ever be
  /// superseded from inside the same gesture, never by an effect that
  /// happens to arrive from a timer or the network at the wrong moment.
  void click() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastClickAt < 100) return;
    _lastClickAt = now;
    _clickPending = true;
    scheduleMicrotask(() {
      if (!_clickPending) return;
      _clickPending = false;
      _play('click');
    });
  }

  /// A [click] waiting out its microtask — see there. Cleared either by
  /// the click playing or by a more specific effect superseding it.
  bool _clickPending = false;

  int _lastClickAt = -1000;

  void denied() => _play('denied');

  /// Screen/turn transition whoosh.
  void whir() => _play('whir');

  /// Distinct "turn passed to the other player" cue — plays alongside
  /// [whir] at handoff so a turn change is unmistakable even with sound
  /// as the only cue (e.g. eyes on the board, not the turn badge).
  void turnPass({String? themeId}) {
    if (themeId != null) {
      final k1 = 'turn_pass_$themeId';
      if (_hasSound(k1)) {
        _play(k1);
        return;
      }
      final clean = themeId.replaceFirst('f_', '');
      final k2 = 'turn_pass_$clean';
      if (_hasSound(k2)) {
        _play(k2);
        return;
      }
    }
    _play('turn_pass');
  }

  /// Mechanical "locked in" clunk — synced to the cannon's ready-flash,
  /// right as it settles into the middle of its grid.
  void cannonReady({String? cannonSkinId}) {
    if (cannonSkinId != null) {
      final k1 = 'cannon_ready_$cannonSkinId';
      if (_hasSound(k1)) {
        _play(k1);
        return;
      }
      final clean = cannonSkinId.replaceFirst('f_', '');
      final k2 = 'cannon_ready_$clean';
      if (_hasSound(k2)) {
        _play(k2);
        return;
      }
    }
    _play('cannon_ready');
  }

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
    required this.safetyTimeout,
    required this.volume,
  });

  final String asset;
  final int size;
  final AudioContext audioContext;

  /// This effect's playback volume, applied once when a player is built.
  final double volume;

  /// Players known to be sitting at position zero, so the next play can
  /// skip rewinding them.
  ///
  /// PERF: `play()` issues platform calls whose native side runs on
  /// Android's main thread, and that is what makes frames stutter while
  /// sound is playing. A clip that ends on its own needs no rewind from
  /// us: `WrappedPlayer.onCompletion` already calls `stop()` natively,
  /// which under `ReleaseMode.stop` is pause-and-seek-to-zero. So a player
  /// handed back by its own completion event is ready to go, and only one
  /// that was cut short — stolen mid-clip, or freed by the safety timer
  /// without a completion — still has to be rewound.
  final Set<AudioPlayer> _rewound = {};

  final List<AudioPlayer> _idle = [];
  final Map<AudioPlayer, void Function()> _busy = {};

  /// Which checkout currently owns each busy player, and which teardown
  /// era the pool is in. Both exist to answer the same question from two
  /// directions — "is the player I am holding still mine to give back?" —
  /// because a checkout is a long-lived chain of awaits and BOTH of the
  /// things it holds across those awaits can be taken from it mid-flight.
  ///
  /// ROOT-CAUSE FIX (effects playing "sometimes, and sometimes not at
  /// all", persisting until the app is restarted). `release()` used to
  /// return its player to [_idle] unconditionally, no matter what had
  /// happened to the pool in the meantime. Two ways that poisons a pool
  /// for the rest of the session:
  ///
  ///  1. **A rebuild underneath a live checkout.** [dispose] tears down
  ///     exactly the players it can see — `_idle` plus `_busy.keys` — but
  ///     a checkout between "took the player out of `_idle`" and "put it
  ///     into `_busy`" is in NEITHER, so its player survives a rebuild the
  ///     whole point of which is that the old players can no longer be
  ///     trusted (the OS may have reclaimed their native samples). Its
  ///     `release()` — or its safety timer, up to a clip-length later —
  ///     then filed that stale player into the freshly rebuilt `_idle`,
  ///     where it sat as a permanently silent slot, handed out to roughly
  ///     one play in `size` forever after. A checkout that IS in `_busy`
  ///     when the rebuild lands hits the same ending by the other road:
  ///     its player gets genuinely disposed, its next platform call
  ///     throws, and the catch-all calls `release()` — filing a DISPOSED
  ///     player into the new pool. Either way: "sometimes it plays,
  ///     sometimes nothing", getting worse with each resume that happens
  ///     to collide with a sound.
  ///  2. **A steal underneath a live checkout.** The steal path detaches
  ///     the old checkout's listeners so they can't hand the player back,
  ///     but it can't unwind that checkout's own in-flight `play()` body:
  ///     if one of its platform calls throws after the steal, its catch
  ///     block still calls `release()`, filing into `_idle` a player the
  ///     NEW checkout is at that moment playing out loud. A third play
  ///     then checks that same player out of `_idle` and `stop()`s it —
  ///     cutting off a clip that had only just started.
  ///
  /// So a checkout now records the era it began in and takes a token
  /// proving ownership of its player, and `release()` verifies both before
  /// touching the pool's books. A checkout that has been superseded either
  /// way retires quietly instead of filing a player it no longer owns.
  int _generation = 0;
  final Map<AudioPlayer, Object> _owner = {};

  List<AudioPlayer> get players => [..._idle, ..._busy.keys];

  /// How long a checked-out player is considered busy before it's forced
  /// back into the idle pool.
  ///
  /// A backstop, not the primary mechanism. It used to be the latter:
  /// under `PlayerMode.lowLatency` Android's SoundPool has no completion
  /// callback at all, so `onPlayerComplete` never fired and this timer was
  /// the only thing that ever returned a player. On `mediaPlayer` (see
  /// [_create] for why the mode changed) completion events do arrive, so
  /// the listener below is what normally frees a player and this only has
  /// to cover a clip that was interrupted without reporting it.
  ///
  /// It still needs to be sized per effect rather than left at the
  /// worst-case fallback — a backstop that fires far too late still pins a
  /// player for seconds if its event is ever missed.
  ///
  /// ROOT-CAUSE FIX (audio still inconsistent — cut off / silent —
  /// specifically during fast-paced gameplay, even after the pooling and
  /// audio-focus fixes above): this used to be ONE flat value
  /// (2200ms) shared by every effect, sized to comfortably outlast the
  /// LONGEST clip (`victory`, ~1.9s). That safely covered `victory`, but it
  /// meant every SHORT, frequently-fired gameplay effect — `cannon_fire`
  /// (~0.72s), `hit` (~0.42s), `miss` (~0.6s) — held its player "busy" for
  /// up to 3-5x its own actual audible length. A HIT grants an immediate
  /// extra shot, so a hit streak (or multiple simultaneous shooters in
  /// LAN/BLITZ chaos mode) routinely fires a pool's fixed handful of
  /// players faster than that inflated busy-window could ever free them,
  /// forcing the steal-the-oldest fallback to trigger far more often than
  /// the pool's actual concurrent-overlap headroom should ever require.
  /// Every extra steal is an extra opportunity for two independent `play()`
  /// calls to end up touching the exact same physical player around the
  /// same time (see the ROOT-CAUSE FIX note on [play] for that race and
  /// its fix) — so shrinking how often stealing happens at all, not just
  /// making a steal itself safe, is part of the fix. Sizing this per
  /// effect (see [SoundService._safetyTimeoutFor]) — that effect's actual
  /// clip length plus a fixed margin, instead of one ceiling sized for the
  /// longest outlier — lets short effects recycle back to idle 2-4x
  /// faster, so a normal hit streak comfortably stays within a pool's
  /// warm supply instead of routinely exhausting it.
  final Duration safetyTimeout;

  /// Per-player "is a previous checkout still mid-flight on this exact
  /// physical player" gate — see the ROOT-CAUSE FIX note on [play].
  final Map<AudioPlayer, Future<void>> _setupDone = {};

  /// Creates every player this pool will ever hold. Called once from
  /// [SoundService.init] (fire-and-forget, well before any gameplay
  /// input) and again by [rebuild] after the app resumes from the
  /// background — never from the gameplay hot path in [play].
  Future<void> warmUp() async {
    if (_idle.isNotEmpty || _busy.isNotEmpty) return; // already built
    // PERF (resume-from-background lag): this used to create the pool's
    // players ONE AT A TIME, `await`-ing each `_create()` fully before
    // starting the next — and `_create()` is itself four sequential
    // awaited platform-channel round trips (see its own doc). Called for
    // every pool in turn from `SoundService.onAppResumed`, that serialized
    // the whole app-resume rebuild into one long chain of platform calls.
    // None of these creations depend on each other, so firing them all at
    // once and awaiting the batch lets the platform channel pipeline them
    // concurrently — the actual fix for the wall-clock stall, rather than
    // just moving it around.
    final created = await Future.wait(
      List.generate(size, (_) => _tryCreate()),
    );
    _idle.addAll(created.whereType<AudioPlayer>());
  }

  /// [_create], but best-effort: a missing slot just means slightly less
  /// overlap headroom for this one effect, same as the old sequential
  /// warmUp's per-iteration try/catch — kept as its own method so
  /// [warmUp] can fire every slot's creation at once via [Future.wait]
  /// without one failed slot cancelling the whole batch.
  Future<AudioPlayer?> _tryCreate() async {
    try {
      return await _create();
    } catch (_) {
      return null;
    }
  }

  /// The warmup this pool is currently running (or has run), so a play
  /// arriving before the pool is built can WAIT for it instead of racing
  /// it. See the note on [SoundService._getPool]: a fire-and-forget
  /// warmup let a themed effect's very first play slip past the empty
  /// pool into the mid-gameplay `_create()` path — and on Windows, where
  /// `setSource` completes asynchronously on a native thread, that race
  /// could silence the clip entirely. Awaiting this makes the first play
  /// of any themed effect deterministic: it fires once the pool is ready
  /// (normally well before gameplay, via [SoundService.warmLoadout]).
  Future<void>? _warm;

  Future<void> ensureWarm() {
    final existing = _warm;
    if (existing != null) return existing;
    final f = warmUp();
    _warm = f;
    return f;
  }

  /// Set by [markStale] when the app comes back from the background, and
  /// cleared by the [ensureFresh] that acts on it. See
  /// [SoundService.onAppResumed]: the OS may have reclaimed the native
  /// samples behind this pool's players while the app was away, and the
  /// Dart-side objects give no sign of it — they keep reporting a normal
  /// idle state and keep playing nothing at all. The flag is how a pool
  /// remembers that it must be rebuilt before it can be trusted again,
  /// without every pool having to be rebuilt up front.
  bool _stale = false;
  Future<void>? _refresh;

  /// Bumped by every [markStale]. A refresh records the value it started
  /// at and only clears [_stale] if that value is still current — so an
  /// app backgrounded and resumed AGAIN while a refresh was in flight
  /// leaves the pool stale, and the next use rebuilds it once more,
  /// rather than trusting players that may have been created before the
  /// second trip to the background.
  int _staleGeneration = 0;

  void markStale() {
    _stale = true;
    _staleGeneration++;
  }

  /// [ensureWarm], plus the post-resume rebuild if one is owed. This is
  /// what every play goes through, so a pool is always rebuilt before its
  /// first use after a resume — but only that one pool, and only if it is
  /// actually used. Concurrent callers (a play and the background pass,
  /// or two plays at once) share the single in-flight rebuild.
  Future<void> ensureFresh() {
    if (!_stale) return ensureWarm();
    final existing = _refresh;
    if (existing != null) return existing;
    // Published before the first await so a second caller landing in the
    // same microtask joins `_refresh` instead of starting its own.
    final claimed = _staleGeneration;
    final completer = Completer<void>();
    _refresh = completer.future;
    rebuild().catchError((Object _) {}).whenComplete(() {
      if (_staleGeneration == claimed) _stale = false;
      _refresh = null;
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  Future<AudioPlayer> _create() async {
    final p = SoundService.playerFactory();
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
    // ROOT-CAUSE FIX (effects "not playing consistently" — the one every
    // round of pool fixes above was actually chasing). This was
    // `PlayerMode.lowLatency`, which on Android is `SoundPool`, and
    // SoundPool was silently dropping most of what it was asked to play.
    //
    // Measured on a real device over one scripted CHAOS match, counting
    // requests in Dart against `addTrack_l` in AudioFlinger — i.e. sounds
    // asked for, versus sounds that actually reached the audio hardware:
    //
    //     lowLatency (SoundPool)   73 requested → 27 audible  (37%)
    //     mediaPlayer              73 requested → 71 audible  (97%)
    //
    // Nothing upstream could see it. `SoundPool.play()` returns a stream id
    // and 0 on failure; the plugin stores that id without checking it, and
    // the Dart-side state flag is set from the call returning, not from a
    // stream actually starting. So every one of those 73 plays reported
    // `PlayerState.playing` — which is why the traces kept coming back
    // clean while the game kept sounding broken, and why each earlier fix
    // (pool bookkeeping, busy windows, missing variants) was real but only
    // ever moved the remaining third around.
    //
    // The trade is a few ms of extra start latency — measured at 14-24ms
    // from request to dispatch, against SoundPool's ~4ms — which is
    // inaudible against a shot that has a visible animation, and a heavier
    // native object per player. In-battle CPU was unchanged at ~95% of a
    // core. Getting the sound out is worth both.
    await p.setVolume(volume);
    await p.setPlayerMode(PlayerMode.mediaPlayer);
    await p.setReleaseMode(ReleaseMode.stop);
    _rewound.add(p);
    return p;
  }

  Future<void> play() async {
    final generation = _generation;
    AudioPlayer player;
    try {
      if (_idle.isNotEmpty) {
        player = _idle.removeLast();
      } else if (_busy.isNotEmpty) {
        // Every one of this pool's fixed players is genuinely busy at
        // once — reuse the oldest. Detach it from its OLD checkout
        // directly (just unsubscribing/cancelling that checkout's own
        // listeners) rather than through that checkout's normal
        // completion path, which would incorrectly hand it straight back
        // to the idle pool at the same moment we're about to reuse it
        // right here — i.e. a player briefly sitting in both `_idle` and
        // `_busy` at once, which a concurrent play() call could then also
        // check out. That's exactly the "reuse while still playing" race
        // this whole pool exists to prevent.
        //
        // Deliberately NOT `_create()`-ing a fresh player here even
        // though one used to be an option — see the class doc: doing
        // that mid-gameplay is exactly what caused the real-device
        // regression this pool now avoids.
        final oldest = _busy.keys.first;
        _busy.remove(oldest)?.call();
        // Ownership passes to this checkout here, so the stolen-from
        // checkout's own `release()` (which its in-flight body can still
        // reach via its catch-all) no longer files this player anywhere —
        // see case 2 on [_owner].
        _owner.remove(oldest);
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

    // ROOT-CAUSE FIX (audio randomly cut off or silent, worse the faster
    // shots come in — hit streaks, multiple LAN/BLITZ shooters): cancelling
    // the OLD checkout's listeners above (so ITS timer/onPlayerComplete
    // can't fire `release()` on a player we're about to reuse) stops that
    // OLD checkout from *finishing* on this player behind our back, but it
    // does NOT stop that OLD checkout's own `play()` call from *still being
    // mid-flight* right here — it may be sitting on an unfinished `await
    // player.resume()` (or `stop()`/`setVolume()`/`setPlaybackRate()`) at
    // the exact moment we steal it. Once that old, unrelated await finally
    // gets its platform-channel response, that OLD call resumes running
    // and dispatches ITS next step on this SAME physical player — now
    // WHILE we're independently configuring and playing it for a
    // completely different shot. Two calls issuing `stop`/`resume`
    // out of order on one player is exactly "sometimes cut off, sometimes
    // silent": whichever call's `resume()` lands on the native side last
    // wins, and a trailing `stop()` from the other can silence a clip the
    // instant after it started.
    //
    // Fixed by giving every player a "setup in flight" gate: before this
    // checkout issues a single platform call, it waits for whatever the
    // PREVIOUS checkout of this exact player was still doing to fully
    // finish (normally an imperceptible few ms — this only ever waits on
    // genuine in-flight work, never on the OLD checkout's full audible
    // clip). That serializes every checkout of a given player, so only
    // one `play()` call is EVER mid-dispatch on it at a time, whether the
    // player came from `_idle` or was just stolen above.
    final previousSetup = _setupDone[player];
    if (previousSetup != null) {
      try {
        await previousSetup;
      } catch (_) {/* we only care that it's finished, not how */}
    }
    // The pool can have been torn down and rebuilt while this checkout sat
    // on the gate above (or on the `_idle`/steal bookkeeping before it) —
    // see case 1 on [_owner]. The player in hand belongs to the previous
    // era either way, so retire it here rather than let it into the books
    // of the pool that replaced it. Disposing is best-effort: in the
    // `_busy` half of the race [dispose] already got to it.
    if (generation != _generation) {
      unawaited(player.dispose().catchError((_) {}));
      return;
    }

    final setupCompleter = Completer<void>();
    _setupDone[player] = setupCompleter.future;

    final token = Object();
    _owner[player] = token;

    late final StreamSubscription<void> sub;
    late final Timer safety;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      safety.cancel();
      sub.cancel();
      // Superseded — by a rebuild, or by a steal — so this player is no
      // longer ours to file. See [_owner] for both cases.
      if (generation != _generation) {
        unawaited(player.dispose().catchError((_) {}));
        return;
      }
      if (!identical(_owner[player], token)) return;
      _owner.remove(player);
      _busy.remove(player);
      // Always back to idle — this pool never exceeds `size` players, so
      // there's never a "grew past capacity, let this one go" case.
      _idle.add(player);
    }

    sub = player.onPlayerComplete.listen((_) {
      // Native side has already rewound it — see [_rewound].
      _rewound.add(player);
      release();
    });
    safety = Timer(safetyTimeout, release);
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
      // `stop()` fixed BOTH preconditions in one call — it pauses (so
      // `playing` goes false) and seeks to 0, which routed to
      // SoundPoolPlayer.stop() and nulled `streamId`, so the next start()
      // took the `soundPool.play(...)` branch instead of resuming a dead
      // stream.
      //
      // The backend is `mediaPlayer` now (see [_create]) and neither
      // precondition is SoundPool's any more, but the call is still exactly
      // right and still required: `stop()` is pause-and-seek-to-zero under
      // `ReleaseMode.stop`, which is what makes a REUSED player start its
      // clip from the beginning rather than resuming wherever the previous
      // shot left it, and it is what clears `playing` so the guard in
      // `WrappedPlayer.play()` lets the next one through.
      // PERF (animations stuttering while sound plays): every call in here
      // is a platform round trip whose native side runs on Android's main
      // thread, and `MediaPlayer`'s seek/start are not cheap there. Firing
      // a shot used to cost three of them. Measured in a live match, sound
      // ON gave worst-frame spikes of 132ms and 60ms — a shell visibly
      // jumping most of its flight; the identical match with sound MUTED
      // never exceeded 26ms. Volume is the one that had no business being
      // here: it never varies for a given effect (only the UI click is
      // quieter, and it is always 0.9), so it is set once when the player
      // is built — see [_ManagedPool.volume].
      //
      // The rewind goes the same way whenever it is already done for us:
      // a clip that ended on its own was rewound natively by the plugin's
      // own completion handling (see [_rewound]), which is the common case
      // now that completion events actually arrive. Only a player that was
      // cut short still needs this, which leaves the ordinary play a
      // single platform call.
      if (!_rewound.remove(player)) {
        await player.stop();
      }
      // Resuming (rather than re-calling play(source)) reuses the already
      // -prepared native player instead of tearing it down and reloading
      // the asset on every single play.
      await player.resume();
      // FEEDBACK ("the button click plays twice"). There was a
      // `setPlaybackRate` here, applying a ±6% pitch wobble so rapid
      // repeats didn't sound robotic. It had to come AFTER `resume()`,
      // because the SoundPool backend could only set a rate on a stream
      // that had already started — and that ordering became a bug the
      // moment the backend changed.
      //
      // Every step here is a platform round trip, and the whole dispatch
      // measures 14-24ms on a loaded frame. `click.wav` is 60ms. So the
      // rate call could easily land after its own clip had already
      // finished — and Android's `MediaPlayer.setPlaybackParams()` STARTS
      // playback on a player that is not currently started. That is a
      // second click, from one press, hitting the shortest clip in the
      // game first.
      //
      // Setting it before `resume()` is no safer: the same call on a
      // paused player starts it too, which would race the resume. The
      // wobble was cosmetic — the old comment here said as much, insisting
      // a failed rate must never fail the play — so it is simply gone
      // rather than traded for a subtler version of the same hazard.
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SoundService: play failed for $asset ($e)');
      }
      release();
    } finally {
      // Unblock whichever checkout (if any) is already waiting on
      // `previousSetup` for THIS checkout, now that our own dispatch —
      // success or failure — is fully done.
      if (!setupCompleter.isCompleted) setupCompleter.complete();
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
    // ROOT-CAUSE FIX (a handful of extra native players silently piling up
    // — worse the more app-resumes happen): if this pool's very first
    // `ensureWarm()` (from `SoundService.warmLoadout`/`_play`) is STILL
    // in flight when the app is backgrounded and resumed right on top of
    // it — the exact window a themed pool warms in, right as a battle
    // screen mounts — `warmUp()`'s own re-entry guard
    // (`if (_idle.isNotEmpty || _busy.isNotEmpty) return`) does nothing
    // here, because at that moment both lists are still genuinely empty.
    // Without waiting for it, [rebuild] would clear state and start a
    // SECOND `warmUp()` for the same pool while the first is still
    // creating its own [size] players; whichever batch's `_create()`
    // calls land last then appends straight into `_idle` on top of the
    // other, so the pool ends up holding up to `2×size` players instead
    // of `size` — never a "silent" bug on its own, but wasted native
    // objects and platform-channel churn on every such resume. Waiting
    // for any in-flight warmup to land first turns the two calls back
    // into a clean sequence: let it finish, THEN tear down everything it
    // just built, THEN warm up fresh.
    final inFlightWarm = _warm;
    if (inFlightWarm != null) {
      try {
        await inFlightWarm;
      } catch (_) {/* only waiting for it to settle, not how */}
    }
    // Cancel every busy player's own listeners FIRST, so none of them can
    // fire mid- or post-disposal and reinsert a dead player into the pool
    // this method (and the `warmUp()` right after it, via [rebuild]) is
    // about to rebuild clean.
    for (final cancel in _busy.values) {
      cancel();
    }
    // PERF: see the matching note on [warmUp] — disposing every player one
    // at a time serialized this pool's teardown into as many sequential
    // platform-channel round trips as it had players, right before
    // [warmUp]'s own chain runs again via [rebuild]. Firing them together
    // lets the platform channel handle the batch concurrently instead.
    // Opens a new era BEFORE anything is torn down, so any checkout that
    // is mid-flight right now — including one holding a player that is in
    // neither list and so is invisible to the teardown below — sees that
    // it has been superseded and retires its player instead of filing it
    // into the pool this rebuild is about to produce. See [_owner].
    _generation++;
    await Future.wait([
      for (final p in [..._idle, ..._busy.keys]) p.dispose().catchError((_) {}),
    ]);
    _idle.clear();
    _busy.clear();
    _owner.clear();
    _rewound.clear();
    _setupDone.clear();
    // A rebuild's fresh `warmUp()` must be awaited by the next play too —
    // drop the cached future so `ensureWarm` re-runs rather than handing
    // back the pre-rebuild (now meaningless) future.
    _warm = null;
  }

  /// Tears down and recreates every player in this pool — see the bugfix
  /// note on [SoundService.onAppResumed] for why that's necessary after
  /// the app returns from the background.
  Future<void> rebuild() async {
    await dispose();
    // ROOT-CAUSE FIX (an effect staying silent for a beat after a resume,
    // and a pool quietly ending up with `2×size` players): this used to
    // call `warmUp()` directly, which leaves `_warm` null. Between
    // `dispose()` clearing the pool and this warmup finishing, `_idle`
    // and `_busy` are both empty and `_warm` is null — so a `play()`
    // arriving in that window ran `ensureWarm()` → `warmUp()` and sailed
    // straight past `warmUp`'s own re-entry guard (which only checks
    // those two empty lists), starting a SECOND, independent build of
    // the same pool. The shot then waited on that second build rather
    // than the one already in flight, and both batches appended their
    // players to `_idle`. `ensureWarm()` publishes the future instead, so
    // a play landing mid-rebuild joins THIS warmup and fires as soon as
    // it lands. Same fix, same reasoning as `dispose`'s own in-flight
    // wait above, just from the other direction.
    await ensureWarm();
  }
}
