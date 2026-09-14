import 'package:battleship_blitz/models/power_up.dart';
import 'package:battleship_blitz/art/impact_fx.dart';
import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/screens/how_to_play_screen.dart';
import 'package:battleship_blitz/screens/settings_screen.dart';
import 'package:battleship_blitz/services/sound_service.dart';
import 'package:battleship_blitz/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProfileStore> _profile() async {
  final p = ProfileStore();
  await p.load();
  return p;
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen,
    {ProfileStore? profile}) async {
  // A tall, wide surface so every section of the settings list and every
  // chapter chip is actually BUILT. Both are lazy scrollables, and off
  // -screen children of one simply do not exist to be found.
  // Deliberately larger than any real phone: both the settings list and
  // the chapter strip are lazy scrollables, and a child scrolled off the
  // end of one is not merely invisible, it has not been built at all.
  tester.view.physicalSize = const Size(1500, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final store = profile ?? await _profile();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(home: screen),
    ),
  );
  // Frame by frame: the entrance stagger is Timer-driven, and one large
  // pump fires those timers without ticking the controllers they start.
  for (var i = 0; i < 70; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}


/// Lets a shell actually cross the water.
///
/// The guide's shells measure their own flight against the wall clock,
/// the same way the game's impact effects do — so `pump`, which only
/// advances FAKE time, never lands one however many frames it draws. A
/// real delay inside `runAsync` is what moves the clock; the pumps after
/// it are what give the ticker a frame to notice.
///
/// Polled rather than slept once: a single fixed delay is a race with
/// whatever else the machine is doing, and this same test passed alone
/// and failed in a loaded full-suite run because of exactly that.
Future<void> _flyShell(WidgetTester tester, {bool Function()? until}) async {
  // Budget deliberately generous: this polls REAL time, and a loaded
  // full-suite run is a great deal slower per step than the same test on
  // its own — which is exactly how this first failed.
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (until == null) {
      if (attempt >= 8) return; // no condition given: just let it land
    } else if (until()) {
      return;
    }
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fxDensity = 1.0;
    screenShakeEnabled = true;
    shellTrailCount = 2;
  });

  group('settings persist and actually take effect', () {
    test('a fresh profile has the documented defaults', () async {
      final p = await _profile();
      expect(p.soundOn, isTrue);
      expect(p.sfxVolume, 1.0);
      expect(p.graphics, GraphicsQuality.balanced);
      expect(p.cinematicFinish, isFalse,
          reason: 'the cinematic finish is opt-in, never on by default');
      // 0.82 is the level menu music always played at before it became
      // adjustable, so an untouched profile sounds exactly as it did.
      expect(p.musicVolume, 0.82);
    });

    test('every setting survives a reload', () async {
      final p = await _profile();
      await p.setSfxVolume(0.3);
      await p.setMusicVolume(0.1);
      await p.setGraphics(GraphicsQuality.low);
      await p.setCinematicFinish(true);

      final reloaded = await _profile();
      expect(reloaded.sfxVolume, closeTo(0.3, 1e-9));
      expect(reloaded.musicVolume, closeTo(0.1, 1e-9));
      expect(reloaded.graphics, GraphicsQuality.low);
      expect(reloaded.cinematicFinish, isTrue);
    });

    test('graphics quality really changes what gets drawn', () async {
      // The setting is only worth having if it reaches the paint code —
      // `fxDensity` is what the impact painters actually read.
      final p = await _profile();
      await p.setGraphics(GraphicsQuality.low);
      expect(fxDensity, lessThan(1.0));
      await p.setGraphics(GraphicsQuality.high);
      expect(fxDensity, greaterThan(1.0));
      await p.setGraphics(GraphicsQuality.balanced);
      expect(fxDensity, 1.0);
    });

    test('every lever the quality setting claims is actually connected',
        () async {
      // BUGFIX: `screenShake` and `shellTrails` were declared on
      // `GraphicsQuality`, given per-quality values, described in the
      // setting's own blurb — and read by nothing at all. Choosing LOW
      // turned the particles down and left both of the other two running
      // at full cost, which is most of what that choice is FOR: the shake
      // is a transform on the whole battle screen, and each trail ghost
      // is a complete second copy of the shell.
      //
      // Asserted on the globals the drawing code actually reads, not on
      // the enum's getters — the getters were never the broken part.
      final p = await _profile();

      await p.setGraphics(GraphicsQuality.low);
      expect(screenShakeEnabled, isFalse,
          reason: 'LOW promises no screen shake');
      expect(shellTrailCount, 0, reason: 'LOW promises no shell trails');

      await p.setGraphics(GraphicsQuality.balanced);
      expect(screenShakeEnabled, isTrue);
      expect(shellTrailCount, 2);

      await p.setGraphics(GraphicsQuality.high);
      expect(screenShakeEnabled, isTrue);
      expect(shellTrailCount, greaterThan(2),
          reason: 'HIGH promises more trail than balanced');
    });

    test('a reloaded profile pushes the quality levers out too', () async {
      // Same trap as the volumes: persisting is not enough, the values
      // have to reach the globals on load or a restart quietly comes back
      // at full cost.
      final p = await _profile();
      await p.setGraphics(GraphicsQuality.low);
      screenShakeEnabled = true;
      shellTrailCount = 99;
      await _profile();
      expect(screenShakeEnabled, isFalse);
      expect(shellTrailCount, 0);
    });

    test('loading a profile pushes its settings at the systems that read '
        'them', () async {
      // Persisting alone is not enough: a restored profile has to SOUND
      // and DRAW the way it was left, which means load() must push the
      // values out, not just read them into fields.
      final p = await _profile();
      await p.setGraphics(GraphicsQuality.high);
      await p.setSfxVolume(0.25);

      fxDensity = 1.0;
      SoundService.instance.sfxVolume = 1.0;
      await _profile();
      expect(fxDensity, GraphicsQuality.high.fxDensity);
      expect(SoundService.instance.sfxVolume, closeTo(0.25, 1e-9));
    });

    test('volumes are clamped, never trusted raw', () async {
      final p = await _profile();
      await p.setSfxVolume(9);
      expect(p.sfxVolume, 1.0);
      await p.setMusicVolume(-4);
      expect(p.musicVolume, 0.0);
    });

    test('each quality step is a distinct, ordered amount of work', () {
      final densities =
          GraphicsQuality.values.map((q) => q.fxDensity).toList();
      expect(densities, equals([...densities]..sort()),
          reason: 'low must cost less than high, or the names lie');
      expect(densities.toSet(), hasLength(GraphicsQuality.values.length));
      expect(GraphicsQuality.low.screenShake, isFalse);
      expect(GraphicsQuality.low.shellTrails,
          lessThan(GraphicsQuality.high.shellTrails));
    });
  });

  group('the settings screen', () {
    testWidgets('shows every group and reflects the stored values',
        (tester) async {
      await _pumpScreen(tester, const SettingsScreen());
      expect(find.text('AUDIO'), findsOneWidget);
      expect(find.text('GRAPHICS'), findsOneWidget);
      expect(find.text('PRESENTATION'), findsOneWidget);
      for (final q in GraphicsQuality.values) {
        expect(find.text(q.label), findsOneWidget, reason: q.label);
      }
    });

    testWidgets('picking a quality writes it through', (tester) async {
      final profile = await _profile();
      await _pumpScreen(tester, const SettingsScreen(), profile: profile);
      await tester.ensureVisible(find.text(GraphicsQuality.low.label));
      await tester.tap(find.text(GraphicsQuality.low.label));
      await tester.pump();
      expect(profile.graphics, GraphicsQuality.low);
      expect(fxDensity, GraphicsQuality.low.fxDensity);
    });
  });

  group('how to play', () {
    testWidgets('has a chapter for the basics and one per battle mode',
        (tester) async {
      await _pumpScreen(tester, const HowToPlayScreen());
      // Twice over: once as the stepper's title, once as its chip.
      expect(find.text('THE BASICS'), findsWidgets);
      for (final mode in LanBattleMode.values) {
        // The chip carries the mode's own label, so a mode added later
        // turns up here without anyone remembering to write a chapter.
        expect(find.text(mode.label), findsWidgets, reason: mode.label);
      }
    });

    testWidgets('the demo board is live — firing changes what it says',
        (tester) async {
      await _pumpScreen(tester, const HowToPlayScreen());
      final before = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();
      // A shell now really crosses the water, so the shot does not
      // resolve until it lands — pump the flight out.
      await tester.tap(find.byKey(const ValueKey('guide-enemy-grid')));
      await _flyShell(tester);
      final after = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();
      expect(after, isNot(equals(before)),
          reason: 'tapping the board has to actually do something');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('switching chapter rebuilds the demo from scratch',
        (tester) async {
      await _pumpScreen(tester, const HowToPlayScreen());
      await tester.tap(find.text(LanBattleMode.ghost.label).first);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // GHOST FLEET records nothing, and the demo says so on its own
      // status bar rather than only in the prose above it.
      expect(find.text('MARKS FADE'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });


    testWidgets('the stepper reaches every chapter without any dragging',
        (tester) async {
      // REGRESSION ("the top nav is not scrollable"). The strip always
      // COULD be dragged — but at phone width the later chapters sit off
      // the end of it with nothing to say so, which is indistinguishable
      // from being stuck. The stepper is the fix, so it has to be able to
      // walk the whole guide on a narrow screen where most chips are not
      // even built.
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = await _profile();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: HowToPlayScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      final total = LanBattleMode.values.length + 1; // + THE BASICS
      for (var i = 1; i < total; i++) {
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('${i + 1} OF $total'), findsOneWidget,
            reason: 'the stepper must reach chapter ${i + 1}');
      }
      // The last chapter really is the last — no further to go.
      expect(find.text('$total OF $total'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('both grids are shown — theirs to fire at, yours to watch',
        (tester) async {
      await _pumpScreen(tester, const HowToPlayScreen());
      expect(find.text('THEIR WATER — TAP TO FIRE'), findsOneWidget);
      expect(find.text('YOUR FLEET — THEY CANNOT SEE IT'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the guide walks forward as the player actually does things',
        (tester) async {
      await _pumpScreen(tester, const HowToPlayScreen());
      // Step one asks for a shot; firing one has to move it on.
      expect(find.textContaining('to fire your first shell'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide-enemy-grid')));
      // The shell has to land before the shot counts — and its flight is
      // timed off the wall clock (`kShellFlight`), so this has to poll
      // real time rather than pump a fixed number of frames. It used to
      // pump 70 frames, which happened to outlast the guide's old
      // hand-picked 620ms flight and stopped working the moment the
      // guide adopted the real one. See [_flyShell].
      await _flyShell(tester,
          until: () =>
              find.textContaining('to fire your first shell').evaluate().isEmpty);
      expect(find.textContaining('to fire your first shell'), findsNothing,
          reason: 'the goal was met, so the guide should have advanced');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('POWER PLAY shows what each multi-shot card covers',
        (tester) async {
      await _pumpScreen(tester, const HowToPlayScreen());
      await tester.tap(find.text(LanBattleMode.powerPlay.label).first);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('WHAT EACH CARD COVERS'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the legend names every mark the board can show',
        (tester) async {
      await _pumpScreen(tester, const HowToPlayScreen());
      expect(find.text('READING THE BOARD'), findsOneWidget);
      for (final label in const [
        'HIT',
        'MISS',
        'SUNK',
        'SPOTTED',
        'YOUR MINE',
        'SCOUT',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.pump(const Duration(seconds: 3));
    });
    testWidgets('a no-turn mode shows reload state instead of turns',
        (tester) async {
      await _pumpScreen(tester, const HowToPlayScreen());
      await tester.tap(find.text(LanBattleMode.chaos.label).first);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('READY'), findsOneWidget);
      expect(find.text('YOUR TURN'), findsNothing,
          reason: 'CHAOS has no turns to take');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('POWER PLAY offers a card to spend', (tester) async {
      await _pumpScreen(tester, const HowToPlayScreen());
      await tester.tap(find.text(LanBattleMode.powerPlay.label).first);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // The guide used to deal a hardcoded SALVO every single turn, so
      // this asserted that exact string. It draws from the real deck now
      // (`PowerUps.draw`), so what matters is that SOME card is in hand
      // and offered — and that it is a card the game actually has.
      final offered = PowerUps.deck
          .where((d) => find.text('${d.name} — USE IT').evaluate().isNotEmpty)
          .toList();
      expect(offered, hasLength(1),
          reason: 'exactly one card should be in hand, from the real deck');
      // Its own one-line description rides along, so a card that needs no
      // target still explains itself. `findsWidgets`, not one: the same
      // string also appears in the full card reference further down the
      // page, which is correct — both are printing the card's own text.
      expect(find.text(offered.single.description), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
    });

    test('every card in the deck can actually be dealt', () {
      // "Make sure every power-up is usable" starts here: a card with no
      // draw weight can never reach a player's hand at all, however well
      // the rest of it is implemented. Checked against the real deck, so
      // adding a card with a zero weight fails right here.
      for (final def in PowerUps.deck) {
        expect(def.weight, greaterThan(0), reason: '${def.name} is undrawable');
      }
      expect(PowerUps.deck.map((d) => d.card).toSet(),
          hasLength(PowerUpCard.values.length),
          reason: 'every PowerUpCard must have exactly one definition');
    });

    test('the guide can route every card to somewhere that does something',
        () {
      // The guide resolves a card down one of three paths, chosen by the
      // card's OWN definition: untargeted cards resolve the moment they
      // are tapped, and targeted ones wait for a square on either your
      // water or theirs (see `_useCard` / `_resolveCardAt`).
      //
      // This pins the routing itself. It is what caught BARRAGE doing
      // nothing: `needsTarget: false` sends it down the untargeted path,
      // but its shots were only wired into the aimed one, so it resolved
      // to the generic "spent" fallback and fired nothing at all.
      final untargeted =
          PowerUps.deck.where((d) => !d.needsTarget).map((d) => d.card);
      final atTheirWater = PowerUps.deck
          .where((d) => d.needsTarget && !d.targetsOwnGrid)
          .map((d) => d.card);
      final atOwnWater = PowerUps.deck
          .where((d) => d.needsTarget && d.targetsOwnGrid)
          .map((d) => d.card);

      // Every card lands in exactly one bucket, and all 24 are covered.
      expect(
        {...untargeted, ...atTheirWater, ...atOwnWater},
        hasLength(PowerUps.deck.length),
      );
      // The own-grid cards are the ones that used to be a dead end: they
      // could be armed and then never spent, because only the enemy board
      // took a tap. If this set ever grows, that path needs checking.
      expect(
        atOwnWater.toSet(),
        {
          PowerUpCard.hardTurn,
          PowerUpCard.autoDodge,
          PowerUpCard.armourPlate,
          PowerUpCard.minefield,
          PowerUpCard.trapLine,
        },
      );
    });
  });
}
