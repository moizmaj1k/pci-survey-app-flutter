import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'landing_page.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'dashboard.dart';
import 'theme/theme_provider.dart';
import 'theme/theme_factory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


void main() {

    WidgetsFlutterBinding.ensureInitialized();

    // If we’re on desktop (Windows/Linux/Mac), wire up sqflite_common_ffi:
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(initialMode: ThemeMode.system),
      child: const PCISurveyApp(),
    ),
  );
}

class PCISurveyApp extends StatelessWidget {
  const PCISurveyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'PCI Survey',
      debugShowCheckedModeBanner: false,
      theme: AppThemeFactory.createLightTheme(),
      darkTheme: AppThemeFactory.createDarkTheme(),
      themeMode: themeProvider.themeMode,
      initialRoute: '/',  // <-- set initial route
      routes: {
        '/': (context) => const LandingPage(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/dashboard': (context) => const DashboardScreen(),
      },
      onUnknownRoute: (_) => MaterialPageRoute(
        builder: (context) => const LandingPage(),
      ),
    );
  }
}