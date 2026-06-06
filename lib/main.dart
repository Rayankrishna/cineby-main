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
  // Allow free rotation — phones stay in their natural orientation, tablets
  // and foldables can use landscape so the app fills the screen instead of
  // being letterboxed with black bars on the sides.
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  await authStore.bootstrap();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF18181A);
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
      // Material 3 picks light snackbar surface by default which makes our
      // dark-bg snackbars unreadable. Force white content text everywhere.
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF1F1E26),
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: Color(0xFFEF0003),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final textTheme = GoogleFonts.manropeTextTheme(
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
