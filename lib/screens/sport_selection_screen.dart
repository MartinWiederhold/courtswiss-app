import 'package:flutter/material.dart';
import '../models/sport.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';

/// Full-screen grid to pick a sport before creating a team.
class SportSelectionScreen extends StatelessWidget {
  const SportSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CsScaffold(
      appBar: const CsGlassAppBar(title: 'Sportart wählen'),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 16, left: 4),
              child: Text(
                'Welche Sportart spielt dein Team?',
                style: CsTextStyles.titleMedium,
              ),
            ),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.3,
                ),
                itemCount: Sport.all.length,
                itemBuilder: (context, index) {
                  final sport = Sport.all[index];
                  return CsAnimatedEntrance.staggered(
                    index: index,
                    child: _SportTile(
                      sport: sport,
                      onTap: () => Navigator.pop(context, sport.key),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SportTile extends StatelessWidget {
  final Sport sport;
  final VoidCallback onTap;

  const _SportTile({required this.sport, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      color: CsColors.blackCard,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background: try asset image, fallback to gradient
            _buildBackground(),
            // Dark gradient overlay for text readability
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            // Sport icon + label
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(CsRadii.sm),
                    ),
                    child: Icon(sport.icon, color: Colors.white, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sport.label,
                      style: CsTextStyles.onDarkPrimary.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    debugPrint('SPORT_TILE: key=${sport.key} asset=${sport.assetPath}');
    return Image.asset(
      sport.assetPath,
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.3),
      errorBuilder: (context, error, stack) {
        debugPrint('SPORT_ASSET_MISSING: ${sport.assetPath} err=$error');
        // Fallback: gradient with sport color
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [sport.color.withValues(alpha: 0.7), sport.color],
            ),
          ),
          child: Center(
            child: Icon(
              sport.icon,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        );
      },
    );
  }
}
