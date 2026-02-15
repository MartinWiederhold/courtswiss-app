// ── DEV NOTE ──────────────────────────────────────────────────────
// New screen: Set new password after user clicks the reset link.
// Opened by DeepLinkService when it detects a password-recovery
// event from Supabase auth state change.
// Created as part of Auth/Onboarding v2 rework.
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _passwordVisible = false;
  bool _confirmVisible = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validatePassword(String pw) {
    if (pw.length < 8) return 'Mindestens 8 Zeichen';
    if (!RegExp(r'[0-9]').hasMatch(pw)) return 'Mind. 1 Zahl erforderlich';
    return null;
  }

  Future<void> _submit() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    final err = _validatePassword(password);
    if (err != null) {
      CsToast.info(context, err);
      return;
    }
    if (password != confirm) {
      CsToast.info(context, 'Passwörter stimmen nicht überein.');
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (!mounted) return;
      CsToast.success(context, 'Passwort erfolgreich geändert.');
      // Pop back; user is now logged in, AuthGate will show main app
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Fehler: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      CsToast.error(
          context, 'Passwort konnte nicht geändert werden. Bitte erneut versuchen.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CsColors.white,
      appBar: const CsGlassAppBar(title: 'Neues Passwort'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: CsColors.lime.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_open_rounded,
                  color: CsColors.gray900,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Neues Passwort setzen',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: CsColors.gray900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Wähle ein sicheres Passwort für dein Konto.',
                style: TextStyle(fontSize: 14, color: CsColors.gray600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              // Password
              TextField(
                controller: _passwordCtrl,
                obscureText: !_passwordVisible,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                style: TextStyle(fontSize: 15, color: CsColors.gray900),
                decoration: InputDecoration(
                  labelText: 'Neues Passwort',
                  hintText: 'Mind. 8 Zeichen, 1 Zahl',
                  labelStyle: TextStyle(color: CsColors.gray500, fontSize: 14),
                  hintStyle: TextStyle(color: CsColors.gray400, fontSize: 14),
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: CsColors.gray500,
                    size: 20,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _passwordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: CsColors.gray400,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _passwordVisible = !_passwordVisible),
                  ),
                  filled: true,
                  fillColor: CsColors.gray50,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CsRadii.md),
                    borderSide: BorderSide(color: CsColors.gray200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CsRadii.md),
                    borderSide: const BorderSide(
                        color: CsColors.gray900, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Confirm
              TextField(
                controller: _confirmCtrl,
                obscureText: !_confirmVisible,
                textInputAction: TextInputAction.done,
                style: TextStyle(fontSize: 15, color: CsColors.gray900),
                decoration: InputDecoration(
                  labelText: 'Passwort bestätigen',
                  hintText: '••••••••',
                  labelStyle: TextStyle(color: CsColors.gray500, fontSize: 14),
                  hintStyle: TextStyle(color: CsColors.gray400, fontSize: 14),
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: CsColors.gray500,
                    size: 20,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _confirmVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: CsColors.gray400,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _confirmVisible = !_confirmVisible),
                  ),
                  filled: true,
                  fillColor: CsColors.gray50,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CsRadii.md),
                    borderSide: BorderSide(color: CsColors.gray200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CsRadii.md),
                    borderSide: const BorderSide(
                        color: CsColors.gray900, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              CsPrimaryButton(
                label: 'Passwort ändern',
                loading: _loading,
                onPressed: _loading ? null : _submit,
                icon: const Icon(Icons.check_rounded, size: 18),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
