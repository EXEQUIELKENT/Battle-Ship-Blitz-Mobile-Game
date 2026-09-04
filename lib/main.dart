import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/route_observer.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'services/game_controller.dart';
import 'services/match_store.dart';
import 'services/network_service.dart';
import 'services/online_service.dart';
import 'services/sound_service.dart';
import 'services/storage_service.dart';
import 'services/vs_ai_session.dart';

/// TEMPORARY DIAGNOSTIC (profile builds only — compiled out of release).
///
/// Reports slow frames to logcat, split into the two numbers that actually
/// tell us WHERE the mobile jank is coming from:
///   * build  = the UI thread (our Dart: widget rebuilds, layout, painting
///              instructions). Slow here means the fix is in our code.
///   * raster = the raster/GPU thread (actually rasterizing + compositing
///              the layers we produced). Slow here means the fix is in how
///              much/what we're asking the GPU to draw — overdraw, saveLayer,
///              blurs, too many compositing layers.
/// Grep logcat for `PERFJANK`. Remove once the bottleneck is identified.
void _installFrameDiagnostics() {
  if (!kProfileMode) return;
  var frames = 0;
  var jank = 0;
  var worstBuild = 0.0;
  var worstRaster = 0.0;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      frames++;
      final build = t.buildDuration.inMicroseconds / 1000.0;
      final raster = t.rasterDuration.inMicroseconds / 1000.0;
      if (build > worstBuild) worstBuild = build;
      if (raster > worstRaster) worstRaster = raster;
      // 16.7ms is the 60fps budget; flag anything that blew it.
      if (build > 16.7 || raster > 16.7) {
        jank++;
        debugPrint('PERFJANK frame build=${build.toStringAsFixed(1)}ms '
            'raster=${raster.toStringAsFixed(1)}ms');
      }
      if (frames % 120 == 0) {
        debugPrint('PERFJANK SUMMARY frames=$frames janky=$jank '
            '(${(jank * 100 / frames).toStringAsFixed(1)}%) '
            'worstBuild=${worstBuild.toStringAsFixed(1)}ms '
            'worstRaster=${worstRaster.toStringAsFixed(1)}ms');
      }
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installFrameDiagnostics();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.abyss,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final profile = ProfileStore();
  await profile.load();

  SoundService.instance.enabled = profile.soundOn;

  // Request the first main-menu music playback immediately during app
  // startup instead of waiting for a button press.
  //
  // SoundService handles autoplay rejection/retries on platforms that have
  // an autoplay policy. On native Android/iOS this can begin immediately.
  unawaited(SoundService.instance.startMenuMusic());

  // Load the pooled sound effects in the background so their initialization
  // cannot delay the first menu frame or the first music request.
  unawaited(SoundService.instance.init());

  // Pre-warm the equipped loadout's themed pools so the very first themed
  // sound (fire/hit/miss/reload/sunk/ship move) is never building its
  // players on the gameplay hot path — see `SoundService.warmLoadout`.
  // Synchronous: it only queues each pool's own async warmup.
  SoundService.instance.warmLoadout(
    cannonSkinId: profile.cannonSkinId,
    shipSkinId: profile.shipSkinId,
    themeId: profile.gameplayThemeId,
  );

  final network = NetworkService();
  final controller = GameController(
    profile: profile,
    network: network,
  );

  // Persists an in-progress hotspot/online match across a full app close
  // — see the class doc. Attached once, for the app's whole lifetime;
  // it listens for whichever match `controller`/`network` happen to be
  // running at any given moment rather than needing to be re-attached
  // per match.
  final matchStore = MatchStore();
  await matchStore.load();
  matchStore.attach(controller, network);

  final online = OnlineService();
  await online.load();

  // Dev/testing convenience (debug builds only): launching with
  // BBZ_AUTOONLINE=1 connects to the game server right away — discovery,
  // registration, heartbeat — instead of waiting for somebody to open the
  // ONLINE (friends) screen. This is what lets automated desktop tests run
  // two instances headlessly and watch them meet on the server.
  if (!kIsWeb && kDebugMode && Platform.environment['BBZ_AUTOONLINE'] == '1') {
    unawaited(online.connectAuto(profile).then((ok) {
      if (ok) online.startHeartbeat();
    }));
  }

  // Whichever way a match ends — played out, surrendered, abandoned, or
  // simply backed out of — it funnels through `NetworkService.stop()`,
  // which drops the mode back to `none`. That is the one reliable place
  // to free the seat on the online server, so neither player is later
  // told they are "already in a battle" over a game that finished ten
  // minutes ago. Wiring it here rather than inside NetworkService keeps
  // that class unaware of accounts and friends, which it has no other
  // reason to know about.
  //
  // It has to be a TRANSITION out of online play, not merely "the mode is
  // none": `startRelayMatch` begins by calling `stop()` to clear out any
  // previous match, so a bare `mode == none` check fires in the middle of
  // starting a match and ends the one just being set up.
  var wasOnline = false;
  network.addListener(() {
    if (network.mode == NetMode.online) {
      wasOnline = true;
      return;
    }
    if (wasOnline && network.mode == NetMode.none) {
      wasOnline = false;
      unawaited(online.endMatch());
    }
  });

  // Same guard-flag shape as `wasOnline` above, and for the same reason:
  // `VsAiSession.start` calls `network.startLoopbackMatch`, which itself
  // calls `stop()` on its way in — a bare `mode == none` check would tear
  // the session down at the exact moment it's being built.
  final vsAiSession = VsAiSession();
  var wasLoopback = false;
  network.addListener(() {
    if (network.mode == NetMode.loopback) {
      wasLoopback = true;
      return;
    }
    if (wasLoopback && network.mode == NetMode.none) {
      wasLoopback = false;
      vsAiSession.end();
    }
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: profile),
        ChangeNotifierProvider.value(value: network),
        ChangeNotifierProvider.value(value: online),
        ChangeNotifierProvider.value(value: controller),
        Provider<VsAiSession>.value(value: vsAiSession),
        ChangeNotifierProvider.value(value: matchStore),
      ],
      child: const BattleshipBlitzApp(),
    ),
  );
}

class BattleshipBlitzApp extends StatefulWidget {
  const BattleshipBlitzApp({super.key});

  @override
  State<BattleshipBlitzApp> createState() => _BattleshipBlitzAppState();
}

/// BUGFIX (all sound and sound effects disappearing mid-game on phones):
/// this app previously had no `WidgetsBindingObserver` anywhere, so it
/// never reacted to the app leaving/returning to the foreground. See
/// `SoundService.onAppResumed()` for why that silently kills audio on
/// Android/iOS after any backgrounding (lock screen, phone call, app
/// switch, notification shade) — this observer is what actually calls it.
class _BattleshipBlitzAppState extends State<BattleshipBlitzApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        SoundService.instance.onAppResumed();
        break;
      case AppLifecycleState.paused:
        // The real save point for `MatchStore` — `detached` (Android's
        // "about to actually be killed") often arrives with no time left
        // to finish a platform-channel write, so waiting for it is how a
        // match ends up with nothing saved at all. `paused` fires first
        // and reliably, whether the app is about to be killed or just
        // backgrounded.
        unawaited(context.read<MatchStore>().flushNow());
        SoundService.instance.onAppPaused();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        SoundService.instance.onAppPaused();
        break;
      case AppLifecycleState.inactive:
        // The app is still in the foreground — this fires for a permission
        // dialog, a peek at the notification shade, the start of a recents
        // swipe — and is very often followed straight back by `resumed`.
        // Quieten the music, but don't tell SoundService the app went
        // away: see `onAppPaused`'s `leftForeground`.
        SoundService.instance.onAppPaused(leftForeground: false);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fallback for browsers that reject audible autoplay: the first
    // interaction anywhere in the app retries the already-requested music.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) =>
          SoundService.instance.notifyUserGesture(),
      child: MaterialApp(
        title: 'Battleship Blitz',
        debugShowCheckedModeBanner: false,
        navigatorObservers: [appRouteObserver],
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppColors.abyss,
          colorScheme: const ColorScheme.dark(
            primary: AppColors.sonar,
            secondary: AppColors.ember,
            surface: AppColors.deepSea,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
