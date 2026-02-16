import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/push_service.dart' show navigatorKey;
import '../services/team_player_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';

/// Screen shown after a player joins a team via invite link.
/// Displays unclaimed player slots – user picks which one they are.
class ClaimScreen extends StatefulWidget {
  final String teamId;
  final String teamName;

  const ClaimScreen({super.key, required this.teamId, required this.teamName});

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
      final players = await TeamPlayerService.listUnclaimedPlayers(
        widget.teamId,
      );
      if (!mounted) return;
      setState(() {
        _players = players;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final rootCtx = navigatorKey.currentContext;
      if (rootCtx != null) {
        CsToast.error(rootCtx, AppLocalizations.of(rootCtx)!.genericError);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredPlayers {
    if (_search.isEmpty) return _players;
    final q = _search.toLowerCase();
    return _players.where((p) {
      final name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'
          .toLowerCase();
      return name.contains(q);
    }).toList();
  }

  Future<void> _claim(Map<String, dynamic> player) async {
    final name = TeamPlayerService.playerDisplayName(player);
    final ranking = TeamPlayerService.rankingLabel(player);
    final label = ranking.isNotEmpty ? '$name · $ranking' : name;

    final l = AppLocalizations.of(context)!;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => CsBottomSheetForm(
        title: l.claimConfirmTitle,
        ctaLabel: l.claimConfirmCta,
        onCta: () => Navigator.pop(ctx, true),
        secondaryLabel: l.cancel,
        onSecondary: () => Navigator.pop(ctx, false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.person, size: 40, color: CsColors.blue),
            const SizedBox(height: 12),
            Text(
              l.claimConfirmBody(label),
              style: CsTextStyles.bodySmall.copyWith(fontSize: 15),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _claiming = true);

    // Capture toast message before the await – l10n depends on context
    // which may be stale after the async gap.
    final welcomeToastFn = l.claimWelcomeToast;
    final errorMsg = l.genericError;

    try {
      final result = await TeamPlayerService.claimPlayer(
        teamId: widget.teamId,
        playerId: player['id'] as String,
      );
      if (!mounted) return;

      final fullName = result['full_name'] as String? ?? name;

      // Use root navigator context for toast + pop – safe after async.
      final rootCtx = navigatorKey.currentContext;
      if (rootCtx != null) {
        CsToast.success(rootCtx, welcomeToastFn(fullName));
      }

      // Pop back with success = true via root navigator.
      navigatorKey.currentState?.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _claiming = false);
      final rootCtx = navigatorKey.currentContext;
      if (rootCtx != null) {
        CsToast.error(rootCtx, errorMsg);
      }
    }
  }

  /// User is not in the pre-created list → skip claiming.
  void _skipClaim() {
    Navigator.pop(context, false); // false = not claimed
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPlayers;
    final l = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      child: CsScaffoldList(
        appBar: CsGlassAppBar(
          title: l.claimWhoAreYou,
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: _claiming ? null : _skipClaim,
              child: Text(l.commonSkip),
            ),
          ],
        ),
        body: _loading
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  children: [
                    const CsSkeletonCard(),
                    const SizedBox(height: 12),
                    ...List.generate(4, (_) => const CsSkeletonCard()),
                  ],
                ),
              )
            : Column(
                children: [
                  // ── Team info card ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: CsCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.group,
                            color: CsColors.lime,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.teamName,
                            style: CsTextStyles.onDarkPrimary.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l.claimPickName,
                            textAlign: TextAlign.center,
                            style: CsTextStyles.onDarkSecondary.copyWith(
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Search ──
                  if (_players.length > 5)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: l.claimSearchHint,
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

                  const SizedBox(height: 4),

                  // ── Player list ──
                  if (_players.isEmpty)
                    Expanded(
                      child: Center(
                        child: CsEmptyState(
                          icon: Icons.person_off,
                          title: l.claimNoSlotTitle,
                          subtitle: l.claimNoSlotBody,
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final player = filtered[index];
                          return CsAnimatedEntrance.staggered(
                            index: index,
                            child: _buildPlayerTile(player),
                          );
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

    return CsCard(
      onTap: _claiming ? null : () => _claim(player),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: CsColors.blue.withValues(alpha: 0.15),
            child: Text(
              _initials(player),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: CsColors.blue,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: CsTextStyles.onDarkPrimary.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (ranking.isNotEmpty)
                  Text(
                    ranking,
                    style: CsTextStyles.onDarkTertiary.copyWith(fontSize: 12),
                  ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: CsColors.lime,
            size: 20,
          ),
        ],
      ),
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
