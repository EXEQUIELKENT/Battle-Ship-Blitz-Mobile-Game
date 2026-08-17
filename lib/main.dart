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

  // Start the first main-menu music request before runApp. This removes the
  // dependency on a menu button being pressed before the initial music
  // request is made. The SoundService still handles browser autoplay
  // rejection and retries when the platform permits playback.
  unawaited(SoundService.instance.startMenuMusic());

  // Sound effects are initialized in the background so their setup cannot
  // delay the first menu frame or the first music request.
  unawaited(SoundService.instance.init());

  final network = NetworkService();
  final controller = GameController(profile: profile, network: network);

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

class BattleshipBlitzApp extends StatelessWidget {
  const BattleshipBlitzApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Keep this as a fallback for browsers that block audible autoplay.
    // It is global rather than tied to a specific button, so the first
    // interaction anywhere can unlock the already-requested menu music.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => SoundService.instance.notifyUserGesture(),
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
