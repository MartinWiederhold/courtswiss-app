import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/cs_theme.dart';

/// Primary button – black bg, white text, 12 px radius, ≥ 48 px height.
///
/// Includes a subtle press animation (scale 0.98) and haptic feedback.
class CsPrimaryButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget? icon;
  final String label;
  final bool loading;

  const CsPrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
  });

  @override
  State<CsPrimaryButton> createState() => _CsPrimaryButtonState();
}

class _CsPrimaryButtonState extends State<CsPrimaryButton> {
  bool _pressed = false;

  void _handleTapDown(TapDownDetails _) => setState(() => _pressed = true);
  void _handleTapUp(TapUpDetails _) => setState(() => _pressed = false);
  void _handleTapCancel() => setState(() => _pressed = false);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed != null ? _handleTapDown : null,
      onTapUp: widget.onPressed != null ? _handleTapUp : null,
      onTapCancel: widget.onPressed != null ? _handleTapCancel : null,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: CsDurations.fast,
        curve: Curves.easeOut,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: widget.icon != null
              ? ElevatedButton.icon(
                  onPressed: widget.loading
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          widget.onPressed?.call();
                        },
                  icon: widget.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: CsColors.white,
                          ),
                        )
                      : widget.icon!,
                  label: Text(widget.label),
                )
              : ElevatedButton(
                  onPressed: widget.loading
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          widget.onPressed?.call();
                        },
                  child: widget.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: CsColors.white,
                          ),
                        )
                      : Text(widget.label),
                ),
        ),
      ),
    );
  }
}

/// Secondary button – transparent/outline with subtle border, black text.
class CsSecondaryButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget? icon;
  final String label;
  final bool loading;

  const CsSecondaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
  });

  @override
  State<CsSecondaryButton> createState() => _CsSecondaryButtonState();
}

class _CsSecondaryButtonState extends State<CsSecondaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed != null
          ? (_) => setState(() => _pressed = true)
          : null,
      onTapUp: widget.onPressed != null
          ? (_) => setState(() => _pressed = false)
          : null,
      onTapCancel: widget.onPressed != null
          ? () => setState(() => _pressed = false)
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: CsDurations.fast,
        curve: Curves.easeOut,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: widget.icon != null
              ? OutlinedButton.icon(
                  onPressed: widget.loading
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          widget.onPressed?.call();
                        },
                  icon: widget.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : widget.icon!,
                  label: Text(widget.label),
                )
              : OutlinedButton(
                  onPressed: widget.loading
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          widget.onPressed?.call();
                        },
                  child: widget.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.label),
                ),
        ),
      ),
    );
  }
}
