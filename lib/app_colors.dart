import 'package:flutter/foundation.dart' show kIsWeb;
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

    // ✨ جديد
    required this.aiText,
    required this.aiHighlight,
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

  // ✨ ألوان خاصة بالـ AI / Markdown
  final Color aiText;
  final Color aiHighlight;

  // ── Semantic ─────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // ── Light ────────────────────────────────────────
  static const AppColors light = AppColors._(
    primary: Color(0xFF2563EB),
    primaryDark: Color(0xFF1E40AF),

    background: Color(0xFFF5F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEFF3F8),

    textPrimary: Color(0xFF1F2937),
    textSecondary: Color(0xFF6B7280),
    onPrimary: Color(0xFFFFFFFF),
    userBubble: Color(0xFF60A5FA),

    // ✨ AI
    aiText: Color(0xFF1F2937),
    aiHighlight: Color(0xFF2563EB),
  );

  // ── Dark ─────────────────────────────────────────
  static const AppColors dark = AppColors._(
    primary: Color(0xFF3B82F6),
    primaryDark: Color(0xFF1D4ED8),

    background: Color(0xFF0B1220),
    surface: Color(0xFF111827),
    surfaceHigh: Color(0xFF1F2937),

    textPrimary: Color(0xFFE5E7EB),
    textSecondary: Color(0xFF9CA3AF),
    onPrimary: Color(0xFFFFFFFF),
    userBubble: Color(0xFF60A5FA),

    // ✨ AI
    aiText: Color(0xFFE5E7EB),
    aiHighlight: Color(0xFF3B82F6),
  );

  // ── Arctic Frost (Web Light) ──────────────────────
  static const AppColors arctic = AppColors._(
    primary:     Color(0xFF0284C7), // sky-600
    primaryDark: Color(0xFF0369A1), // sky-700

    background:  Color(0xFFEEF8FF), // icy white-blue
    surface:     Color(0xFFFFFFFF), // pure white cards
    surfaceHigh: Color(0xFFD6EEFF), // frost fill / hover

    textPrimary:   Color(0xFF0C2140), // deep ocean navy
    textSecondary: Color(0xFF3D7EA6), // muted arctic sky
    onPrimary:     Color(0xFFFFFFFF),
    userBubble:    Color(0xFF7DD3FC), // sky-300

    // ✨ AI
    aiText:      Color(0xFF0C2140),
    aiHighlight: Color(0xFF0284C7),
  );

  // ── Context ──────────────────────────────────────
  static AppColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (brightness == Brightness.dark) return dark;
    if (kIsWeb) return arctic;
    return light;
  }
}
