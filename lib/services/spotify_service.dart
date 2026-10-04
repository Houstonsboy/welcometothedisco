import 'package:welcometothedisco/services/spotify_api.dart';

export 'spotify_api.dart'
    show SpotifyApi, SpotifyTrack, SpotifyArtistDetails, NowPlaying;

/// Spotify access for versus flows (lockeroom, backroom, playground).
/// Single [SpotifyApi] instance so token/session behavior stays consistent.
class SpotifyService {
  SpotifyService._();

  static final SpotifyApi api = SpotifyApi();
}
