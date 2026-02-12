import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/sport.dart';
import '../services/invite_service.dart';
import '../services/member_service.dart';
import '../services/avatar_service.dart';
import '../services/match_service.dart';
import '../services/notification_service.dart';
import '../services/team_player_service.dart';
import 'claim_screen.dart';
import 'create_match_screen.dart';
import 'match_detail_screen.dart';
import 'notifications_screen.dart';

class TeamDetailScreen extends StatefulWidget {
  final String teamId;
  final Map<String, dynamic> team;

  const TeamDetailScreen({
    super.key,
    required this.teamId,
    required this.team,
  });

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  static final _supabase = Supabase.instance.client;

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
    return _members.any(
        (m) => m['user_id'] == uid && m['role'] == 'captain');
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
    // Resolve avatars AFTER all parallel loads complete so that
    // both _members and _playerSlots (claimed_by) are available.
    await _resolveAvatarUrls();
  }

  // ── Notifications ────────────────────────────────────────

  Future<void> _loadUnreadCount() async {
    try {
      final count = await NotificationService.getUnreadCount();
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
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
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final rankCtrl = TextEditingController();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Spieler hinzufügen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstCtrl,
                decoration: const InputDecoration(labelText: 'Vorname *'),
                textCapitalization: TextCapitalization.words,
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: lastCtrl,
                decoration: const InputDecoration(labelText: 'Nachname *'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: rankCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ranking (z.B. 7)',
                  hintText: 'optional',
                ),
                keyboardType: TextInputType.number,
              ),
              if (saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final first = firstCtrl.text.trim();
                      final last = lastCtrl.text.trim();
                      if (first.isEmpty || last.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Vor- und Nachname sind Pflicht')),
                        );
                        return;
                      }
                      final rank = int.tryParse(rankCtrl.text.trim());

                      setStateDialog(() => saving = true);
                      try {
                        await TeamPlayerService.createPlayer(
                          teamId: widget.teamId,
                          firstName: first,
                          lastName: last,
                          ranking: rank,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setStateDialog(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Fehler: $e')),
                          );
                        }
                      }
                    },
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );

    // Refresh after dialog closes
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
                'user_id, role, nickname, is_playing, created_at, cs_app_profiles(display_name, email, avatar_path)')
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

        final userIds =
            members.map((m) => m['user_id'] as String).toSet().toList();

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

      // Avatar resolution is handled by _loadAll() after all parallel loads,
      // or explicitly after standalone _loadMembers() calls below.

      // Check forced nickname only if team has NO player slots
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
    if (_playerSlots.isNotEmpty) return; // skip if slots exist
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    final myMember = _members.where((m) => m['user_id'] == uid).firstOrNull;
    if (myMember == null) return;

    final nickname = myMember['nickname'] as String?;
    if (nickname == null ||
        RegExp(r'^Spieler \d+$').hasMatch(nickname)) {
      _forceNicknameDialog();
    }
  }

  Future<void> _forceNicknameDialog() async {
    if (_nicknameDialogShowing) return;
    _nicknameDialogShowing = true;

    final ctrl = TextEditingController();
    bool saving = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Wie heisst du?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Bitte gib deinen Namen ein,\ndamit dein Team dich erkennt.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    labelText: 'Dein Name im Team',
                    hintText: 'z.B. Max, Sandro, Martin W.',
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
            actions: [
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final name = ctrl.text.trim();
                        if (name.length < 2) {
                          setStateDialog(
                              () => errorText = 'Mindestens 2 Zeichen');
                          return;
                        }
                        setStateDialog(() {
                          saving = true;
                          errorText = null;
                        });
                        try {
                          await MemberService.updateMyNickname(
                              widget.teamId, name);
                          if (!mounted) return;
                          Navigator.pop(ctx);
                        } catch (e) {
                          setStateDialog(() {
                            saving = false;
                            errorText = 'Fehler: $e';
                          });
                        }
                      },
                child: const Text('Speichern'),
              ),
            ],
          ),
        ),
      ),
    );

    _nicknameDialogShowing = false;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Name gespeichert')),
      );
      _loadMembers().then((_) => _resolveAvatarUrls());
    }
  }

  // ── Nickname Edit ────────────────────────────────────────

  Future<void> _editNickname(Map<String, dynamic> member) async {
    final ctrl =
        TextEditingController(text: member['nickname'] as String? ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name ändern'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Dein Name im Team'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name aktualisiert ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  // ── Toggle is_player ─────────────────────────────────────

  Future<void> _toggleIsPlayer(Map<String, dynamic> member, bool value) async {
    final uid = member['user_id'] as String?;

    if (value) {
      // ── Turning ON: Captain wants to play ──
      // 1) Show ranking picker (mandatory)
      final ranking = await _showRankingPicker(uid);
      if (ranking == null) return; // cancelled → switch stays off

      try {
        await TeamPlayerService.upsertCaptainSlot(
          teamId: widget.teamId,
          ranking: ranking,
        );
        await Future.wait([_loadMembers(), _loadPlayerSlots()]);
        await _resolveAvatarUrls();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } else {
      // ── Turning OFF: Captain stops playing ──
      try {
        await TeamPlayerService.removeCaptainSlot(teamId: widget.teamId);
        await Future.wait([_loadMembers(), _loadPlayerSlots()]);
        await _resolveAvatarUrls();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  /// Ranking picker dialog – barrierDismissible: false.
  /// Returns selected ranking int, or null if cancelled.
  Future<int?> _showRankingPicker(String? uid) async {
    final ctrl = TextEditingController();

    // Pre-fill with existing ranking from claimed slot
    if (uid != null && _claimedMap.containsKey(uid)) {
      final existing = _claimedMap[uid]!['ranking'];
      if (existing != null) ctrl.text = existing.toString();
    }

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Dein Ranking'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Als spielender Captain brauchst du\n'
                  'ein Ranking für die Aufstellung.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    labelText: 'Ranking',
                    hintText: 'z.B. 7',
                    prefixText: 'R',
                    errorText: errorText,
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx), // cancel → null
                child: const Text('Abbrechen'),
              ),
              ElevatedButton(
                onPressed: () {
                  final val = int.tryParse(ctrl.text.trim());
                  if (val == null || val < 1 || val > 99) {
                    setStateDialog(
                        () => errorText = 'Bitte Zahl von 1–99 eingeben');
                    return;
                  }
                  Navigator.pop(ctx, val);
                },
                child: const Text('Speichern'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Invite Share ──────────────────────────────────────────

  Future<void> _shareInviteLink() async {
    try {
      final token = await InviteService.createInvite(widget.teamId);
      final teamName = widget.team['name'] ?? 'Team';
      final shareText = InviteService.buildShareText(token, teamName);

      // ignore: avoid_print
      print('INVITE_TOKEN=$token');
      // ignore: avoid_print
      print('INVITE_DEEP_LINK=${InviteService.buildDeepLink(token)}');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite token created ✅')),
      );

      await Share.share(shareText, subject: 'CourtSwiss Team Invite');
    } catch (e) {
      // ignore: avoid_print
      print('shareInviteLink failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Fehler beim Erstellen des Invite-Links: $e')),
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  String _memberDisplayName(Map<String, dynamic> member) {
    final userId = member['user_id'] as String?;

    // 1) Check claimed player slot first
    if (userId != null && _claimedMap.containsKey(userId)) {
      return TeamPlayerService.playerDisplayName(_claimedMap[userId]!);
    }

    // 2) Nickname from cs_team_members
    final nickname = member['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) return nickname;

    // 3) Check embedded profile from FK join
    final embedded = member['cs_app_profiles'];
    if (embedded is Map<String, dynamic>) {
      final name = embedded['display_name'] as String?;
      final email = embedded['email'] as String?;
      if (name != null && name.isNotEmpty && name != 'Spieler') return name;
      if (email != null && email.isNotEmpty) return email;
    }

    // 4) Check separate _profiles map (fallback path)
    if (userId != null && _profiles.containsKey(userId)) {
      final profile = _profiles[userId]!;
      final name = profile['display_name'] as String?;
      final email = profile['email'] as String?;
      if (name != null && name.isNotEmpty && name != 'Spieler') return name;
      if (email != null && email.isNotEmpty) return email;
    }

    // 5) Last resort: shortened user_id
    if (userId != null && userId.length > 8) {
      return '${userId.substring(0, 8)}…';
    }
    return userId ?? '–';
  }

  String _roleLabel(Map<String, dynamic> member) {
    final role = member['role'] as String?;
    final isPlaying = member['is_playing'] as bool? ?? true;

    switch (role) {
      case 'captain':
        return isPlaying ? 'Captain (spielend)' : 'Captain';
      case 'member':
        return 'Spieler';
      default:
        return role ?? '–';
    }
  }

  String _captainDisplay() {
    final captain =
        _members.where((m) => m['role'] == 'captain').firstOrNull;
    if (captain == null) return '—';
    return _memberDisplayName(captain);
  }

  /// Ranking string for a member (from player slot or cs_team_members).
  String _rankingStr(String userId) {
    final slot = _claimedMap[userId];
    if (slot != null) {
      final r = slot['ranking'];
      if (r != null) return 'R$r';
    }
    return '';
  }

  // ── Avatar ──────────────────────────────────────────────────

  /// Resolves avatar signed URLs for ALL relevant users:
  ///   – _members  (user_id)
  ///   – _playerSlots  (claimed_by, when != null)
  /// Fetches avatar_path from cs_app_profiles in one batch query.
  Future<void> _resolveAvatarUrls() async {
    // 1) Collect every user ID that might have an avatar
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

    // 2) Batch-query profiles for avatar_path
    try {
      final profileRows = await _supabase
          .from('cs_app_profiles')
          .select('user_id, avatar_path')
          .inFilter('user_id', allUserIds.toList());

      // ignore: avoid_print
      print('AVATAR_RESOLVE requested=${allUserIds.length} '
          'returned=${(profileRows as List).length}');

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

      // 3) Deduplicate paths and batch-resolve signed URLs
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

    AvatarService.createSignedUrl(path).then((newUrl) {
      if (mounted) {
        setState(() => _avatarUrls[userId] = newUrl);
      }
    }).catchError((e) {
      // ignore: avoid_print
      print('avatar refresh failed for $userId: $e');
    });
  }

  String _initials(Map<String, dynamic> member) {
    final userId = member['user_id'] as String?;

    // Use player slot initials if claimed
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profilbild aktualisiert ✅')),
      );

      _loadMembers().then((_) => _resolveAvatarUrls());
    } on AvatarUploadException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Hochladen: $e')),
      );
    }
  }

  // ── Bucket Setup Dialog ────────────────────────────────────
  Future<void> _showBucketSetupDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Storage Setup erforderlich'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Der Storage-Bucket "profile-photos" wurde '
                'noch nicht angelegt.\n'
                'Bitte folge diesen Schritten:',
              ),
              const SizedBox(height: 16),
              _setupStep('1', 'Supabase Dashboard → Storage → "New bucket"'),
              _setupStep('2', 'Name exakt: profile-photos'),
              _setupStep('3', 'Public: OFF (private)'),
              _setupStep(
                  '4', 'SQL Editor → untenstehende Policies ausführen'),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
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
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: AvatarService.setupSql),
              );
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text('SQL in Zwischenablage kopiert ✅')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('SQL kopieren'),
          ),
          TextButton(
            onPressed: () {
              AvatarService.resetBucketCache();
              Navigator.pop(ctx);
            },
            child: const Text('Schliessen'),
          ),
        ],
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
            backgroundColor: Colors.blue,
            child: Text(number,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
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
      final availRows =
          await MatchService.listAvailabilityBatch(matchIds);

      final counts = <String, Map<String, int>>{};
      for (final row in availRows) {
        final mid = row['match_id'] as String;
        final status = row['status'] as String;
        counts.putIfAbsent(
            mid, () => {'yes': 0, 'no': 0, 'maybe': 0});
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

  // ── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.team['name'] ?? 'Team'),
        actions: [
          Badge(
            label: Text('$_unreadCount'),
            isLabelVisible: _unreadCount > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Benachrichtigungen',
              onPressed: _openNotifications,
            ),
          ),
          IconButton(
            onPressed: _shareInviteLink,
            icon: const Icon(Icons.share),
            tooltip: 'Einladungslink teilen',
          ),
          IconButton(
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        children: [
          // ── Sport Header Banner ──
          _buildSportHeader(),

          // ── Team Info ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('Team', widget.team['name']),
                _infoRow('Club', widget.team['club_name']),
                _infoRow('Liga', widget.team['league']),
                _infoRow('Saison', widget.team['season_year']?.toString()),
                if (!_loading) _infoRow('Kapitän', _captainDisplay()),
              ],
            ),
          ),
          const Divider(),

          // ═══════════════════════════════════════════
          // ── KADER (Player Slots) ──────────────────
          // ═══════════════════════════════════════════
          if (_playerSlots.isNotEmpty) ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Kader (${_playerSlots.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (_isAdmin)
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1),
                      tooltip: 'Spieler hinzufügen',
                      onPressed: _addPlayerSlotDialog,
                    ),
                ],
              ),
            ),
            ..._buildPlayerSlotTiles(),
            const Divider(thickness: 2, height: 32),
          ] else if (_isAdmin) ...[
            // Show "add player" prompt when no slots exist yet
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Kader',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.person_add_alt_1),
                    tooltip: 'Spieler hinzufügen',
                    onPressed: _addPlayerSlotDialog,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Noch keine Spieler angelegt.\n'
                'Lege Spieler mit Name + Ranking an,\n'
                'damit sich Mitglieder zuordnen können.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            const Divider(thickness: 2, height: 32),
          ],

          // ═══════════════════════════════════════════
          // ── MITGLIEDER (Team Members) ─────────────
          // ═══════════════════════════════════════════
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Mitglieder (${_loading ? '…' : _members.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text('Fehler:\n$_error',
                    textAlign: TextAlign.center),
              ),
            )
          else if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Noch keine Mitglieder.')),
            )
          else
            ..._buildMemberTiles(),

          const Divider(thickness: 2, height: 32),

          // ═══════════════════════════════════════════
          // ── SPIELE ────────────────────────────────
          // ═══════════════════════════════════════════
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Spiele (${_matchesLoading ? '…' : _matches.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (_isAdmin)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Spiel hinzufügen',
                    onPressed: _createMatch,
                  ),
              ],
            ),
          ),

          if (_matchesLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_matches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Noch keine Spiele geplant.')),
            )
          else
            ..._buildMatchTiles(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Player Slot tiles ───────────────────────────────────

  List<Widget> _buildPlayerSlotTiles() {
    final tiles = <Widget>[];
    for (int i = 0; i < _playerSlots.length; i++) {
      tiles.add(_buildPlayerSlotTile(_playerSlots[i]));
      if (i < _playerSlots.length - 1) {
        tiles.add(const Divider(height: 1));
      }
    }
    return tiles;
  }

  Widget _buildPlayerSlotTile(Map<String, dynamic> slot) {
    final name = TeamPlayerService.playerDisplayName(slot);
    final ranking = TeamPlayerService.rankingLabel(slot);
    final claimedBy = slot['claimed_by'] as String?;
    final isClaimed = claimedBy != null;
    final uid = _supabase.auth.currentUser?.id;
    final isMySlot = claimedBy == uid;

    // Find avatar for claimed player
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

    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: isClaimed
            ? Colors.green.shade50
            : Colors.grey.shade200,
        backgroundImage:
            avatarUrl != null ? NetworkImage(avatarUrl) : null,
        onBackgroundImageError: avatarUrl != null && claimedBy != null
            ? (error, stack) => _onAvatarImageError(claimedBy)
            : null,
        child: avatarUrl == null
            ? Text(
                slotInitials,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isClaimed
                      ? Colors.green.shade700
                      : Colors.grey.shade500,
                ),
              )
            : null,
      ),
      title: Text(
        ranking.isNotEmpty ? '$name · $ranking' : name,
        style: TextStyle(
          fontWeight: isMySlot ? FontWeight.bold : FontWeight.normal,
          color: isClaimed ? null : Colors.grey.shade600,
        ),
      ),
      subtitle: Text(
        isClaimed
            ? (isMySlot ? '✅ Verbunden (du)' : '✅ Verbunden')
            : '⬜ Nicht zugeordnet',
        style: TextStyle(
          fontSize: 12,
          color: isClaimed ? Colors.green : Colors.grey,
        ),
      ),
      trailing: _isAdmin && !isClaimed
          ? PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') {
                  try {
                    await TeamPlayerService.deletePlayer(
                        slot['id'] as String);
                    _loadPlayerSlots();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fehler: $e')),
                    );
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'delete', child: Text('🗑️ Entfernen')),
              ],
            )
          : null,
    );
  }

  // ── Member tile builder ──────────────────────────────────

  List<Widget> _buildMemberTiles() {
    final tiles = <Widget>[];
    for (int i = 0; i < _members.length; i++) {
      tiles.add(_buildMemberTile(_members[i]));
      if (i < _members.length - 1) {
        tiles.add(const Divider(height: 1));
      }
    }
    return tiles;
  }

  Widget _buildMemberTile(Map<String, dynamic> m) {
    final uid = _supabase.auth.currentUser?.id;
    final memberUid = m['user_id'] as String? ?? '';
    final isMe = memberUid == uid;
    final isCaptainRow = m['role'] == 'captain';
    final avatarUrl = _avatarUrl(m);
    final rankStr = _rankingStr(memberUid);

    // Check if this member has claimed a slot
    final hasClaimed = _claimedMap.containsKey(memberUid);

    return ListTile(
      leading: GestureDetector(
        onTap: isMe ? _changeAvatar : null,
        child: CircleAvatar(
          radius: 22,
          backgroundColor: isCaptainRow
              ? Colors.amber.shade100
              : Colors.grey.shade200,
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
                    fontSize: 14,
                    color: isCaptainRow
                        ? Colors.amber.shade800
                        : Colors.grey.shade600,
                  ),
                )
              : null,
        ),
      ),
      title: Text(
        rankStr.isNotEmpty
            ? '${_memberDisplayName(m)} · $rankStr'
            : _memberDisplayName(m),
      ),
      subtitle: Text(
        hasClaimed
            ? '${_roleLabel(m)} · ✅ Zugeordnet'
            : _roleLabel(m),
      ),
      trailing: isMe
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCaptainRow)
                  Tooltip(
                    message: 'Ich spiele mit',
                    child: Switch.adaptive(
                      value: m['is_playing'] == true,
                      onChanged: (val) => _toggleIsPlayer(m, val),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.camera_alt, size: 20),
                  tooltip: 'Profilbild ändern',
                  onPressed: _changeAvatar,
                ),
                if (!hasClaimed && _playerSlots.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.link, size: 20),
                    tooltip: 'Spieler-Slot zuordnen',
                    onPressed: () => _openClaimScreen(),
                  ),
                if (!hasClaimed && _playerSlots.isEmpty)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: 'Name ändern',
                    onPressed: () => _editNickname(m),
                  ),
              ],
            )
          : null,
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

  List<Widget> _buildMatchTiles() {
    final tiles = <Widget>[];
    for (int i = 0; i < _matches.length; i++) {
      tiles.add(_buildMatchTile(_matches[i]));
      if (i < _matches.length - 1) {
        tiles.add(const Divider(height: 1));
      }
    }
    return tiles;
  }

  Widget _buildMatchTile(Map<String, dynamic> match) {
    final isHome = match['is_home'] == true;
    final counts = _matchAvailCounts[match['id']] ??
        {'yes': 0, 'no': 0, 'maybe': 0};

    return ListTile(
      leading: Icon(
        isHome ? Icons.home : Icons.directions_car,
        color: isHome ? Colors.blue : Colors.orange,
      ),
      title: Text(match['opponent'] ?? '?'),
      subtitle: Text(
        '${_formatMatchDate(match)}  •  ${isHome ? 'Heim' : 'Auswärts'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('✅${counts['yes']}',
              style: const TextStyle(fontSize: 12, color: Colors.green)),
          const SizedBox(width: 4),
          Text('❌${counts['no']}',
              style: const TextStyle(fontSize: 12, color: Colors.red)),
          const SizedBox(width: 4),
          Text('❓${counts['maybe']}',
              style:
                  const TextStyle(fontSize: 12, color: Colors.orange)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () => _openMatch(match),
    );
  }

  Widget _buildSportHeader() {
    final sportKey = widget.team['sport_key'] as String?;
    final sport = Sport.byKey(sportKey);
    final color = sport?.color ?? Colors.blueGrey;

    return SizedBox(
      height: 160,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image or gradient
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
                  colors: [
                    color.withValues(alpha: 0.6),
                    color,
                  ],
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
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          // Team name + sport label
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
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
                    Icon(sport?.icon ?? Icons.sports,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      sport?.label ?? 'Sport',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                      ),
                    ),
                    if ((widget.team['league'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '• ${widget.team['league']}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          shadows: [
                            Shadow(blurRadius: 4, color: Colors.black54)
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
          colors: [
            sport.color.withValues(alpha: 0.7),
            sport.color,
          ],
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value ?? '–')),
        ],
      ),
    );
  }
}
