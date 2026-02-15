import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/cs_theme.dart';
import 'cs_buttons.dart';

/// Premium modal bottom-sheet form layout.
///
/// Features:
/// - Rounded top (24 px), drag handle, blurred scrim.
/// - Title + close icon header.
/// - Scrollable form content (keyboard-aware via internal scroll).
/// - Sticky primary CTA at the bottom – **always visible**, even with keyboard.
/// - Fixed height (~85 % of screen) so the sheet never "sinks" to the bottom.
/// - No layout shift / resize when keyboard opens or closes.
///
/// Usage:
/// ```dart
/// CsBottomSheetForm.show(
///   context: context,
///   title: 'Neuer Spieler',
///   ctaLabel: 'Speichern',
///   onCta: () { ... },
///   builder: (ctx) => Column(children: [ ... ]),
/// );
/// ```
class CsBottomSheetForm extends StatelessWidget {
  final String title;
  final String ctaLabel;
  final VoidCallback? onCta;
  final bool ctaLoading;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Widget child;

  const CsBottomSheetForm({
    super.key,
    required this.title,
    required this.ctaLabel,
    required this.onCta,
    required this.child,
    this.ctaLoading = false,
    this.secondaryLabel,
    this.onSecondary,
  });

  /// Convenience helper to present the sheet as a modal bottom sheet.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required String ctaLabel,
    required VoidCallback? onCta,
    bool ctaLoading = false,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => CsBottomSheetForm(
        title: title,
        ctaLabel: ctaLabel,
        onCta: onCta,
        ctaLoading: ctaLoading,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary,
        child: builder(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    // Use viewPadding (physical safe-area, stable regardless of keyboard
    // state) so the footer padding never changes when the keyboard opens.
    final safeBottom = mq.viewPadding.bottom;

    // Fixed sheet height: 85 % of screen → always starts high.
    // The framework will clamp this to available space when the keyboard
    // is open, but the internal layout stays stable because we don't
    // read viewInsets anywhere.
    final sheetHeight = mq.size.height * 0.85;

    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(CsRadii.xl)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          height: sheetHeight,
          decoration: const BoxDecoration(
            color: CsColors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(CsRadii.xl)),
          ),
          child: Column(
            children: [
              // ── Drag handle ──
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CsColors.gray300,
                    borderRadius: BorderRadius.circular(CsRadii.full),
                  ),
                ),
              ),

              // ── Header ──
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: CsTextStyles.titleLarge,
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                        color: CsColors.gray500,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // ── Content (scrollable, takes all remaining space) ──
              // Tap on whitespace / labels / gaps dismisses the keyboard.
              // Inputs handle their own focus so they are not affected.
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  behavior: HitTestBehavior.translucent,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: child,
                  ),
                ),
              ),

              // ── Sticky CTA – ALWAYS visible ──
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  safeBottom > 0 ? safeBottom : 12,
                ),
                decoration: BoxDecoration(
                  color: CsColors.white,
                  border: Border(
                    top: BorderSide(
                      color: CsColors.gray200.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CsPrimaryButton(
                      onPressed: onCta,
                      label: ctaLabel,
                      loading: ctaLoading,
                    ),
                    if (secondaryLabel != null) ...[
                      const SizedBox(height: 8),
                      CsSecondaryButton(
                        onPressed: onSecondary,
                        label: secondaryLabel!,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
