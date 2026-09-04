import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:battleship_blitz/services/sound_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for a real [AudioPlayer]. Playback itself needs a platform
/// plugin, but none of the bugs these tests pin are about playback — they
/// are about the pool's BOOKKEEPING: which player is idle, which checkout
/// owns it, and whether a rebuild has retired it. This models the one
/// behaviour of a real player that those bugs turn on: once disposed, it
/// refuses every call, exactly as the plugin does.
class _FakePlayer extends AudioPlayer {
  bool disposed = false;

  /// Held by [stop] while set, so a test can park a checkout mid-dispatch
  /// and do something to the pool underneath it.
  Completer<void>? stopGate;

  /// Makes the next call fail the way a real platform call intermittently
  /// does, so a test can drive a checkout into its error path.
  bool failNextCall = false;

  final _events = StreamController<void>.broadcast();

  @override
  Stream<void> get onPlayerComplete => _events.stream;

  void _check() {
    if (disposed) throw StateError('player has been disposed');
    if (failNextCall) {
      failNextCall = false;
      throw StateError('platform call failed');
    }
  }

  @override
  set positionUpdater(PositionUpdater? updater) {/* no frame polling here */}

  @override
  Future<void> setAudioContext(AudioContext ctx) async {}

  @override
  Future<void> setSource(Source source) async {}

  @override
  Future<void> setPlayerMode(PlayerMode mode) async {}

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}

  @override
  Future<void> setVolume(double volume) async => _check();

  @override
  Future<void> setPlaybackRate(double rate) async => _check();

  @override
  Future<void> resume() async => _check();

  @override
  Future<void> stop() async {
    final gate = stopGate;
    if (gate != null) await gate.future;
    _check();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  final sound = SoundService.instance;

  setUp(() {
    AudioLogger.logLevel = AudioLogLevel.none;
    SoundService.playerFactory = _FakePlayer.new;
    sound.resetForTesting();
  });

  tearDown(() {
    SoundService.playerFactory = AudioPlayer.new;
    sound.resetForTesting();
  });

  /// `onAppResumed` waits for `endOfFrame` before touching anything, so it
  /// needs a frame pumped under it to complete.
  Future<void> resume(WidgetTester tester) async {
    final done = sound.onAppResumed();
    await tester.pump();
    await done;
  }

  /// Runs out every checkout's safety timer — the only thing that returns
  /// a low-latency player to its pool, since Android's SoundPool has no
  /// completion callback — so assertions see a settled pool.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 3));

  List<_FakePlayer> playersOf(String key) =>
      sound.poolPlayers(key).cast<_FakePlayer>();

  // 'whir' is a one-player pool with no pitch variation — the simplest
  // possible shape for reasoning about who holds what.
  const key = 'whir';

  group('every catalogue id brings its own sound', () {
    // REGRESSION ("the sounds don't play consistently on all the themes").
    // Every miss is picked by the target's gameplay theme and every handoff
    // cue by the current one, so a theme with no file of its own silently
    // lands on the generic sound — audible as that board simply never
    // sounding like itself. Two ways in: `miss_mk1`/`miss_royal` were never
    // authored, and the only non-family `turn_pass` files belonged to the
    // four flat themes deleted when the illustrated legacy decks replaced
    // them, so all nine legacy boards lost theirs at once. Both also
    // funnelled every player onto one shared pool for that effect.
    bool has(String key) => SoundService.hasVariantForTesting(key);

    test('every gameplay theme has a miss and a turn-pass', () {
      for (final theme in Catalog.gameplayThemes) {
        expect(has('miss_${theme.id}'), isTrue, reason: 'miss_${theme.id}');
        expect(has('turn_pass_${theme.id}'), isTrue,
            reason: 'turn_pass_${theme.id}');
      }
    });

    test('every cannon has a fire, ready and hit', () {
      for (final cannon in Catalog.cannonSkins) {
        expect(has('cannon_fire_${cannon.id}'), isTrue, reason: cannon.id);
        expect(has('cannon_ready_${cannon.id}'), isTrue, reason: cannon.id);
        expect(has('hit_${cannon.id}'), isTrue, reason: cannon.id);
      }
    });

    test('every ship skin has a sunk, place and move', () {
      for (final ship in Catalog.shipSkins) {
        expect(has('sunk_${ship.id}'), isTrue, reason: ship.id);
        expect(has('place_${ship.id}'), isTrue, reason: ship.id);
        expect(has('move_${ship.id}'), isTrue, reason: ship.id);
      }
    });
  });

  _missKeyingTests();

  group('busy-window sizing', () {
    // REGRESSION (fire/hit/miss dropping out in a real match while the menu
    // was fine): a battle plays THEMED keys, and the clip-length table is
    // keyed by base effect names only, so every one of them used to fall
    // through to the 2200ms worst-case fallback. On Android that window is
    // the only thing that returns a player to its pool, so a 3-player pool
    // could sustain barely 1.4 shots a second before stealing players from
    // clips still playing.
    Duration t(String key) => SoundService.safetyTimeoutForTesting(key);

    test('a themed variant is sized like the effect it belongs to', () {
      expect(t('hit_mk1'), t('hit'));
      expect(t('cannon_fire_inferno'), t('cannon_fire'));
      expect(t('miss_phantom'), t('miss'));
      expect(t('cannon_ready_mk1'), t('cannon_ready'));
      expect(t('turn_pass_classic'), t('turn_pass'));
      expect(t('sunk_f_pirate'), t('sunk'));
      expect(t('place_gold'), t('place'));
      expect(t('move_steel'), t('move'));
    });

    test('no gameplay key falls back to the worst-case window', () {
      const fallback = Duration(milliseconds: 2200);
      for (final key in [
        'cannon_fire_mk1',
        'cannon_fire_f_scifi',
        'hit_inferno',
        'hit_f_volcanic',
        'miss_arctic',
        'miss_f_naval',
        'sunk_steel',
        'cannon_ready_void',
        'move_f_steam',
      ]) {
        expect(t(key), isNot(fallback), reason: '$key must know its own clip');
      }
    });

    test('cannon_fire and cannon_ready are not confused for each other', () {
      // They share a prefix, so the longest match has to win.
      expect(t('cannon_ready_kraken'), t('cannon_ready'));
      expect(t('cannon_ready_kraken'), isNot(t('cannon_fire')));
    });
  });

  testWidgets('a finished play hands its player back, once', (tester) async {
    await sound.playForTesting(key);
    await settle(tester);

    final pool = playersOf(key);
    expect(pool, hasLength(1));
    expect(pool.single.disposed, isFalse);
  });

  testWidgets('a rebuild landing on a live checkout leaves no stale player '
      'behind in the pool', (tester) async {
    // REGRESSION (effects "sometimes play, sometimes disappear entirely",
    // and stay broken until the app restarts). A checkout holds its player
    // across a chain of awaits. If the pool is torn down and rebuilt during
    // that chain — which is exactly what a resume from the background used
    // to do to every pool at once — the checkout would still file its now
    // -dead player into the REBUILT pool when it finished. From then on the
    // pool handed that silent player out on roughly one play in `size`.
    await sound.playForTesting(key);
    await tester.pump();
    final original = playersOf(key).single;

    // Park a second checkout mid-dispatch, holding `original`.
    final gate = Completer<void>();
    original.stopGate = gate;
    final parked = sound.playForTesting(key);
    await tester.pump();

    // The app goes away and comes back, then something plays — which is
    // what actually triggers the rebuild now that resume itself is lazy.
    sound.onAppPaused();
    await resume(tester);
    final rebuilt = sound.playForTesting(key);
    await tester.pump();

    // ...and only now does the parked checkout get to finish, against a
    // player the rebuild has already disposed underneath it.
    gate.complete();
    original.stopGate = null;
    await parked;
    await rebuilt;
    await settle(tester);

    final pool = playersOf(key);
    expect(pool, hasLength(1),
        reason: 'the retired player must not rejoin the rebuilt pool');
    expect(pool.single, isNot(same(original)));
    expect(pool.single.disposed, isFalse,
        reason: 'a disposed player in the pool plays nothing, forever');
  });

  testWidgets('a stolen player is never left in both idle and busy',
      (tester) async {
    // When every player is busy, `play` steals the oldest. The checkout it
    // was taken from is still mid-dispatch, and if one of ITS platform
    // calls then fails it used to file the player back as idle — while the
    // thief was playing it. The next play would check that same player out
    // and stop it, cutting a clip off just after it started.
    await sound.playForTesting(key);
    await tester.pump();
    final only = playersOf(key).single;

    final gate = Completer<void>();
    only.stopGate = gate;
    final first = sound.playForTesting(key);
    await tester.pump();

    final thief = sound.playForTesting(key);
    await tester.pump();

    // The stolen-from checkout only ever reaches `release()` by failing, so
    // that is the case worth pinning: it un-parks, its next platform call
    // fails, and its error path tries to file a player that is now the
    // thief's.
    only.stopGate = null;
    only.failNextCall = true;
    gate.complete();
    await first;
    await thief;
    await settle(tester);

    final pool = playersOf(key);
    expect(pool.toSet(), hasLength(pool.length),
        reason: 'a player listed twice can be checked out twice at once');
    expect(pool, hasLength(1));
  });

  testWidgets('a transient inactive does not invalidate the pools',
      (tester) async {
    // `inactive` fires for a permission dialog, a peek at the notification
    // shade, the start of a recents swipe. The app never left, so its
    // players are fine — rebuilding every pool for one of those is pure
    // cost, and each rebuild is another chance to land on a live checkout.
    await sound.playForTesting(key);
    await settle(tester);
    final before = playersOf(key).single;

    sound.onAppPaused(leftForeground: false);
    await resume(tester);
    await sound.playForTesting(key);
    await settle(tester);

    expect(playersOf(key).single, same(before));
  });

  testWidgets('a real backgrounding does invalidate the pools',
      (tester) async {
    // The other half of the same rule: the OS genuinely can reclaim the
    // native samples behind a backgrounded app's players, and nothing on
    // the Dart side shows it — they keep reporting a healthy idle state and
    // keep playing silence. So a pool that has actually been away is
    // rebuilt before it is trusted again.
    await sound.playForTesting(key);
    await settle(tester);
    final before = playersOf(key).single;

    sound.onAppPaused();
    await resume(tester);
    await sound.playForTesting(key);
    await settle(tester);

    final after = playersOf(key).single;
    expect(after, isNot(same(before)));
    expect(before.disposed, isTrue);
    expect(after.disposed, isFalse);
  });

  testWidgets('resuming rebuilds nothing on its own', (tester) async {
    // The resume path used to walk every pool in the app and rebuild it,
    // one per frame — ~350 platform round trips across a third of a second,
    // landing exactly as the player looks at the screen again. Pools are
    // only flagged now; the rebuild happens on first use, so a resume onto
    // a screen that plays two sounds costs two small rebuilds, not thirty.
    await sound.playForTesting(key);
    await sound.playForTesting('click');
    await settle(tester);
    final untouched = playersOf('click');

    sound.onAppPaused();
    await resume(tester);
    await sound.playForTesting(key);
    await settle(tester);

    expect(playersOf('click'), orderedEquals(untouched),
        reason: 'a pool nothing played must not have been rebuilt');
  });

  // FEEDBACK ("the button audio plays twice on the deploy screen too").
  // A pool only comes into existence when its effect is actually played,
  // so "did this make a sound?" is just "does it have a pool?".
  group('one press, one sound', () {
    testWidgets('an ordinary button still clicks', (tester) async {
      sound.click();
      await settle(tester);
      expect(playersOf('click'), isNotEmpty);
    });

    testWidgets('a button that raises its own cue does not also click',
        (tester) async {
      // Exactly the shape `NeonButton` + `PlacementScreen._randomize` had
      // on the device: the button clicks, then the handler it invokes
      // whirs, both synchronously inside one tap.
      sound.click();
      sound.whir();
      await settle(tester);

      expect(playersOf('whir'), isNotEmpty);
      expect(playersOf('click'), isEmpty,
          reason: 'the specific cue should have superseded the generic click');
    });

    testWidgets('an effect from outside the gesture does not eat the click',
        (tester) async {
      // A shot landing from a timer or the network while a button is
      // pressed must not silence that button — only something raised
      // inside the same tap can.
      sound.click();
      await tester.pump();
      sound.whir();
      await settle(tester);

      expect(playersOf('click'), isNotEmpty);
    });
  });
}

/// FEEDBACK ("I use an MK-I cannon but the miss still registers as the
/// opponent's lava theme"). A miss belongs to the shell, not to the water
/// it lands in — the same rule `hit` and `cannonFire` have always used.
/// Asked the other way round, a shot onto any themed battlefield took that
/// board's splash no matter what fired it.
void _missKeyingTests() {
  test('a miss follows the shooter, not the board it lands on', () {
    // Both ids exist as sounds, so the ONLY thing deciding the outcome is
    // which one is consulted first.
    expect(SoundService.hasVariantForTesting('miss_mk1'), isTrue);
    expect(SoundService.hasVariantForTesting('miss_f_volcanic'), isTrue);
    expect(
      SoundService.missKeyForTesting(
        themeId: 'f_volcanic',
        cannonSkinId: 'mk1',
      ),
      'miss_mk1',
    );
  });

  test("the board is still the fallback when the gun has no miss", () {
    expect(
      SoundService.missKeyForTesting(themeId: 'f_volcanic', cannonSkinId: null),
      'miss_f_volcanic',
    );
    expect(
      SoundService.missKeyForTesting(themeId: null, cannonSkinId: null),
      'miss',
    );
  });

}
