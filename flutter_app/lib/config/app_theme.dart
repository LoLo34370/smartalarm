import 'package:flutter/material.dart';

/// Couleurs sémantiques du projet : vert = protégé, rouge = alerte, gris = inactif.
abstract final class AppColors {
  static const background = Color(0xFFF3F5F4);
  static const surface = Colors.white;
  static const border = Color(0xFFE3E8E5);

  static const protected = Color(0xFF2E7D32);
  static const protectedSoft = Color(0xFFE6F2E7);
  static const alert = Color(0xFFC62828);
  static const alertSoft = Color(0xFFFCE8E8);
  static const inactive = Color(0xFF6B7470);
  static const inactiveSoft = Color(0xFFECEFED);
  static const warning = Color(0xFFB26A00);
  static const warningSoft = Color(0xFFFFF3E0);

  static const textPrimary = Color(0xFF17201B);
  static const textSecondary = Color(0xFF5D6762);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.protected,
    surface: AppColors.surface,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
