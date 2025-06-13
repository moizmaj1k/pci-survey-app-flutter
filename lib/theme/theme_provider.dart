import 'package:flutter/material.dart';
import 'package:pci_survey_application/theme/theme_factory.dart';  // for AppColors

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode;
  Color _primaryColor;   // ← new

  ThemeProvider({
    ThemeMode initialMode = ThemeMode.system,
    Color initialPrimary = AppColors.primary,  // ← new
  })  : _themeMode = initialMode,
        _primaryColor = initialPrimary;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Color get primaryColor => _primaryColor;    // ← new

  /// Toggle between light and dark themes.
  void toggleTheme(bool enableDarkMode) {
    _themeMode = enableDarkMode ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  /// Set a specific theme mode.
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  /// ← this is what you called but didn’t exist:
  void setPrimaryColor(Color color) {
    _primaryColor = color;
    notifyListeners();
  }
}
