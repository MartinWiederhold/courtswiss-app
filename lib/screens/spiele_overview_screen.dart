// ── DEV NOTE ──────────────────────────────────────────────────────
// New screen: Global "Spiele" tab showing all matches across all teams.
// Created as part of bottom-tab-bar navigation refactor.
// Data: MatchService.listAllMyMatches() → cs_matches joined with cs_teams.
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
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
    // Reload when a team is deleted/left or a match is created/deleted
    TeamService.teamChangeNotifier.addListener(_onDataChanged);
    MatchService.matchChangeNotifier.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    TeamService.teamChangeNotifier.removeListener(_onDataChanged);
    MatchService.matchChangeNotifier.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    // Team or match changed → reload matches from DB
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
    final l = AppLocalizations.of(context)!;

    return CsScaffoldList(
      appBar: CsGlassAppBar(
        title: l.gamesTitle,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: l.refresh,
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
                        title: l.connectionError,
                        subtitle: l.dataLoadError,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(l.tryAgain),
                      ),
                    ],
                  ),
                )
              : _matches.isEmpty
                  ? CsEmptyState(
                      icon: Icons.event_outlined,
                      title: l.noGamesYet,
                      subtitle: l.noGamesSubtitle,
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
    final l = AppLocalizations.of(context)!;
    final isHome = match['is_home'] as bool?;
    final teamName = match['team_name'] as String? ?? '–';

    final IconData homeIcon;
    final String homeLabel;
    final CsChipVariant homeVariant;
    if (isHome == true) {
      homeIcon = Icons.home_outlined;
      homeLabel = l.home;
      homeVariant = CsChipVariant.info;
    } else if (isHome == false) {
      homeIcon = Icons.directions_car_outlined;
      homeLabel = l.away;
      homeVariant = CsChipVariant.amber;
    } else {
      homeIcon = Icons.help_outline;
      homeLabel = l.unknownPlayer; // "Unbekannt"
      homeVariant = CsChipVariant.neutral;
    }

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
                homeIcon,
                color: CsColors.gray900,
                size: 20,
              ),
              const SizedBox(width: 10),
              CsStatusChip(
                label: homeLabel,
                variant: homeVariant,
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
