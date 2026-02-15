// ── DEV NOTE ──────────────────────────────────────────────────────
// New screen: Root bottom-tab-bar navigation with 3 tabs:
//   - Teams (default) → TeamsScreen
//   - Spiele           → SpieleOverviewScreen
//   - Profil           → ProfilScreen
//
// Created as part of bottom-tab-bar navigation refactor.
// Replaces direct TeamsScreen usage in LoggedInScreen.
//
// Files touched by this refactor:
//   NEW: lib/screens/main_tab_screen.dart
//   NEW: lib/screens/spiele_overview_screen.dart
//   NEW: lib/screens/profil_screen.dart
//   MOD: lib/screens/auth_gate.dart (LoggedInScreen → MainTabScreen)
//   MOD: lib/screens/teams_screen.dart (removed gear icon)
//   MOD: lib/services/match_service.dart (listAllMyMatches)
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/cs_theme.dart';
import 'teams_screen.dart';
import 'spiele_overview_screen.dart';
import 'profil_screen.dart';

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;

  // Use IndexedStack to keep each tab alive when switching
  static const _tabs = <Widget>[
    TeamsScreen(),
    SpieleOverviewScreen(),
    ProfilScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(
              color: CsColors.gray200,
              width: 0.5,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: CsColors.white,
          elevation: 0,
          selectedItemColor: CsColors.lime.computeLuminance() > 0.5
              ? CsColors.gray900 // lime is too bright → use dark icon with lime indicator
              : CsColors.lime,
          unselectedItemColor: CsColors.gray400,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.groups_outlined),
              activeIcon: Icon(Icons.groups),
              label: 'Teams',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.event_outlined),
              activeIcon: Icon(Icons.event),
              label: 'Spiele',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}
