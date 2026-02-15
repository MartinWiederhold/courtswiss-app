// ── DEV NOTE ──────────────────────────────────────────────────────
// UPDATED: DeepLinkService now handles THREE types of deep links:
//   a) Invite join links: courtswiss://join?token=XYZ
//   b) Supabase auth callbacks: io.courtswiss://login#... (confirm, magic link)
//   c) Password reset links: io.courtswiss://reset-password#...
// The service routes auth callbacks to Supabase PKCE exchange and
// broadcasts invite tokens as before.
// Modified as part of Auth/Onboarding v2 rework.
// ──────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages deep link parsing and dispatching.
///
/// Link types:
///   - **Invite**: `courtswiss://join?token=XYZ`
///   - **Auth callback**: `io.courtswiss://login#access_token=...` (email confirm / magic link)
///   - **Password reset**: `io.courtswiss://reset-password#access_token=...`
class DeepLinkService {
  DeepLinkService._();
  static final instance = DeepLinkService._();

  final _appLinks = AppLinks();

  // ── Invite tokens ────────────────────────────────────────

  /// Token waiting to be processed (e.g. user not yet logged in)
  String? _pendingToken;
  String? get pendingToken => _pendingToken;
  void clearPendingToken() => _pendingToken = null;

  /// Stream controller for incoming invite tokens
  final _tokenController = StreamController<String>.broadcast();
  Stream<String> get onInviteToken => _tokenController.stream;

  // ── Password reset events ────────────────────────────────

  /// Fires when a password-recovery deep link has been processed.
  final _passwordRecoveryController = StreamController<void>.broadcast();
  Stream<void> get onPasswordRecovery => _passwordRecoveryController.stream;

  StreamSubscription<Uri>? _sub;

  /// Initialize: check initial link + listen for future links
  Future<void> init() async {
    // Check if app was opened via deep link
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('DeepLinkService: getInitialLink error: $e');
    }

    // Listen for incoming links while app is running
    _sub = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) => debugPrint('DeepLinkService: uriLinkStream error: $e'),
    );
  }

  void _handleUri(Uri uri) {
    debugPrint('DeepLinkService: received uri=$uri');

    // ── 1. Auth callback (confirm / magic link) ──────────────
    // io.courtswiss://login#access_token=...&type=signup
    // io.courtswiss://login#access_token=...&type=magiclink
    if (_isAuthCallback(uri)) {
      debugPrint('DeepLinkService: detected auth callback');
      _handleAuthCallback(uri);
      return;
    }

    // ── 2. Password reset callback ───────────────────────────
    // io.courtswiss://reset-password#access_token=...&type=recovery
    if (_isPasswordResetCallback(uri)) {
      debugPrint('DeepLinkService: detected password reset callback');
      _handlePasswordResetCallback(uri);
      return;
    }

    // ── 3. Invite token ──────────────────────────────────────
    // courtswiss://join?token=XYZ  or  https://courtswiss.app/join?token=XYZ
    final token = uri.queryParameters['token'];
    if (token != null && token.isNotEmpty) {
      // ignore: avoid_print
      print('DEEP_LINK token=$token');
      _pendingToken = token;
      _tokenController.add(token);
      return;
    }

    debugPrint('DeepLinkService: unrecognised URI, ignoring');
  }

  // ── Auth callback detection & handling ─────────────────────

  bool _isAuthCallback(Uri uri) {
    // Match io.courtswiss://login... or io.courtswiss://login-callback...
    if (uri.scheme == 'io.courtswiss' && uri.host == 'login') return true;
    // Also handle the fragment containing access_token on login path
    if (uri.path.contains('login') &&
        uri.fragment.contains('access_token')) {
      return true;
    }
    return false;
  }

  bool _isPasswordResetCallback(Uri uri) {
    if (uri.scheme == 'io.courtswiss' && uri.host == 'reset-password') {
      return true;
    }
    if (uri.path.contains('reset-password') &&
        uri.fragment.contains('access_token')) {
      return true;
    }
    return false;
  }

  Future<void> _handleAuthCallback(Uri uri) async {
    try {
      // Supabase PKCE: the flutter SDK can recover session from the URI
      final sessionUri = _reconstructSessionUri(uri);
      await Supabase.instance.client.auth.getSessionFromUrl(sessionUri);
      debugPrint('DeepLinkService: auth callback session recovered');
    } catch (e) {
      debugPrint('DeepLinkService: auth callback error: $e');
    }
  }

  Future<void> _handlePasswordResetCallback(Uri uri) async {
    try {
      final sessionUri = _reconstructSessionUri(uri);
      await Supabase.instance.client.auth.getSessionFromUrl(sessionUri);
      debugPrint('DeepLinkService: password reset session recovered');
      _passwordRecoveryController.add(null);
    } catch (e) {
      debugPrint('DeepLinkService: password reset callback error: $e');
    }
  }

  /// Reconstruct the full URI that Supabase SDK expects (scheme://host#fragment).
  /// Some platforms deliver the fragment in different ways; normalise it here.
  Uri _reconstructSessionUri(Uri uri) {
    // If the URI already has a proper fragment, just return it.
    if (uri.fragment.isNotEmpty) return uri;
    // Fallback: return as-is
    return uri;
  }

  void dispose() {
    _sub?.cancel();
    _tokenController.close();
    _passwordRecoveryController.close();
  }
}
