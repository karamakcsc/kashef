import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Cairo',
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF2563EB),
          onPrimary: Colors.white,
          secondary: Color(0xFF22C55E),
          onSecondary: Colors.white,
          error: Color(0xFFEF4444),
          onError: Colors.white,
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F172A),
        ),
        scaffoldBackgroundColor: AppColors.light.background,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.light.surface,
          foregroundColor: AppColors.light.textPrimary,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 18,
            color: AppColors.light.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: AppColors.light.textSecondary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.light.primary,
            foregroundColor: AppColors.light.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.light.primary,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.light.surfaceHigh,
          hintStyle: TextStyle(color: AppColors.light.textSecondary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        cardTheme: CardThemeData(
          color: AppColors.light.surface,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dividerTheme:
            DividerThemeData(color: AppColors.light.surfaceHigh),
        textTheme: TextTheme(
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.light.textPrimary,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: AppColors.light.textSecondary,
          ),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Cairo',
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF3B82F6),
          onPrimary: Colors.white,
          secondary: Color(0xFF22C55E),
          onSecondary: Colors.white,
          error: Color(0xFFEF4444),
          onError: Colors.white,
          surface: Color(0xFF1E293B),
          onSurface: Color(0xFFF1F5F9),
        ),
        scaffoldBackgroundColor: AppColors.dark.background,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.dark.surface,
          foregroundColor: AppColors.dark.textPrimary,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 18,
            color: AppColors.dark.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: AppColors.dark.textSecondary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.dark.primary,
            foregroundColor: AppColors.dark.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.dark.primary,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.dark.surfaceHigh,
          hintStyle: TextStyle(color: AppColors.dark.textSecondary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        cardTheme: CardThemeData(
          color: AppColors.dark.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dividerTheme:
            DividerThemeData(color: AppColors.dark.surface),
        textTheme: TextTheme(
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.dark.textPrimary,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: AppColors.dark.textSecondary,
          ),
        ),
      );
}
