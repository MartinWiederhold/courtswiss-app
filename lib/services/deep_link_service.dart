import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Manages deep link parsing and pending invite tokens.
class DeepLinkService {
  DeepLinkService._();
  static final instance = DeepLinkService._();

  final _appLinks = AppLinks();

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

    // Ignore auth callbacks (io.courtswiss://login...)
    // Only handle invite links: courtswiss://join?token=... or https://courtswiss.app/join?token=...
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return;

    // ignore: avoid_print
    print('DEEP_LINK token=$token');
    _pendingToken = token;
    _tokenController.add(token);
  }

  void dispose() {
    _sub?.cancel();
    _tokenController.close();
  }
}
