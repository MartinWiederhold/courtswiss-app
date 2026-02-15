// ── DEV NOTE ──────────────────────────────────────────────────────
// UPDATED: AuthGate now shows AuthScreen when no session exists,
// instead of a loading spinner (we no longer auto-create anon).
// Invite links arriving without a session create an on-demand anon
// session so the invite can still be accepted.
// Password recovery deep links push ResetPasswordScreen.
// Modified as part of Auth/Onboarding v2 rework.
// ──────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/profile_service.dart';
import '../services/identity_link_service.dart';
import '../services/invite_service.dart';
import '../services/member_service.dart';
import '../services/deep_link_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/team_player_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';
import '../screens/auth_screen.dart';
import '../screens/main_tab_screen.dart';
import '../screens/team_detail_screen.dart';
import '../screens/claim_screen.dart';
import '../screens/reset_password_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<String>? _inviteSub;
  StreamSubscription<void>? _pwRecoverySub;

  /// True while we're creating an on-demand anon session for an invite.
  bool _creatingAnonForInvite = false;

  @override
  void initState() {
    super.initState();
    _listenForInviteWithoutSession();
    _listenForPasswordRecovery();
  }

  @override
  void dispose() {
    _inviteSub?.cancel();
    _pwRecoverySub?.cancel();
    super.dispose();
  }

  /// If an invite link arrives and there is NO session, create an anon
  /// session on-demand so the invite flow can proceed.
  void _listenForInviteWithoutSession() {
    _inviteSub = DeepLinkService.instance.onInviteToken.listen((token) async {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) return; // already logged in → handled by LoggedInScreen

      if (_creatingAnonForInvite) return; // prevent double-fire
      _creatingAnonForInvite = true;
      try {
        debugPrint('AuthGate: creating anon session for invite token');
        await Supabase.instance.client.auth.signInAnonymously();
        // Save the anon UID so we can migrate data later if user registers
        await IdentityLinkService.saveAnonUid();
        // The auth state change will rebuild the widget tree → LoggedInScreen
        // will pick up the pending invite token.
      } catch (e) {
        debugPrint('AuthGate: anon session creation failed: $e');
      } finally {
        _creatingAnonForInvite = false;
      }
    });
  }

  /// Password recovery deep links push the ResetPasswordScreen.
  void _listenForPasswordRecovery() {
    _pwRecoverySub = DeepLinkService.instance.onPasswordRecovery.listen((_) {
      if (!mounted) return;
      // Push ResetPasswordScreen on top of whatever is showing
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const LoggedInScreen();
        }

        // No session → show Auth screen (Login / Register)
        return const AuthScreen();
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  LoggedInScreen — wraps MainTabScreen + handles invites/push
// ══════════════════════════════════════════════════════════════════

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
        CsToast.info(context, message);
      },
    );
  }

  Future<void> _init() async {
    // Migrate anon data if this is a fresh login after an anon session
    try {
      final migrated = await IdentityLinkService.migrateIfNeeded();
      if (migrated) {
        debugPrint('LoggedInScreen: anon data migrated successfully');
      }
    } catch (e) {
      debugPrint('IdentityLinkService.migrateIfNeeded error: $e');
    }

    // Ensure profile exists
    try {
      await ProfileService.ensureProfile();
    } catch (e) {
      debugPrint('ensureProfile error: $e');
    }

    // Initialise FCM push notifications (after auth session exists)
    try {
      await PushService.initPush();
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
        'ACCEPT_INVITE result teamId=${result.teamId} joined=${result.joined}',
      );
      if (!mounted) return;

      // Pop any pushed screens back to root
      Navigator.of(context).popUntil((route) => route.isFirst);

      // Force TeamsScreen to rebuild and re-fetch
      setState(() => _refreshCounter++);

      if (result.joined) {
        // ── Check if team has player slots → ClaimScreen ──
        final hasSlots = await TeamPlayerService.hasPlayerSlots(result.teamId);
        final alreadyClaimed = await TeamPlayerService.getMyClaimedPlayer(
          result.teamId,
        );

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
              CsToast.success(context, 'Willkommen, $name!');
            }
          } else {
            CsToast.success(context, 'Spieler zugeordnet');
          }

          // Navigate to TeamDetailScreen
          _navigateToTeam(result.teamId, team);
        } else {
          // No player slots → old flow: mandatory name dialog
          final name = await _showMandatoryNameDialog(result.teamId);
          if (!mounted) return;

          if (name != null) {
            CsToast.success(context, 'Willkommen, $name!');
          }

          _navigateToTeam(result.teamId, null);
        }
      } else {
        CsToast.info(context, 'Du bist bereits Mitglied dieses Teams');
      }
    } catch (e) {
      debugPrint('acceptInvite failed: $e');
      if (!mounted) return;
      CsToast.error(context, 'Einladung konnte nicht angenommen werden.');
    }
  }

  Future<void> _navigateToTeam(
    String teamId,
    Map<String, dynamic>? preloadedTeam,
  ) async {
    try {
      final team =
          preloadedTeam ??
          await Supabase.instance.client
              .from('cs_teams')
              .select()
              .eq('id', teamId)
              .single();

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TeamDetailScreen(teamId: teamId, team: team),
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

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: CsMotion.sheet,
      builder: (ctx) {
        bool saving = false;
        String? errorText;

        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (ctx, setStateSheet) {
              final text = controller.text.trim();
              final isValid = text.length >= 2 && text.length <= 30;

              return Container(
                margin: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                decoration: const BoxDecoration(
                  color: CsColors.blackCard,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(CsRadii.xl),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Wie heisst du?',
                        style: CsTextStyles.onDarkPrimary.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bitte gib deinen Namen ein,\ndamit dein Team dich erkennt.',
                        style: CsTextStyles.onDarkSecondary.copyWith(
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: controller,
                        style: CsTextStyles.onDarkPrimary,
                        decoration: InputDecoration(
                          labelText: 'Dein Name im Team',
                          hintText: 'z.B. Max, Sandro, Martin W.',
                          errorText: errorText,
                          counterText: '${text.length}/30',
                          counterStyle: CsTextStyles.onDarkTertiary.copyWith(
                            fontSize: 11,
                          ),
                          labelStyle: CsTextStyles.onDarkSecondary,
                          hintStyle: CsTextStyles.onDarkTertiary,
                          prefixIcon: const Icon(
                            Icons.person_outline,
                            color: CsColors.gray400,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.07),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(CsRadii.md),
                            borderSide: BorderSide(
                              color:
                                  Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(CsRadii.md),
                            borderSide: const BorderSide(
                              color: CsColors.lime,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(CsRadii.md),
                            borderSide: const BorderSide(
                              color: CsColors.amber,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(CsRadii.md),
                            borderSide: const BorderSide(
                              color: CsColors.amber,
                              width: 1.5,
                            ),
                          ),
                        ),
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 30,
                        onChanged: (_) => setStateSheet(() {}),
                      ),
                      if (saving) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(CsRadii.md),
                          child: const LinearProgressIndicator(
                            color: CsColors.lime,
                            backgroundColor: CsColors.blackCard2,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      CsPrimaryButton(
                        label: 'Speichern',
                        icon: const Icon(Icons.check_rounded, size: 18),
                        onPressed: (!isValid || saving)
                            ? null
                            : () async {
                                final name = controller.text.trim();

                                if (name.length < 2) {
                                  setStateSheet(
                                    () => errorText =
                                        'Mindestens 2 Zeichen',
                                  );
                                  return;
                                }

                                setStateSheet(() {
                                  saving = true;
                                  errorText = null;
                                });

                                try {
                                  await MemberService.updateMyNickname(
                                    teamId,
                                    name,
                                  );
                                  savedName = name;
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  setStateSheet(() {
                                    saving = false;
                                    errorText = 'Name konnte nicht gespeichert werden.';
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
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
    return MainTabScreen(key: ValueKey(_refreshCounter));
  }
}
