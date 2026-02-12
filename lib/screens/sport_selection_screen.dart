import 'package:flutter/material.dart';
import '../models/sport.dart';

/// Full-screen grid to pick a sport before creating a team.
class SportSelectionScreen extends StatelessWidget {
  const SportSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sportart wählen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16, left: 4),
              child: Text(
                'Welche Sportart spielt dein Team?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.4,
                ),
                itemCount: Sport.all.length,
                itemBuilder: (context, index) {
                  final sport = Sport.all[index];
                  return _SportTile(
                    sport: sport,
                    onTap: () => Navigator.pop(context, sport.key),
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
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
            // Sport icon + label
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Row(
                children: [
                  Icon(sport.icon, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sport.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black54),
                        ],
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
      errorBuilder: (context, error, stack) {
        debugPrint(
            'SPORT_ASSET_MISSING: ${sport.assetPath} err=$error');
        // Fallback: gradient with sport color
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                sport.color.withValues(alpha: 0.7),
                sport.color,
              ],
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
