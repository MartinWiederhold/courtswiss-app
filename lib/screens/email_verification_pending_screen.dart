// ── DEV NOTE ──────────────────────────────────────────────────────
// New screen: Shown after a user registers with email + password.
// Tells the user to check their inbox and click the confirmation link.
// Provides a "Resend" button + auto-polls auth state to detect
// when the user returns from the confirmation link.
// Created as part of Auth/Onboarding v2 rework.
// ──────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    setState(() => _resending = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
        emailRedirectTo: 'io.courtswiss://login',
      );
      if (!mounted) return;
      CsToast.success(context, 'E-Mail erneut gesendet.');
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'E-Mail konnte nicht gesendet werden.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CsColors.white,
      appBar: const CsGlassAppBar(title: ''),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Icon
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
              Text(
                'Bitte bestätige deine E-Mail',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: CsColors.gray900,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Wir haben eine Bestätigungs-E-Mail an',
                style: TextStyle(fontSize: 14, color: CsColors.gray600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                widget.email,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: CsColors.gray900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'gesendet. Bitte klicke auf den Link in der E-Mail,\num dein Konto zu aktivieren.',
                style: TextStyle(fontSize: 14, color: CsColors.gray600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // Resend button
              CsSecondaryButton(
                label: 'E-Mail erneut senden',
                loading: _resending,
                onPressed: _resending ? null : _resendEmail,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
              const SizedBox(height: 12),
              // Back to login
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Zurück zur Anmeldung',
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
