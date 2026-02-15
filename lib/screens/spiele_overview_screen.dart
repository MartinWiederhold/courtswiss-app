// ── DEV NOTE ──────────────────────────────────────────────────────
// New screen: Global "Spiele" tab showing all matches across all teams.
// Created as part of bottom-tab-bar navigation refactor.
// Data: MatchService.listAllMyMatches() → cs_matches joined with cs_teams.
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../services/match_service.dart';
import '../services/team_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';
import 'match_detail_screen.dart';

class SpieleOverviewScreen extends StatefulWidget {
  const SpieleOverviewScreen({super.key});

  @override
  State<SpieleOverviewScreen> createState() => _SpieleOverviewScreenState();
}

class _SpieleOverviewScreenState extends State<SpieleOverviewScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _matches = [];

  @override
  void initState() {
    super.initState();
    _load();
    // Reload when a team is deleted (or structurally changed)
    TeamService.teamChangeNotifier.addListener(_onTeamChanged);
  }

  @override
  void dispose() {
    TeamService.teamChangeNotifier.removeListener(_onTeamChanged);
    super.dispose();
  }

  void _onTeamChanged() {
    // Team was deleted → reload matches from DB
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matches = await MatchService.listAllMyMatches();
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openMatch(Map<String, dynamic> match) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MatchDetailScreen(
          matchId: match['id'] as String,
          teamId: match['team_id'] as String,
          match: match,
        ),
      ),
    );
    _load();
  }

  String _formatMatchDate(Map<String, dynamic> match) {
    final dt = DateTime.tryParse(match['match_at'] ?? '')?.toLocal();
    if (dt == null) return '–';
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  // ══════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return CsScaffoldList(
      appBar: CsGlassAppBar(
        title: 'Spiele',
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                children:
                    List.generate(4, (_) => const CsSkeletonCard()),
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CsEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Verbindungsproblem',
                        subtitle: 'Daten konnten nicht geladen werden.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Nochmal versuchen'),
                      ),
                    ],
                  ),
                )
              : _matches.isEmpty
                  ? const CsEmptyState(
                      icon: Icons.event_outlined,
                      title: 'Noch keine Spiele',
                      subtitle:
                          'Erstelle dein erstes Spiel in einem Team.',
                    )
                  : ListView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: _matches.length,
                      itemBuilder: (context, i) {
                        return CsAnimatedEntrance.staggered(
                          index: i,
                          child: _buildMatchTile(_matches[i]),
                        );
                      },
                    ),
    );
  }

  // ── Match tile (mirrors TeamDetailScreen style) ─────────

  Widget _buildMatchTile(Map<String, dynamic> match) {
    final isHome = match['is_home'] == true;
    final teamName = match['team_name'] as String? ?? '–';

    return CsCard(
      backgroundColor: CsColors.white,
      borderColor: CsColors.gray200.withValues(alpha: 0.45),
      boxShadow: CsShadows.soft,
      onTap: () => _openMatch(match),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(
                isHome
                    ? Icons.home_outlined
                    : Icons.directions_car_outlined,
                color: CsColors.gray900,
                size: 20,
              ),
              const SizedBox(width: 10),
              CsStatusChip(
                label: isHome ? 'Heim' : 'Auswärts',
                variant:
                    isHome ? CsChipVariant.info : CsChipVariant.amber,
              ),
              const SizedBox(width: 8),
              // Team name chip
              Expanded(
                child: Text(
                  teamName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: CsColors.gray500,
                    overflow: TextOverflow.ellipsis,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: CsColors.gray900,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Opponent
          Text(
            match['opponent'] ?? '?',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: CsColors.gray900,
            ),
          ),
          const SizedBox(height: 4),
          // Date + location
          Row(
            children: [
              const Icon(
                Icons.calendar_today,
                size: 13,
                color: CsColors.gray600,
              ),
              const SizedBox(width: 5),
              Text(
                _formatMatchDate(match),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: CsColors.gray600,
                ),
              ),
              if ((match['location'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.location_on_outlined,
                  size: 13,
                  color: CsColors.gray600,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    match['location'].toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: CsColors.gray600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
