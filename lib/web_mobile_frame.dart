import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Max width of the simulated mobile screen on desktop browsers.
const double kWebMobileWidth = 430;

/// Screen-width threshold above which desktop layout is applied.
const double kWebBreakpoint = 600;

/// Wraps [child] in a centered, phone-shaped frame when running on Flutter Web
/// on a desktop browser (viewport width > [kWebBreakpoint]).
///
/// On native Android/iOS or mobile browsers the child is returned unchanged.
///
/// Usage — wrap MaterialApp:
/// ```dart
/// return WebMobileFrame(child: MaterialApp(...));
/// ```
class WebMobileFrame extends StatefulWidget {
  final Widget child;

  const WebMobileFrame({super.key, required this.child});

  @override
  State<WebMobileFrame> createState() => _WebMobileFrameState();
}

class _WebMobileFrameState extends State<WebMobileFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Native platforms — no frame
    if (!kIsWeb) return widget.child;

    return LayoutBuilder(builder: (ctx, constraints) {
      // Mobile browser — full width, no frame
      if (constraints.maxWidth <= kWebBreakpoint) return widget.child;

      // Desktop browser — gradient background + centered mobile frame
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A1628), // deep navy
              Color(0xFF0F172A), // slate-900
              Color(0xFF07111C), // darkest navy
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Container(
              width: kWebMobileWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  // Primary depth shadow
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 60,
                    spreadRadius: 8,
                    offset: const Offset(0, 10),
                  ),
                  // Subtle blue ambient glow
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.10),
                    blurRadius: 90,
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: widget.child,
              ),
            ),
          ),
        ),
      );
    });
  }
}
