import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:welcometothedisco/services/spotify_auth.dart';

class NowPlaying {
  final String trackName;
  final String artistName;
  final String albumName;
  final String? albumArtUrl;
  final int durationMs;
  final int progressMs;
  final bool isPlaying;

  const NowPlaying({
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.albumArtUrl,
    required this.durationMs,
    required this.progressMs,
    required this.isPlaying,
  });

  factory NowPlaying.fromJson(Map<String, dynamic> json) {
    final item = json['item'] as Map<String, dynamic>? ?? {};
    final artists = (item['artists'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final album = item['album'] as Map<String, dynamic>? ?? {};
    final images = (album['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return NowPlaying(
      trackName: item['name'] as String? ?? 'Unknown',
      artistName: artists.isNotEmpty ? artists.first['name'] as String? ?? '' : '',
      albumName: album['name'] as String? ?? '',
      albumArtUrl: images.isNotEmpty ? images.first['url'] as String? : null,
      durationMs: item['duration_ms'] as int? ?? 0,
      progressMs: json['progress_ms'] as int? ?? 0,
      isPlaying: json['is_playing'] as bool? ?? false,
    );
  }
}

class SpotifyTrack {
  final String id;
  final String uri;
  final String name;
  final String artistName;
  final String? albumArtUrl;

  const SpotifyTrack({
    required this.id,
    required this.uri,
    required this.name,
    required this.artistName,
    this.albumArtUrl,
  });

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) {
    final artists = (json['artists'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final album = json['album'] as Map<String, dynamic>? ?? {};
    final images = (album['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return SpotifyTrack(
      id: json['id'] as String? ?? '',
      uri: json['uri'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      artistName: artists.isNotEmpty ? artists.first['name'] as String? ?? '' : '',
      albumArtUrl: images.isNotEmpty ? images.first['url'] as String? : null,
    );
  }
}

class SpotifyPlaylist {
  final String id;
  final String name;
  final String? imageUrl;
  final int trackCount;

  const SpotifyPlaylist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.trackCount,
  });

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> json) {
    final images = (json['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tracks = json['tracks'] as Map<String, dynamic>? ?? {};
    return SpotifyPlaylist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      imageUrl: images.isNotEmpty ? images.first['url'] as String? : null,
      trackCount: tracks['total'] as int? ?? 0,
    );
  }
}

class SpotifyApi {
  static const String _base = 'https://api.spotify.com/v1';

  final SpotifyAuth _auth;

  SpotifyApi(this._auth);

  // ── Internal helpers ────────────────────────────────────────────────────

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getToken();
    if (token == null) throw Exception('Not authenticated — call login() first');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<http.Response> _get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final h = await _headers();
    final resp = await http.get(uri, headers: h);
    debugPrint('[SpotifyApi] GET $path → ${resp.statusCode}');
    return resp;
  }

  Future<http.Response> _put(String path, {Object? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final h = await _headers();
    final resp = await http.put(uri, headers: h, body: body != null ? jsonEncode(body) : null);
    debugPrint('[SpotifyApi] PUT $path → ${resp.statusCode}');
    return resp;
  }

  Future<http.Response> _post(String path, {Object? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final h = await _headers();
    final resp = await http.post(uri, headers: h, body: body != null ? jsonEncode(body) : null);
    debugPrint('[SpotifyApi] POST $path → ${resp.statusCode}');
    return resp;
  }

  // ── Devices ───────────────────────────────────────────────────────────────

  /// Returns the ID of the current active device, or null if none.
  Future<String?> getActiveDeviceId() async {
    final resp = await _get('/me/player/devices');
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final devices = (json['devices'] as List?) ?? [];
    for (final d in devices) {
      if (d['is_active'] == true) return d['id'] as String?;
    }
    if (devices.isNotEmpty) return devices.first['id'] as String?;
    return null;
  }

  // ── Playback control ──────────────────────────────────────────────────────

  /// Play a specific track URI. Requires Premium + an active device.
  Future<bool> play(String spotifyUri) async {
    final deviceId = await getActiveDeviceId();
    if (deviceId == null) {
      debugPrint('[SpotifyApi] play() — no active device');
      return false;
    }
    final resp = await _put(
      '/me/player/play',
      query: {'device_id': deviceId},
      body: {'uris': [spotifyUri]},
    );
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  Future<bool> pause() async {
    final deviceId = await getActiveDeviceId();
    if (deviceId == null) return false;
    final resp = await _put('/me/player/pause', query: {'device_id': deviceId});
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  Future<bool> resume() async {
    final deviceId = await getActiveDeviceId();
    if (deviceId == null) return false;
    final resp = await _put('/me/player/play', query: {'device_id': deviceId});
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  Future<bool> skipNext() async {
    final resp = await _post('/me/player/next');
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  Future<bool> skipPrevious() async {
    final resp = await _post('/me/player/previous');
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  /// Add a track URI to the user's playback queue.
  Future<bool> queueTrack(String trackUri) async {
    final resp = await _post('/me/player/queue', query: {'uri': trackUri});
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

  // ── Now playing ───────────────────────────────────────────────────────────

  Future<NowPlaying?> getNowPlaying() async {
    final resp = await _get('/me/player/currently-playing');
    if (resp.statusCode == 204 || resp.body.isEmpty) return null;
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json['item'] == null) return null;
    return NowPlaying.fromJson(json);
  }

  /// Polls now-playing every [interval]. Close the returned StreamController
  /// to stop polling.
  Stream<NowPlaying?> pollNowPlaying({Duration interval = const Duration(seconds: 3)}) {
    late StreamController<NowPlaying?> controller;
    Timer? timer;

    controller = StreamController<NowPlaying?>(
      onListen: () {
        timer = Timer.periodic(interval, (_) async {
          try {
            final np = await getNowPlaying();
            if (!controller.isClosed) controller.add(np);
          } catch (e) {
            debugPrint('[SpotifyApi] pollNowPlaying error: $e');
          }
        });
        // Fire immediately on first listen
        getNowPlaying().then((np) {
          if (!controller.isClosed) controller.add(np);
        });
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );

    return controller.stream;
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<List<SpotifyTrack>> searchTracks(String query, {int limit = 20}) async {
    final resp = await _get('/search', query: {
      'q': query,
      'type': 'track',
      'limit': '$limit',
    });
    if (resp.statusCode != 200) return [];
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final tracks = json['tracks'] as Map<String, dynamic>? ?? {};
    final items = (tracks['items'] as List?) ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .map((t) => SpotifyTrack.fromJson(t))
        .toList();
  }

  // ── Playlists ─────────────────────────────────────────────────────────────

  Future<List<SpotifyPlaylist>> getMyPlaylists({int limit = 50}) async {
    final resp = await _get('/me/playlists', query: {'limit': '$limit'});
    if (resp.statusCode != 200) return [];
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (json['items'] as List?) ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .map((p) => SpotifyPlaylist.fromJson(p))
        .toList();
  }

  Future<String?> createPlaylist(String name, {String description = '', bool public = false}) async {
    final userResp = await _get('/me');
    if (userResp.statusCode != 200) return null;
    final userId = (jsonDecode(userResp.body) as Map<String, dynamic>)['id'] as String;

    final resp = await _post('/users/$userId/playlists', body: {
      'name': name,
      'description': description,
      'public': public,
    });
    if (resp.statusCode != 201 && resp.statusCode != 200) return null;
    return (jsonDecode(resp.body) as Map<String, dynamic>)['id'] as String?;
  }

  Future<bool> addToPlaylist(String playlistId, List<String> trackUris) async {
    final resp = await _post('/playlists/$playlistId/tracks', body: {
      'uris': trackUris,
    });
    return resp.statusCode == 201 || resp.statusCode == 200;
  }
}
