import 'package:flutter/material.dart';

/// Central source for all Aurora gradient and glow definitions.
/// Widgets MUST import from here — no raw hex in widget files.
class AppGradients {
  AppGradients._();

  // ── Aurora gradient colours ────────────────────────────────────────────────
  static const _lightA = Color(0xFF6366F1); // indigo-500
  static const _lightB = Color(0xFF7C3AED); // violet-600
  static const _lightC = Color(0xFFC026D3); // fuchsia-600

  static const _darkA = Color(0xFF818CF8);  // indigo-400
  static const _darkB = Color(0xFFA78BFA);  // violet-400
  static const _darkC = Color(0xFFE879F9);  // fuchsia-400

  // Blob fill colours (used in AuroraBackground)
  static const _lightBlob1 = Color(0xFF6366F1);
  static const _lightBlob2 = Color(0xFF8B5CF6);
  static const _lightBlob3 = Color(0xFFD946EF);

  static const _darkBlob1 = Color(0xFF6366F1);
  static const _darkBlob2 = Color(0xFF7C3AED);
  static const _darkBlob3 = Color(0xFFC026D3);

  // ── Public API ────────────────────────────────────────────────────────────

  /// 135° Aurora gradient — top-left → bottom-right, indigo → violet → fuchsia.
  static LinearGradient auroraGradient(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isLight
          ? const [_lightA, _lightB, _lightC]
          : const [_darkA,  _darkB,  _darkC],
      stops: const [0.0, 0.52, 1.0],
    );
  }

  /// Subtle indigo glow shadow for elevated gradient elements.
  static BoxShadow glowShadow(Brightness brightness) {
    final colour = brightness == Brightness.dark ? _darkA : _lightA;
    return BoxShadow(
      color: colour.withValues(alpha: 0.38),
      blurRadius: 22,
      spreadRadius: -2,
      offset: const Offset(0, 5),
    );
  }

  /// Colours for the three animated blobs in AuroraBackground.
  static List<Color> blobColors(Brightness brightness) {
    return brightness == Brightness.dark
        ? const [_darkBlob1, _darkBlob2, _darkBlob3]
        : const [_lightBlob1, _lightBlob2, _lightBlob3];
  }
}
