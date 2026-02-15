import 'package:flutter/material.dart';
import '../../theme/cs_theme.dart';

/// Semantic variant for [CsStatusChip].
enum CsChipVariant { success, amber, neutral, error, info, lime }

/// Premium pill-shaped status chip.
///
/// Variants: `success` (green), `amber` (warning), `neutral` (gray),
/// `error` (red), `info` (blue), `lime` (brand accent).
class CsStatusChip extends StatelessWidget {
  final String label;
  final CsChipVariant variant;
  final IconData? icon;

  const CsStatusChip({
    super.key,
    required this.label,
    this.variant = CsChipVariant.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (variant) {
      CsChipVariant.success => (
        CsColors.success.withValues(alpha: 0.12),
        CsColors.success,
      ),
      CsChipVariant.amber => (
        CsColors.warning.withValues(alpha: 0.12),
        CsColors.warning,
      ),
      CsChipVariant.neutral => (CsColors.gray200, CsColors.gray600),
      CsChipVariant.error => (
        CsColors.error.withValues(alpha: 0.12),
        CsColors.error,
      ),
      CsChipVariant.info => (
        CsColors.info.withValues(alpha: 0.12),
        CsColors.info,
      ),
      CsChipVariant.lime => (
        CsColors.lime.withValues(alpha: 0.25),
        CsColors.gray900,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CsRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
