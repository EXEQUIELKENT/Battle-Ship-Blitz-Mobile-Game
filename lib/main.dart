import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/route_observer.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'services/game_controller.dart';
import 'services/network_service.dart';
import 'services/sound_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  final network = NetworkService();
  final controller = GameController(
    profile: profile,
    network: network,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: profile),
        ChangeNotifierProvider.value(value: network),
        ChangeNotifierProvider.value(value: controller),
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
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        SoundService.instance.onAppPaused();
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
