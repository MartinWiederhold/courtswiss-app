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
import '../l10n/app_localizations.dart';
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
  StreamSubscription<AuthState>? _authEventSub;

  /// True while we're creating an on-demand anon session for an invite.
  bool _creatingAnonForInvite = false;

  @override
  void initState() {
    super.initState();
    _listenForInviteWithoutSession();
    _listenForAuthEvents();
  }

  @override
  void dispose() {
    _inviteSub?.cancel();
    _authEventSub?.cancel();
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

  /// Listen for auth events — specifically password recovery.
  ///
  /// When the user clicks a password-reset deep link
  /// (`io.courtswiss://reset-password?code=...`), `supabase_flutter`
  /// automatically exchanges the PKCE code for a session and fires
  /// [AuthChangeEvent.passwordRecovery].  We react by pushing the
  /// [ResetPasswordScreen].
  void _listenForAuthEvents() {
    _authEventSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      debugPrint('AuthGate: auth event=${data.event}');
      if (data.event == AuthChangeEvent.passwordRecovery) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
        );
      }
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

  /// Guard to prevent concurrent invite processing (deep link can fire twice).
  bool _processingInvite = false;

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
        final rootCtx = navigatorKey.currentContext;
        if (rootCtx == null) return;
        final l = AppLocalizations.of(rootCtx);
        final message = NotificationService.formatMessage(notification, l);
        CsToast.info(rootCtx, message);
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
    // Guard against concurrent invite processing (deep link can fire twice).
    if (_processingInvite) return;
    _processingInvite = true;

    // ignore: avoid_print
    print('ACCEPT_INVITE token=$token');
    try {
      final result = await InviteService.acceptInvite(token);
      // ignore: avoid_print
      print(
        'ACCEPT_INVITE result teamId=${result.teamId} joined=${result.joined}',
      );
      if (!mounted) return;

      // Capture navigator via global key – safe across async gaps.
      final nav = navigatorKey.currentState;

      // Pop any pushed screens back to root
      nav?.popUntil((route) => route.isFirst);

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

          final claimed = await nav?.push<bool>(
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
            _showToast(CsToast.success, name != null ? 'Willkommen, $name!' : null);
          } else {
            _showToast(CsToast.success, 'Spieler zugeordnet');
          }

          // Navigate to TeamDetailScreen
          _navigateToTeam(result.teamId, team);
        } else {
          // No player slots → old flow: mandatory name dialog
          final name = await _showMandatoryNameDialog(result.teamId);
          if (!mounted) return;

          _showToast(CsToast.success, name != null ? 'Willkommen, $name!' : null);
          _navigateToTeam(result.teamId, null);
        }
      } else {
        _showToast(CsToast.info, 'Du bist bereits Mitglied dieses Teams');
      }
    } catch (e) {
      debugPrint('acceptInvite failed: $e');
      if (!mounted) return;
      _showToast(CsToast.error, 'Einladung konnte nicht angenommen werden.');
    } finally {
      _processingInvite = false;
    }
  }

  /// Show a toast using the global [navigatorKey] context – safe after async gaps.
  void _showToast(void Function(BuildContext, String) toastFn, String? message) {
    if (message == null) return;
    final ctx = navigatorKey.currentContext;
    if (ctx != null) toastFn(ctx, message);
  }

  Future<void> _navigateToTeam(
    String teamId,
    Map<String, dynamic>? preloadedTeam,
  ) async {
    // Wait one frame so any pending route exit animations (sheet pop,
    // ClaimScreen pop) are fully processed before we push a new route.
    // Pushing in the same frame as a pop can corrupt the navigator
    // overlay's _children list → '_children.contains(child)' assertion.
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    await completer.future;

    if (!mounted) return;

    try {
      final team =
          preloadedTeam ??
          await Supabase.instance.client
              .from('cs_teams')
              .select()
              .eq('id', teamId)
              .single();

      if (!mounted) return;
      navigatorKey.currentState?.push(
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

    // Capture the root navigator BEFORE showing the sheet – safe for
    // post-await usage even if the sheet's local context is deactivated.
    final rootNav = navigatorKey.currentState;

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: CsMotion.sheet,
      builder: (sheetCtx) {
        bool saving = false;
        String? errorText;

        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (ctx, setStateSheet) {
              final text = controller.text.trim();
              final isValid = text.length >= 2 && text.length <= 30;

              // Use sheetCtx (outer route context) for MediaQuery so
              // the StatefulBuilder element does NOT register as a
              // MediaQuery dependent.  This prevents the
              // '_dependents.isEmpty' assertion when the keyboard
              // dismisses during the sheet's exit animation.
              final bottomInset =
                  MediaQuery.of(sheetCtx).viewInsets.bottom;
              final safeBottom =
                  MediaQuery.of(sheetCtx).padding.bottom;

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
                            borderRadius:
                                BorderRadius.circular(CsRadii.full),
                          ),
                        ),
                      ),
                      // Content
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          16 + bottomInset + safeBottom,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Icon
                            Center(
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: CsColors.gray100,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person_outline_rounded,
                                  color: CsColors.gray700,
                                  size: 26,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: Text(
                                'Wie heisst du?',
                                style: CsTextStyles.titleLarge,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Center(
                              child: Text(
                                'Bitte gib deinen Namen ein,\ndamit dein Team dich erkennt.',
                                style: CsTextStyles.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Dein Name im Team',
                              style: CsTextStyles.labelSmall,
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: controller,
                              style: TextStyle(
                                fontSize: 15,
                                color: CsColors.gray900,
                              ),
                              decoration: InputDecoration(
                                hintText: 'z.B. Max, Sandro, Martin W.',
                                errorText: errorText,
                                counterText: '${text.length}/30',
                                prefixIcon: const Icon(
                                  Icons.person_outline,
                                  color: CsColors.gray500,
                                  size: 20,
                                ),
                              ),
                              autofocus: true,
                              textCapitalization:
                                  TextCapitalization.words,
                              maxLength: 30,
                              onChanged: (_) => setStateSheet(() {}),
                            ),
                            if (saving) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(CsRadii.md),
                                child: LinearProgressIndicator(
                                  color: CsColors.gray900,
                                  backgroundColor: CsColors.gray200,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            CsPrimaryButton(
                              label: 'Speichern',
                              icon: const Icon(
                                Icons.check_rounded,
                                size: 18,
                              ),
                              onPressed: (!isValid || saving)
                                  ? null
                                  : () async {
                                      final name =
                                          controller.text.trim();

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
                                        await MemberService
                                            .updateMyNickname(
                                          teamId,
                                          name,
                                        );
                                        savedName = name;
                                        // Use root navigator to pop –
                                        // the sheet's local ctx may
                                        // already be deactivated after
                                        // the await.
                                        rootNav?.pop();
                                      } catch (e) {
                                        // Guard: sheet may have been
                                        // dismissed externally while
                                        // the RPC was running.
                                        if (!ctx.mounted) return;
                                        setStateSheet(() {
                                          saving = false;
                                          errorText =
                                              'Name konnte nicht gespeichert werden.';
                                        });
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
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
    // Defer disposal: the sheet's exit animation is still running and the
    // TextField inside still references this controller.  Disposing it now
    // causes a repaint cascade → overlay '_children.contains(child)' assert.
    final ctrl = controller;
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    return savedName;
  }

  @override
  Widget build(BuildContext context) {
    return MainTabScreen(key: ValueKey(_refreshCounter));
  }
}
