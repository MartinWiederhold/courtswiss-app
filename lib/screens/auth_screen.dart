// ── DEV NOTE ──────────────────────────────────────────────────────
// REPLACED: old magic-link LoginScreen.
// NEW: Premium auth screen with "Anmelden" / "Registrieren" toggle.
//   - Anmelden: email + password → signInWithPassword
//   - Registrieren: email + password + confirm → signUp (email confirm)
//   - "Passwort vergessen?" link → ForgotPasswordScreen
// Created as part of Auth/Onboarding v2 rework.
// ──────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';
import 'email_verification_pending_screen.dart';
import 'forgot_password_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // Login fields
  final _loginEmailCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _loginLoading = false;
  bool _loginPasswordVisible = false;

  // Register fields
  final _regEmailCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  final _regConfirmCtrl = TextEditingController();
  bool _regLoading = false;
  bool _regPasswordVisible = false;
  bool _regConfirmVisible = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPasswordCtrl.dispose();
    _regConfirmCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════
  //  VALIDATION
  // ══════════════════════════════════════════════════════════

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? _validatePassword(String pw) {
    if (pw.length < 8) return 'Mindestens 8 Zeichen';
    if (!RegExp(r'[0-9]').hasMatch(pw)) return 'Mind. 1 Zahl erforderlich';
    return null;
  }

  // ══════════════════════════════════════════════════════════
  //  LOGIN
  // ══════════════════════════════════════════════════════════

  Future<void> _login() async {
    final email = _loginEmailCtrl.text.trim().toLowerCase();
    final password = _loginPasswordCtrl.text;

    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      CsToast.info(context, 'Bitte eine gültige E-Mail eingeben.');
      return;
    }
    if (password.isEmpty) {
      CsToast.info(context, 'Bitte Passwort eingeben.');
      return;
    }

    setState(() => _loginLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      // AuthGate will automatically react to the new session
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = _mapAuthError(e);
      CsToast.error(context, msg);
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Anmeldung fehlgeschlagen. Bitte versuche es erneut.');
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════
  //  REGISTER
  // ══════════════════════════════════════════════════════════

  /// Returns `true` when the current session is an anonymous user
  /// (i.e. has no email). In that case we can upgrade in-place via
  /// `updateUser()` to keep the same user_id and avoid DB migration.
  bool get _isCurrentSessionAnon {
    final user = Supabase.instance.client.auth.currentUser;
    return user != null && user.email == null;
  }

  Future<void> _register() async {
    final email = _regEmailCtrl.text.trim().toLowerCase();
    final password = _regPasswordCtrl.text;
    final confirm = _regConfirmCtrl.text;

    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      CsToast.info(context, 'Bitte eine gültige E-Mail eingeben.');
      return;
    }
    final pwError = _validatePassword(password);
    if (pwError != null) {
      CsToast.info(context, pwError);
      return;
    }
    if (password != confirm) {
      CsToast.info(context, 'Passwörter stimmen nicht überein.');
      return;
    }

    setState(() => _regLoading = true);
    try {
      if (_isCurrentSessionAnon) {
        // ── Anon upgrade path ─────────────────────────────────
        // Upgrade the anonymous user in-place so the user_id stays
        // the same and no data migration is necessary.
        debugPrint('AuthScreen: upgrading anon user via updateUser');
        final res = await Supabase.instance.client.auth.updateUser(
          UserAttributes(email: email, password: password),
          emailRedirectTo: 'io.courtswiss://login',
        );

        if (!mounted) return;

        // After updateUser with a new email Supabase sends a
        // confirmation link. The user object will have
        // emailConfirmedAt == null until the link is clicked.
        final needsConfirmation =
            res.user != null && res.user!.emailConfirmedAt == null;

        if (needsConfirmation) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EmailVerificationPendingScreen(email: email),
            ),
          );
        }
        // else: if auto-confirmed, AuthGate will react
      } else {
        // ── Fresh sign-up path ────────────────────────────────
        final res = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: 'io.courtswiss://login',
        );

        if (!mounted) return;

        final needsConfirmation =
            res.user != null && res.user!.emailConfirmedAt == null;

        if (needsConfirmation) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EmailVerificationPendingScreen(email: email),
            ),
          );
        }
        // else: if auto-confirmed, AuthGate will react
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = _mapAuthError(e);
      CsToast.error(context, msg);
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, 'Registrierung fehlgeschlagen. Bitte versuche es erneut.');
    } finally {
      if (mounted) setState(() => _regLoading = false);
    }
  }

  String _mapAuthError(AuthException e) {
    final code = e.statusCode;
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'E-Mail oder Passwort ungültig.';
    }
    if (msg.contains('email not confirmed')) {
      return 'E-Mail noch nicht bestätigt. Bitte prüfe dein Postfach.';
    }
    if (msg.contains('already registered') ||
        msg.contains('user already registered')) {
      return 'Diese E-Mail ist bereits registriert. Bitte melde dich an.';
    }
    if (code == '429' || msg.contains('rate limit')) {
      return 'Zu viele Versuche. Bitte warte kurz.';
    }
    return 'Fehler: ${e.message}';
  }

  // ══════════════════════════════════════════════════════════
  //  INPUT DECORATION HELPER
  // ══════════════════════════════════════════════════════════

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(
        color: CsColors.gray500,
        fontSize: 14,
      ),
      hintStyle: TextStyle(
        color: CsColors.gray400,
        fontSize: 14,
      ),
      prefixIcon: Icon(prefixIcon, color: CsColors.gray500, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: CsColors.gray50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CsRadii.md),
        borderSide: BorderSide(color: CsColors.gray200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CsRadii.md),
        borderSide: const BorderSide(color: CsColors.gray900, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CsRadii.md),
        borderSide: const BorderSide(color: CsColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CsRadii.md),
        borderSide: const BorderSide(color: CsColors.error, width: 1.5),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CsColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 40),

              // ── Logo ─────────────────────────────────────
              SizedBox(
                width: 120,
                child: Image.asset(
                  'assets/sports/Logo_Courtswiss.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Willkommen',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: CsColors.gray900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Dein Team. Deine Matches.',
                style: TextStyle(
                  fontSize: 14,
                  color: CsColors.gray500,
                ),
              ),
              const SizedBox(height: 28),

              // ── Tab bar ──────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: CsColors.gray100,
                  borderRadius: BorderRadius.circular(CsRadii.md),
                ),
                padding: const EdgeInsets.all(3),
                child: TabBar(
                  controller: _tabCtrl,
                  onTap: (_) => setState(() {}),
                  indicator: BoxDecoration(
                    color: CsColors.white,
                    borderRadius: BorderRadius.circular(CsRadii.sm),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: CsColors.gray900,
                  unselectedLabelColor: CsColors.gray500,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [
                    Tab(text: 'Anmelden'),
                    Tab(text: 'Registrieren'),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Tab content ──────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _tabCtrl.index == 0
                    ? _buildLoginForm()
                    : _buildRegisterForm(),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── LOGIN FORM ──────────────────────────────────────────

  Widget _buildLoginForm() {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Email
        TextField(
          controller: _loginEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.email],
          style: TextStyle(fontSize: 15, color: CsColors.gray900),
          decoration: _inputDecoration(
            label: 'E-Mail',
            hint: 'name@domain.ch',
            prefixIcon: Icons.email_outlined,
          ),
        ),
        const SizedBox(height: 14),

        // Password
        TextField(
          controller: _loginPasswordCtrl,
          obscureText: !_loginPasswordVisible,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          style: TextStyle(fontSize: 15, color: CsColors.gray900),
          decoration: _inputDecoration(
            label: 'Passwort',
            hint: '••••••••',
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(
                _loginPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: CsColors.gray400,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _loginPasswordVisible = !_loginPasswordVisible),
            ),
          ),
          onSubmitted: (_) => _login(),
        ),
        const SizedBox(height: 8),

        // Forgot password
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ForgotPasswordScreen(),
                ),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Passwort vergessen?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: CsColors.gray600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Submit
        CsPrimaryButton(
          label: 'Anmelden',
          loading: _loginLoading,
          onPressed: _loginLoading ? null : _login,
          icon: const Icon(Icons.login_rounded, size: 18),
        ),
      ],
    );
  }

  // ── REGISTER FORM ───────────────────────────────────────

  Widget _buildRegisterForm() {
    return Column(
      key: const ValueKey('register'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Email
        TextField(
          controller: _regEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.email],
          style: TextStyle(fontSize: 15, color: CsColors.gray900),
          decoration: _inputDecoration(
            label: 'E-Mail',
            hint: 'name@domain.ch',
            prefixIcon: Icons.email_outlined,
          ),
        ),
        const SizedBox(height: 14),

        // Password
        TextField(
          controller: _regPasswordCtrl,
          obscureText: !_regPasswordVisible,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          style: TextStyle(fontSize: 15, color: CsColors.gray900),
          decoration: _inputDecoration(
            label: 'Passwort',
            hint: 'Mind. 8 Zeichen, 1 Zahl',
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(
                _regPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: CsColors.gray400,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _regPasswordVisible = !_regPasswordVisible),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Confirm password
        TextField(
          controller: _regConfirmCtrl,
          obscureText: !_regConfirmVisible,
          textInputAction: TextInputAction.done,
          style: TextStyle(fontSize: 15, color: CsColors.gray900),
          decoration: _inputDecoration(
            label: 'Passwort bestätigen',
            hint: '••••••••',
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(
                _regConfirmVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: CsColors.gray400,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _regConfirmVisible = !_regConfirmVisible),
            ),
          ),
          onSubmitted: (_) => _register(),
        ),
        const SizedBox(height: 10),

        // Password hint
        Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: CsColors.gray400),
            const SizedBox(width: 6),
            Text(
              'Mind. 8 Zeichen mit mind. 1 Zahl',
              style: TextStyle(fontSize: 12, color: CsColors.gray400),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Submit
        CsPrimaryButton(
          label: 'Registrieren',
          loading: _regLoading,
          onPressed: _regLoading ? null : _register,
          icon: const Icon(Icons.person_add_outlined, size: 18),
        ),
      ],
    );
  }
}
