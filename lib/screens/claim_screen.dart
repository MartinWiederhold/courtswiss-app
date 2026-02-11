import 'package:flutter/material.dart';
import '../services/team_player_service.dart';

/// Screen shown after a player joins a team via invite link.
/// Displays unclaimed player slots – user picks which one they are.
class ClaimScreen extends StatefulWidget {
  final String teamId;
  final String teamName;

  const ClaimScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  @override
  State<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends State<ClaimScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _players = [];
  String _search = '';
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final players =
          await TeamPlayerService.listUnclaimedPlayers(widget.teamId);
      if (!mounted) return;
      setState(() {
        _players = players;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredPlayers {
    if (_search.isEmpty) return _players;
    final q = _search.toLowerCase();
    return _players.where((p) {
      final name =
          '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.toLowerCase();
      return name.contains(q);
    }).toList();
  }

  Future<void> _claim(Map<String, dynamic> player) async {
    final name = TeamPlayerService.playerDisplayName(player);
    final ranking = TeamPlayerService.rankingLabel(player);
    final label = ranking.isNotEmpty ? '$name · $ranking' : name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spieler bestätigen'),
        content: Text('Bist du "$label"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nein'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ja, das bin ich'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _claiming = true);
    try {
      final result = await TeamPlayerService.claimPlayer(
        teamId: widget.teamId,
        playerId: player['id'] as String,
      );
      if (!mounted) return;

      final fullName = result['full_name'] as String? ?? name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Willkommen, $fullName!')),
      );

      // Pop back with success = true
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _claiming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  /// User is not in the pre-created list → skip claiming.
  void _skipClaim() {
    Navigator.pop(context, false); // false = not claimed
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPlayers;

    return PopScope(
      canPop: false, // blocking – must pick or skip
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wer bist du?'),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: _claiming ? null : _skipClaim,
              child: const Text('Überspringen'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Team info ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'Team: ${widget.teamName}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Wähle deinen Namen aus der Liste,\n'
                      'damit das Team dich zuordnen kann.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Search ──
                  if (_players.length > 5)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Name suchen…',
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),

                  if (_claiming)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator(),
                    ),

                  const SizedBox(height: 8),

                  // ── Player list ──
                  if (_players.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Keine verfügbaren Spieler-Slots.\n\n'
                            'Dein Captain hat noch keine Spieler angelegt,\n'
                            'oder alle Slots sind bereits vergeben.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final player = filtered[index];
                          return _buildPlayerTile(player);
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildPlayerTile(Map<String, dynamic> player) {
    final name = TeamPlayerService.playerDisplayName(player);
    final ranking = TeamPlayerService.rankingLabel(player);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue.shade50,
        child: Text(
          _initials(player),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
      ),
      title: Text(name),
      subtitle: ranking.isNotEmpty ? Text(ranking) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: _claiming ? null : () => _claim(player),
    );
  }

  String _initials(Map<String, dynamic> player) {
    final first = player['first_name'] as String? ?? '';
    final last = player['last_name'] as String? ?? '';
    final f = first.isNotEmpty ? first[0].toUpperCase() : '';
    final l = last.isNotEmpty ? last[0].toUpperCase() : '';
    return '$f$l'.trim();
  }
}
