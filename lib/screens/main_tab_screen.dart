// ── DEV NOTE ──────────────────────────────────────────────────────
// Root bottom-tab-bar navigation with 3 tabs:
//   - Teams (default) → TeamsScreen
//   - Spiele           → SpieleOverviewScreen
//   - Profil           → ProfilScreen
//
// Premium touches:
//   • Subtle haptic feedback on tab switch (selectionClick)
//   • Fade + slight scale transition on page change (~220 ms)
//   • Micro-scale bounce on the active tab icon
//   • IndexedStack preserves state across tabs (no rebuild)
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../theme/cs_theme.dart';
import 'teams_screen.dart';
import 'spiele_overview_screen.dart';
import 'profil_screen.dart';

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  // Use IndexedStack to keep each tab alive when switching
  static const _tabs = <Widget>[
    TeamsScreen(),
    SpieleOverviewScreen(),
    ProfilScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    );
    _scaleAnim = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    // Start fully visible (no animation on first load)
    _animCtrl.value = 1.0;
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
    _animCtrl.forward(from: 0.0);
  }

  /// Wraps the active icon in a scale-up micro-animation (1.0 → 1.08)
  /// that plays each time the icon becomes active.
  Widget _activeIcon(IconData icon) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (_, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: IndexedStack(
            index: _currentIndex,
            children: _tabs,
          ),
        ),
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
          onTap: _onTabTapped,
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
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.groups_outlined),
              activeIcon: _activeIcon(Icons.groups),
              label: l.tabTeams,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.event_outlined),
              activeIcon: _activeIcon(Icons.event),
              label: l.tabGames,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline),
              activeIcon: _activeIcon(Icons.person),
              label: l.tabProfile,
            ),
          ],
        ),
      ),
    );
  }
}
