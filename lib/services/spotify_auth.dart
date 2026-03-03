import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

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

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

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

  /// Opens the Spotify login page in a browser/webview, returns an access token
  /// on success, or null on failure.
  Future<String?> login() async {
    final verifier = _generateCodeVerifier();
    final challenge = _generateCodeChallenge(verifier);

    final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': _scopes.join(' '),
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
    });

    debugPrint('[SpotifyAuth] Opening auth URL...');
    debugPrint('[SpotifyAuth] redirect_uri=$redirectUri');

    final String resultUrl;
    try {
      resultUrl = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: 'welcometothedisco',
      );
    } catch (e) {
      debugPrint('[SpotifyAuth] Browser auth cancelled or failed: $e');
      return null;
    }

    final code = Uri.parse(resultUrl).queryParameters['code'];
    if (code == null) {
      debugPrint('[SpotifyAuth] No code in callback URL');
      return null;
    }

    debugPrint('[SpotifyAuth] Got auth code, exchanging for token...');
    return _exchangeCode(code, verifier);
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
        debugPrint('[SpotifyAuth] Token exchange failed: ${response.statusCode} ${response.body}');
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
        debugPrint('[SpotifyAuth] Refresh failed: ${response.statusCode} ${response.body}');
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

  /// Returns a valid access token, refreshing if needed.
  /// Returns null if not logged in or refresh fails.
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
