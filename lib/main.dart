import 'package:app_web_ui/services/page_transitions.dart';
import 'package:app_web_ui/services/pages/home.dart';
import 'package:app_web_ui/services/pages/login_page.dart';
import 'package:app_web_ui/stores/auth_store.dart';
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
    const background = Color(0xFF0B0B10);
    const surface = Color(0xFF16161D);
    const accent = Color(0xFFE50914);

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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Reelix',
      theme: base.copyWith(textTheme: textTheme),
      home: Observer(
        builder:
            (_) =>
                authStore.isAuthenticated
                    ? const MyHomePage(title: 'Reelix')
                    : const LoginPage(),
      ),
    );
  }
}
