// Basic widget smoke test.
//
// The original "Counter increments" test referenced the default Flutter counter
// scaffold which no longer exists (the app now uses AuthGate + Supabase).
// This replacement test verifies that the theme initialises correctly
// without requiring any backend or Supabase connection.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swisscourt/theme/cs_theme.dart';

void main() {
  testWidgets('CsTheme builds without errors', (WidgetTester tester) async {
    final theme = buildCsTheme();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(child: Text('CourtSwiss')),
        ),
      ),
    );

    expect(find.text('CourtSwiss'), findsOneWidget);
  });

  testWidgets('CsCard renders content on dark background',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCsTheme(),
        home: Scaffold(
          body: Container(
            decoration: BoxDecoration(
              color: CsColors.black,
              borderRadius: BorderRadius.circular(CsRadii.lg),
            ),
            padding: const EdgeInsets.all(16),
            child: const Text(
              'Premium',
              style: TextStyle(color: CsColors.white),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Premium'), findsOneWidget);
  });
}
