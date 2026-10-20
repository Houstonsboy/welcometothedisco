// test/token_storage_service_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';

const _storage = FlutterSecureStorage();

String _past() => DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();
String _future() => DateTime.now().add(const Duration(hours: 1)).toIso8601String();

/// Seeds an expired session for [uid] so the next getAccessToken() refreshes.
Map<String, String> _expiredSession(String uid) => {
      'spotify_access_token_$uid': 'old-access',
      'spotify_refresh_token_$uid': 'refresh-1',
      'spotify_token_expiry_$uid': _past(),
    };

void main() {
  // Every test uses its own uid: the service remembers per process which
  // users it has already checked for unscoped tokens.
  var n = 0;
  String freshUid() => 'user${n++}';

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TokenStorageService.httpClient = null;
  });

  group('per-user scoping', () {
    test("one account never sees another account's Spotify session", () async {
      final alice = freshUid(), bob = freshUid();
      TokenStorageService.currentUid = () => alice;
      await TokenStorageService.saveTokens(
          accessToken: 'a', refreshToken: 'r', expiresIn: 3600);

      TokenStorageService.currentUid = () => bob;
      expect(await TokenStorageService.hasSpotifyTokens(), isFalse);
      expect(await TokenStorageService.getAccessToken(), isNull);

      TokenStorageService.currentUid = () => alice;
      expect(await TokenStorageService.getAccessToken(), 'a');
    });

    test('pre-existing shared tokens are claimed by the first signed-in user only', () async {
      final alice = freshUid(), bob = freshUid();
      FlutterSecureStorage.setMockInitialValues({
        'spotify_access_token': 'legacy',
        'spotify_refresh_token': 'legacy-r',
        'spotify_token_expiry': _future(),
      });

      TokenStorageService.currentUid = () => alice;
      expect(await TokenStorageService.getAccessToken(), 'legacy');
      expect(await _storage.read(key: 'spotify_access_token'), isNull);

      TokenStorageService.currentUid = () => bob;
      expect(await TokenStorageService.hasSpotifyTokens(), isFalse);
    });

    test('tokens saved with nobody signed in go to the next user to sign in', () async {
      final alice = freshUid();
      TokenStorageService.currentUid = () => null;
      await TokenStorageService.saveTokens(
          accessToken: 'cold-start', refreshToken: 'r', expiresIn: 3600);

      TokenStorageService.currentUid = () => alice;
      expect(await TokenStorageService.getAccessToken(), 'cold-start');
    });

    test("clearTokens only clears the current user's session", () async {
      final alice = freshUid(), bob = freshUid();
      for (final uid in [alice, bob]) {
        TokenStorageService.currentUid = () => uid;
        await TokenStorageService.saveTokens(
            accessToken: uid, refreshToken: 'r', expiresIn: 3600);
      }
      await TokenStorageService.clearTokens(); // bob
      expect(await TokenStorageService.hasSpotifyTokens(), isFalse);
      TokenStorageService.currentUid = () => alice;
      expect(await TokenStorageService.hasSpotifyTokens(), isTrue);
    });
  });

  group('refresh', () {
    late String uid;
    var calls = 0;

    setUp(() {
      uid = freshUid();
      calls = 0;
      TokenStorageService.currentUid = () => uid;
      FlutterSecureStorage.setMockInitialValues(_expiredSession(uid));
    });

    void respond(http.Response Function() reply) {
      TokenStorageService.httpClient = MockClient((_) async {
        calls++;
        return reply();
      });
    }

    test('success stores and returns the new token, keeping a rotated refresh token', () async {
      respond(() => http.Response(
          jsonEncode({'access_token': 'new', 'refresh_token': 'refresh-2', 'expires_in': 3600}),
          200));
      expect(await TokenStorageService.getAccessToken(), 'new');
      expect(await TokenStorageService.getRefreshToken(), 'refresh-2');
    });

    test('offline: returns null but keeps the session', () async {
      TokenStorageService.httpClient =
          MockClient((_) async => throw const SocketException('offline'));
      expect(await TokenStorageService.getAccessToken(), isNull);
      expect(await TokenStorageService.hasSpotifyTokens(), isTrue);
      expect(await TokenStorageService.getRefreshToken(), 'refresh-1');
    });

    for (final status in [429, 500, 503]) {
      test('HTTP $status: returns null but keeps the session', () async {
        respond(() => http.Response('', status));
        expect(await TokenStorageService.getAccessToken(), isNull);
        expect(await TokenStorageService.hasSpotifyTokens(), isTrue);
      });
    }

    test('a 400 that is not invalid_grant keeps the session', () async {
      respond(() => http.Response(jsonEncode({'error': 'invalid_request'}), 400));
      expect(await TokenStorageService.getAccessToken(), isNull);
      expect(await TokenStorageService.hasSpotifyTokens(), isTrue);
    });

    test('invalid_grant (revoked refresh token) clears the session', () async {
      respond(() => http.Response(jsonEncode({'error': 'invalid_grant'}), 400));
      expect(await TokenStorageService.getAccessToken(), isNull);
      expect(await TokenStorageService.hasSpotifyTokens(), isFalse);
    });

    test('concurrent callers share one refresh request', () async {
      respond(() => http.Response(
          jsonEncode({'access_token': 'new', 'expires_in': 3600}), 200));
      final tokens = await Future.wait(
          List.generate(5, (_) => TokenStorageService.getAccessToken()));
      expect(tokens, everyElement('new'));
      expect(calls, 1);
    });
  });
}
