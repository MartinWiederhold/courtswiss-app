// ── DEV NOTE ──────────────────────────────────────────────────────
// New screen: "Profil" tab in bottom navigation.
// Replaces the settings gear-icon in the TeamsScreen header.
// Contains: user info card, language switch, notification preferences
// (inline), app info.
// Created as part of bottom-tab-bar navigation refactor.
// UPDATED: Added language switch section (de/en) for BMAD Step 1.
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show localeController;
import '../services/account_service.dart';
import '../services/push_prefs_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/delete_account_dialog.dart';
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
      final l = AppLocalizations.of(context)!;
      CsToast.error(context, l.prefsLoadError);
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
      final l = AppLocalizations.of(context)!;
      CsToast.error(context, l.prefsSaveError);
    }
  }

  bool _isTypeEnabled(String type) => !_typesDisabled.contains(type);

  // ── Locale helpers ─────────────────────────────────────

  String _currentLocaleCode() {
    final loc = localeController.locale;
    if (loc != null) return loc.languageCode;
    // When null (system), resolve from the actual app locale
    return Localizations.localeOf(context).languageCode;
  }

  // ══════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email;
    final isAnon = user?.isAnonymous ?? true;

    return CsScaffoldList(
      appBar: CsGlassAppBar(
        title: l.profileTitle,
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
                                email ?? l.anonymousPlayer,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: CsColors.gray900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isAnon
                                    ? l.notLoggedIn
                                    : l.loggedIn,
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

                // ── Language switch ──────────────────────────
                CsAnimatedEntrance(
                  delay: const Duration(milliseconds: 30),
                  child: CsLightCard(
                    color: Colors.white,
                    border: Border.all(
                        color: CsColors.gray200, width: 0.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.language,
                              color: CsColors.gray800,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              l.languageTitle,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: CsColors.gray900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _LanguageTile(
                          label: l.german,
                          flag: '🇩🇪',
                          selected: _currentLocaleCode() == 'de',
                          onTap: () =>
                              localeController.setLocale(const Locale('de')),
                        ),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          color: CsColors.gray200,
                        ),
                        _LanguageTile(
                          label: l.english,
                          flag: '🇬🇧',
                          selected: _currentLocaleCode() == 'en',
                          onTap: () =>
                              localeController.setLocale(const Locale('en')),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── Push notifications toggle ────────────────
                CsAnimatedEntrance(
                  delay: const Duration(milliseconds: 50),
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
                                l.pushNotifications,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: CsColors.gray900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l.pushToggleSubtitle,
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
                  delay: const Duration(milliseconds: 90),
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
                            l.individualNotifications,
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
                                        _eventTypeLabel(l, type),
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
                  delay: const Duration(milliseconds: 130),
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
                            l.pushInfoBanner,
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
                    delay: const Duration(milliseconds: 170),
                    child: CsLightCard(
                      color: Colors.white,
                      border: Border.all(
                          color: CsColors.gray200, width: 0.5),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            l.createAccountHint,
                            style: TextStyle(
                              fontSize: 13,
                              color: CsColors.gray600,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          CsPrimaryButton(
                            label: l.registerLogin,
                            icon: const Icon(Icons.login_rounded, size: 18),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const AuthScreen(showClose: true),
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
                    delay: const Duration(milliseconds: 170),
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
                              l.logout,
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

                  // ── Konto section (delete account) ────────
                  CsAnimatedEntrance(
                    delay: const Duration(milliseconds: 190),
                    child: CsLightCard(
                      color: Colors.white,
                      border: Border.all(
                          color: CsColors.gray200, width: 0.5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.manage_accounts_outlined,
                                color: CsColors.gray800,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                l.accountSectionTitle,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: CsColors.gray900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () => _showDeleteAccountDialog(context, l),
                            child: Row(
                              children: [
                                Icon(Icons.delete_forever_rounded,
                                    size: 18, color: CsColors.error),
                                const SizedBox(width: 8),
                                Text(
                                  l.deleteAccount,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: CsColors.error,
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
                ],

                // ── App version ─────────────────────────────
                CsAnimatedEntrance(
                  delay: const Duration(milliseconds: 210),
                  child: Center(
                    child: Text(
                      l.appVersion,
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

  // ── Delete-account flow ──────────────────────────────────

  Future<void> _showDeleteAccountDialog(
    BuildContext context,
    AppLocalizations l,
  ) async {
    // 1. Show the confirmation dialog (it manages its own controller).
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteAccountDialog(
        confirmWord: l.confirmWordDelete,
      ),
    );

    // 2. Safety: check mounted after the async gap.
    if (!mounted) return;

    // 3. If user cancelled or dismissed, do nothing.
    if (confirmed != true) return;

    // 4. User confirmed — perform deletion.
    try {
      await AccountService.deleteAccount();
      // Reset locale controller to system default (fire-and-forget).
      localeController.setLocale(null);
      // AuthGate will rebuild and show AuthScreen automatically
      // because signOut was called inside AccountService.deleteAccount().
    } on PostgrestException catch (e) {
      debugPrint('deleteAccount PostgrestException: '
          'code=${e.code} message=${e.message} '
          'details=${e.details} hint=${e.hint}');
      if (!mounted) return;
      CsToast.error(context, '${l.accountDeleteError}: ${e.message}');
    } on AuthException catch (e) {
      debugPrint('deleteAccount AuthException: '
          'statusCode=${e.statusCode} message=${e.message}');
      if (!mounted) return;
      CsToast.error(context, '${l.accountDeleteError}: ${e.message}');
    } catch (e) {
      debugPrint('deleteAccount error: $e');
      if (!mounted) return;
      CsToast.error(context, l.accountDeleteError);
    }
  }

  /// Localized event-type labels.
  String _eventTypeLabel(AppLocalizations l, String type) {
    switch (type) {
      case 'lineup_published':
        return l.lineupPublished;
      case 'replacement_promoted':
        return l.replacementPromoted;
      case 'no_reserve_available':
        return l.noReserveAvailable;
      default:
        return type;
    }
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

// ─── Language Tile ─────────────────────────────────────────────────
/// A compact, tappable row for a single language option.
class _LanguageTile extends StatelessWidget {
  final String label;
  final String flag;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.label,
    required this.flag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CsRadii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: CsColors.gray900,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle,
                color: CsColors.emerald,
                size: 22,
              )
            else
              Icon(
                Icons.circle_outlined,
                color: CsColors.gray300,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}
