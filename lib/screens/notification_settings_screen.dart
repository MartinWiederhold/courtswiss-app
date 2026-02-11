import 'package:flutter/material.dart';
import '../services/push_prefs_service.dart';

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
  bool _loading = true;
  bool _pushEnabled = true;
  List<String> _typesDisabled = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Laden: $e')),
      );
    }
  }

  Future<void> _save() async {
    try {
      await PushPrefsService.setPrefs(
        pushEnabled: _pushEnabled,
        typesDisabled: _typesDisabled,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    }
  }

  void _togglePush(bool value) {
    setState(() => _pushEnabled = value);
    _save();
  }

  void _toggleType(String type, bool enabled) {
    setState(() {
      if (enabled) {
        _typesDisabled.remove(type);
      } else {
        if (!_typesDisabled.contains(type)) {
          _typesDisabled.add(type);
        }
      }
    });
    _save();
  }

  bool _isTypeEnabled(String type) => !_typesDisabled.contains(type);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Benachrichtigungs-Einstellungen')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // ── Global push toggle ──────────────────────────
                SwitchListTile(
                  title: const Text('Push-Benachrichtigungen'),
                  subtitle: const Text(
                    'Aktiviere oder deaktiviere alle Push-Nachrichten.',
                  ),
                  secondary: const Icon(Icons.notifications_active),
                  value: _pushEnabled,
                  onChanged: _togglePush,
                ),

                const Divider(),

                // ── Per-type toggles ────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Einzelne Benachrichtigungen',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                  ),
                ),

                ...PushPrefsService.allEventTypes.map((type) {
                  final enabled = _isTypeEnabled(type);
                  return SwitchListTile(
                    title: Text(PushPrefsService.eventTypeLabel(type)),
                    value: _pushEnabled && enabled,
                    // Disable individual toggles when global push is off.
                    onChanged: _pushEnabled
                        ? (val) => _toggleType(type, val)
                        : null,
                    secondary: Icon(
                      _eventIcon(type),
                      color: _pushEnabled && enabled
                          ? Colors.blue
                          : Colors.grey,
                    ),
                  );
                }),

                const SizedBox(height: 24),

                // ── Info card ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    color: Colors.blue.shade50,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue, size: 20),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Push-Nachrichten werden in Kürze aktiviert. '
                              'Deine Einstellungen werden bereits gespeichert.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  IconData _eventIcon(String type) {
    switch (type) {
      case 'lineup_published':
        return Icons.campaign;
      case 'replacement_promoted':
        return Icons.arrow_upward;
      case 'no_reserve_available':
        return Icons.warning_amber;
      default:
        return Icons.notifications;
    }
  }
}
