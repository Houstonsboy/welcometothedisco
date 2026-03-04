import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Distinct result of Spotify login. Use [statusLabel] for UI text.
enum SpotifyAuthResultType { success, cancelled, error }

class SpotifyAuthResult {
  final SpotifyAuthResultType type;
  final String? accessToken;
  final String? message;

  const SpotifyAuthResult._(this.type, {this.accessToken, this.message});

  factory SpotifyAuthResult.success(String token) =>
      SpotifyAuthResult._(SpotifyAuthResultType.success, accessToken: token);
  factory SpotifyAuthResult.cancelled() =>
      const SpotifyAuthResult._(SpotifyAuthResultType.cancelled);
  factory SpotifyAuthResult.error({String? message}) =>
      SpotifyAuthResult._(SpotifyAuthResultType.error, message: message);

  bool get isSuccess => type == SpotifyAuthResultType.success;
  bool get isCancelled => type == SpotifyAuthResultType.cancelled;
  bool get isError => type == SpotifyAuthResultType.error;

  String get statusLabel {
    switch (type) {
      case SpotifyAuthResultType.success:
        return 'Authentication & authorization successful';
      case SpotifyAuthResultType.cancelled:
        return 'Login cancelled';
      case SpotifyAuthResultType.error:
        return message != null && message!.isNotEmpty ? message! : 'Authentication failed';
    }
  }
}

class SpotifyAuth {
  static const String clientId = '6fa99bd6412b4bd3ae11279feff19f53';
  static const String redirectUri = 'welcometothedisco://callback';
  static const String _authEndpoint = 'https://accounts.spotify.com/authorize';
  static const String _tokenEndpoint = 'https://accounts.spotify.com/api/token';

  static const List<String> _scopes = [
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-currently-playing',
    'playlist-read-private',
    'playlist-modify-public',
    'playlist-modify-private',
    'streaming',
  ];

  static const _storage = FlutterSecureStorage();
  static const _keyAccessToken = 'sp_access_token';
  static const _keyRefreshToken = 'sp_refresh_token';
  static const _keyExpiresAt = 'sp_expires_at';
  static const _keyPkceVerifier = 'sp_pkce_verifier';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  // Completer that login() waits on until app_links delivers the callback URI.
  Completer<Uri>? _pendingCallback;
  StreamSubscription<Uri>? _linkSub;

  bool get isLoggedIn => _accessToken != null && _expiresAt != null;

  // ── PKCE helpers ──────────────────────────────────────────────────────────

  static String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(64, (_) => random.nextInt(256));
    final encoded = base64UrlEncode(bytes).replaceAll('=', '');
    return encoded.length > 128 ? encoded.substring(0, 128) : encoded;
  }

  static String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  /// Opens Spotify login in the external browser, then waits for app_links to
  /// deliver the redirect URI. app_links is the ONLY deep-link handler — no
  /// flutter_web_auth_2 competing for the same intent.
  ///
  /// Times out after 5 minutes (user probably abandoned the flow).
  Future<SpotifyAuthResult> login() async {
    final verifier = _generateCodeVerifier();
    final challenge = _generateCodeChallenge(verifier);

    // Persist verifier in case the process is killed before the callback arrives.
    await _storage.write(key: _keyPkceVerifier, value: verifier);

    final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': _scopes.join(' '),
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
    });

    // Set up a Completer that will be resolved by the app_links stream.
    _pendingCallback = Completer<Uri>();

    final appLinks = AppLinks();
    _linkSub = appLinks.uriLinkStream.listen(
      (uri) {
        debugPrint('[SpotifyAuth] uriLinkStream received: $uri');
        if (uri.toString().startsWith('welcometothedisco://callback') &&
            _pendingCallback != null &&
            !_pendingCallback!.isCompleted) {
          _pendingCallback!.complete(uri);
        }
      },
      onError: (e) {
        debugPrint('[SpotifyAuth] uriLinkStream error: $e');
        if (_pendingCallback != null && !_pendingCallback!.isCompleted) {
          _pendingCallback!.completeError(e);
        }
      },
    );

    debugPrint('[SpotifyAuth] Opening auth URL in external browser...');
    debugPrint('[SpotifyAuth] redirect_uri=$redirectUri');

    final launched = await launchUrl(
      authUrl,
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      await _cancelLogin();
      return SpotifyAuthResult.error(message: 'Could not open browser');
    }

    // Wait for the deep-link callback (up to 5 minutes).
    Uri callbackUri;
    try {
      callbackUri = await _pendingCallback!.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException('Login timed out'),
      );
    } on TimeoutException {
      debugPrint('[SpotifyAuth] Login timed out');
      await _cancelLogin();
      return SpotifyAuthResult.cancelled();
    } catch (e) {
      debugPrint('[SpotifyAuth] Login error waiting for callback: $e');
      await _cancelLogin();
      return SpotifyAuthResult.error(message: e.toString());
    } finally {
      await _cancelLogin();
    }

    final code = callbackUri.queryParameters['code'];
    if (code == null) {
      debugPrint('[SpotifyAuth] No code in callback URI');
      await _clearPkceVerifier();
      return SpotifyAuthResult.cancelled();
    }

    debugPrint('[SpotifyAuth] Got auth code, exchanging for token...');
    final token = await _exchangeCode(code, verifier);
    await _clearPkceVerifier();
    if (token != null) {
      return SpotifyAuthResult.success(token);
    }
    return SpotifyAuthResult.error(message: 'Token exchange failed');
  }

  Future<void> _cancelLogin() async {
    await _linkSub?.cancel();
    _linkSub = null;
    _pendingCallback = null;
  }

  // ── Cold-start deep link handler ──────────────────────────────────────────

  /// Call in main() when the app is opened directly by the redirect URI.
  /// Reads the stored PKCE verifier, exchanges the code, persists tokens.
  Future<bool> handleCallbackUri(String uri) async {
    final code = Uri.parse(uri).queryParameters['code'];
    if (code == null) {
      debugPrint('[SpotifyAuth] handleCallbackUri: no code in URI');
      await _clearPkceVerifier();
      return false;
    }

    final verifier = await _storage.read(key: _keyPkceVerifier);
    if (verifier == null) {
      debugPrint('[SpotifyAuth] handleCallbackUri: no stored PKCE verifier');
      return false;
    }

    debugPrint('[SpotifyAuth] handleCallbackUri: exchanging code for token...');
    final token = await _exchangeCode(code, verifier);
    await _clearPkceVerifier();
    if (token != null) {
      debugPrint('[SpotifyAuth] handleCallbackUri: success, token stored');
      return true;
    }
    return false;
  }

  Future<void> _clearPkceVerifier() async {
    await _storage.delete(key: _keyPkceVerifier);
  }

  // ── Token exchange ────────────────────────────────────────────────────────

  Future<String?> _exchangeCode(String code, String verifier) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
          'client_id': clientId,
          'code_verifier': verifier,
        },
      );

      if (response.statusCode != 200) {
        debugPrint('[SpotifyAuth] Token exchange failed ${response.statusCode}: ${response.body}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _applyTokenResponse(json);
      await _persistTokens();
      debugPrint('[SpotifyAuth] Token exchange success, expires in ${json['expires_in']}s');
      return _accessToken;
    } catch (e) {
      debugPrint('[SpotifyAuth] Token exchange error: $e');
      return null;
    }
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<String?> _refresh() async {
    if (_refreshToken == null) return null;
    debugPrint('[SpotifyAuth] Refreshing token...');

    try {
      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken!,
          'client_id': clientId,
        },
      );

      if (response.statusCode != 200) {
        debugPrint('[SpotifyAuth] Refresh failed ${response.statusCode}: ${response.body}');
        await logout();
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _applyTokenResponse(json);
      await _persistTokens();
      debugPrint('[SpotifyAuth] Token refreshed OK');
      return _accessToken;
    } catch (e) {
      debugPrint('[SpotifyAuth] Refresh error: $e');
      return null;
    }
  }

  // ── Public token getter ───────────────────────────────────────────────────

  Future<String?> getToken() async {
    if (_accessToken == null) {
      await _loadTokens();
      if (_accessToken == null) return null;
    }

    if (_expiresAt != null &&
        DateTime.now().isAfter(_expiresAt!.subtract(const Duration(minutes: 2)))) {
      return _refresh();
    }

    return _accessToken;
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyExpiresAt);
    await _clearPkceVerifier();
    debugPrint('[SpotifyAuth] Logged out, tokens cleared');
  }

  // ── Secure storage helpers ────────────────────────────────────────────────

  void _applyTokenResponse(Map<String, dynamic> json) {
    _accessToken = json['access_token'] as String?;
    if (json.containsKey('refresh_token')) {
      _refreshToken = json['refresh_token'] as String?;
    }
    final expiresIn = json['expires_in'] as int? ?? 3600;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
  }

  Future<void> _persistTokens() async {
    if (_accessToken != null) {
      await _storage.write(key: _keyAccessToken, value: _accessToken);
    }
    if (_refreshToken != null) {
      await _storage.write(key: _keyRefreshToken, value: _refreshToken);
    }
    if (_expiresAt != null) {
      await _storage.write(key: _keyExpiresAt, value: _expiresAt!.toIso8601String());
    }
  }

  Future<void> _loadTokens() async {
    _accessToken = await _storage.read(key: _keyAccessToken);
    _refreshToken = await _storage.read(key: _keyRefreshToken);
    final expiresStr = await _storage.read(key: _keyExpiresAt);
    if (expiresStr != null) {
      _expiresAt = DateTime.tryParse(expiresStr);
    }
    if (_accessToken != null) {
      debugPrint('[SpotifyAuth] Loaded cached tokens, expires at $_expiresAt');
    }
  }
}
