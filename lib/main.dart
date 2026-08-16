import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
  await SoundService.instance.init();

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
    // BUGFIX: see the doc comment on SoundService.notifyUserGesture — this
    // Listener wraps the ENTIRE app (not just one button) so the very
    // first tap anywhere retries menu music that a browser blocked from
    // autoplaying, instead of it staying silent until the user happens to
    // press something that plays its own sound.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => SoundService.instance.notifyUserGesture(),
      child: MaterialApp(
        title: 'Battleship Blitz',
        debugShowCheckedModeBanner: false,
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
