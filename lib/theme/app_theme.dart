import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Catppuccin Mocha
  static const base = Color(0xFF1e1e2e);
  static const mantle = Color(0xFF181825);
  static const crust = Color(0xFF11111b);
  static const surface0 = Color(0xFF313244);
  static const surface1 = Color(0xFF45475a);
  static const surface2 = Color(0xFF585b70);
  static const overlay0 = Color(0xFF6c7086);
  static const overlay1 = Color(0xFF7f849c);
  static const overlay2 = Color(0xFF9399b2);
  static const subtext0 = Color(0xFFa6adc8);
  static const subtext1 = Color(0xFFbac2de);
  static const text = Color(0xFFcdd6f4);
  static const lavender = Color(0xFFb4befe);
  static const blue = Color(0xFF89b4fa);
  static const sapphire = Color(0xFF74c7ec);
  static const sky = Color(0xFF89dceb);
  static const teal = Color(0xFF94e2d5);
  static const green = Color(0xFFa6e3a1);
  static const yellow = Color(0xFFf9e2af);
  static const peach = Color(0xFFfab387);
  static const maroon = Color(0xFFeba0ac);
  static const red = Color(0xFFf38ba8);
  static const mauve = Color(0xFFcba6f7);
  static const pink = Color(0xFFf5c2e7);
  static const flamingo = Color(0xFFf2cdcd);
  static const rosewater = Color(0xFFf5e0dc);
}

class AppTheme {
  static ThemeData get dark {
    final baseTextTheme = GoogleFonts.jetBrainsMonoTextTheme(
      ThemeData.dark().textTheme,
    );

    // Smaller font sizes for mobile
    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(fontSize: 28),
      displayMedium: baseTextTheme.displayMedium?.copyWith(fontSize: 24),
      displaySmall: baseTextTheme.displaySmall?.copyWith(fontSize: 20),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(fontSize: 18),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(fontSize: 16),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(fontSize: 14),
      titleLarge: baseTextTheme.titleLarge?.copyWith(fontSize: 14),
      titleMedium: baseTextTheme.titleMedium?.copyWith(fontSize: 13),
      titleSmall: baseTextTheme.titleSmall?.copyWith(fontSize: 12),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(fontSize: 13),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(fontSize: 12),
      bodySmall: baseTextTheme.bodySmall?.copyWith(fontSize: 11),
      labelLarge: baseTextTheme.labelLarge?.copyWith(fontSize: 12),
      labelMedium: baseTextTheme.labelMedium?.copyWith(fontSize: 11),
      labelSmall: baseTextTheme.labelSmall?.copyWith(fontSize: 10),
    ).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.base,
      fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.blue,
        secondary: AppColors.mauve,
        surface: AppColors.surface0,
        error: AppColors.red,
        onPrimary: AppColors.base,
        onSecondary: AppColors.base,
        onSurface: AppColors.text,
        onError: AppColors.base,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.mantle,
        foregroundColor: AppColors.text,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface0,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.base,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.surface1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.surface1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.blue),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: AppColors.base,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      dividerColor: AppColors.surface1,
      iconTheme: const IconThemeData(color: AppColors.subtext0),
    );
  }
}
