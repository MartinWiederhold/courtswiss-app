import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/ranking_data.dart';
import '../models/sport.dart';
import '../services/invite_service.dart';
import '../services/member_service.dart';
import '../services/avatar_service.dart';
import '../services/match_service.dart';
import '../services/event_service.dart';
import '../services/push_service.dart' show navigatorKey;
import '../services/team_player_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/ranking_selector.dart';
import '../widgets/ui/ui.dart';
import 'claim_screen.dart';
import 'create_match_screen.dart';
import 'event_inbox_screen.dart';
import 'match_detail_screen.dart';

class TeamDetailScreen extends StatefulWidget {
  final String teamId;
  final Map<String, dynamic> team;

  const TeamDetailScreen({super.key, required this.teamId, required this.team});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  static final _supabase = Supabase.instance.client;

  // ── Tab state ──
  int _tabIndex = 0;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _members = [];
  Map<String, Map<String, dynamic>> _profiles = {};

  /// user_id → signed avatar URL (resolved after member load)
  Map<String, String> _avatarUrls = {};

  /// user_id → storage path (for signed URL refresh)
  Map<String, String> _avatarPaths = {};
  bool _nicknameDialogShowing = false;

  // ── Player Slots ──
  List<Map<String, dynamic>> _playerSlots = [];

  /// user_id → cs_team_players row (for claimed players)
  Map<String, Map<String, dynamic>> _claimedMap = {};

  // ── Notifications ──
  int _unreadCount = 0;

  // ── Matches state ──
  List<Map<String, dynamic>> _matches = [];
  bool _matchesLoading = true;
  Map<String, Map<String, int>> _matchAvailCounts = {};

  bool get _isAdmin {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;
    if (widget.team['created_by'] == uid) return true;
    return _members.any((m) => m['user_id'] == uid && m['role'] == 'captain');
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadMembers(),
      _loadPlayerSlots(),
      _loadMatches(),
      _loadUnreadCount(),
    ]);
    await _resolveAvatarUrls();
  }

  // ── Notifications ────────────────────────────────────────

  Future<void> _loadUnreadCount() async {
    try {
      final count = await EventService.fetchUnreadCount();
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EventInboxScreen()),
    );
    _loadUnreadCount();
  }

  // ── Player Slots ────────────────────────────────────────

  Future<void> _loadPlayerSlots() async {
    try {
      final slots = await TeamPlayerService.listPlayers(widget.teamId);
      if (!mounted) return;
      setState(() {
        _playerSlots = slots;
        _claimedMap = TeamPlayerService.buildClaimedMap(slots);
      });
    } catch (e) {
      // ignore: avoid_print
      print('_loadPlayerSlots error: $e');
    }
  }

  Future<void> _addPlayerSlotDialog() async {
    final l = AppLocalizations.of(context)!;
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    String selectedCountry = 'CH';
    int? selectedRanking;
    String? rankingError;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setStateBs) {
          // Use sheetCtx (outer route context) for MediaQuery so the
          // StatefulBuilder element does NOT register as a MediaQuery
          // dependent – prevents '_dependents.isEmpty' assertion when
          // keyboard dismisses during exit animation.
          final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
          final safeBottom = MediaQuery.of(sheetCtx).padding.bottom;

          return ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CsRadii.xl),
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: CsColors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(CsRadii.xl),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: CsColors.gray300,
                        borderRadius: BorderRadius.circular(CsRadii.full),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.addPlayer,
                            style: CsTextStyles.titleLarge,
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                            color: CsColors.gray500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        16,
                        20,
                        16 + bottomInset,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l.firstName, style: CsTextStyles.labelSmall),
                          const SizedBox(height: 6),
                          TextField(
                            controller: firstCtrl,
                            decoration: InputDecoration(
                              hintText: l.firstNameHint,
                            ),
                            textCapitalization: TextCapitalization.words,
                            autofocus: true,
                          ),
                          const SizedBox(height: 16),
                          Text(l.lastName, style: CsTextStyles.labelSmall),
                          const SizedBox(height: 6),
                          TextField(
                            controller: lastCtrl,
                            decoration: InputDecoration(
                              hintText: l.lastNameHint,
                            ),
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 16),
                          RankingSelector(
                            country: selectedCountry,
                            rankingValue: selectedRanking,
                            rankingError: rankingError,
                            enabled: !saving,
                            onCountryChanged: (c) => setStateBs(() {
                              selectedCountry = c;
                              selectedRanking = null;
                              rankingError = null;
                            }),
                            onRankingChanged: (v) => setStateBs(() {
                              selectedRanking = v;
                              rankingError = null;
                            }),
                          ),
                          if (saving) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // CTA
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      12 + safeBottom,
                    ),
                    decoration: BoxDecoration(
                      color: CsColors.white,
                      border: Border(
                        top: BorderSide(
                          color: CsColors.gray200.withValues(alpha: 0.6),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: CsPrimaryButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final first = firstCtrl.text.trim();
                              final last = lastCtrl.text.trim();
                              if (first.isEmpty || last.isEmpty) {
                                CsToast.info(ctx, l.enterFirstAndLastName);
                                return;
                              }
                              if (selectedRanking == null) {
                                setStateBs(() {
                                  rankingError = l.selectRanking;
                                });
                                return;
                              }

                              setStateBs(() => saving = true);
                              try {
                                await TeamPlayerService.createPlayer(
                                  teamId: widget.teamId,
                                  firstName: first,
                                  lastName: last,
                                  ranking: selectedRanking,
                                );
                                // Use root navigator – ctx may be
                                // deactivated after the async gap.
                                navigatorKey.currentState?.pop();
                              } catch (e) {
                                if (!ctx.mounted) return;
                                setStateBs(() => saving = false);
                                final rootCtx = navigatorKey.currentContext;
                                if (rootCtx != null) {
                                  CsToast.error(rootCtx, l.genericError);
                                }
                              }
                            },
                      label: l.addButton,
                      loading: saving,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    _loadPlayerSlots();
  }

  // ── Data ──────────────────────────────────────────────────

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<Map<String, dynamic>> members;

      try {
        final rows = await _supabase
            .from('cs_team_members')
            .select(
              'user_id, role, nickname, is_playing, created_at, cs_app_profiles(display_name, email, avatar_path)',
            )
            .eq('team_id', widget.teamId)
            .order('created_at', ascending: true);

        members = List<Map<String, dynamic>>.from(rows);
        _profiles = {};
      } catch (embedError) {
        // ignore: avoid_print
        print('_loadMembers embed failed, fallback: $embedError');

        final memberRows = await _supabase
            .from('cs_team_members')
            .select('user_id, role, nickname, is_playing, created_at')
            .eq('team_id', widget.teamId)
            .order('created_at', ascending: true);

        members = List<Map<String, dynamic>>.from(memberRows);

        final userIds = members
            .map((m) => m['user_id'] as String)
            .toSet()
            .toList();

        Map<String, Map<String, dynamic>> profileMap = {};

        if (userIds.isNotEmpty) {
          final profileRows = await _supabase
              .from('cs_app_profiles')
              .select('user_id, display_name, email, avatar_path')
              .inFilter('user_id', userIds);

          for (final p in List<Map<String, dynamic>>.from(profileRows)) {
            profileMap[p['user_id'] as String] = p;
          }
        }

        _profiles = profileMap;
      }

      if (!mounted) return;
      setState(() {
        _members = members;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _playerSlots.isEmpty) _checkNicknameRequired();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Forced Nickname (only for teams WITHOUT player slots) ──

  void _checkNicknameRequired() {
    if (_nicknameDialogShowing) return;
    if (_playerSlots.isNotEmpty) return;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    final myMember = _members.where((m) => m['user_id'] == uid).firstOrNull;
    if (myMember == null) return;

    final nickname = myMember['nickname'] as String?;
    if (nickname == null || RegExp(r'^Spieler \d+$').hasMatch(nickname)) {
      _forceNicknameDialog();
    }
  }

  Future<void> _forceNicknameDialog() async {
    if (_nicknameDialogShowing) return;
    _nicknameDialogShowing = true;

    final l = AppLocalizations.of(context)!;
    final ctrl = TextEditingController();
    bool saving = false;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setStateBs) {
          // Use sheetCtx (outer route context) for MediaQuery so the
          // StatefulBuilder element does NOT register as a MediaQuery
          // dependent – prevents '_dependents.isEmpty' assertion when
          // keyboard dismisses during exit animation.
          final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
          final safeBottom = MediaQuery.of(sheetCtx).padding.bottom;

          return PopScope(
            canPop: false,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(CsRadii.xl),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: CsColors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(CsRadii.xl),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 4),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: CsColors.gray300,
                          borderRadius: BorderRadius.circular(CsRadii.full),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.whatsYourName,
                              style: CsTextStyles.titleLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          16,
                          20,
                          16 + bottomInset,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l.nicknamePrompt,
                              style: CsTextStyles.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l.yourTeamName,
                              style: CsTextStyles.labelSmall,
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: ctrl,
                              decoration: InputDecoration(
                                hintText: l.nicknameHint,
                                errorText: errorText,
                                counterText: '',
                              ),
                              autofocus: true,
                              textCapitalization: TextCapitalization.words,
                              maxLength: 30,
                            ),
                            if (saving) ...[
                              const SizedBox(height: 8),
                              const LinearProgressIndicator(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        12,
                        20,
                        12 + safeBottom,
                      ),
                      decoration: BoxDecoration(
                        color: CsColors.white,
                        border: Border(
                          top: BorderSide(
                            color: CsColors.gray200.withValues(alpha: 0.6),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: CsPrimaryButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final name = ctrl.text.trim();
                                if (name.length < 2) {
                                  setStateBs(
                                    () => errorText = l.minTwoChars,
                                  );
                                  return;
                                }
                                setStateBs(() {
                                  saving = true;
                                  errorText = null;
                                });
                                try {
                                  await MemberService.updateMyNickname(
                                    widget.teamId,
                                    name,
                                  );
                                  // Use root navigator – ctx may be
                                  // deactivated after the async gap.
                                  navigatorKey.currentState?.pop();
                                } catch (e) {
                                  if (!ctx.mounted) return;
                                  setStateBs(() {
                                    saving = false;
                                    errorText = l.nicknameSaveError;
                                  });
                                }
                              },
                        label: l.save,
                        loading: saving,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    _nicknameDialogShowing = false;

    if (mounted) {
      CsToast.success(context, l.nameSaved);
      _loadMembers().then((_) => _resolveAvatarUrls());
    }
  }

  // ── Nickname Edit ────────────────────────────────────────

  Future<void> _editNickname(Map<String, dynamic> member) async {
    final l = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(
      text: member['nickname'] as String? ?? '',
    );

    final newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final safeBottom = MediaQuery.of(ctx).padding.bottom;

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(CsRadii.xl),
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: CsColors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(CsRadii.xl),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: CsColors.gray300,
                      borderRadius: BorderRadius.circular(CsRadii.full),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.changeName,
                          style: CsTextStyles.titleLarge,
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                          color: CsColors.gray500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.yourTeamName,
                        style: CsTextStyles.labelSmall,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: ctrl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + safeBottom),
                  decoration: BoxDecoration(
                    color: CsColors.white,
                    border: Border(
                      top: BorderSide(
                        color: CsColors.gray200.withValues(alpha: 0.6),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: CsPrimaryButton(
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    label: l.save,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (newName == null || newName.isEmpty) return;

    try {
      await _supabase
          .from('cs_team_members')
          .update({'nickname': newName})
          .eq('team_id', widget.teamId)
          .eq('user_id', member['user_id']);

      await _loadMembers();
      await _resolveAvatarUrls();
      if (!mounted) return;
      CsToast.success(context, l.nameUpdated);
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l.nameSaveError);
    }
  }

  // ── Toggle is_player ─────────────────────────────────────

  bool _togglingIsPlayer = false;

  bool get _captainPlays {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;
    return _claimedMap.containsKey(uid);
  }

  Future<void> _toggleIsPlayer(Map<String, dynamic> member, bool value) async {
    if (_togglingIsPlayer) return;
    _togglingIsPlayer = true;

    final previousPlaying = member['is_playing'];
    setState(() => member['is_playing'] = value);

    try {
      if (value) {
        await TeamPlayerService.upsertCaptainSlot(
          teamId: widget.teamId,
          ranking: null,
        );
      } else {
        await TeamPlayerService.removeCaptainSlot(teamId: widget.teamId);
      }

      if (!mounted) return;
      await Future.wait([_loadMembers(), _loadPlayerSlots()]);
      if (!mounted) return;
      await _resolveAvatarUrls();
    } catch (e) {
      if (!mounted) return;
      setState(() => member['is_playing'] = previousPlaying);
      CsToast.error(context, AppLocalizations.of(context)!.changeSaveError);
    } finally {
      _togglingIsPlayer = false;
    }
  }

  // ── Invite Share ──────────────────────────────────────────

  Future<void> _shareInviteLink() async {
    final l = AppLocalizations.of(context)!;
    try {
      final token = await InviteService.createInvite(widget.teamId);
      final teamName = widget.team['name'] ?? 'Team';
      final shareText = InviteService.buildShareText(token, teamName);

      // ignore: avoid_print
      print('INVITE_TOKEN=$token');
      // ignore: avoid_print
      print('INVITE_DEEP_LINK=${InviteService.buildDeepLink(token)}');

      if (!mounted) return;
      CsToast.success(context, l.inviteLinkCreated);

      await Share.share(shareText, subject: l.shareSubject);
    } catch (e) {
      // ignore: avoid_print
      print('shareInviteLink failed: $e');
      if (!mounted) return;
      CsToast.error(context, l.inviteLinkError);
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  String _memberDisplayName(Map<String, dynamic> member) {
    final userId = member['user_id'] as String?;

    if (userId != null && _claimedMap.containsKey(userId)) {
      return TeamPlayerService.playerDisplayName(_claimedMap[userId]!);
    }

    final nickname = member['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) return nickname;

    final embedded = member['cs_app_profiles'];
    if (embedded is Map<String, dynamic>) {
      final name = embedded['display_name'] as String?;
      final email = embedded['email'] as String?;
      if (name != null && name.isNotEmpty && name != 'Spieler') return name;
      if (email != null && email.isNotEmpty) return email;
    }

    if (userId != null && _profiles.containsKey(userId)) {
      final profile = _profiles[userId]!;
      final name = profile['display_name'] as String?;
      final email = profile['email'] as String?;
      if (name != null && name.isNotEmpty && name != 'Spieler') return name;
      if (email != null && email.isNotEmpty) return email;
    }

    if (userId != null && userId.length > 8) {
      return '${userId.substring(0, 8)}…';
    }
    return userId ?? '–';
  }

  String _roleLabel(Map<String, dynamic> member, AppLocalizations l) {
    final role = member['role'] as String?;
    final uid = member['user_id'] as String?;

    switch (role) {
      case 'captain':
        final plays = uid != null && _claimedMap.containsKey(uid);
        return plays ? l.chipCaptainPlaying : l.chipCaptain;
      case 'member':
        return l.chipPlayer;
      default:
        return role ?? '–';
    }
  }

  String _captainDisplay() {
    final captain = _members.where((m) => m['role'] == 'captain').firstOrNull;
    if (captain == null) return '—';
    return _memberDisplayName(captain);
  }

  String _rankingStr(String userId) {
    final slot = _claimedMap[userId];
    if (slot != null) {
      final r = slot['ranking'];
      if (r is int) return RankingData.label(r);
      if (r is num) return RankingData.label(r.toInt());
    }
    return '';
  }

  // ── Avatar ──────────────────────────────────────────────────

  Future<void> _resolveAvatarUrls() async {
    final allUserIds = <String>{};

    for (final m in _members) {
      final uid = m['user_id'] as String?;
      if (uid != null) allUserIds.add(uid);
    }
    for (final slot in _playerSlots) {
      final claimedBy = slot['claimed_by'] as String?;
      if (claimedBy != null) allUserIds.add(claimedBy);
    }

    if (allUserIds.isEmpty) {
      if (mounted) setState(() => _avatarUrls = {});
      return;
    }

    try {
      final profileRows = await _supabase
          .from('cs_app_profiles')
          .select('user_id, avatar_path')
          .inFilter('user_id', allUserIds.toList());

      // ignore: avoid_print
      print(
        'AVATAR_RESOLVE requested=${allUserIds.length} '
        'returned=${(profileRows as List).length}',
      );

      final pathsByUid = <String, String>{};
      for (final p in List<Map<String, dynamic>>.from(profileRows)) {
        final uid = p['user_id'] as String?;
        final path = AvatarService.avatarPathFromProfile(p);
        if (uid != null && path != null) pathsByUid[uid] = path;
      }

      // ignore: avoid_print
      print('AVATAR_RESOLVE withPath=${pathsByUid.length}');

      _avatarPaths = Map.of(pathsByUid);

      if (pathsByUid.isEmpty) {
        if (mounted) setState(() => _avatarUrls = {});
        return;
      }

      final uniquePaths = pathsByUid.values.toSet().toList();
      final signedMap = await AvatarService.createSignedUrls(uniquePaths);

      final result = <String, String>{};
      for (final entry in pathsByUid.entries) {
        final signed = signedMap[entry.value];
        if (signed != null) result[entry.key] = signed;
      }

      if (mounted) setState(() => _avatarUrls = result);
    } catch (e) {
      // ignore: avoid_print
      print('_resolveAvatarUrls error: $e');
    }
  }

  String? _avatarUrl(Map<String, dynamic> member) {
    final userId = member['user_id'] as String?;
    if (userId == null) return null;
    return _avatarUrls[userId];
  }

  void _onAvatarImageError(String userId) {
    final path = _avatarPaths[userId];
    if (path == null) return;

    setState(() => _avatarUrls.remove(userId));

    AvatarService.createSignedUrl(path)
        .then((newUrl) {
          if (mounted) {
            setState(() => _avatarUrls[userId] = newUrl);
          }
        })
        .catchError((e) {
          // ignore: avoid_print
          print('avatar refresh failed for $userId: $e');
        });
  }

  String _initials(Map<String, dynamic> member) {
    final userId = member['user_id'] as String?;

    if (userId != null && _claimedMap.containsKey(userId)) {
      final slot = _claimedMap[userId]!;
      final f = (slot['first_name'] as String? ?? '');
      final l = (slot['last_name'] as String? ?? '');
      if (f.isNotEmpty && l.isNotEmpty) {
        return '${f[0]}${l[0]}'.toUpperCase();
      }
    }

    final name = _memberDisplayName(member);
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (name.length >= 2) return name.substring(0, 2).toUpperCase();
    if (name.isNotEmpty) return name[0].toUpperCase();
    return '?';
  }

  Future<void> _changeAvatar() async {
    final l = AppLocalizations.of(context)!;
    final bucketOk = await AvatarService.checkBucketExists();
    if (!bucketOk) {
      if (!mounted) return;
      await _showBucketSetupDialog();
      return;
    }

    try {
      final path = await AvatarService.pickAndUploadAvatar();
      if (path == null) return;
      if (!mounted) return;

      final uid = _supabase.auth.currentUser?.id;
      if (uid != null) {
        try {
          final signedUrl = await AvatarService.createSignedUrl(path);
          if (mounted) {
            setState(() {
              _avatarPaths[uid] = path;
              _avatarUrls[uid] = signedUrl;
            });
          }
        } catch (_) {}
      }

      if (!mounted) return;
      CsToast.success(context, l.avatarUpdated);

      _loadMembers().then((_) => _resolveAvatarUrls());
    } on AvatarUploadException catch (e) {
      if (!mounted) return;
      CsToast.error(context, e.userMessage);
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l.avatarUploadError);
    }
  }

  // ── Bucket Setup Dialog ────────────────────────────────────
  Future<void> _showBucketSetupDialog() async {
    final l = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CsColors.black.withValues(alpha: 0.35),
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CsRadii.xl),
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: CsColors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(CsRadii.xl),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CsColors.gray300,
                    borderRadius: BorderRadius.circular(CsRadii.full),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.storageSetupRequired,
                        style: CsTextStyles.titleLarge,
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          AvatarService.resetBucketCache();
                          Navigator.pop(ctx);
                        },
                        color: CsColors.gray500,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.storageSetupBody,
                        style: CsTextStyles.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      _setupStep('1', l.storageStep1),
                      _setupStep('2', l.storageStep2),
                      _setupStep('3', l.storageStep3),
                      _setupStep('4', l.storageStep4),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: CsColors.gray100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: CsColors.gray300),
                        ),
                        child: SelectableText(
                          AvatarService.setupSql,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: CsSecondaryButton(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: AvatarService.setupSql),
                            );
                            CsToast.success(ctx, l.sqlCopied);
                          },
                          label: l.copySql,
                          icon: const Icon(Icons.copy, size: 18),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CsPrimaryButton(
                          onPressed: () {
                            AvatarService.resetBucketCache();
                            Navigator.pop(ctx);
                          },
                          label: l.closeButton,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _setupStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: CsColors.black,
            child: Text(
              number,
              style: const TextStyle(color: CsColors.lime, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: CsTextStyles.bodyMedium)),
        ],
      ),
    );
  }

  // ── Matches ──────────────────────────────────────────────

  Future<void> _loadMatches() async {
    setState(() => _matchesLoading = true);
    try {
      final matches = await MatchService.listMatches(widget.teamId);

      final matchIds = matches.map((m) => m['id'] as String).toList();
      final availRows = await MatchService.listAvailabilityBatch(matchIds);

      final counts = <String, Map<String, int>>{};
      for (final row in availRows) {
        final mid = row['match_id'] as String;
        final status = row['status'] as String;
        counts.putIfAbsent(mid, () => {'yes': 0, 'no': 0, 'maybe': 0});
        counts[mid]![status] = (counts[mid]![status] ?? 0) + 1;
      }

      if (!mounted) return;
      setState(() {
        _matches = matches;
        _matchAvailCounts = counts;
      });
    } catch (e) {
      // ignore: avoid_print
      print('_loadMatches error: $e');
    } finally {
      if (mounted) setState(() => _matchesLoading = false);
    }
  }

  Future<void> _createMatch() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateMatchScreen(teamId: widget.teamId),
      ),
    );
    if (created == true) _loadMatches();
  }

  Future<void> _openMatch(Map<String, dynamic> match) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MatchDetailScreen(
          matchId: match['id'] as String,
          teamId: widget.teamId,
          match: match,
        ),
      ),
    );
    _loadMatches();
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

  Future<void> _refreshAll() async {
    await _loadAll();
  }

  // ══════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tabLabels = [l.teamDetailTabOverview, l.teamDetailTabTeam, l.teamDetailTabMatches];

    return CsScaffoldList(
      appBar: CsGlassAppBar(
        title: '',
        actions: [
          Badge(
            label: Text('$_unreadCount'),
            isLabelVisible: _unreadCount > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: l.notificationsTooltip,
              onPressed: _openNotifications,
            ),
          ),
          IconButton(
            onPressed: _shareInviteLink,
            icon: const Icon(Icons.share_outlined),
            tooltip: l.shareInviteTooltip,
          ),
          IconButton(onPressed: _refreshAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      // FAB: visible only for captain on "Team" tab (index 1)
      floatingActionButton: _isAdmin && _tabIndex == 1
          ? FloatingActionButton(
              onPressed: _addPlayerSlotDialog,
              tooltip: l.addPlayer,
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,
      body: Column(
        children: [
          // ── Sport Header Banner ──
          _buildSportHeader(),

          // ── Segment Tabs ──
          CsSegmentTabs(
            labels: tabLabels,
            selectedIndex: _tabIndex,
            onChanged: (i) => setState(() => _tabIndex = i),
          ),

          // ── Tab Content ──
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeIn,
              switchOutCurve: Curves.easeOut,
              child: _buildTabContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabIndex) {
      case 0:
        return _buildOverviewTab();
      case 1:
        return _buildPlayersTab();
      case 2:
        return _buildMatchesTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Tab 0: Übersicht ──────────────────────────────────────

  Widget _buildOverviewTab() {
    final l = AppLocalizations.of(context)!;
    final claimed = _playerSlots.where((s) => s['claimed_by'] != null).length;
    final total = _playerSlots.length;

    return ListView(
      key: const ValueKey('overview'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        CsAnimatedEntrance(
          child: CsCard(
            backgroundColor: CsColors.white,
            borderColor: CsColors.gray200.withValues(alpha: 0.45),
            boxShadow: CsShadows.soft,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: CsColors.gray900,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: CsColors.black,
                        borderRadius:
                            BorderRadius.circular(CsRadii.full),
                      ),
                      child: Text(
                        l.teamInfoBadge,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: CsColors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _infoRow(l.teamInfoTeam, widget.team['name']),
                _infoRow(l.teamInfoClub, widget.team['club_name']),
                _infoRow(l.teamInfoLeague, widget.team['league']),
                _infoRow(l.teamInfoSeason, widget.team['season_year']?.toString()),
                if (!_loading) _infoRow(l.teamInfoCaptain, _captainDisplay()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── Quick-Settings (Captain toggle + Invite link) ──
        ..._buildSettingsCards(),

        if (total > 0)
          CsAnimatedEntrance(
            delay: const Duration(milliseconds: 80),
            child: CsCard(
              backgroundColor: CsColors.white,
              borderColor: CsColors.gray200.withValues(alpha: 0.45),
              boxShadow: CsShadows.soft,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CsProgressRow(
                    label: l.playersLabel,
                    value: '$total',
                    progress: 1.0,
                    color: CsColors.lime,
                    onDark: false,
                  ),
                  const SizedBox(height: 12),
                  CsProgressRow(
                    label: l.connectedLabel,
                    value: '$claimed / $total',
                    progress: total > 0 ? claimed / total : 0,
                    color: CsColors.emerald,
                    onDark: false,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (_matches.isNotEmpty)
          CsAnimatedEntrance(
            delay: const Duration(milliseconds: 160),
            child: CsCard(
              backgroundColor: CsColors.white,
              borderColor: CsColors.gray200.withValues(alpha: 0.45),
              boxShadow: CsShadows.soft,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.sports_score,
                        color: CsColors.gray900,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: CsColors.black,
                          borderRadius:
                              BorderRadius.circular(CsRadii.full),
                        ),
                        child: Text(
                          l.nextMatch,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: CsColors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _matches.first['opponent'] ?? '?',
                    style: const TextStyle(
                      fontSize: 16,
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
                        _formatMatchDate(_matches.first),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: CsColors.gray600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Tab 1: Spieler ────────────────────────────────────────

  Widget _buildPlayersTab() {
    final l = AppLocalizations.of(context)!;
    final claimed = _playerSlots.where((s) => s['claimed_by'] != null).length;
    final total = _playerSlots.length;

    return ListView(
      key: const ValueKey('players'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // Progress rows
        if (total > 0) ...[
          CsCard(
            backgroundColor: CsColors.white,
            borderColor: CsColors.gray200.withValues(alpha: 0.45),
            boxShadow: CsShadows.soft,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                CsProgressRow(
                  label: l.playersLabel,
                  value: '$total',
                  progress: 1.0,
                  color: CsColors.lime,
                  onDark: false,
                ),
                const SizedBox(height: 12),
                CsProgressRow(
                  label: l.connectedLabel,
                  value: '$claimed / $total',
                  progress: total > 0 ? claimed / total : 0,
                  color: CsColors.emerald,
                  onDark: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Player slots section
        if (_playerSlots.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: CsSectionHeader(
                  title: l.teamSectionCount('${_playerSlots.length}'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1, size: 20),
                  tooltip: l.addPlayer,
                  onPressed: _addPlayerSlotDialog,
                ),
            ],
          ),
          ...List.generate(_playerSlots.length, (i) {
            return CsAnimatedEntrance.staggered(
              index: i,
              child: _buildPlayerSlotTile(_playerSlots[i]),
            );
          }),
          const SizedBox(height: 16),
        ] else if (_isAdmin) ...[
          Row(
            children: [
              Expanded(
                child: CsSectionHeader(
                  title: l.teamDetailTabTeam,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.person_add_alt_1, size: 20),
                tooltip: l.addPlayer,
                onPressed: _addPlayerSlotDialog,
              ),
            ],
          ),
          CsLightCard(
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: CsColors.gray400),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.noPlayersEmptyBody,
                    style: CsTextStyles.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Members section
        CsSectionHeader(
          title: l.connectedPlayersTitle(_loading ? '…' : '${_members.length}'),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),

        if (_loading)
          ...List.generate(3, (_) => const CsSkeletonCard())
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
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
                    onPressed: _loadMembers,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(l.tryAgain),
                  ),
                ],
              ),
            ),
          )
        else if (_members.isEmpty)
          CsEmptyState(
            icon: Icons.people_outline,
            title: l.noPlayersYet,
            subtitle: l.shareInviteSubtitle,
          )
        else
          ...List.generate(_members.length, (i) {
            return CsAnimatedEntrance.staggered(
              index: i,
              child: _buildMemberTile(_members[i]),
            );
          }),
      ],
    );
  }

  // ── Tab 2: Spiele ─────────────────────────────────────────

  Widget _buildMatchesTab() {
    final l = AppLocalizations.of(context)!;
    return ListView(
      key: const ValueKey('matches'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (_matchesLoading)
          ...List.generate(3, (_) => const CsSkeletonCard())
        else if (_matches.isEmpty)
          CsEmptyState(
            icon: Icons.event_outlined,
            title: l.noGamesYet,
            subtitle: l.noMatchesTeamSubtitle,
            ctaLabel: _isAdmin ? l.createMatch : null,
            onCtaTap: _isAdmin ? _createMatch : null,
          )
        else ...[
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CsPrimaryButton(
                onPressed: _createMatch,
                label: l.createMatch,
                icon: const Icon(Icons.add, size: 20),
              ),
            ),
          ...List.generate(_matches.length, (i) {
            return CsAnimatedEntrance.staggered(
              index: i,
              child: _buildMatchTile(_matches[i]),
            );
          }),
        ],
      ],
    );
  }

  // ── Settings cards (shown in Übersicht) ──────────────────

  List<Widget> _buildSettingsCards() {
    final l = AppLocalizations.of(context)!;
    final uid = _supabase.auth.currentUser?.id;
    final myMember =
        _members.where((m) => m['user_id'] == uid).firstOrNull;
    final isCaptain = myMember?['role'] == 'captain';

    return [
      // Captain plays toggle
      if (isCaptain) ...[
        CsAnimatedEntrance(
          delay: const Duration(milliseconds: 40),
          child: CsCard(
            backgroundColor: CsColors.white,
            borderColor: CsColors.gray200.withValues(alpha: 0.45),
            boxShadow: CsShadows.soft,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.captainPlaysTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CsColors.gray900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.captainPlaysSubtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: CsColors.gray600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch.adaptive(
                  value: _captainPlays,
                  onChanged: myMember != null && !_togglingIsPlayer
                      ? (val) => _toggleIsPlayer(myMember, val)
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],

      // Invite link
      CsAnimatedEntrance(
        delay: const Duration(milliseconds: 60),
        child: CsCard(
          backgroundColor: CsColors.white,
          borderColor: CsColors.gray200.withValues(alpha: 0.45),
          boxShadow: CsShadows.soft,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.link,
                    size: 18,
                    color: CsColors.gray900,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l.inviteLinkTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: CsColors.gray900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l.inviteLinkDescription,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: CsColors.gray600,
                ),
              ),
              const SizedBox(height: 12),
              CsPrimaryButton(
                onPressed: _shareInviteLink,
                label: l.shareLink,
                icon: const Icon(Icons.share, size: 18),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
    ];
  }

  // ── Player Slot tiles ───────────────────────────────────

  Widget _buildPlayerSlotTile(Map<String, dynamic> slot) {
    final loc = AppLocalizations.of(context)!;
    final name = TeamPlayerService.playerDisplayName(slot);
    final ranking = TeamPlayerService.rankingLabel(slot);
    final claimedBy = slot['claimed_by'] as String?;
    final isClaimed = claimedBy != null;
    final uid = _supabase.auth.currentUser?.id;
    final isMySlot = claimedBy == uid;

    String? avatarUrl;
    if (claimedBy != null) {
      avatarUrl = _avatarUrls[claimedBy];
    }

    final slotInitials = () {
      final f = (slot['first_name'] as String? ?? '');
      final l = (slot['last_name'] as String? ?? '');
      if (f.isNotEmpty && l.isNotEmpty) return '${f[0]}${l[0]}'.toUpperCase();
      if (f.isNotEmpty) return f[0].toUpperCase();
      return '?';
    }();

    return CsCard(
      backgroundColor: CsColors.white,
      borderColor: CsColors.gray200.withValues(alpha: 0.45),
      boxShadow: CsShadows.soft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: isClaimed
                ? CsColors.lime.withValues(alpha: 0.15)
                : CsColors.gray100,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            onBackgroundImageError: avatarUrl != null && claimedBy != null
                ? (error, stack) => _onAvatarImageError(claimedBy)
                : null,
            child: avatarUrl == null
                ? Text(
                    slotInitials,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isClaimed ? CsColors.gray900 : CsColors.gray400,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          // Name + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ranking.isNotEmpty ? '$name · $ranking' : name,
                  style: TextStyle(
                    fontWeight: isMySlot ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                    color: CsColors.gray900,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (isClaimed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: CsColors.lime,
                          borderRadius:
                              BorderRadius.circular(CsRadii.full),
                        ),
                        child: Text(
                          isMySlot ? loc.chipYou : loc.chipConnected,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: CsColors.black,
                            letterSpacing: 0.2,
                          ),
                        ),
                      )
                    else
                      CsStatusChip(
                        label: loc.chipOpen,
                        variant: CsChipVariant.neutral,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_isAdmin && !isClaimed)
            PopupMenuButton<String>(
              popUpAnimationStyle: CsMotion.dialog,
              iconColor: CsColors.gray500,
              onSelected: (value) async {
                if (value == 'delete') {
                  try {
                    await TeamPlayerService.deletePlayer(slot['id'] as String);
                    _loadPlayerSlots();
                  } catch (e) {
                    if (!mounted) return;
                    CsToast.error(context, loc.actionError);
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'delete', child: Text(loc.removePlayer)),
              ],
            ),
        ],
      ),
    );
  }

  // ── Member tile builder ──────────────────────────────────

  Widget _buildMemberTile(Map<String, dynamic> m) {
    final l = AppLocalizations.of(context)!;
    final uid = _supabase.auth.currentUser?.id;
    final memberUid = m['user_id'] as String? ?? '';
    final isMe = memberUid == uid;
    final isCaptainRow = m['role'] == 'captain';
    final avatarUrl = _avatarUrl(m);
    final rankStr = _rankingStr(memberUid);

    final hasClaimed = _claimedMap.containsKey(memberUid);

    return CsCard(
      backgroundColor: CsColors.white,
      borderColor: CsColors.gray200.withValues(alpha: 0.45),
      boxShadow: CsShadows.soft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: isMe ? _changeAvatar : null,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: isCaptainRow
                  ? CsColors.lime.withValues(alpha: 0.15)
                  : CsColors.gray100,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
              onBackgroundImageError: avatarUrl != null
                  ? (error, stack) => _onAvatarImageError(memberUid)
                  : null,
              child: avatarUrl == null
                  ? Text(
                      _initials(m),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isCaptainRow ? CsColors.gray900 : CsColors.gray400,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rankStr.isNotEmpty
                      ? '${_memberDisplayName(m)} · $rankStr'
                      : _memberDisplayName(m),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                    color: CsColors.gray900,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Role chip
                    if (isCaptainRow)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: CsColors.lime,
                          borderRadius:
                              BorderRadius.circular(CsRadii.full),
                        ),
                        child: Text(
                          _roleLabel(m, l),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: CsColors.black,
                            letterSpacing: 0.2,
                          ),
                        ),
                      )
                    else
                      CsStatusChip(
                        label: _roleLabel(m, l),
                        variant: CsChipVariant.neutral,
                      ),
                    if (hasClaimed) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: CsColors.black,
                          borderRadius:
                              BorderRadius.circular(CsRadii.full),
                        ),
                        child: Text(
                          l.chipAssigned,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: CsColors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isMe)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.camera_alt,
                    size: 18,
                    color: CsColors.gray500,
                  ),
                  tooltip: l.changeAvatarTooltip,
                  onPressed: _changeAvatar,
                ),
                if (!hasClaimed && _playerSlots.isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.link,
                      size: 18,
                      color: CsColors.gray500,
                    ),
                    tooltip: l.claimSlotTooltip,
                    onPressed: () => _openClaimScreen(),
                  ),
                if (!hasClaimed && _playerSlots.isEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.edit,
                      size: 18,
                      color: CsColors.gray500,
                    ),
                    tooltip: l.changeNameTooltip,
                    onPressed: () => _editNickname(m),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openClaimScreen() async {
    final claimed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClaimScreen(
          teamId: widget.teamId,
          teamName: widget.team['name'] ?? 'Team',
        ),
      ),
    );
    if (claimed == true) {
      await Future.wait([_loadPlayerSlots(), _loadMembers()]);
      await _resolveAvatarUrls();
    }
  }

  // ── Match tile builder ───────────────────────────────────

  Widget _buildMatchTile(Map<String, dynamic> match) {
    final l = AppLocalizations.of(context)!;
    final isHome = match['is_home'] == true;
    final counts =
        _matchAvailCounts[match['id']] ?? {'yes': 0, 'no': 0, 'maybe': 0};

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
                isHome ? Icons.home_outlined : Icons.directions_car_outlined,
                color: CsColors.gray900,
                size: 20,
              ),
              const SizedBox(width: 10),
              CsStatusChip(
                label: isHome ? l.home : l.away,
                variant: isHome ? CsChipVariant.info : CsChipVariant.amber,
              ),
              const Spacer(),
              // Availability mini counts
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _miniCount(Icons.check_circle_outline, counts['yes'] ?? 0),
                  const SizedBox(width: 10),
                  _miniCount(Icons.cancel_outlined, counts['no'] ?? 0),
                  const SizedBox(width: 10),
                  _miniCount(Icons.help_outline, counts['maybe'] ?? 0),
                ],
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
          // Title
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

  Widget _miniCount(IconData icon, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildSportHeader() {
    final sportKey = widget.team['sport_key'] as String?;
    final sport = Sport.byKey(sportKey);
    final color = sport?.color ?? Colors.blueGrey;

    return SizedBox(
      height: 140,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (sport != null)
            Image.asset(
              sport.assetPath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => _sportGradient(sport),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.6), color],
                ),
              ),
            ),
          // Overlay gradient for text readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
          // Team name + sport label
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.team['name'] ?? 'Team',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      sport?.icon ?? Icons.sports,
                      color: Colors.white70,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      sport?.label ?? 'Sport',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black54),
                        ],
                      ),
                    ),
                    if ((widget.team['league'] ?? '')
                        .toString()
                        .isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '• ${widget.team['league']}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          shadows: [
                            Shadow(blurRadius: 4, color: Colors.black54),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sportGradient(Sport sport) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [sport.color.withValues(alpha: 0.7), sport.color],
        ),
      ),
      child: Center(
        child: Icon(
          sport.icon,
          size: 64,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CsColors.gray600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '–',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CsColors.gray900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
