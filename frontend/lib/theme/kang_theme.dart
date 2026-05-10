import 'package:flutter/material.dart';

class KangColors {
  const KangColors._();

  static const deepPurple = Color(0xFF2B1844);
  static const royalPurple = Color(0xFF5B3FA3);
  static const orchid = Color(0xFF7B61C8);
  static const softPurple = Color(0xFFF0EAFB);
  static const purpleWash = Color(0xFFF7F3FD);
  static const mint = Color(0xFF58D6C3);
  static const mintDeep = Color(0xFF2DB7A5);
  static const mintSoft = Color(0xFFEAFBF7);
  static const ink = Color(0xFF1E192B);
  static const slate = Color(0xFF655F73);
  static const line = Color(0xFFE7E0F0);
  static const surface = Color(0xFFFFFCFF);
  static const surfaceWarm = Color(0xFFFAF7FE);
}

class KangTheme {
  const KangTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: KangColors.royalPurple,
      primary: KangColors.royalPurple,
      secondary: KangColors.mint,
      surface: KangColors.surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: KangColors.surfaceWarm,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: KangColors.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        headlineSmall: TextStyle(
          color: KangColors.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        titleLarge: TextStyle(
          color: KangColors.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        titleMedium: TextStyle(
          color: KangColors.ink,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        bodyMedium: TextStyle(
          color: KangColors.slate,
          letterSpacing: 0,
          height: 1.45,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.94),
        prefixIconColor: KangColors.royalPurple,
        suffixIconColor: KangColors.slate,
        labelStyle: const TextStyle(color: KangColors.slate),
        floatingLabelStyle: const TextStyle(
          color: KangColors.royalPurple,
          fontWeight: FontWeight.w700,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: KangColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: KangColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: KangColors.royalPurple,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: KangColors.deepPurple,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          foregroundColor: KangColors.royalPurple,
          side: const BorderSide(color: KangColors.line),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: KangColors.royalPurple,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: KangColors.line),
        ),
      ),
    );
  }
}
