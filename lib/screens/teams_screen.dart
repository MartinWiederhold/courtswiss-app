import 'package:flutter/material.dart';
import '../models/sport.dart';
import '../services/team_service.dart';
import '../services/event_service.dart';
import 'sport_selection_screen.dart';
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

  /// Guard to prevent auto-opening sport selection more than once.
  bool _autoCreateShown = false;

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

      // Auto-open sport selection for fresh users (no teams yet)
      if (_teams.isEmpty && !_autoCreateShown) {
        _autoCreateShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _createTeamFlow();
        });
      }
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

  Future<void> _createTeamFlow() async {
    // 1) Sport selection screen
    final sportKey = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const SportSelectionScreen()),
    );
    if (sportKey == null || !mounted) return;

    // 2) Create team dialog with selected sport
    final ok = await _showCreateTeamDialog(sportKey);
    if (ok == true) {
      await _load();
    }
  }

  Future<bool?> _showCreateTeamDialog(String sportKey) async {
    final sport = Sport.byKey(sportKey);
    final nameCtrl = TextEditingController();
    final clubCtrl = TextEditingController();
    final leagueCtrl = TextEditingController(text: '3. Liga Herren');
    final yearCtrl =
        TextEditingController(text: DateTime.now().year.toString());

    bool submitting = false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Team erstellen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sport preview chip
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (sport?.color ?? Colors.blueGrey)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(sport?.icon ?? Icons.sports,
                          size: 20,
                          color: sport?.color ?? Colors.blueGrey),
                      const SizedBox(width: 8),
                      Text(
                        sport?.label ?? sportKey,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: sport?.color ?? Colors.blueGrey,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.check_circle,
                          size: 18, color: Colors.green),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Team Name *'),
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: clubCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Club (optional)'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: leagueCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Liga (optional)'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 8),
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
          ),
          actions: [
            TextButton(
              onPressed:
                  submitting ? null : () => Navigator.pop(context, false),
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
                          const SnackBar(
                              content: Text('Bitte Team Name eingeben.')),
                        );
                        return;
                      }
                      if (year == null) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Bitte gültiges Saison-Jahr eingeben.')),
                        );
                        return;
                      }

                      setStateDialog(() => submitting = true);

                      try {
                        await TeamService.createTeam(
                          name: name,
                          clubName: clubCtrl.text.trim().isEmpty
                              ? null
                              : clubCtrl.text.trim(),
                          league: leagueCtrl.text.trim().isEmpty
                              ? null
                              : leagueCtrl.text.trim(),
                          seasonYear: year,
                          sportKey: sportKey,
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
  }

  Future<bool> _confirmDeleteTeam(Map<String, dynamic> team) async {
    final teamId = team['id'] as String;
    final teamName = team['name'] ?? 'Team';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Team löschen?'),
        content: const Text(
          'Willst du das Team wirklich löschen? '
          'Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await TeamService.deleteTeam(teamId);
      if (!mounted) return true;
      setState(() => _teams.removeWhere((t) => t['id'] == teamId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Team "$teamName" gelöscht')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Löschen: $e')),
      );
      return false;
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
        onPressed: _createTeamFlow,
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
                        final teamId = t['id'] as String;
                        final sportKey = t['sport_key'] as String?;
                        final sport = Sport.byKey(sportKey);
                        return Dismissible(
                          key: ValueKey(teamId),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            color: Colors.red,
                            child: const Icon(Icons.delete,
                                color: Colors.white),
                          ),
                          confirmDismiss: (_) => _confirmDeleteTeam(t),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  (sport?.color ?? Colors.blueGrey)
                                      .withValues(alpha: 0.15),
                              child: Icon(
                                sport?.icon ?? Icons.sports,
                                color: sport?.color ?? Colors.blueGrey,
                              ),
                            ),
                            title: Text(t['name'] ?? ''),
                            subtitle: Text(
                              '${sport?.label ?? ''}'
                              '${(t['league'] ?? '').toString().isNotEmpty ? ' • ${t['league']}' : ''}'
                              ' • Saison ${t['season_year']}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TeamDetailScreen(
                                    teamId: teamId,
                                    team: t,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}
