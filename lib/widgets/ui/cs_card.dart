import 'package:flutter/material.dart';
import '../../theme/cs_theme.dart';

/// Premium dark card – black background, 16 px radius, soft shadow.
///
/// Optional [accentBarColor] renders a 6 px accent stripe at the top.
/// All text inside should use white / lime colours.
///
/// Pass [backgroundColor], [borderColor], [boxShadow], [splashColor] or
/// [highlightColor] to override the defaults locally without affecting
/// other cards in the app.
class CsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Optional colour bar at the top of the card (e.g. lime, amber, blue).
  final Color? accentBarColor;

  /// Height of the accent bar in logical pixels (default: 6).
  final double accentBarHeight;

  /// Override the card background colour (default: [CsColors.blackCard]).
  final Color? backgroundColor;

  /// Override the card border colour.
  final Color? borderColor;

  /// Override the card box shadow.
  final List<BoxShadow>? boxShadow;

  /// Override the InkWell splash colour.
  final Color? splashColor;

  /// Override the InkWell highlight colour.
  final Color? highlightColor;

  const CsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.accentBarColor,
    this.accentBarHeight = 6,
    this.backgroundColor,
    this.borderColor,
    this.boxShadow,
    this.splashColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? CsColors.blackCard;
    final border = borderColor ??
        CsColors.white.withValues(alpha: CsOpacity.border);
    final shadow = boxShadow ?? CsShadows.card;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CsRadii.lg),
        boxShadow: shadow,
        border: Border.all(color: border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(CsRadii.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CsRadii.lg),
          splashColor:
              splashColor ?? CsColors.lime.withValues(alpha: 0.08),
          highlightColor:
              highlightColor ?? CsColors.white.withValues(alpha: 0.04),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (accentBarColor != null)
                Container(height: accentBarHeight, color: accentBarColor),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lighter card variant for content that sits ON white background
/// but should not be fully dark (e.g. info banners, summary cards).
class CsLightCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Border? border;

  const CsLightCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color ?? CsColors.gray50,
        borderRadius: BorderRadius.circular(CsRadii.lg),
        border: border ?? Border.all(color: CsColors.gray200, width: 0.5),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
