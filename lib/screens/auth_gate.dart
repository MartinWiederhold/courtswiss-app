import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/profile_service.dart';
import '../services/invite_service.dart';
import '../services/member_service.dart';
import '../services/deep_link_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/team_player_service.dart';
import '../screens/teams_screen.dart';
import '../screens/team_detail_screen.dart';
import '../screens/claim_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const LoggedInScreen();
        }

        // With anonymous auth this should not happen;
        // safety-net: show a loading spinner while session is being created.
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class LoggedInScreen extends StatefulWidget {
  const LoggedInScreen({super.key});

  @override
  State<LoggedInScreen> createState() => _LoggedInScreenState();
}

class _LoggedInScreenState extends State<LoggedInScreen> {
  StreamSubscription<String>? _tokenSub;

  /// Incremented after each successful invite-accept to force TeamsScreen rebuild.
  int _refreshCounter = 0;

  /// Guard to prevent showing the name dialog more than once at a time.
  bool _nameDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _init();
    _listenForInviteTokens();
    _subscribeNotifications();
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    NotificationService.unsubscribe();
    PushService.dispose();
    super.dispose();
  }

  void _subscribeNotifications() {
    NotificationService.subscribe(
      onInsert: (notification) {
        if (!mounted) return;
        final message = NotificationService.formatMessage(notification);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔔 $message'),
            duration: const Duration(seconds: 4),
          ),
        );
      },
    );
  }

  Future<void> _init() async {
    // Ensure profile exists
    try {
      await ProfileService.ensureProfile();
    } catch (e) {
      debugPrint('ensureProfile error: $e');
    }

    // Initialise FCM push notifications (after auth session exists)
    try {
      await PushService.initPush();
      // Show FCM token in UI for debug (easy to copy from SnackBar)
      if (mounted && PushService.lastToken != null) {
        final token = PushService.lastToken!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(
              'FCM: ${token.substring(0, 30)}…',
              style: const TextStyle(fontSize: 11),
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'FULL',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('FCM Token'),
                    content: SelectableText(
                      token,
                      style: const TextStyle(fontSize: 12),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('PushService.initPush error: $e');
    }

    // Process pending token from deep link (app opened via link before login)
    final pending = DeepLinkService.instance.pendingToken;
    if (pending != null) {
      DeepLinkService.instance.clearPendingToken();
      await _acceptInviteToken(pending);
    }
  }

  void _listenForInviteTokens() {
    // Listen for deep links arriving while logged in
    _tokenSub = DeepLinkService.instance.onInviteToken.listen((token) {
      DeepLinkService.instance.clearPendingToken();
      _acceptInviteToken(token);
    });
  }

  Future<void> _acceptInviteToken(String token) async {
    // ignore: avoid_print
    print('ACCEPT_INVITE token=$token');
    try {
      final result = await InviteService.acceptInvite(token);
      // ignore: avoid_print
      print(
          'ACCEPT_INVITE result teamId=${result.teamId} joined=${result.joined}');
      if (!mounted) return;

      // Pop any pushed screens back to root
      Navigator.of(context).popUntil((route) => route.isFirst);

      // Force TeamsScreen to rebuild and re-fetch
      setState(() => _refreshCounter++);

      if (result.joined) {
        // ── Check if team has player slots → ClaimScreen ──
        final hasSlots =
            await TeamPlayerService.hasPlayerSlots(result.teamId);
        final alreadyClaimed =
            await TeamPlayerService.getMyClaimedPlayer(result.teamId);

        if (!mounted) return;

        if (hasSlots && alreadyClaimed == null) {
          // Team has player slots and user hasn't claimed one yet → ClaimScreen
          Map<String, dynamic>? team;
          try {
            team = await Supabase.instance.client
                .from('cs_teams')
                .select()
                .eq('id', result.teamId)
                .single();
          } catch (_) {}

          if (!mounted) return;

          final claimed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => ClaimScreen(
                teamId: result.teamId,
                teamName: team?['name'] ?? 'Team',
              ),
            ),
          );

          if (!mounted) return;

          if (claimed != true) {
            // User skipped claiming → show mandatory name dialog as fallback
            final name = await _showMandatoryNameDialog(result.teamId);
            if (!mounted) return;
            if (name != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✅ Willkommen, $name!')),
              );
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Spieler zugeordnet!')),
            );
          }

          // Navigate to TeamDetailScreen
          _navigateToTeam(result.teamId, team);
        } else {
          // No player slots → old flow: mandatory name dialog
          final name = await _showMandatoryNameDialog(result.teamId);
          if (!mounted) return;

          if (name != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('✅ Willkommen, $name!')),
            );
          }

          _navigateToTeam(result.teamId, null);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('ℹ️ Du bist bereits Mitglied dieses Teams')),
        );
      }
    } catch (e) {
      debugPrint('acceptInvite failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Invite fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _navigateToTeam(
      String teamId, Map<String, dynamic>? preloadedTeam) async {
    try {
      final team = preloadedTeam ??
          await Supabase.instance.client
              .from('cs_teams')
              .select()
              .eq('id', teamId)
              .single();

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TeamDetailScreen(
            teamId: teamId,
            team: team,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Failed to navigate to team detail: $e');
    }
  }

  // ── Mandatory name dialog (blocking, non-dismissible) ──────────

  Future<String?> _showMandatoryNameDialog(String teamId) async {
    if (_nameDialogShowing) return null;
    _nameDialogShowing = true;

    final controller = TextEditingController();
    String? savedName;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool saving = false;
        String? errorText;

        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (ctx, setStateDialog) {
              final text = controller.text.trim();
              final isValid = text.length >= 2 && text.length <= 30;

              return AlertDialog(
                title: const Text('Wie heisst du?'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Bitte gib deinen Namen ein,\n'
                      'damit dein Team dich erkennt.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText: 'Dein Name im Team',
                        hintText: 'z.B. Max, Sandro, Martin W.',
                        errorText: errorText,
                        counterText: '${text.length}/30',
                      ),
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 30,
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    if (saving) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
                actions: [
                  ElevatedButton(
                    onPressed: (!isValid || saving)
                        ? null
                        : () async {
                            final name = controller.text.trim();

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
                                  teamId, name);
                              savedName = name;
                              if (ctx.mounted) Navigator.pop(ctx);
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
              );
            },
          ),
        );
      },
    );

    _nameDialogShowing = false;
    controller.dispose();
    return savedName;
  }

  @override
  Widget build(BuildContext context) {
    return TeamsScreen(key: ValueKey(_refreshCounter));
  }
}
