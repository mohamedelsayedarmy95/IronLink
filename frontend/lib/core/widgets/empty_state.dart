import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'iron_button.dart';

/// Abstract geometric mark for empty states — overlapping rings on a faint
/// grid, drawn rather than shipped as an asset so it inherits theme colors
/// and stays crisp at any density.
///
/// The ring count carries meaning: one for a solo conversation, several for
/// a group, so the mark differs per screen without needing separate art.
class _EmptyStateMark extends CustomPainter {
  const _EmptyStateMark({required this.rings, required this.seedAngle});

  final int rings;
  final double seedAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;

    // Faint concentric guides — depth without a drop shadow.
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = IronColors.borderSubtle;
    canvas.drawCircle(center, radius, guide);
    canvas.drawCircle(center, radius * 0.62, guide);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = IronColors.accentText.withValues(alpha: 0.55);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = IronColors.accentSubtle.withValues(alpha: 0.6);

    if (rings == 1) {
      canvas.drawCircle(center, radius * 0.34, fillPaint);
      canvas.drawCircle(center, radius * 0.34, ringPaint);
      return;
    }

    // Petals arranged evenly so the composition stays balanced for any count.
    final orbit = radius * 0.32;
    final petal = radius * 0.30;
    for (var i = 0; i < rings; i++) {
      final angle = seedAngle + (2 * math.pi / rings) * i;
      final c = center + Offset(math.cos(angle) * orbit, math.sin(angle) * orbit);
      canvas.drawCircle(c, petal, fillPaint);
      canvas.drawCircle(c, petal, ringPaint);
    }
  }

  @override
  bool shouldRepaint(_EmptyStateMark old) =>
      old.rings != rings || old.seedAngle != seedAngle;
}

/// Empty states that explain the gap and offer the next step, instead of a
/// bare icon and a dead-end sentence.
class IronEmptyState extends StatelessWidget {
  const IronEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.rings = 3,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;

  /// Shapes in the mark. 1 reads as a single thread, 3+ as a group.
  final int rings;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: IronSpacing.xl,
          vertical: IronSpacing.lg,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Decorative: the title below already carries the meaning, so the
            // mark is hidden from screen readers rather than described twice.
            ExcludeSemantics(
              child: SizedBox(
                width: 96,
                height: 96,
                child: CustomPaint(
                  painter: _EmptyStateMark(rings: rings, seedAngle: -math.pi / 2),
                ),
              ),
            ),
            const SizedBox(height: IronSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: IronTypography.displaySmall(color: IronColors.textPrimary),
            ),
            const SizedBox(height: IronSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: IronTypography.bodyMedium(color: IronColors.textSecondary),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: IronSpacing.lg),
              IronButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Failure counterpart to [IronEmptyState]: same composition, but framed as
/// something to retry rather than something the user has yet to create.
class IronErrorState extends StatelessWidget {
  const IronErrorState({
    super.key,
    required this.title,
    required this.message,
    this.retryLabel,
    this.onRetry,
  });

  final String title;
  final String message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: IronSpacing.xl,
          vertical: IronSpacing.lg,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: IronColors.semanticError.withValues(alpha: 0.12),
                border: Border.all(
                  color: IronColors.semanticError.withValues(alpha: 0.35),
                ),
              ),
              child: const Icon(Icons.cloud_off_outlined,
                  size: 26, color: IronColors.semanticError),
            ),
            const SizedBox(height: IronSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: IronTypography.headlineLarge(color: IronColors.textPrimary),
            ),
            const SizedBox(height: IronSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: IronTypography.bodyMedium(color: IronColors.textSecondary),
            ),
            if (retryLabel != null && onRetry != null) ...[
              const SizedBox(height: IronSpacing.lg),
              IronButton(
                label: retryLabel!,
                onPressed: onRetry,
                variant: IronButtonVariant.secondary,
                icon: Icons.refresh,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
