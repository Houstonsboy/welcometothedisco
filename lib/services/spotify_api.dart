import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:welcometothedisco/models/artist_versus_model.dart';
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
  final String artistName;      // primary artist display name
  final String? artistId;       // primary artist ID
  final List<String> allArtistIds;    // ALL credited artist IDs
  final List<String> allArtistNames;  // ALL credited artist names
  final String? albumArtUrl;
  final int popularity;   // 0-100, from full track objects only
  final String? isrc;     // international standard recording code for dedup

  const SpotifyTrack({
    required this.id,
    required this.uri,
    required this.name,
    required this.artistName,
    this.artistId,
    this.allArtistIds = const [],
    this.allArtistNames = const [],
    this.albumArtUrl,
    this.popularity = 0,
    this.isrc,
  });

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) {
    final artists =
        (json['artists'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final album = json['album'] as Map<String, dynamic>? ?? {};
    final images =
        (album['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final externalIds = json['external_ids'] as Map<String, dynamic>? ?? {};
    return SpotifyTrack(
      id: json['id'] as String? ?? '',
      uri: json['uri'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      artistName:
          artists.isNotEmpty ? artists.first['name'] as String? ?? '' : '',
      artistId: artists.isNotEmpty ? artists.first['id'] as String? : null,
      allArtistIds: artists
          .map((a) => a['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
      allArtistNames: artists
          .map((a) => a['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList(),
      albumArtUrl: images.isNotEmpty ? images.first['url'] as String? : null,
      popularity: json['popularity'] as int? ?? 0,
      isrc: externalIds['isrc'] as String?,
    );
  }

  /// Returns true if [artistId] or [artistName] appears anywhere in
  /// the full credited artists list — covers features and collabs.
  bool hasArtist({String? id, String? name}) {
    if (id != null && allArtistIds.contains(id)) return true;
    if (name != null) {
      final lower = name.toLowerCase();
      return allArtistNames.any((n) => n.toLowerCase().contains(lower));
    }
    return false;
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
    if (resp.statusCode >= 400) debugPrint('[SpotifyApi] GET $path error body: ${resp.body}');
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
    if (resp.statusCode >= 400) debugPrint('[SpotifyApi] PUT $path error body: ${resp.body}');
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
    if (resp.statusCode >= 400) debugPrint('[SpotifyApi] POST $path error body: ${resp.body}');
    return resp;
  }

  // ── Devices ───────────────────────────────────────────────────────────────

  Future<SpotifyUser?> getCurrentUser() async {
    final resp = await _get('/me');
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return SpotifyUser.fromJson(json);
  }

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

  Future<bool> playRoundTracks(String track1Uri, String track2Uri) async {
    final deviceId = await getActiveDeviceId();
    if (deviceId == null) {
      debugPrint('[SpotifyApi] playRoundTracks() — no active device');
      return false;
    }
    final playResp = await _put(
      '/me/player/play',
      query: {'device_id': deviceId},
      body: {'uris': [track1Uri]},
    );
    if (playResp.statusCode != 204 && playResp.statusCode != 200) {
      debugPrint('[SpotifyApi] playRoundTracks() — play failed: ${playResp.statusCode}');
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 300));
    final queueResp = await _post(
      '/me/player/queue',
      query: {'uri': track2Uri, 'device_id': deviceId},
    );
    final queueOk = queueResp.statusCode == 204 || queueResp.statusCode == 200;
    debugPrint('[SpotifyApi] playRoundTracks() — queue track2: ${queueResp.statusCode}');
    return queueOk;
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

  Future<bool> queueTrack(String trackUri) async {
    final resp = await _post('/me/player/queue', query: {'uri': trackUri});
    return resp.statusCode == 204 || resp.statusCode == 200;
  }

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

  Future<List<SpotifyArtistDetails>> searchArtists(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final resp = await _get('/search', query: {
      'q': q,
      'type': 'artist',
      'limit': '$limit',
    });
    if (resp.statusCode != 200) return [];
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final artists = json['artists'] as Map<String, dynamic>? ?? {};
    final items = (artists['items'] as List?) ?? [];
    return items
        .cast<Map<String, dynamic>>()
        .map((a) => SpotifyArtistDetails.fromJson(a))
        .toList();
  }

  /// Search for tracks by query, scoped to two artist IDs.
  ///
  /// Strategy: run two parallel Spotify track searches using
  /// `artist:<name>` qualifier — one per artist — then merge,
  /// deduplicate by track ID, and filter to only tracks whose
  /// primary artist ID matches one of the two provided IDs.
  ///
  /// This gives real Spotify search ranking (not just top-tracks)
  /// while guaranteeing results belong to the selected artists.
  Future<Map<String, List<SpotifyTrack>>> searchTracksByArtists(
  String query, {
  required String artist1Id,
  required String artist1Name,
  required String artist2Id,
  required String artist2Name,
  int limitPerArtist = 20,
}) async {
  final q = query.trim();
  if (q.isEmpty) return {artist1Id: [], artist2Id: []};

  // Run three searches in parallel:
  // [0] artist-scoped for artist1 (catches their main tracks)
  // [1] artist-scoped for artist2 (catches their main tracks)
  // [2] broad query with no artist qualifier (catches features for both)
  // The broad search returns more results so we request a higher limit.
  final responses = await Future.wait([
    _get('/search', query: {
      'q': '$q artist:$artist1Name',
      'type': 'track',
      'limit': '$limitPerArtist',
    }),
    _get('/search', query: {
      'q': '$q artist:$artist2Name',
      'type': 'track',
      'limit': '$limitPerArtist',
    }),
    _get('/search', query: {
      'q': q,
      'type': 'track',
      'limit': '50', // broader net to surface features
    }),
  ]);

  List<SpotifyTrack> _parseTracks(http.Response resp) {
    if (resp.statusCode != 200) return [];
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final items =
        (json['tracks']?['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return items.map((t) => SpotifyTrack.fromJson(t)).toList();
  }

  // Merge artist-scoped + broad results, then partition by artist.
  // Deduplication is by track ID within each artist's final list.
  final artist1Scoped = _parseTracks(responses[0]);
  final artist2Scoped = _parseTracks(responses[1]);
  final broad = _parseTracks(responses[2]);

  List<SpotifyTrack> _buildList(
      List<SpotifyTrack> scoped, String artistId, String artistName) {
    // Start with artist-scoped results (best ranking), then append
    // any featured tracks found in the broad search not already present.
    final seen = <String>{};
    final result = <SpotifyTrack>[];

    for (final track in [...scoped, ...broad]) {
      if (seen.contains(track.id)) continue;
      if (!track.hasArtist(id: artistId, name: artistName)) continue;
      seen.add(track.id);
      result.add(track);
    }
    return result;
  }

  return {
    artist1Id: _buildList(artist1Scoped, artist1Id, artist1Name),
    artist2Id: _buildList(artist2Scoped, artist2Id, artist2Name),
  };
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

  Future<String?> createPlaylist(String name,
      {String description = '', bool public = false}) async {
    final userResp = await _get('/me');
    if (userResp.statusCode != 200) return null;
    final userId =
        (jsonDecode(userResp.body) as Map<String, dynamic>)['id'] as String;

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

  Future<SpotifyAlbumDetails?> getAlbumDetails(String albumId) async {
    if (albumId.isEmpty) return null;
    final resp = await _get('/albums/$albumId');
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return SpotifyAlbumDetails.fromJson(json);
  }

  Future<SpotifyArtistDetails?> getArtistDetails(String artistId) async {
    if (artistId.isEmpty) return null;
    final resp = await _get('/artists/$artistId');
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return SpotifyArtistDetails.fromJson(json);
  }

  Future<List<SpotifyTrack>> getArtistTopTracks(
    String artistId, {
    String market = 'US',
  }) async {
    if (artistId.isEmpty) return [];
    final resp = await _get(
      '/artists/$artistId/top-tracks',
      query: {'market': market},
    );
    if (resp.statusCode != 200) {
      debugPrint(
          '[SpotifyApi] getArtistTopTracks($artistId) → ${resp.statusCode}');
      return [];
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final items =
        (json['tracks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return items.map((t) => SpotifyTrack.fromJson(t)).toList();
  }

  Future<List<List<SpotifyTrack>>> getBothArtistsTopTracks(
    String artist1Id,
    String artist2Id, {
    String market = 'US',
  }) async {
    final results = await Future.wait([
      getArtistTopTracks(artist1Id, market: market),
      getArtistTopTracks(artist2Id, market: market),
    ]);
    return results;
  }

  /// Fetches an artist's full discography (albums + singles), collects all
  /// track IDs, batch-fetches full track details for popularity scores, then
  /// deduplicates by ISRC and returns tracks sorted by popularity descending.
  Future<List<SpotifyTrack>> getArtistDiscographyTracks(
    String artistId, {
    String market = 'US',
  }) async {
    if (artistId.isEmpty) return [];

    // Step 1: get artist's own albums and singles (up to 50 — covers most artists)
    final albumsResp = await _get(
      '/artists/$artistId/albums',
      query: {
        'include_groups': 'album,single',
        'market': market,
        'limit': '50',
      },
    );
    if (albumsResp.statusCode != 200) return [];

    final albumsJson = jsonDecode(albumsResp.body) as Map<String, dynamic>;
    final albumItems =
        (albumsJson['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final albumIds = albumItems
        .map((a) => a['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (albumIds.isEmpty) return [];

    // Step 2: batch-fetch full album objects (includes first 50 tracks each)
    final albumBatches = <List<String>>[];
    for (int i = 0; i < albumIds.length; i += 20) {
      albumBatches.add(albumIds.sublist(i, math.min(i + 20, albumIds.length)));
    }

    final albumResponses = await Future.wait(
      albumBatches.map((batch) => _get('/albums', query: {'ids': batch.join(',')})),
    );

    // Step 3: collect all track IDs from the embedded track lists
    final allTrackIds = <String>[];
    for (final resp in albumResponses) {
      if (resp.statusCode != 200) continue;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final albums =
          (json['albums'] as List?)?.cast<Map<String, dynamic>?>() ?? [];
      for (final album in albums) {
        if (album == null) continue;
        final trackPage = album['tracks'] as Map<String, dynamic>? ?? {};
        final items =
            (trackPage['items'] as List?)?.cast<Map<String, dynamic>?>() ?? [];
        for (final track in items) {
          if (track == null) continue;
          final id = track['id'] as String? ?? '';
          if (id.isNotEmpty) allTrackIds.add(id);
        }
      }
    }

    if (allTrackIds.isEmpty) return [];

    // Step 4: batch-fetch full track objects (adds popularity + ISRC)
    final uniqueIds = allTrackIds.toSet().toList();
    final fullTracks = await getTracksByIds(uniqueIds);

    // Step 5: sort by popularity first (so we keep the best version when deduping)
    fullTracks.sort((a, b) => b.popularity.compareTo(a.popularity));

    // Step 6: filter to this artist, deduplicate by ISRC then name+artist fallback
    final deduped = <SpotifyTrack>[];
    final seenIsrcs = <String>{};
    final seenNameKeys = <String>{};

    for (final track in fullTracks) {
      if (!track.hasArtist(id: artistId)) continue;

      final isrc = track.isrc;
      if (isrc != null && isrc.isNotEmpty) {
        if (!seenIsrcs.add(isrc)) continue;
      } else {
        final key = '${track.name.toLowerCase()}|${track.artistId ?? ''}';
        if (!seenNameKeys.add(key)) continue;
      }

      deduped.add(track);
    }

    return deduped; // already sorted by popularity desc
  }

  Future<List<List<SpotifyTrack>>> getBothArtistsDiscographyTracks(
    String artist1Id,
    String artist2Id, {
    String market = 'US',
  }) async {
    final results = await Future.wait([
      getArtistDiscographyTracks(artist1Id, market: market),
      getArtistDiscographyTracks(artist2Id, market: market),
    ]);
    return results;
  }

  Future<SpotifyAlbumWithTracks?> getAlbumWithTracks(String albumId) async {
    if (albumId.isEmpty) return null;
    final resp = await _get('/albums/$albumId');
    if (resp.statusCode != 200) {
      debugPrint(
          '[SpotifyApi] getAlbumWithTracks($albumId) → ${resp.statusCode}');
      return null;
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return SpotifyAlbumWithTracks.fromJson(json);
  }

  Future<List<SpotifyAlbumWithTracks?>> getBothAlbumsWithTracks(
      String album1Id, String album2Id) async {
    return Future.wait([
      getAlbumWithTracks(album1Id),
      getAlbumWithTracks(album2Id),
    ]);
  }
  /// Fetches full track details for up to 50 track IDs in one request.
/// Preserves the original ID order so round indices stay consistent
/// with what was saved in Firestore.
Future<List<SpotifyTrack>> getTracksByIds(List<String> trackIds) async {
  if (trackIds.isEmpty) return [];

  // Spotify /tracks accepts max 50 IDs per request.
  // If somehow more than 50 are passed, chunk into batches.
  final allTracks = <SpotifyTrack>[];

  final chunks = <List<String>>[];
  for (int i = 0; i < trackIds.length; i += 50) {
    chunks.add(trackIds.sublist(i, math.min(i + 50, trackIds.length)));
  }

  for (final chunk in chunks) {
    final resp = await _get('/tracks', query: {'ids': chunk.join(',')});
    if (resp.statusCode != 200) {
      debugPrint('[SpotifyApi] getTracksByIds → ${resp.statusCode}');
      continue;
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final items =
        (json['tracks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    // Spotify returns null for invalid/unavailable track IDs — filter them out
    allTracks.addAll(
      items
          .where((t) => t['id'] != null)
          .map((t) => SpotifyTrack.fromJson(t)),
    );
  }

  return allTracks;
}

  Future<VersusModel> enrichWithSpotifyData(VersusModel versus) async {
    // Images + artist names were denormalized at creation — skip Spotify call.
    if ((versus.album1ImageUrl?.isNotEmpty ?? false) &&
        (versus.album2ImageUrl?.isNotEmpty ?? false)) {
      versus.album1Title ??= versus.album1Name;
      versus.album2Title ??= versus.album2Name;
      return versus;
    }

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

  Future<List<VersusModel>> enrichVersusList(List<VersusModel> list) async {
    return Future.wait(list.map(enrichWithSpotifyData));
  }

  /// Fetches artist images from Spotify and sets artist1ImageUrl / artist2ImageUrl.
  Future<ArtistVersusModel> enrichArtistVersus(ArtistVersusModel versus) async {
    // Images were denormalized at creation — skip Spotify call.
    if ((versus.artist1ImageUrl?.isNotEmpty ?? false) &&
        (versus.artist2ImageUrl?.isNotEmpty ?? false)) {
      return versus;
    }

    final token = await TokenStorageService.getAccessToken();
    if (token == null) return versus;

    final results = await Future.wait([
      getArtistDetails(versus.artist1ID),
      getArtistDetails(versus.artist2ID),
    ]);
    final artist1 = results[0];
    final artist2 = results[1];
    versus.artist1ImageUrl = artist1?.imageUrl;
    versus.artist2ImageUrl = artist2?.imageUrl;
    return versus;
  }

  Future<List<ArtistVersusModel>> enrichArtistVersusList(
      List<ArtistVersusModel> list) async {
    return Future.wait(list.map(enrichArtistVersus));
  }
}