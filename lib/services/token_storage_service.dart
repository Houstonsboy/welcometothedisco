// lib/services/token_storage_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Stores and retrieves Spotify tokens via [FlutterSecureStorage].
/// Refreshes the access token when expired (no user interaction; uses Spotify
/// refresh_token API). Full Spotify login is only needed when no tokens exist
/// (first time or after tokens were removed / long time unused).
class TokenStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _accessTokenKey = 'spotify_access_token';
  static const _refreshTokenKey = 'spotify_refresh_token';
  static const _expiryKey = 'spotify_token_expiry';
  static const _tokenEndpoint = 'https://accounts.spotify.com/api/token';

  /// Save tokens after Spotify login (e.g. after PKCE exchange or Cloud Function).
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) async {
    final expiry = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .toIso8601String();

    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(key: _expiryKey, value: expiry),
    ]);
    debugPrint('[TokenStorageService] Tokens saved, expires in ${expiresIn}s');
  }

  /// Returns a valid access token, refreshing if expired. Returns null if no tokens
  /// or refresh failed (prompt user to reconnect Spotify).
  static Future<String?> getAccessToken() async {
    final token = await _storage.read(key: _accessTokenKey);
    final expiry = await _storage.read(key: _expiryKey);

    if (token == null || expiry == null) return null;

    final expiryDate = DateTime.parse(expiry);
    final isExpired = DateTime.now().isAfter(
      expiryDate.subtract(const Duration(minutes: 15)),
    );

    if (isExpired) return await _refreshAccessToken();
    return token;
  }

  static Future<String?> getRefreshToken() async {
    return _storage.read(key: _refreshTokenKey);
  }

  static Future<bool> hasSpotifyTokens() async {
    final token = await _storage.read(key: _accessTokenKey);
    return token != null;
  }

  static Future<String?> _refreshAccessToken() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return null;

    debugPrint('[TokenStorageService] Refreshing access token...');
    try {
      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': AppConfig.spotifyClientId,
        },
      );

      if (response.statusCode != 200) {
        debugPrint('[TokenStorageService] Refresh failed ${response.statusCode}: ${response.body}');
        await clearTokens();
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = json['access_token'] as String?;
      final newRefresh = json['refresh_token'] as String? ?? refreshToken;
      final expiresIn = json['expires_in'] as int? ?? 3600;

      if (accessToken == null) {
        await clearTokens();
        return null;
      }

      await saveTokens(
        accessToken: accessToken,
        refreshToken: newRefresh,
        expiresIn: expiresIn,
      );
      debugPrint('[TokenStorageService] Token refreshed OK');
      return accessToken;
    } catch (e) {
      debugPrint('[TokenStorageService] Refresh error: $e');
      await clearTokens();
      return null;
    }
  }

  /// Clear tokens on logout or Spotify disconnect.
  static Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _expiryKey),
    ]);
    debugPrint('[TokenStorageService] Tokens cleared');
  }
}
