import 'package:flutter/material.dart';
import '../services/team_service.dart';
import '../services/event_service.dart';
import 'team_detail_screen.dart';
import 'event_inbox_screen.dart';
import 'notification_settings_screen.dart';

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _teams = [];
  int _unreadEventCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadUnreadCount();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final teams = await TeamService.listMyTeams();
      if (!mounted) return;
      setState(() => _teams = teams);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await EventService.fetchUnreadCount();
      if (mounted) setState(() => _unreadEventCount = count);
    } catch (_) {}
  }

  Future<void> _openInbox() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EventInboxScreen()),
    );
    // Refresh badge after returning from inbox
    _loadUnreadCount();
  }

  Future<void> _createTeamDialog() async {
    final nameCtrl = TextEditingController();
    final clubCtrl = TextEditingController();
    final leagueCtrl = TextEditingController(text: '3. Liga Herren');
    final yearCtrl = TextEditingController(text: DateTime.now().year.toString());

    bool submitting = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !submitting,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Team erstellen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Team Name'),
              ),
              TextField(
                controller: clubCtrl,
                decoration: const InputDecoration(labelText: 'Club (optional)'),
              ),
              TextField(
                controller: leagueCtrl,
                decoration: const InputDecoration(labelText: 'Liga (optional)'),
              ),
              TextField(
                controller: yearCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Saison Jahr'),
              ),
              if (submitting) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final year = int.tryParse(yearCtrl.text.trim());

                      if (name.isEmpty) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Bitte Team Name eingeben.')),
                        );
                        return;
                      }
                      if (year == null) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Bitte gültiges Saison-Jahr eingeben.')),
                        );
                        return;
                      }

                      setStateDialog(() => submitting = true);

                      try {
                        await TeamService.createTeam(
                          name: name,
                          clubName: clubCtrl.text.trim().isEmpty ? null : clubCtrl.text.trim(),
                          league: leagueCtrl.text.trim().isEmpty ? null : leagueCtrl.text.trim(),
                          seasonYear: year,
                        );

                        if (!mounted) return;
                        Navigator.pop(context, true);

                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Team erstellt ✅')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text('Fehler: $e')),
                        );
                        setStateDialog(() => submitting = false);
                      }
                    },
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Teams'),
        actions: [
          Badge(
            label: Text('$_unreadEventCount'),
            isLabelVisible: _unreadEventCount > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Benachrichtigungen',
              onPressed: _openInbox,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              );
            },
          ),
          IconButton(onPressed: () { _load(); _loadUnreadCount(); }, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createTeamDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Fehler:\n$_error', textAlign: TextAlign.center))
              : _teams.isEmpty
                  ? const Center(child: Text('Noch keine Teams. Tippe + um ein Team zu erstellen.'))
                  : ListView.separated(
                      itemCount: _teams.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final t = _teams[i];
                        return ListTile(
                          title: Text(t['name'] ?? ''),
                          subtitle: Text('${t['league'] ?? ''} • Saison ${t['season_year']}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TeamDetailScreen(
                                  teamId: t['id'] as String,
                                  team: t,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}
