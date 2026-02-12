import 'package:flutter/material.dart';

/// Represents a supported sport with display metadata.
class Sport {
  final String key;
  final String label;
  final String assetPath;
  final IconData icon;
  final Color color;

  const Sport({
    required this.key,
    required this.label,
    required this.assetPath,
    required this.icon,
    required this.color,
  });

  /// All supported sports (fixed list).
  /// Asset filenames MUST match the case on disk exactly.
  static const List<Sport> all = [
    Sport(
      key: 'football',
      label: 'Fussball',
      assetPath: 'assets/sports/Fussball.jpg',
      icon: Icons.sports_soccer,
      color: Color(0xFF4CAF50),
    ),
    Sport(
      key: 'tennis',
      label: 'Tennis',
      assetPath: 'assets/sports/Tennis.jpg',
      icon: Icons.sports_tennis,
      color: Color(0xFFFFC107),
    ),
    Sport(
      key: 'volleyball',
      label: 'Volleyball',
      assetPath: 'assets/sports/Volleyball.jpg',
      icon: Icons.sports_volleyball,
      color: Color(0xFFFF9800),
    ),
    Sport(
      key: 'handball',
      label: 'Handball',
      assetPath: 'assets/sports/Handball.jpg',
      icon: Icons.sports_handball,
      color: Color(0xFF2196F3),
    ),
    Sport(
      key: 'basketball',
      label: 'Basketball',
      assetPath: 'assets/sports/Basketball.jpg',
      icon: Icons.sports_basketball,
      color: Color(0xFFE65100),
    ),
    Sport(
      key: 'icehockey',
      label: 'Eishockey',
      assetPath: 'assets/sports/icehockey.jpg',
      icon: Icons.sports_hockey,
      color: Color(0xFF00BCD4),
    ),
    Sport(
      key: 'badminton',
      label: 'Badminton',
      assetPath: 'assets/sports/Badminton.jpg',
      icon: Icons.sports_tennis,
      color: Color(0xFF8BC34A),
    ),
    Sport(
      key: 'tabletennis',
      label: 'Tischtennis',
      assetPath: 'assets/sports/Tischtennis.jpg',
      icon: Icons.sports_tennis,
      color: Color(0xFF9C27B0),
    ),
    Sport(
      key: 'floorball',
      label: 'Unihockey / Floorball',
      assetPath: 'assets/sports/Unihockey.jpg',
      icon: Icons.sports_hockey,
      color: Color(0xFFf44336),
    ),
    Sport(
      key: 'rugby',
      label: 'Rugby',
      assetPath: 'assets/sports/Rugby.jpg',
      icon: Icons.sports_rugby,
      color: Color(0xFF795548),
    ),
    Sport(
      key: 'other',
      label: 'Andere',
      assetPath: 'assets/sports/other.jpg',
      icon: Icons.sports,
      color: Color(0xFF607D8B),
    ),
  ];

  /// Find a sport by key, returns null if not found.
  static Sport? byKey(String? key) {
    if (key == null || key.isEmpty) return null;
    return all.where((s) => s.key == key).firstOrNull;
  }

  /// Get the asset path for a sport key, with fallback.
  static String assetForKey(String? key) {
    final sport = byKey(key);
    return sport?.assetPath ?? 'assets/sports/default.jpg';
  }

  /// Get the icon for a sport key, with fallback.
  static IconData iconForKey(String? key) {
    final sport = byKey(key);
    return sport?.icon ?? Icons.sports;
  }

  /// Get the color for a sport key, with fallback.
  static Color colorForKey(String? key) {
    final sport = byKey(key);
    return sport?.color ?? Colors.blueGrey;
  }

  /// Get the label for a sport key, with fallback.
  static String labelForKey(String? key) {
    final sport = byKey(key);
    return sport?.label ?? 'Sport';
  }
}
