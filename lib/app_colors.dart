import 'package:flutter/material.dart';

class AppColors {
  const AppColors._({
    required this.primary,
    required this.primaryDark,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.textPrimary,
    required this.textSecondary,
    required this.onPrimary,
    required this.userBubble,
    required this.aiText,
    required this.aiHighlight,
    required this.successColor,
  });

  final Color primary;
  final Color primaryDark;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color textPrimary;
  final Color textSecondary;
  final Color onPrimary;
  final Color userBubble;
  final Color aiText;
  final Color aiHighlight;

  // Adaptive success (brightness-aware instance field)
  final Color successColor;

  // ── Semantic (static) ─────────────────────────────
  static const Color success = Color(0xFF059669); // emerald-600
  static const Color warning = Color(0xFFD97706); // amber-600
  static const Color error   = Color(0xFFE11D48); // rose-600

  // ── Aurora Light ──────────────────────────────────
  static const AppColors light = AppColors._(
    primary:       Color(0xFF6366F1), // indigo-500
    primaryDark:   Color(0xFF4F46E5), // indigo-600
    background:    Color(0xFFF5F4FD),
    surface:       Color(0xFFFFFFFF),
    surfaceHigh:   Color(0xFFEEEDFB),
    textPrimary:   Color(0xFF1E1B4B), // deep indigo
    textSecondary: Color(0xFF5B5F86),
    onPrimary:     Color(0xFFFFFFFF),
    userBubble:    Color(0xFF818CF8), // indigo-400
    aiText:        Color(0xFF1E1B4B),
    aiHighlight:   Color(0xFF7C3AED), // violet-600
    successColor:  Color(0xFF059669),
  );

  // ── Aurora Dark ───────────────────────────────────
  static const AppColors dark = AppColors._(
    primary:       Color(0xFF818CF8), // indigo-400
    primaryDark:   Color(0xFF6366F1),
    background:    Color(0xFF0B0B16),
    surface:       Color(0xFF16182A),
    surfaceHigh:   Color(0xFF1F2236),
    textPrimary:   Color(0xFFF2F2FA),
    textSecondary: Color(0xFF9A9CC0),
    onPrimary:     Color(0xFF0B0B16),
    userBubble:    Color(0xFF818CF8),
    aiText:        Color(0xFFF2F2FA),
    aiHighlight:   Color(0xFFA78BFA), // violet-400
    successColor:  Color(0xFF34D399), // emerald-400
  );

  // ── Arctic Frost (archived — preserved for potential revert) ──────────────
  static const AppColors arctic = AppColors._(
    primary:       Color(0xFF0284C7),
    primaryDark:   Color(0xFF0369A1),
    background:    Color(0xFFEEF8FF),
    surface:       Color(0xFFFFFFFF),
    surfaceHigh:   Color(0xFFD6EEFF),
    textPrimary:   Color(0xFF0C2140),
    textSecondary: Color(0xFF3D7EA6),
    onPrimary:     Color(0xFFFFFFFF),
    userBubble:    Color(0xFF7DD3FC),
    aiText:        Color(0xFF0C2140),
    aiHighlight:   Color(0xFF0284C7),
    successColor:  Color(0xFF059669),
  );

  // ── Context factory ───────────────────────────────
  static AppColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? dark : light;
  }
}
