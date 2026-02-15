// Static ranking data for Swiss (CH) and German (DE) tennis classifications.
//
// Values are mapped to integers for DB storage while preserving correct
// ordering (lower = better player):
//   CH  N1→-4 … N4→-1, R1→1 … R9→9
//   DE  LK 1→1001 … LK 25→1025
//
// Existing R-rankings (1–9) remain 100% backward-compatible.

class RankingCountry {
  final String code;
  final String name;
  const RankingCountry(this.code, this.name);
}

class RankingOption {
  final String label;
  final int value;
  const RankingOption(this.label, this.value);
}

class RankingSection {
  final String title;
  final List<RankingOption> options;
  const RankingSection(this.title, this.options);
}

class RankingData {
  RankingData._();

  // ── Countries ──────────────────────────────────────────────

  static const countries = [
    RankingCountry('CH', 'Schweiz'),
    RankingCountry('DE', 'Deutschland'),
  ];

  // ── Sections per country ───────────────────────────────────

  static List<RankingSection> sectionsFor(String countryCode) {
    switch (countryCode) {
      case 'DE':
        return _deSections;
      default:
        return _chSections;
    }
  }

  /// Flat list of all options for a country.
  static List<RankingOption> optionsFor(String countryCode) {
    return sectionsFor(countryCode)
        .expand((s) => s.options)
        .toList(growable: false);
  }

  // ── DB int ↔ display label ─────────────────────────────────

  /// Convert a DB integer to a human-readable ranking label.
  static String label(int? value) {
    if (value == null) return '';
    if (value >= -4 && value <= -1) return 'N${value + 5}';
    if (value >= 1 && value <= 9) return 'R$value';
    if (value >= 1001 && value <= 1025) return 'LK ${value - 1000}';
    // Fallback for legacy data
    return 'R$value';
  }

  /// Infer country code from a ranking int.
  static String countryFor(int value) {
    if (value >= 1001) return 'DE';
    return 'CH';
  }

  // ── Swiss (CH) ─────────────────────────────────────────────

  static const _chSections = [
    RankingSection('N-Klassierungen', [
      RankingOption('N1', -4),
      RankingOption('N2', -3),
      RankingOption('N3', -2),
      RankingOption('N4', -1),
    ]),
    RankingSection('R-Klassierungen', [
      RankingOption('R1', 1),
      RankingOption('R2', 2),
      RankingOption('R3', 3),
      RankingOption('R4', 4),
      RankingOption('R5', 5),
      RankingOption('R6', 6),
      RankingOption('R7', 7),
      RankingOption('R8', 8),
      RankingOption('R9', 9),
    ]),
  ];

  // ── Germany (DE) ───────────────────────────────────────────

  static const _deSections = [
    RankingSection('Leistungsklassen (LK)', [
      RankingOption('LK 1', 1001),
      RankingOption('LK 2', 1002),
      RankingOption('LK 3', 1003),
      RankingOption('LK 4', 1004),
      RankingOption('LK 5', 1005),
      RankingOption('LK 6', 1006),
      RankingOption('LK 7', 1007),
      RankingOption('LK 8', 1008),
      RankingOption('LK 9', 1009),
      RankingOption('LK 10', 1010),
      RankingOption('LK 11', 1011),
      RankingOption('LK 12', 1012),
      RankingOption('LK 13', 1013),
      RankingOption('LK 14', 1014),
      RankingOption('LK 15', 1015),
      RankingOption('LK 16', 1016),
      RankingOption('LK 17', 1017),
      RankingOption('LK 18', 1018),
      RankingOption('LK 19', 1019),
      RankingOption('LK 20', 1020),
      RankingOption('LK 21', 1021),
      RankingOption('LK 22', 1022),
      RankingOption('LK 23', 1023),
      RankingOption('LK 24', 1024),
      RankingOption('LK 25', 1025),
    ]),
  ];
}
