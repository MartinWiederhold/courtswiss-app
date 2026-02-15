// ── DEV NOTE ──────────────────────────────────────────────────────
// New screen: "Passwort vergessen" — send password reset email.
// Created as part of Auth/Onboarding v2 rework.
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

    if (email.isEmpty || !valid) {
      CsToast.info(context, 'Bitte eine gültige E-Mail eingeben.');
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.courtswiss://reset-password',
      );
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'E-Mail konnte nicht gesendet werden.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CsColors.white,
      appBar: const CsGlassAppBar(title: 'Passwort vergessen'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _sent ? _buildSentState() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        const Spacer(flex: 2),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: CsColors.gray100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.lock_reset_rounded,
            color: CsColors.gray500,
            size: 32,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Passwort zurücksetzen',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: CsColors.gray900,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Gib deine E-Mail-Adresse ein und wir senden dir einen Link zum Zurücksetzen.',
          style: TextStyle(fontSize: 14, color: CsColors.gray600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          style: TextStyle(fontSize: 15, color: CsColors.gray900),
          decoration: InputDecoration(
            labelText: 'E-Mail',
            hintText: 'name@domain.ch',
            labelStyle: TextStyle(color: CsColors.gray500, fontSize: 14),
            hintStyle: TextStyle(color: CsColors.gray400, fontSize: 14),
            prefixIcon: Icon(
              Icons.email_outlined,
              color: CsColors.gray500,
              size: 20,
            ),
            filled: true,
            fillColor: CsColors.gray50,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CsRadii.md),
              borderSide: BorderSide(color: CsColors.gray200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CsRadii.md),
              borderSide: const BorderSide(color: CsColors.gray900, width: 1.5),
            ),
          ),
          onSubmitted: (_) => _sendReset(),
        ),
        const SizedBox(height: 20),
        CsPrimaryButton(
          label: 'Link senden',
          loading: _loading,
          onPressed: _loading ? null : _sendReset,
          icon: const Icon(Icons.send_rounded, size: 18),
        ),
        const Spacer(flex: 3),
      ],
    );
  }

  Widget _buildSentState() {
    return Column(
      children: [
        const Spacer(flex: 2),
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
          'E-Mail gesendet!',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: CsColors.gray900,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Prüfe dein Postfach und klicke auf den Link, um ein neues Passwort zu setzen.',
          style: TextStyle(fontSize: 14, color: CsColors.gray600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        CsSecondaryButton(
          label: 'Zurück zur Anmeldung',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
        ),
        const Spacer(flex: 3),
      ],
    );
  }
}
