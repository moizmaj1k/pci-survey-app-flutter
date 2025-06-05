import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:provider/provider.dart';
import 'landing_page.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'dashboard.dart';
import 'survey_dashboard.dart';
import 'theme/theme_provider.dart';
import 'theme/theme_factory.dart';
import 'distress_form.dart';


Future<void> main() async {
  // Ensure binding and plugin services are ready
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FMTC backend (ObjectBox) for offline cache
  await FMTCObjectBoxBackend().initialise();

  // Create the offline tile store before runApp
  await const FMTCStore('osmCache').manage.create();
  await const FMTCStore('topoCache').manage.create();
  await const FMTCStore('esriCache').manage.create();

  // Setup sqflite on desktop
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
      initialRoute: '/',
      routes: {
        '/':               (_) => const LandingPage(),
        '/login':          (_) => const LoginScreen(),
        '/signup':         (_) => const SignupScreen(),
        '/dashboard':      (_) => const DashboardScreen(),
        '/surveyDashboard': (context) {
          final surveyId = ModalRoute.of(context)!.settings.arguments as int;
          return SurveyDashboard(surveyId: surveyId);
        },
        DistressForm.routeName: (_) => const DistressForm(),
      },
      onUnknownRoute: (_) => MaterialPageRoute(
        builder: (context) => const LandingPage(),
      ),
    );
  }
}