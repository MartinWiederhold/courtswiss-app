import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/cs_theme.dart';

/// Glassmorphism-style AppBar with white/95% background + blur + subtle divider.
///
/// Title is centred, actions on the right.
/// Uses [BackdropFilter] for the frosted glass effect.
class CsGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const CsGlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: CsColors.white.withValues(alpha: 0.95),
            border: Border(
              bottom: BorderSide(
                color: CsColors.gray300.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
          ),
          child: AppBar(
            title: Text(title),
            centerTitle: true,
            leading: leading,
            automaticallyImplyLeading: automaticallyImplyLeading,
            actions: actions,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
        ),
      ),
    );
  }
}
