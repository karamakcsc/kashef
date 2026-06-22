import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kcsc_ai/main.dart';
import 'package:kcsc_ai/app_colors.dart';

void main() {
  testWidgets('HomePage renders without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // The app should build without throwing
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('AppColors dark palette is correct', (WidgetTester tester) async {
    expect(AppColors.dark.primary,     equals(const Color(0xFF3B82F6)));
    expect(AppColors.dark.primaryDark, equals(const Color(0xFF2563EB)));
    expect(AppColors.dark.background,  equals(const Color(0xFF0F172A)));
    expect(AppColors.dark.surface,     equals(const Color(0xFF1E293B)));
    expect(AppColors.dark.surfaceHigh, equals(const Color(0xFF334155)));
    expect(AppColors.dark.textPrimary, equals(const Color(0xFFF1F5F9)));
    expect(AppColors.dark.onPrimary,   equals(Colors.white));
  });

  testWidgets('AppColors light palette is correct', (WidgetTester tester) async {
    expect(AppColors.light.primary,    equals(const Color(0xFF2563EB)));
    expect(AppColors.light.background, equals(const Color(0xFFF8FAFC)));
    expect(AppColors.light.surface,    equals(const Color(0xFFFFFFFF)));
  });

  testWidgets('AppColors static constants are correct', (WidgetTester tester) async {
    expect(AppColors.success, equals(const Color(0xFF22C55E)));
    expect(AppColors.warning, equals(const Color(0xFFF59E0B)));
    expect(AppColors.error,   equals(const Color(0xFFEF4444)));
  });
}
