// lib/widgets/app_nav_bar.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';

class AppNavBar extends StatefulWidget implements PreferredSizeWidget {
  final String title;
  const AppNavBar({Key? key, this.title = ''}) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  _AppNavBarState createState() => _AppNavBarState();
}

class _AppNavBarState extends State<AppNavBar> {
  late StreamSubscription<ConnectivityResult> _sub;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    // 1) Check initial state
    Connectivity().checkConnectivity().then((status) {
      setState(() => _isOnline = status != ConnectivityResult.none);
    });
    // 2) Listen for changes
    _sub = Connectivity().onConnectivityChanged.listen((status) {
      setState(() => _isOnline = status != ConnectivityResult.none);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProv = context.watch<ThemeProvider>();
    final isDark = themeProv.isDarkMode;

    return AppBar(
      title: Text(widget.title),
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      elevation: 1,
      actions: [
        // Connectivity indicator toggles red/green live
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(
            _isOnline ? Icons.wifi : Icons.wifi_off,
            color: _isOnline ? Colors.green : Colors.red,
          ),
        ),
        // Theme toggle
        IconButton(
          icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
          onPressed: () => themeProv.toggleTheme(!isDark),
        ),
      ],
    );
  }
}
