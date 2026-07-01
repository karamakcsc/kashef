import 'package:flutter/material.dart';
import 'app_gradients.dart';

/// Ambient three-blob animated background.
///
/// Wraps [child] in a Stack with three slowly drifting radial-gradient blobs.
/// Completely still when [MediaQuery.disableAnimations] is true.
/// RepaintBoundary isolates animation repaints from child widgets.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with TickerProviderStateMixin {
  late final AnimationController _c1;
  late final AnimationController _c2;
  late final AnimationController _c3;

  late final Animation<Alignment> _pos1;
  late final Animation<Alignment> _pos2;
  late final Animation<Alignment> _pos3;

  @override
  void initState() {
    super.initState();

    _c1 = AnimationController(vsync: this, duration: const Duration(seconds: 18))
      ..repeat(reverse: true);
    _c2 = AnimationController(vsync: this, duration: const Duration(seconds: 22))
      ..repeat(reverse: true);
    _c3 = AnimationController(vsync: this, duration: const Duration(seconds: 26))
      ..repeat(reverse: true);

    final ease = CurvedAnimation(parent: _c1, curve: Curves.easeInOut);
    final ease2 = CurvedAnimation(parent: _c2, curve: Curves.easeInOut);
    final ease3 = CurvedAnimation(parent: _c3, curve: Curves.easeInOut);

    _pos1 = AlignmentTween(
      begin: const Alignment(-0.8, -0.8),
      end:   const Alignment(0.3,  0.2),
    ).animate(ease);

    _pos2 = AlignmentTween(
      begin: const Alignment(0.7, -0.5),
      end:   const Alignment(-0.2, 0.6),
    ).animate(ease2);

    _pos3 = AlignmentTween(
      begin: const Alignment(0.1,  0.8),
      end:   const Alignment(0.8, -0.3),
    ).animate(ease3);
  }

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    _c3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    final brightness = Theme.of(context).brightness;
    final blobs = AppGradients.blobColors(brightness);
    final isLight = brightness == Brightness.light;

    return RepaintBoundary(
      child: Stack(
        children: [
          if (!reduced) ...[
            _Blob(animation: _pos1, colour: blobs[0], size: 400, opacity: isLight ? 0.10 : 0.14),
            _Blob(animation: _pos2, colour: blobs[1], size: 300, opacity: isLight ? 0.09 : 0.12),
            _Blob(animation: _pos3, colour: blobs[2], size: 250, opacity: isLight ? 0.08 : 0.11),
          ],
          widget.child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Animation<Alignment> animation;
  final Color colour;
  final double size;
  final double opacity;

  const _Blob({
    required this.animation,
    required this.colour,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) => Align(
        alignment: animation.value,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                colour.withValues(alpha: opacity),
                colour.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
