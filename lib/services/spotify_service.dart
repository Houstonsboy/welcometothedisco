import 'package:welcometothedisco/services/spotify_api.dart';

export 'spotify_api.dart'
    show SpotifyApi, SpotifyUser, SpotifyTrack, SpotifyArtistDetails, NowPlaying,
        PlaybackResult;

/// Spotify access for versus flows (lockeroom, backroom, playground).
/// Single [SpotifyApi] instance so token/session behavior stays consistent.
class SpotifyService {
  SpotifyService._();

  static final SpotifyApi api = SpotifyApi();

  static SpotifyUser? _currentUser;

  /// Cached profile from the last [refreshCurrentUser] call. Null until the
  /// first successful fetch (e.g. before Spotify login completes).
  static SpotifyUser? get currentUser => _currentUser;

  /// Whether the signed-in Spotify account is Premium. Fails closed: unknown
  /// (not yet fetched, or the fetch failed) reads as false so playback
  /// controls never appear enabled only to 403 with PREMIUM_REQUIRED.
  static bool get isPremium => _currentUser?.isPremium ?? false;

  /// Fetches and caches the current Spotify profile (including
  /// [SpotifyUser.product]). Call once after Spotify login/connect; safe to
  /// call again to refresh (e.g. after a Spotify tier change).
  static Future<SpotifyUser?> refreshCurrentUser() async {
    final user = await api.getCurrentUser();
    _currentUser = user;
    return user;
  }
}
