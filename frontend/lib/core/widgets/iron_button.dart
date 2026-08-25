import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

enum IronButtonVariant { primary, secondary, destructive, ghost }

/// Buttons with the spec's tactile press behaviour: a 0.98 scale over 150ms
/// plus a haptic tick, so a tap is confirmed before the network is.
///
/// Three things here are deliberate rather than decorative:
/// * Press animation is skipped when the platform reports reduced-motion, so
///   the button still responds without moving for users who ask for that.
/// * Loading swaps the label for a spinner but keeps the button's own width,
///   so nothing around it reflows mid-tap (CLS).
/// * Minimum height is 48px, above the 44px touch floor.
class IronButton extends StatefulWidget {
  const IronButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = IronButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IronButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;

  /// Overrides the announced label when the visible text is not descriptive
  /// enough on its own.
  final String? semanticLabel;

  @override
  State<IronButton> createState() => _IronButtonState();
}

class _IronButtonState extends State<IronButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    switch (widget.variant) {
      case IronButtonVariant.destructive:
        HapticFeedback.mediumImpact();
      case IronButtonVariant.primary:
      case IronButtonVariant.secondary:
      case IronButtonVariant.ghost:
        HapticFeedback.lightImpact();
    }
    widget.onPressed!.call();
  }

  ({Color bg, Color fg, Color? border}) get _colors {
    if (!_enabled) {
      return (
        bg: widget.variant == IronButtonVariant.ghost
            ? Colors.transparent
            : IronColors.surfaceSecondary,
        fg: IronColors.textDisabled,
        border: null,
      );
    }
    return switch (widget.variant) {
      IronButtonVariant.primary => (
          bg: IronColors.accentPrimary,
          fg: IronColors.textPrimary,
          border: null,
        ),
      IronButtonVariant.secondary => (
          bg: IronColors.surfaceSecondary,
          fg: IronColors.textPrimary,
          border: IronColors.borderInteractive,
        ),
      IronButtonVariant.destructive => (
          bg: IronColors.semanticError,
          fg: IronColors.textPrimary,
          border: null,
        ),
      IronButtonVariant.ghost => (
          bg: Colors.transparent,
          fg: IronColors.accentText,
          border: null,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final c = _colors;
    final scale = (_pressed && _enabled && !reduceMotion) ? 0.98 : 1.0;

    final content = widget.loading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: c.fg),
          )
        : Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20, color: c.fg),
                const SizedBox(width: IronSpacing.xs),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: IronTypography.labelLarge(color: c.fg),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel ?? widget.label,
      child: ExcludeSemantics(
        child: AnimatedScale(
          scale: scale,
          duration: IronMotion.press,
          curve: IronMotion.pressCurve,
          child: Material(
            color: c.bg,
            borderRadius: BorderRadius.circular(IronRadius.md),
            child: InkWell(
              onTap: _enabled ? _handleTap : null,
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              borderRadius: BorderRadius.circular(IronRadius.md),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: EdgeInsets.symmetric(
                  horizontal: widget.variant == IronButtonVariant.ghost
                      ? IronSpacing.md
                      : IronSpacing.lg,
                  vertical: IronSpacing.sm,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(IronRadius.md),
                  border: c.border == null
                      ? null
                      : Border.all(color: c.border!),
                ),
                child: Center(
                  widthFactor: widget.expand ? null : 1.0,
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
