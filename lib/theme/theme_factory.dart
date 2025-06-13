import 'package:flutter/material.dart';

/// Defines standard Bootstrap-like colors for use in the app.
class AppColors {
  static const Color primary   = Color(0xFF0D6EFD);
  static const Color secondary = Color(0xFF6C757D);
  static const Color success   = Color(0xFF198754);
  static const Color danger    = Color(0xFFDC3545);
  static const Color warning   = Color(0xFFFFC107);
  static const Color info      = Color(0xFF0DCAF0);
  static const Color light     = Color(0xFFF8F9FA);
  static const Color dark      = Color(0xFF212529);
}

/// Factory for creating light and dark [ThemeData] instances.
class AppThemeFactory {
  /// Light theme: white background, black text, Bootstrap accents.
  /// If you don’t pass a primary, it falls back to AppColors.primary.
  static ThemeData createLightTheme({
    Color primary = AppColors.primary,
  }) {
    final base = ThemeData.light();
    return base.copyWith(
      primaryColor: primary,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.info,
        surface: Colors.white,
        onSurface: Colors.black,
        error: AppColors.danger,
        onError: Colors.white,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.black,
        displayColor: Colors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      buttonTheme: base.buttonTheme.copyWith(
        buttonColor: primary,
        textTheme: ButtonTextTheme.primary,
      ),
      dividerColor: AppColors.secondary,
    );
  }

  /// Dark theme: black background, white text, Bootstrap accents.
  /// If you don’t pass a primary, it falls back to AppColors.primary.
  static ThemeData createDarkTheme({
    Color primary = AppColors.primary,
  }) {
    final base = ThemeData.dark();
    return base.copyWith(
      primaryColor: primary,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.info,
        surface: Colors.black,
        onSurface: Colors.white,
        error: AppColors.danger,
        onError: Colors.black,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      buttonTheme: base.buttonTheme.copyWith(
        buttonColor: primary,
        textTheme: ButtonTextTheme.primary,
      ),
      dividerColor: AppColors.secondary,
    );
  }
}
