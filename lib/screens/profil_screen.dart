// ── DEV NOTE ──────────────────────────────────────────────────────
// New screen: "Profil" tab in bottom navigation.
// Replaces the settings gear-icon in the TeamsScreen header.
// Contains: user info card, notification preferences (inline), app info.
// Created as part of bottom-tab-bar navigation refactor.
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/push_prefs_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';
import 'auth_screen.dart';

class ProfilScreen extends StatefulWidget {
  const ProfilScreen({super.key});

  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends State<ProfilScreen> {
  bool _loading = true;
  bool _pushEnabled = true;
  List<String> _typesDisabled = [];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    setState(() => _loading = true);
    try {
      final prefs = await PushPrefsService.getPrefs();
      if (!mounted) return;
      setState(() {
        _pushEnabled = prefs['push_enabled'] as bool? ?? true;
        _typesDisabled =
            List<String>.from(prefs['types_disabled'] as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CsToast.error(
          context, 'Einstellungen konnten nicht geladen werden.');
    }
  }

  // ── Preference toggles ─────────────────────────────────

  void _togglePush(bool value) {
    final prev = _pushEnabled;
    setState(() => _pushEnabled = value);
    _saveWithRollback(() => setState(() => _pushEnabled = prev));
  }

  void _toggleType(String type, bool enabled) {
    final prevDisabled = List<String>.from(_typesDisabled);
    setState(() {
      if (enabled) {
        _typesDisabled.remove(type);
      } else {
        if (!_typesDisabled.contains(type)) {
          _typesDisabled.add(type);
        }
      }
    });
    _saveWithRollback(
        () => setState(() => _typesDisabled = prevDisabled));
  }

  Future<void> _saveWithRollback(VoidCallback rollback) async {
    try {
      await PushPrefsService.setPrefs(
        pushEnabled: _pushEnabled,
        typesDisabled: _typesDisabled,
      );
    } catch (_) {
      if (!mounted) return;
      rollback();
      CsToast.error(context,
          'Einstellungen konnten nicht gespeichert werden.');
    }
  }

  bool _isTypeEnabled(String type) => !_typesDisabled.contains(type);

  // ══════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email;
    final isAnon = user?.isAnonymous ?? true;

    return CsScaffoldList(
      appBar: const CsGlassAppBar(
        title: 'Profil',
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                children: List.generate(
                    3, (_) => const CsSkeletonCard()),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                // ── User info card ──────────────────────────
                CsAnimatedEntrance(
                  child: CsLightCard(
                    color: Colors.white,
                    border: Border.all(
                        color: CsColors.gray200, width: 0.5),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: CsColors.lime
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isAnon
                                ? Icons.person_outline
                                : Icons.person,
                            color: CsColors.gray800,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                email ?? 'Anonymer Spieler',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: CsColors.gray900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isAnon
                                    ? 'Nicht eingeloggt'
                                    : 'Eingeloggt',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CsColors.gray500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── Push notifications toggle ────────────────
                CsAnimatedEntrance(
                  delay: const Duration(milliseconds: 40),
                  child: CsLightCard(
                    color: Colors.white,
                    border: Border.all(
                        color: CsColors.gray200, width: 0.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_outlined,
                          color: CsColors.gray800,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Push-Benachrichtigungen',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: CsColors.gray900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Alle Push-Nachrichten ein/aus',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CsColors.gray500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _pushEnabled,
                          onChanged: _togglePush,
                          activeTrackColor: CsColors.emerald,
                          activeThumbColor: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── Per-type notification toggles ────────────
                CsAnimatedEntrance(
                  delay: const Duration(milliseconds: 80),
                  child: CsLightCard(
                    color: Colors.white,
                    border: Border.all(
                        color: CsColors.gray200, width: 0.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Einzelne Benachrichtigungen',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: CsColors.gray900,
                            ),
                          ),
                        ),
                        ...PushPrefsService.allEventTypes
                            .asMap()
                            .entries
                            .map((entry) {
                          final index = entry.key;
                          final type = entry.value;
                          final enabled = _isTypeEnabled(type);

                          return Column(
                            children: [
                              if (index > 0)
                                Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  color: CsColors.gray200,
                                ),
                              SizedBox(
                                height: 58,
                                child: Row(
                                  children: [
                                    Icon(
                                      _eventIcon(type),
                                      color: CsColors.gray800,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        PushPrefsService
                                            .eventTypeLabel(
                                                type),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight:
                                              FontWeight.w500,
                                          color:
                                              CsColors.gray900,
                                        ),
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: _pushEnabled &&
                                          enabled,
                                      onChanged: _pushEnabled
                                          ? (val) =>
                                              _toggleType(
                                                  type, val)
                                          : null,
                                      activeTrackColor:
                                          CsColors.emerald,
                                      activeThumbColor:
                                          Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── Info banner ──────────────────────────────
                CsAnimatedEntrance(
                  delay: const Duration(milliseconds: 120),
                  child: CsLightCard(
                    color: const Color(0xFFF7F7F7),
                    border: Border.all(
                        color: CsColors.gray200, width: 0.5),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.info_outline,
                            color: CsColors.gray700,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Push-Nachrichten werden in Kürze aktiviert. '
                            'Deine Einstellungen werden bereits gespeichert.',
                            style: TextStyle(
                              fontSize: 13,
                              color: CsColors.gray700,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── Account actions ───────────────────────
                if (isAnon) ...[
                  CsAnimatedEntrance(
                    delay: const Duration(milliseconds: 160),
                    child: CsLightCard(
                      color: Colors.white,
                      border: Border.all(
                          color: CsColors.gray200, width: 0.5),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            'Erstelle ein Konto, um eigene Teams zu erstellen '
                            'und dein Profil zu sichern.',
                            style: TextStyle(
                              fontSize: 13,
                              color: CsColors.gray600,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          CsPrimaryButton(
                            label: 'Registrieren / Anmelden',
                            icon: const Icon(Icons.login_rounded, size: 18),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AuthScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  CsAnimatedEntrance(
                    delay: const Duration(milliseconds: 160),
                    child: CsLightCard(
                      color: Colors.white,
                      border: Border.all(
                          color: CsColors.gray200, width: 0.5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: TextButton(
                        onPressed: () async {
                          await Supabase.instance.client.auth.signOut();
                          // AuthGate will rebuild and show AuthScreen
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.logout_rounded,
                                size: 18, color: CsColors.error),
                            const SizedBox(width: 8),
                            Text(
                              'Abmelden',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: CsColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── App version ─────────────────────────────
                CsAnimatedEntrance(
                  delay: const Duration(milliseconds: 200),
                  child: Center(
                    child: Text(
                      'CourtSwiss · v1.0.0',
                      style: TextStyle(
                        fontSize: 12,
                        color: CsColors.gray400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  IconData _eventIcon(String type) {
    switch (type) {
      case 'lineup_published':
        return Icons.campaign_outlined;
      case 'replacement_promoted':
        return Icons.arrow_upward;
      case 'no_reserve_available':
        return Icons.warning_amber_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }
}
