import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/push_prefs_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';

/// Settings screen for notification preferences.
///
/// Shows a global push toggle and per-event-type switches.
/// Uses optimistic UI: toggles update locally immediately,
/// then persist via RPC in the background.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late AppLocalizations l;
  bool _loading = true;
  bool _pushEnabled = true;
  List<String> _typesDisabled = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    l = AppLocalizations.of(context)!;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await PushPrefsService.getPrefs();
      if (!mounted) return;
      setState(() {
        _pushEnabled = prefs['push_enabled'] as bool? ?? true;
        _typesDisabled = List<String>.from(
          prefs['types_disabled'] as List? ?? [],
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CsToast.error(context, l.prefsLoadError);
    }
  }

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
    _saveWithRollback(() => setState(() => _typesDisabled = prevDisabled));
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
      CsToast.error(context, l.prefsSaveError);
    }
  }

  bool _isTypeEnabled(String type) => !_typesDisabled.contains(type);

  @override
  Widget build(BuildContext context) {
    return CsScaffoldList(
      appBar: CsGlassAppBar(title: l.notifications),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                children: List.generate(4, (_) => const CsSkeletonCard()),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // ── Global push toggle ──────────────────────────
                CsAnimatedEntrance(
                  child: CsLightCard(
                    color: Colors.white,
                    border: Border.all(color: CsColors.gray200, width: 0.5),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
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

                // ── Per-type toggles ────────────────────────────
                CsAnimatedEntrance(
                  delay: const Duration(milliseconds: 60),
                  child: CsLightCard(
                    color: Colors.white,
                    border: Border.all(color: CsColors.gray200, width: 0.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
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
                          final isLast =
                              index == PushPrefsService.allEventTypes.length - 1;

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
                                        _eventTypeLabel(type),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: CsColors.gray900,
                                        ),
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: _pushEnabled && enabled,
                                      onChanged: _pushEnabled
                                          ? (val) => _toggleType(type, val)
                                          : null,
                                      activeTrackColor: CsColors.emerald,
                                      activeThumbColor: Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                              if (isLast) const SizedBox.shrink(),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── Info banner ─────────────────────────────────
                CsAnimatedEntrance(
                  delay: const Duration(milliseconds: 120),
                  child: CsLightCard(
                    color: const Color(0xFFF7F7F7),
                    border: Border.all(color: CsColors.gray200, width: 0.5),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
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
              ],
            ),
    );
  }

  String _eventTypeLabel(String type) {
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
