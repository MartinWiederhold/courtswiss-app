import 'package:flutter/material.dart';
import '../../theme/cs_theme.dart';

/// Premium toast / snackbar helper.
///
/// Shows a minimal, high-quality toast at the bottom of the screen.
/// Design: pure black background, white text + icon, rounded corners,
/// smooth slide-up animation, auto-dismiss.
abstract final class CsToast {
  /// Show a **success** toast with a white check icon.
  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.check_rounded,
    );
  }

  /// Show an **error** toast with a white warning icon.
  static void error(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.error_outline_rounded,
    );
  }

  /// Show an **info** toast with a white info icon.
  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.info_outline_rounded,
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Internal
  // ─────────────────────────────────────────────────────────────

  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    // Dismiss any existing toast to avoid stacking.
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: CsColors.white, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  color: CsColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0E0E0E),
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CsRadii.lg), // 16px
        ),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        duration: duration,
        dismissDirection: DismissDirection.down,
        animation: CurvedAnimation(
          parent: const AlwaysStoppedAnimation(1),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }
}
