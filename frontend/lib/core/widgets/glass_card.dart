import 'package:flutter/material.dart';
import '../theme.dart';

/// A glassmorphism card with blurred background and subtle border.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color backgroundColor;
  final Border? border;
  final double blurSigmaX;
  final double blurSigmaY;

  const GlassCard({
    Key? key,
    required this.child,
    this.borderRadius = 16.0,
    this.backgroundColor = Colors.transparent,
    this.border,
    this.blurSigmaX = 20.0,
    this.blurSigmaY = 20.0,
  }) : super(key: key);

  factory GlassCard.dark({required Widget child, double borderRadius = 16.0}) {
    return GlassCard(
      child: child,
      borderRadius: borderRadius,
      backgroundColor: Colors.white.withOpacity(0.1),
      border: Border.all(color: Colors.white.withOpacity(0.2)),
      blurSigmaX: 20.0,
      blurSigmaY: 20.0,
    );
  }

  factory GlassCard.light({required Widget child, double borderRadius = 16.0}) {
    return GlassCard(
      child: child,
      borderRadius: borderRadius,
      backgroundColor: Colors.white.withOpacity(0.8),
      border: Border.all(color: Colors.white.withOpacity(0.3)),
      blurSigmaX: 20.0,
      blurSigmaY: 20.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = backgroundColor == Colors.transparent
        ? (isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.white.withOpacity(0.8))
        : backgroundColor;
    final borderColor = border ??
        Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.3),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigmaX, sigmaY: blurSigmaY),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: border,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: child,
        ),
      ),
    );
  }
}