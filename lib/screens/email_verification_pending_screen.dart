// ── DEV NOTE ──────────────────────────────────────────────────────
// Shown after sign-up (or anon-upgrade) when the session is null,
// i.e. email confirmation is required before login is possible.
//
// UX principles:
//   • Anti-enumeration: wording never confirms whether an account
//     with the given email actually exists.
//   • Resend with rate-limit handling.
//   • "Already have an account? Log in" CTA pops back to AuthScreen
//     with the email pre-filled on the login tab.
//   • Auto-detects successful confirmation via onAuthStateChange.
// ──────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_localizations.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';

class EmailVerificationPendingScreen extends StatefulWidget {
  final String email;

  const EmailVerificationPendingScreen({super.key, required this.email});

  @override
  State<EmailVerificationPendingScreen> createState() =>
      _EmailVerificationPendingScreenState();
}

class _EmailVerificationPendingScreenState
    extends State<EmailVerificationPendingScreen> {
  bool _resending = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // Listen for auth state change → if user confirms email, they get a session
    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((authState) {
      if (authState.event == AuthChangeEvent.signedIn &&
          authState.session != null) {
        // User confirmed → pop back to root, AuthGate will show main app
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _resendEmail() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _resending = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
        emailRedirectTo: 'io.courtswiss://login',
      );
      if (!mounted) return;
      CsToast.success(context, l.resendEmailSuccess);
    } on AuthException catch (e) {
      if (!mounted) return;
      debugPrint('resendEmail AuthException: '
          'statusCode=${e.statusCode} message=${e.message}');
      CsToast.error(context, l.resendEmailRateLimit);
    } catch (e) {
      if (!mounted) return;
      debugPrint('resendEmail error: $e');
      CsToast.error(context, l.resendEmailRateLimit);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: CsColors.white,
      appBar: const CsGlassAppBar(title: ''),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── Icon ──────────────────────────────────────────
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: CsColors.lime.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  color: CsColors.gray900,
                  size: 36,
                ),
              ),
              const SizedBox(height: 24),

              // ── Title ─────────────────────────────────────────
              Text(
                l.verificationPendingTitle,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: CsColors.gray900,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // ── Email (bold) ──────────────────────────────────
              Text(
                widget.email,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: CsColors.gray900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // ── Neutral body (anti-enumeration) ───────────────
              Text(
                l.verificationPendingBody,
                style: TextStyle(fontSize: 14, color: CsColors.gray600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ── Resend confirmation email ─────────────────────
              CsSecondaryButton(
                label: l.resendConfirmationEmail,
                loading: _resending,
                onPressed: _resending ? null : _resendEmail,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
              const SizedBox(height: 12),

              // ── Already have an account? Log in ───────────────
              TextButton(
                onPressed: () => Navigator.pop(context, widget.email),
                child: Text(
                  l.alreadyHaveAccountLogin,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: CsColors.gray600,
                  ),
                ),
              ),

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
