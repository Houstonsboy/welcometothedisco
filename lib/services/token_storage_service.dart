// lib/services/token_storage_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Stores and retrieves Spotify tokens via [FlutterSecureStorage].
/// Refreshes the access token when expired (no user interaction; uses Spotify
/// refresh_token API). Full Spotify login is only needed when no tokens exist
/// (first time, or Spotify revoked the refresh token).
///
/// Tokens are scoped to the signed-in Firebase user, so a second account on
/// the same device never inherits the first account's Spotify session. Tokens
/// saved with no Firebase user (cold-start login redirect before auth is
/// restored) go to unscoped keys and are claimed by the next signed-in read.
class TokenStorageService {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _accessTokenKey = 'spotify_access_token';
  static const _refreshTokenKey = 'spotify_refresh_token';
  static const _expiryKey = 'spotify_token_expiry';
  static const _tokenEndpoint = 'https://accounts.spotify.com/api/token';
  static const _timeout = Duration(seconds: 15);

  /// The one refresh in flight, shared by every caller that finds the token
  /// expired at the same moment. Spotify may rotate the refresh token, so
  /// parallel refreshes could each spend it and race to save.
  static Future<String?>? _refreshInFlight;

  /// The user whose unscoped tokens have already been claimed this process,
  /// so the check costs one secure-storage read per user, not per call.
  static String? _claimedFor;

  /// Test seams: the signed-in uid and the HTTP client used for refreshes.
  @visibleForTesting
  static String? Function() currentUid = () => FirebaseAuth.instance.currentUser?.uid;
  @visibleForTesting
  static http.Client? httpClient;

  static String? get _uid => currentUid();

  static String _key(String base, String? uid) => uid == null ? base : '${base}_$uid';

  /// Moves unscoped tokens (written before per-user scoping existed, or with
  /// no Firebase user signed in) to [uid]'s keys, unless [uid] has its own.
  static Future<void> _claimUnscopedTokens(String uid) async {
    final legacyAccess = await _storage.read(key: _accessTokenKey);
    if (legacyAccess == null) return;
    final ownAccess = await _storage.read(key: _key(_accessTokenKey, uid));
    if (ownAccess == null) {
      final legacyRefresh = await _storage.read(key: _refreshTokenKey);
      final legacyExpiry = await _storage.read(key: _expiryKey);
      await Future.wait([
        _storage.write(key: _key(_accessTokenKey, uid), value: legacyAccess),
        if (legacyRefresh != null)
          _storage.write(key: _key(_refreshTokenKey, uid), value: legacyRefresh),
        if (legacyExpiry != null)
          _storage.write(key: _key(_expiryKey, uid), value: legacyExpiry),
      ]);
    }
    await _deleteTokens(null);
  }

  /// Reads one token field for the current user (claiming unscoped tokens first).
  static Future<String?> _read(String base) async {
    final uid = _uid;
    if (uid != null && _claimedFor != uid) {
      await _claimUnscopedTokens(uid);
      _claimedFor = uid;
    }
    return _storage.read(key: _key(base, uid));
  }

  /// Save tokens after Spotify login (e.g. after PKCE exchange).
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) async {
    final uid = _uid;
    // New unscoped tokens must be claimed by the next signed-in read.
    if (uid == null) _claimedFor = null;
    final expiry = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .toIso8601String();

    await Future.wait([
      _storage.write(key: _key(_accessTokenKey, uid), value: accessToken),
      _storage.write(key: _key(_refreshTokenKey, uid), value: refreshToken),
      _storage.write(key: _key(_expiryKey, uid), value: expiry),
    ]);
    debugPrint('[TokenStorageService] Tokens saved, expires in ${expiresIn}s');
  }

  /// Returns a valid access token, refreshing if expired. Returns null if
  /// Spotify isn't connected, or a refresh failed (offline / Spotify down —
  /// the tokens are kept, so a later call can still succeed).
  static Future<String?> getAccessToken() async {
    final token = await _read(_accessTokenKey);
    final expiry = await _read(_expiryKey);

    if (token == null || expiry == null) return null;

    final expiryDate = DateTime.tryParse(expiry);
    final isExpired = expiryDate == null ||
        DateTime.now().isAfter(expiryDate.subtract(const Duration(minutes: 15)));

    if (isExpired) {
      return _refreshInFlight ??=
          _refreshAccessToken().whenComplete(() => _refreshInFlight = null);
    }
    return token;
  }

  static Future<String?> getRefreshToken() => _read(_refreshTokenKey);

  /// True when the current user has connected Spotify (even if the access
  /// token is currently expired — it is refreshed on next use).
  static Future<bool> hasSpotifyTokens() async {
    final token = await _read(_accessTokenKey);
    return token != null;
  }

  static Future<String?> _refreshAccessToken() async {
    final refreshToken = await _read(_refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) return null;

    debugPrint('[TokenStorageService] Refreshing access token...');
    final http.Response response;
    try {
      final post = httpClient?.post ?? http.post;
      response = await post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': AppConfig.spotifyClientId,
        },
      ).timeout(_timeout);
    } catch (e) {
      // Offline or timed out: keep the tokens, the next call retries.
      debugPrint('[TokenStorageService] Refresh error (tokens kept): $e');
      return null;
    }

    if (response.statusCode != 200) {
      // Only `invalid_grant` means the refresh token itself is dead (revoked,
      // or the user removed the app's access). Anything else — 429, 5xx — is
      // transient, and wiping the tokens would force a needless full login.
      if (_isInvalidGrant(response)) {
        debugPrint('[TokenStorageService] Refresh token rejected — clearing');
        await clearTokens();
      } else {
        debugPrint('[TokenStorageService] Refresh failed ${response.statusCode} (tokens kept)');
      }
      return null;
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = json['access_token'] as String?;
      if (accessToken == null) return null;
      final newRefresh = json['refresh_token'] as String? ?? refreshToken;
      final expiresIn = json['expires_in'] as int? ?? 3600;

      await saveTokens(
        accessToken: accessToken,
        refreshToken: newRefresh,
        expiresIn: expiresIn,
      );
      debugPrint('[TokenStorageService] Token refreshed OK');
      return accessToken;
    } catch (e) {
      debugPrint('[TokenStorageService] Refresh response unreadable (tokens kept): $e');
      return null;
    }
  }

  static bool _isInvalidGrant(http.Response response) {
    if (response.statusCode != 400) return false;
    try {
      final json = jsonDecode(response.body);
      return json is Map && json['error'] == 'invalid_grant';
    } catch (_) {
      return false;
    }
  }

  /// Clear the current user's tokens on Spotify disconnect / account deletion.
  static Future<void> clearTokens() async {
    await _deleteTokens(_uid);
    debugPrint('[TokenStorageService] Tokens cleared');
  }

  static Future<void> _deleteTokens(String? uid) async {
    await Future.wait([
      _storage.delete(key: _key(_accessTokenKey, uid)),
      _storage.delete(key: _key(_refreshTokenKey, uid)),
      _storage.delete(key: _key(_expiryKey, uid)),
    ]);
  }
}
