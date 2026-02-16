import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_localizations.dart';
import '../models/sport.dart';
import '../services/team_service.dart';
import '../services/event_service.dart';
import '../theme/cs_theme.dart';
import '../constants/app_constants.dart';
import '../widgets/ui/ui.dart';
import 'auth_screen.dart';
import 'create_team_screen.dart';
import 'team_detail_screen.dart';
import 'event_inbox_screen.dart';

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

  // ═══════════════════════════════════════════════════════════
  //  Quick-Start Guide
  // ═══════════════════════════════════════════════════════════

  List<String> _guideSteps(AppLocalizations l) => [
    l.guideStep1,
    l.guideStep2,
    l.guideStep3,
    l.guideStep4,
    l.guideStep5,
    l.guideStep6,
  ];

  /// Builds the numbered guide list (used in the empty-state card).
  Widget _buildGuideContent({bool showTitle = true}) {
    final l = AppLocalizations.of(context)!;
    final steps = _guideSteps(l);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTitle) ...[
          Text(
            l.howItWorks,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: CsColors.gray900,
            ),
          ),
          const SizedBox(height: 12),
        ],
        ...List.generate(steps.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CsColors.lime,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: CsColors.gray900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    steps[i],
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: CsColors.gray800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEmptyState() {
    final l = AppLocalizations.of(context)!;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Premium icon circle
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: CsColors.gray100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.groups_outlined,
                size: 32,
                color: CsColors.gray400,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l.welcomeTitle(kAppName),
              style: CsTextStyles.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l.welcomeSubtitle,
              style: CsTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Guide in a clean light CsCard (white bg, no accent bar)
            CsCard(
              backgroundColor: CsColors.white,
              borderColor: const Color(0xFFEDEDED),
              padding: const EdgeInsets.all(20),
              child: _buildGuideContent(),
            ),

          ],
        ),
      ),
    );
  }

  void _showGuideBottomSheet() {
    final l = AppLocalizations.of(context)!;
    final steps = _guideSteps(l);

    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: CsMotion.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CsRadii.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CsColors.gray300,
                    borderRadius: BorderRadius.circular(CsRadii.full),
                  ),
                ),
              ),
              Text(l.howItWorks, style: CsTextStyles.titleLarge),
              const SizedBox(height: 16),
              ...List.generate(steps.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CsColors.black,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: CsColors.lime,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          steps[i],
                          style: CsTextStyles.bodyMedium.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: CsSecondaryButton(
                  onPressed: () => Navigator.pop(ctx),
                  label: l.understood,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Navigation
  // ═══════════════════════════════════════════════════════════

  Future<void> _openInbox() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EventInboxScreen()),
    );
    _loadUnreadCount();
  }

  Future<void> _createTeamFlow() async {
    // Gate: anonymous users must register/login before creating a team
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || (user.isAnonymous)) {
      await _showAccountRequiredGate();
      return;
    }

    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateTeamScreen()),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  /// Shows a bottom sheet telling anon users they need an account to create teams.
  Future<void> _showAccountRequiredGate() async {
    final l = AppLocalizations.of(context)!;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: CsColors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CsRadii.xl)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CsColors.gray300,
                    borderRadius: BorderRadius.circular(CsRadii.full),
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: CsColors.lime.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_add_outlined,
                    color: CsColors.gray900,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l.accountRequired,
                  style: CsTextStyles.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  l.accountRequiredBody,
                  style: CsTextStyles.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                CsPrimaryButton(
                  label: l.registerLogin,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  onPressed: () {
                    // Close the sheet first, then push AuthScreen
                    // with showClose so the user can return.
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AuthScreen(showClose: true),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                CsSecondaryButton(
                  onPressed: () => Navigator.pop(ctx),
                  label: l.cancel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteTeam(Map<String, dynamic> team) async {
    final l = AppLocalizations.of(context)!;
    final teamId = team['id'] as String;
    final teamName = team['name'] ?? 'Team';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: CsColors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CsRadii.xl)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CsColors.gray300,
                    borderRadius: BorderRadius.circular(CsRadii.full),
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: CsColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: CsColors.error,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(l.deleteTeamTitle, style: CsTextStyles.titleLarge),
                const SizedBox(height: 8),
                Text(
                  l.deleteTeamBody(teamName),
                  style: CsTextStyles.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CsColors.error,
                      foregroundColor: CsColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(CsRadii.md),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(l.delete),
                  ),
                ),
                const SizedBox(height: 8),
                CsSecondaryButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  label: l.cancel,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return false;

    try {
      await TeamService.deleteTeam(teamId);
      if (!mounted) return true;
      setState(() => _teams.removeWhere((t) => t['id'] == teamId));
      CsToast.success(context, l.teamDeleted(teamName));
      return true;
    } catch (e) {
      if (!mounted) return false;
      CsToast.error(context, l.teamDeleteError);
      return false;
    }
  }

  Future<bool> _confirmLeaveTeam(Map<String, dynamic> team) async {
    final l = AppLocalizations.of(context)!;
    final teamId = team['id'] as String;
    final teamName = team['name'] ?? 'Team';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: CsColors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(CsRadii.xl)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CsColors.gray300,
                    borderRadius: BorderRadius.circular(CsRadii.full),
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: CsColors.blue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.logout,
                    color: CsColors.blue,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(l.removeTeamTitle, style: CsTextStyles.titleLarge),
                const SizedBox(height: 8),
                Text(
                  l.removeTeamBody(teamName),
                  style: CsTextStyles.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CsColors.blue,
                      foregroundColor: CsColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(CsRadii.md),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(l.remove),
                  ),
                ),
                const SizedBox(height: 8),
                CsSecondaryButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  label: l.cancel,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return false;

    try {
      await TeamService.leaveTeam(teamId);
      if (!mounted) return true;
      setState(() => _teams.removeWhere((t) => t['id'] == teamId));
      CsToast.success(context, l.teamRemoved(teamName));
      return true;
    } catch (e) {
      if (!mounted) return false;
      CsToast.error(context, l.teamRemoveError);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Accent color helper
  // ═══════════════════════════════════════════════════════════

  Color _accentForSport(Sport? sport) {
    if (sport == null) return CsColors.lime;
    final key = sport.key;
    if (key == 'tennis' || key == 'badminton' || key == 'squash') {
      return CsColors.lime;
    }
    if (key == 'football' || key == 'volleyball' || key == 'basketball' || key == 'handball') {
      return CsColors.blue;
    }
    if (key == 'hockey' || key == 'unihockey') return CsColors.amber;
    return CsColors.lime;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return CsScaffoldList(
      appBar: CsGlassAppBar(
        title: l.myTeams,
        automaticallyImplyLeading: false,
        actions: [
          Badge(
            label: Text('$_unreadEventCount'),
            isLabelVisible: _unreadEventCount > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: l.notifications,
              onPressed: _openInbox,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: l.howItWorks,
            onPressed: _showGuideBottomSheet,
          ),
          IconButton(
            onPressed: () {
              _load();
              _loadUnreadCount();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FloatingActionButton(
          onPressed: _createTeamFlow,
          child: const Icon(Icons.add),
        ),
      ),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                children: List.generate(
                  4,
                  (_) => const CsSkeletonCard(),
                ),
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
              : _teams.isEmpty
                  ? _buildEmptyState()
                  : _buildSegmentedList(),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Segmented list: "Eigene Teams" vs "Geteilte Teams"
  // ═══════════════════════════════════════════════════════════

  Widget _buildSegmentedList() {
    final l = AppLocalizations.of(context)!;
    final ownTeams =
        _teams.where((t) => t['is_owner'] == true).toList();
    final sharedTeams =
        _teams.where((t) => t['is_owner'] != true).toList();

    int globalIndex = 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // ── Eigene Teams ────────────────────────────────
        if (ownTeams.isNotEmpty) ...[
          _buildSectionHeader(l.ownTeams, Icons.shield_outlined),
          ...ownTeams.map((t) {
            final idx = globalIndex++;
            return _buildTeamCard(t, idx);
          }),
          const SizedBox(height: 16),
        ],

        // ── Geteilte Teams ──────────────────────────────
        if (sharedTeams.isNotEmpty) ...[
          _buildSectionHeader(l.sharedTeams, Icons.group_outlined),
          ...sharedTeams.map((t) {
            final idx = globalIndex++;
            return _buildTeamCard(t, idx);
          }),
        ],

        // (No hint text when only shared teams exist – keeps UI clean)
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: CsColors.gray500),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CsColors.gray500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamCard(Map<String, dynamic> t, int animIndex) {
    final l = AppLocalizations.of(context)!;
    final teamId = t['id'] as String;
    final sportKey = t['sport_key'] as String?;
    final sport = Sport.byKey(sportKey);
    final accent = _accentForSport(sport);
    final isOwner = t['is_owner'] == true;

    return CsAnimatedEntrance.staggered(
      index: animIndex,
      child: Dismissible(
        key: ValueKey(teamId),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: isOwner ? CsColors.error : CsColors.blue,
            borderRadius: BorderRadius.circular(CsRadii.lg),
          ),
          child: Icon(
            isOwner ? Icons.delete : Icons.logout,
            color: Colors.white,
          ),
        ),
        confirmDismiss: (_) =>
            isOwner ? _confirmDeleteTeam(t) : _confirmLeaveTeam(t),
        child: CsCard(
          backgroundColor: CsColors.white,
          borderColor: CsColors.gray200.withValues(alpha: 0.45),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 20,
              spreadRadius: 0,
              offset: Offset(0, 6),
            ),
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
          splashColor: CsColors.gray200.withValues(alpha: 0.25),
          highlightColor: CsColors.gray100.withValues(alpha: 0.5),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TeamDetailScreen(teamId: teamId, team: t),
              ),
            );
            _load();
          },
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: icon + chips
              Row(
                children: [
                  Icon(
                    sport?.icon ?? Icons.sports,
                    color: CsColors.gray900,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  if (sport != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius:
                            BorderRadius.circular(CsRadii.full),
                      ),
                      child: Text(
                        sport.label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: CsColors.black,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  if ((t['league'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0B0B),
                        borderRadius:
                            BorderRadius.circular(CsRadii.full),
                      ),
                      child: Text(
                        t['league'].toString(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: CsColors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right,
                    color: CsColors.gray900,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                t['name'] ?? '',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: CsColors.gray900,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 13,
                    color: CsColors.gray600,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    l.season(t['season_year']?.toString() ?? ''),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: CsColors.gray600,
                    ),
                  ),
                  if ((t['club_name'] ?? '')
                      .toString()
                      .isNotEmpty) ...[
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.business,
                      size: 13,
                      color: CsColors.gray600,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        t['club_name'].toString(),
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
        ),
      ),
    );
  }
}
