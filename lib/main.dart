import 'package:app_web_ui/services/pages/home.dart';

import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
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
      fontFamily: 'Inter',
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cineby',
      theme: base.copyWith(
        textTheme: base.textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const MyHomePage(title: 'Cineby'),
    );
  }
}
