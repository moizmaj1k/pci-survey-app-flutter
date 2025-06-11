import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart'; // Import this
import '../theme/theme_provider.dart';
import 'package:flutter/services.dart';

class AppNavBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool automaticallyImplyLeading;
  const AppNavBar({
    Key? key,
    this.title = '',
    this.automaticallyImplyLeading = true,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final themeProv = context.watch<ThemeProvider>();
    final isDark = themeProv.isDarkMode;

    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      initialData: const [ConnectivityResult.none],
      builder: (ctx, connectivitySnapshot) {
        // Now listen to internet_connection_checker_plus stream
        return StreamBuilder<InternetStatus>(
          stream: InternetConnection().onStatusChange,
          initialData: InternetStatus.connected, // Assume connected initially
          builder: (ctx, internetSnapshot) {
            final connectivityStatuses = connectivitySnapshot.data!;
            final internetStatus = internetSnapshot.data!;

            // Check if there's any network connection (Wi-Fi, mobile, etc.) AND
            // if there's actual internet access.
            final isOnline = connectivityStatuses.any((s) => s != ConnectivityResult.none) &&
                             internetStatus == InternetStatus.connected;

            return AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              // dynamically switch the status‐bar icon brightness
              systemOverlayStyle: isDark
                ? SystemUiOverlayStyle.light.copyWith(
                    statusBarColor: Colors.transparent,            // Android
                    statusBarIconBrightness: Brightness.light,     // Android
                    statusBarBrightness: Brightness.dark,          // iOS (controls the status bar text/icons)
                  )
                : SystemUiOverlayStyle.dark.copyWith(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness: Brightness.dark,
                    statusBarBrightness: Brightness.light,
                  ),
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 18, // Adjust the font size as needed
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
              automaticallyImplyLeading: automaticallyImplyLeading,

              foregroundColor: Theme.of(context).colorScheme.onSurface,
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    isOnline ? Icons.wifi : Icons.wifi_off,
                    color: isOnline ? Colors.green : Colors.red,
                  ),
                ),
                IconButton(
                  icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                  onPressed: () => themeProv.toggleTheme(!isDark),
                ),
              ],
            );
          },
        );
      },
    );
  }
}