// ── DEV NOTE ──────────────────────────────────────────────────────
// DeepLinkService handles ONLY invite deep links:
//   - lineup://join?token=XYZ
//
// Auth callbacks (email confirmation, password reset) are handled
// AUTOMATICALLY by supabase_flutter v2.12+ via its built-in
// AppLinks listener + PKCE code exchange.
// See: SupabaseAuth._startDeeplinkObserver() in the SDK source.
//
// Removing the redundant auth callback handling eliminates the race
// condition where two handlers competed to exchange the single-use
// PKCE code.
// ──────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Manages deep link parsing and dispatching for **invite links only**.
///
/// Link type handled:
///   - **Invite**: `lineup://join?token=XYZ`
///
/// Auth callbacks (`io.courtswiss://login?code=...` and
/// `io.courtswiss://reset-password?code=...`) are handled by
/// `supabase_flutter`'s built-in deep link observer.
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

    // ── Invite token ──────────────────────────────────────
    // lineup://join?token=XYZ  or  https://lineup.app/join?token=XYZ
    final token = uri.queryParameters['token'];
    if (token != null && token.isNotEmpty) {
      // ignore: avoid_print
      print('DEEP_LINK token=$token');
      _pendingToken = token;
      _tokenController.add(token);
      return;
    }

    // Auth callbacks (io.courtswiss://login?code=... and
    // io.courtswiss://reset-password?code=...) are handled automatically
    // by supabase_flutter's built-in SupabaseAuth deep link observer.
    // No action needed here.
    debugPrint('DeepLinkService: not an invite link, '
        'letting supabase_flutter handle it (scheme=${uri.scheme} host=${uri.host})');
  }

  void dispose() {
    _sub?.cancel();
    _tokenController.close();
  }
}
