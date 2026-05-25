import 'package:app_web_ui/services/page_transitions.dart';
import 'package:app_web_ui/services/pages/login_page.dart';
import 'package:app_web_ui/services/pages/root_shell.dart';
import 'package:app_web_ui/stores/auth_store.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await authStore.bootstrap();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF292830);
    const surface = Color(0xFF35343E);
    const accent = Color(0xFFEF0003);

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
      ).copyWith(surface: surface),
      scaffoldBackgroundColor: background,
      pageTransitionsTheme: pageTransitions,
    );

    final textTheme = GoogleFonts.interTextTheme(
      base.textTheme,
    ).apply(bodyColor: Colors.white, displayColor: Colors.white);

    final botToastBuilder = BotToastInit();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Reelix',
      theme: base.copyWith(textTheme: textTheme),
      navigatorObservers: [BotToastNavigatorObserver()],
      builder: (context, child) => botToastBuilder(context, child),
      home: Observer(
        builder:
            (_) =>
                authStore.isAuthenticated
                    ? const RootShell()
                    : const LoginPage(),
      ),
    );
  }
}
