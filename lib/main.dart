import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:pci_survey_application/database_helper.dart';
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
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';
import 'services/uploader.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This is the entry point for background workmanager tasks.
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // background: no context, runs silently
    await Uploader().uploadAllPending();
    return Future.value(true);
  });
}


Future<bool> _isUserLoggedIn() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('auth_token') != null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1️⃣ Initialize Firebase
  await Firebase.initializeApp();

  // 2️⃣ Hook up the background task dispatcher for image uploads
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );
  // Run every 15 minutes (Android) / best‐effort on iOS
  Workmanager().registerPeriodicTask(
    'uploadImagesTask',   // unique name
    'uploadImages',       // task name
    frequency: const Duration(minutes: 15),
  );

  // 3️⃣ Your existing FMTC setup
  await FMTCObjectBoxBackend().initialise();
  await const FMTCStore('osmCache').manage.create();
  await const FMTCStore('topoCache').manage.create();
  await const FMTCStore('esriCache').manage.create();
  await const FMTCStore('cartoPositronCache').manage.create();
  await const FMTCStore('cartoDarkCache').manage.create();
  await const FMTCStore('cyclosmCache').manage.create();

  // 4️⃣ sqflite‐ffi for desktop
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 5️⃣ Run your app, providing both ThemeProvider and Uploader
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(initialMode: ThemeMode.system)),
        ChangeNotifierProvider(create: (_) => Uploader()),          // <-- your upload service
      ],
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
      theme: AppThemeFactory.createLightTheme(
        primary: themeProvider.primaryColor,
      ),
      darkTheme: AppThemeFactory.createDarkTheme(
        primary: themeProvider.primaryColor,
      ),
      themeMode: themeProvider.themeMode,
      home: FutureBuilder<bool>(
        future: _isUserLoggedIn(),
        builder: (context, authSnap) {
          if (authSnap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (authSnap.hasData && authSnap.data == true) {
            // user has a token, now load the local user record
            return FutureBuilder<Map<String, dynamic>?>(
              future: DatabaseHelper().getCurrentUser(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (userSnap.hasData && userSnap.data != null) {
                  // re-save in case you want to refresh timestamp etc.
                  DatabaseHelper().saveCurrentUser(userSnap.data!['id'] as int);
                  return const DashboardScreen();
                }
                // token existed but no local user → fall back
                return const LandingPage();
              },
            );
          }
          // no token → show landing (or login)
          return const LandingPage();
        },
      ),

      // keep all your named routes exactly as before
      routes: {
        '/login':          (_) => const LoginScreen(),
        '/signup':         (_) => const SignupScreen(),
        '/dashboard':      (_) => const DashboardScreen(),
        '/surveyDashboard':(context) {
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