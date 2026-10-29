import 'package:flutter/material.dart';

abstract final class AppColors {
  // Brand identity colors
  static const Color orange = Color(0xFFFF6720);
  static const Color purple = Color(0xFF4C12A1);
  static const Color purpleMid = Color(0xFF9B7DD4);
  static const Color lilac = Color(0xFFDECDE7);
  static const Color cloud = Color(0xFFF0EEE9);
  static const Color gray = Color(0xFFD0D0CE);
  static const Color charcoal = Color(0xFF25282A);
  static const Color success = Color(0xFF22C55E);
  static const Color danger = Color(0xFFEF4444);

  // Modern surface & neutral tokens
  static const Color darkBackground = Color(0xFF121316);
  static const Color darkSurface = Color(0xFF1B1D22);
  static const Color darkSurfaceElevated = Color(0xFF24272F);
  static const Color darkBorder = Color(0xFF2E323B);
  static const Color darkText = Color(0xFFF1F3F5);
  static const Color darkTextMuted = Color(0xFF9DA3AE);

  static const Color lightBackground = Color(0xFFFAFAFB);
  static const Color lightSurface = Colors.white;
  static const Color lightSurfaceElevated = Color(0xFFF3F4F6);
  static const Color lightBorder = Color(0xFFE4E6EA);
  static const Color lightText = Color(0xFF191B1F);
  static const Color lightTextMuted = Color(0xFF6B7280);

  // Brand tint helpers
  static const Color purpleLightTint = Color(0xFFF5F0FF);
  static const Color purpleDarkTint = Color(0xFF2B1D45);
}
