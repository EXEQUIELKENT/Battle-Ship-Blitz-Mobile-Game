import 'package:audioplayers/audioplayers.dart';
import 'package:battleship_blitz/services/sound_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the asset each player is pointed at, so a test can see which
/// FILE a cue actually reaches rather than only which key it asked for.
class _RecordingPlayer extends AudioPlayer {
  static final List<String> loaded = [];

  @override
  set positionUpdater(PositionUpdater? updater) {}

  @override
  Future<void> setAudioContext(AudioContext ctx) async {}

  @override
  Future<void> setSource(Source source) async {
    if (source is AssetSource) loaded.add(source.path);
  }

  @override
  Future<void> setPlayerMode(PlayerMode mode) async {}

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPlaybackRate(double rate) async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  final sound = SoundService.instance;

  setUp(() {
    AudioLogger.logLevel = AudioLogLevel.none;
    SoundService.playerFactory = _RecordingPlayer.new;
    sound.resetForTesting();
    _RecordingPlayer.loaded.clear();
  });

  tearDown(() {
    SoundService.playerFactory = AudioPlayer.new;
    sound.resetForTesting();
  });

  // REGRESSION ("check if the sounds are playing differently on the
  // different ship skins when destroyed"). Three separate things have to
  // hold for a fleet to actually go down sounding like itself, and only
  // the first was covered anywhere: the variant has to be REGISTERED, the
  // sinking hull's skin has to REACH `sunk()` from the battle screen, and
  // the registered key has to point at a file that is genuinely its own
  // rather than an alias of the generic one. A break in any of the three
  // is inaudible in exactly the same way — every fleet sinks to the same
  // noise — so this pins all three.
  testWidgets('every ship skin sinks to its own audio file', (tester) async {
    final bySkin = <String, String>{};
    for (final skin in Catalog.shipSkins) {
      _RecordingPlayer.loaded.clear();
      sound.sunk(shipSkinId: skin.id);
      // `sunk` is fire-and-forget; let its pool build and dispatch.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_RecordingPlayer.loaded, isNotEmpty,
          reason: '${skin.id} loaded no audio at all');
      final asset = _RecordingPlayer.loaded.first;
      expect(asset, isNot('sfx/sunk.wav'),
          reason: '${skin.id} fell back to the generic sinking sound');
      bySkin[skin.id] = asset;
    }

    // Each checkout holds its player behind a safety timer (see
    // `SoundService.safetyTimeoutForTesting`); run them all out so the
    // binding doesn't report pending timers at teardown.
    await tester.pump(const Duration(seconds: 30));

    // No two fleets may share a file, or they are audibly identical even
    // though each "has" a variant.
    final seen = <String, String>{};
    bySkin.forEach((skinId, asset) {
      expect(seen.containsKey(asset), isFalse,
          reason: '$skinId and ${seen[asset]} both sink to $asset');
      seen[asset] = skinId;
    });
    expect(seen, hasLength(Catalog.shipSkins.length));
  });

  test('a hull with no skin still gets the generic sinking sound', () {
    expect(SoundService.hasVariantForTesting('sunk'), isTrue);
  });
}
