import 'package:flutter/material.dart';
import '../../theme/cs_theme.dart';
import 'cs_buttons.dart';

/// Premium empty-state widget: icon, title, subtitle, optional CTA button.
class CsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onCtaTap;

  const CsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCtaTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: CsColors.gray100,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: CsColors.gray400),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: CsTextStyles.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: CsTextStyles.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            if (ctaLabel != null && onCtaTap != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 220,
                child: CsPrimaryButton(
                  onPressed: onCtaTap,
                  label: ctaLabel!,
                  icon: const Icon(Icons.add, size: 20),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
