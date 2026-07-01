import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_gradients.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GradientAppBar
// ─────────────────────────────────────────────────────────────────────────────
/// AppBar with Aurora diagonal gradient. White icons + light status bar overlay.
///
/// Usage: drop-in replacement for [AppBar] wherever a gradient header is needed.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final double elevation;
  final PreferredSizeWidget? bottom;

  const GradientAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.elevation = 0,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      elevation: elevation,
      shadowColor: Colors.black26,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      bottom: bottom,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.auroraGradient(brightness),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GradientButton
// ─────────────────────────────────────────────────────────────────────────────
/// Full-width button with Aurora gradient fill, glow shadow, and scale-on-press.
///
/// Use in place of [ElevatedButton] for primary actions.
class GradientButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool loading;
  final double height;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.loading = false,
    this.height = 50,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final c = AppColors.of(context);
    final enabled = widget.onPressed != null && !widget.loading;

    return GestureDetector(
      onTapDown:   enabled ? (_) => setState(() => _pressing = true) : null,
      onTapUp:     enabled ? (_) => setState(() => _pressing = false) : null,
      onTapCancel: enabled ? ()  => setState(() => _pressing = false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              widget.onPressed!();
            }
          : null,
      child: AnimatedScale(
        scale: _pressing ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: widget.height,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: enabled ? AppGradients.auroraGradient(brightness) : null,
            color: enabled ? null : c.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled ? [AppGradients.glowShadow(brightness)] : null,
          ),
          child: Center(
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: enabled ? Colors.white : c.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              child: widget.loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GlassCard
// ─────────────────────────────────────────────────────────────────────────────
/// Frosted-glass card with subtle Aurora border.
///
/// Uses [BackdropFilter] blur — wrap with [RepaintBoundary] if performance is
/// critical, or keep it scoped to occasional elements.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double borderAlpha;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
    this.borderAlpha = 0.20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(borderRadius),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: isLight
                    ? c.surface.withValues(alpha: 0.80)
                    : c.surface.withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: c.primary.withValues(alpha: borderAlpha),
                  width: 0.5,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GradientHeader  (Drawer / section header)
// ─────────────────────────────────────────────────────────────────────────────
/// A small gradient header block — useful for the Drawer or card headers.
class GradientHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double height;

  const GradientHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 16),
    this.height = 90,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        gradient: AppGradients.auroraGradient(brightness),
      ),
      child: child,
    );
  }
}
