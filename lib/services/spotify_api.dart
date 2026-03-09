import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';

class SpotifyUser {
  final String id;
  final String displayName;
  final String? imageUrl;

  const SpotifyUser({
    required this.id,
    required this.displayName,
    this.imageUrl,
  });

  factory SpotifyUser.fromJson(Map<String, dynamic> json) {
    final images = (json['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return SpotifyUser(
      id: json['id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? json['id'] as String? ?? 'Spotify User',
      imageUrl: images.isNotEmpty ? images.first['url'] as String? : null,
    );
  }
}

class NowPlaying {
  final String? trackId;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? albumArtUrl;
  final int durationMs;
  final int progressMs;
  final bool isPlaying;

  const NowPlaying({
    this.trackId,
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
      trackId: item['id'] as String?,
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

class SpotifyAlbumDetails {
  final String id;
  final String title;
  final String artistName;
  final String? artistId;
  final String? imageUrl;

  const SpotifyAlbumDetails({
    required this.id,
    required this.title,
    required this.artistName,
    this.artistId,
    this.imageUrl,
  });

  factory SpotifyAlbumDetails.fromJson(Map<String, dynamic> json) {
    final artists = (json['artists'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final images = (json['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return SpotifyAlbumDetails(
      id: json['id'] as String? ?? '',
      title: json['name'] as String? ?? 'Unknown Album',
      artistName: artists.isNotEmpty ? artists.first['name'] as String? ?? '' : '',
      artistId: artists.isNotEmpty ? artists.first['id'] as String? : null,
      imageUrl: images.isNotEmpty ? images.first['url'] as String? : null,
    );
  }
}

class SpotifyArtistDetails {
  final String id;
  final String name;
  final String? imageUrl;

  const SpotifyArtistDetails({
    required this.id,
    required this.name,
    this.imageUrl,
  });

  factory SpotifyArtistDetails.fromJson(Map<String, dynamic> json) {
    final images = (json['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return SpotifyArtistDetails(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Artist',
      imageUrl: images.isNotEmpty ? images.first['url'] as String? : null,
    );
  }
}

class SpotifyAlbumTrack {
  final String id;
  final int trackNumber;
  final String name;
  final String artistName;
  final int durationMs;

  const SpotifyAlbumTrack({
    required this.id,
    required this.trackNumber,
    required this.name,
    required this.artistName,
    required this.durationMs,
  });

  String get uri => 'spotify:track:$id';

  String get durationFormatted {
    final m = durationMs ~/ 60000;
    final s = ((durationMs % 60000) ~/ 1000).toString().padLeft(2, '0');
    return '$m:$s';
  }

  factory SpotifyAlbumTrack.fromJson(Map<String, dynamic> json) {
    final artists = (json['artists'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return SpotifyAlbumTrack(
      id: json['id'] as String? ?? '',
      trackNumber: json['track_number'] as int? ?? 0,
      name: json['name'] as String? ?? 'Unknown Track',
      artistName: artists.isNotEmpty ? artists.first['name'] as String? ?? '' : '',
      durationMs: json['duration_ms'] as int? ?? 0,
    );
  }
}

class SpotifyAlbumWithTracks {
  final String id;
  final String title;
  final String artistName;
  final String? imageUrl;
  final int totalTracks;
  final String releaseDate;
  final List<SpotifyAlbumTrack> tracks;

  const SpotifyAlbumWithTracks({
    required this.id,
    required this.title,
    required this.artistName,
    this.imageUrl,
    required this.totalTracks,
    required this.releaseDate,
    required this.tracks,
  });

  factory SpotifyAlbumWithTracks.fromJson(Map<String, dynamic> json) {
    final artists = (json['artists'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final images = (json['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tracksJson = json['tracks'] as Map<String, dynamic>? ?? {};
    final trackItems = (tracksJson['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return SpotifyAlbumWithTracks(
      id: json['id'] as String? ?? '',
      title: json['name'] as String? ?? 'Unknown Album',
      artistName: artists.isNotEmpty ? artists.first['name'] as String? ?? '' : '',
      imageUrl: images.isNotEmpty ? images.first['url'] as String? : null,
      totalTracks: json['total_tracks'] as int? ?? trackItems.length,
      releaseDate: json['release_date'] as String? ?? '',
      tracks: trackItems.map(SpotifyAlbumTrack.fromJson).toList(),
    );
  }
}

class SpotifyApi {
  static const String _base = 'https://api.spotify.com/v1';

  SpotifyApi();

  // ── Internal helpers ────────────────────────────────────────────────────

  Future<Map<String, String>?> _headers() async {
    final token = await TokenStorageService.getAccessToken();
    if (token == null) return null;
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<http.Response> _get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final h = await _headers();
    if (h == null) {
      debugPrint('[SpotifyApi] GET $path → no token (Spotify not connected)');
      return http.Response('', 401);
    }
    final resp = await http.get(uri, headers: h);
    debugPrint('[SpotifyApi] GET $path → ${resp.statusCode}');
    return resp;
  }

  Future<http.Response> _put(String path, {Object? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final h = await _headers();
    if (h == null) {
      debugPrint('[SpotifyApi] PUT $path → no token (Spotify not connected)');
      return http.Response('', 401);
    }
    final resp = await http.put(uri, headers: h, body: body != null ? jsonEncode(body) : null);
    debugPrint('[SpotifyApi] PUT $path → ${resp.statusCode}');
    return resp;
  }

  Future<http.Response> _post(String path, {Object? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final h = await _headers();
    if (h == null) {
      debugPrint('[SpotifyApi] POST $path → no token (Spotify not connected)');
      return http.Response('', 401);
    }
    final resp = await http.post(uri, headers: h, body: body != null ? jsonEncode(body) : null);
    debugPrint('[SpotifyApi] POST $path → ${resp.statusCode}');
    return resp;
  }

  // ── Devices ───────────────────────────────────────────────────────────────

  /// Current Spotify user profile (display name, image). Returns null if not connected or request fails.
  Future<SpotifyUser?> getCurrentUser() async {
    final resp = await _get('/me');
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return SpotifyUser.fromJson(json);
  }

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

  /// Queue two tracks for a versus round in sequence.
  /// Returns true only when both queue calls succeed.
  Future<bool> queueRoundTracks(String track1Uri, String track2Uri) async {
    final firstOk = await queueTrack(track1Uri);
    if (!firstOk) return false;
    final secondOk = await queueTrack(track2Uri);
    if (!secondOk) return false;
    debugPrint('[SpotifyApi] queued round tracks: $track1Uri | $track2Uri');
    return true;
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

  /// Search for albums by user query. Returns list of album details (id, title, artist, image).
  Future<List<SpotifyAlbumDetails>> searchAlbums(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final resp = await _get('/search', query: {
      'q': q,
      'type': 'album',
      'limit': '$limit',
    });
    if (resp.statusCode != 200) return [];
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final albums = json['albums'] as Map<String, dynamic>? ?? {};
    final items = (albums['items'] as List?) ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .map((a) => SpotifyAlbumDetails.fromJson(a))
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

  // ── Versus album enrichment ───────────────────────────────────────────────

  /// Fetches Spotify album metadata for one album ID (cover, title, artist only).
  Future<SpotifyAlbumDetails?> getAlbumDetails(String albumId) async {
    if (albumId.isEmpty) return null;
    final resp = await _get('/albums/$albumId');
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return SpotifyAlbumDetails.fromJson(json);
  }

  /// Fetches Spotify artist metadata for one artist ID (name, profile image).
  Future<SpotifyArtistDetails?> getArtistDetails(String artistId) async {
    if (artistId.isEmpty) return null;
    final resp = await _get('/artists/$artistId');
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return SpotifyArtistDetails.fromJson(json);
  }

  /// Fetches full album data including the track list for a single album ID.
  Future<SpotifyAlbumWithTracks?> getAlbumWithTracks(String albumId) async {
    if (albumId.isEmpty) return null;
    final resp = await _get('/albums/$albumId');
    if (resp.statusCode != 200) {
      debugPrint('[SpotifyApi] getAlbumWithTracks($albumId) → ${resp.statusCode}');
      return null;
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return SpotifyAlbumWithTracks.fromJson(json);
  }

  /// Fetches full album data for two album IDs in parallel.
  Future<List<SpotifyAlbumWithTracks?>> getBothAlbumsWithTracks(
      String album1Id, String album2Id) async {
    return Future.wait([
      getAlbumWithTracks(album1Id),
      getAlbumWithTracks(album2Id),
    ]);
  }

  /// Takes a VersusModel, fetches album1/album2 details in parallel,
  /// and mutates the same model with title/artist/image fields.
  Future<VersusModel> enrichWithSpotifyData(VersusModel versus) async {
    final token = await TokenStorageService.getAccessToken();
    if (token == null) return versus;

    final results = await Future.wait([
      getAlbumDetails(versus.album1ID),
      getAlbumDetails(versus.album2ID),
    ]);

    final album1 = results[0];
    final album2 = results[1];

    versus.album1Title = album1?.title ?? versus.album1Name ?? versus.album1ID;
    versus.album1ArtistName = album1?.artistName;
    versus.album1ImageUrl = album1?.imageUrl;

    versus.album2Title = album2?.title ?? versus.album2Name ?? versus.album2ID;
    versus.album2ArtistName = album2?.artistName;
    versus.album2ImageUrl = album2?.imageUrl;

    return versus;
  }

  /// Enriches all versus docs with album metadata.
  Future<List<VersusModel>> enrichVersusList(List<VersusModel> list) async {
    return Future.wait(list.map(enrichWithSpotifyData));
  }
}
