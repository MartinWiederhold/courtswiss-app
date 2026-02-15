import 'package:flutter/material.dart';
import '../../theme/cs_theme.dart';

/// Compact progress row: label on the left, value on the right,
/// and a rounded progress bar underneath.
///
/// ```
/// Spieler                       6 / 6
/// ████████████████████████████████████
/// ```
class CsProgressRow extends StatelessWidget {
  final String label;
  final String value;
  final double progress; // 0.0 – 1.0
  final Color color;

  /// If true, text is rendered for dark card backgrounds (white text).
  final bool onDark;

  const CsProgressRow({
    super.key,
    required this.label,
    required this.value,
    required this.progress,
    this.color = CsColors.emerald,
    this.onDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        onDark ? CsColors.white.withValues(alpha: CsOpacity.secondary) : CsColors.gray600;
    final valueColor =
        onDark ? CsColors.white : CsColors.black;
    final trackColor =
        onDark ? CsColors.white.withValues(alpha: CsOpacity.border) : CsColors.gray200;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(CsRadii.full),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: trackColor,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}
