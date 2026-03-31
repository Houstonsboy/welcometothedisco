import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kDefaultColor1 = AppTheme.gradientStart;
const _kDefaultColor2 = AppTheme.gradientEnd;
const _kSpotifyGreen  = AppTheme.spotifyGreen;

class VersusPlayground extends StatefulWidget {
  final VersusModel versus;

  const VersusPlayground({super.key, required this.versus});

  @override
  State<VersusPlayground> createState() => _VersusPlaygroundState();
}

class _VersusPlaygroundState extends State<VersusPlayground>
    with TickerProviderStateMixin {
  final SpotifyApi _api = SpotifyApi();

  late final Future<List<SpotifyAlbumWithTracks?>> _albumsFuture;
  late final AnimationController _pulseController;
  late final AnimationController _slideController;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _slideAnim;

  int _selectedAlbum = 0; // 0 = album1, 1 = album2
  late final PageController _pageController;
  int _activeTrackIndex = 0; // shared across both albums — same index = head-to-head
  int? _playingTrackIndex;

  /// Which album's track plays FIRST when Play is pressed.
  /// 0 = album1 leads (default), 1 = album2 leads.
  /// Set by tapping a row on a specific album tab.
  int _leadAlbumIndex = 0;

  /// Resolved album data (set once the future completes).
  List<SpotifyAlbumWithTracks?>? _albums;

  /// True while the play button is firing the Spotify play + queue calls.
  bool _isPlayLoading = false;
  bool _isBombLoading = false;
  StreamSubscription<NowPlaying?>? _nowPlayingSub;
  String? _advanceOnTrackId;
  String? _currentRoundTrack1Id;
  String? _currentRoundTrack2Id;
  bool _roundTrack2Started = false;

  /// At each track index, which album was voted: 0 = album1, 1 = album2.
  /// Only one vote per index (toggle: voting for one disables the other).
  final Map<int, int> _votesByIndex = {};

  // extracted palette colors — start with defaults
  Color _color1 = _kDefaultColor1;
  Color _color2 = _kDefaultColor2;

  @override
  void initState() {
    super.initState();
    _albumsFuture = _api.getBothAlbumsWithTracks(
      widget.versus.album1ID,
      widget.versus.album2ID,
    );

    _albumsFuture.then((list) {
      if (!mounted || list == null || list.length < 2) return;
      setState(() => _albums = list);
      _extractPalette(
        list[0]?.imageUrl ?? widget.versus.album1ImageUrl,
        list[1]?.imageUrl ?? widget.versus.album2ImageUrl,
      );
    });

    _pageController = PageController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnim = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );

    _slideController.forward();
  }

  Future<void> _extractPalette(String? url1, String? url2) async {
    if (url1 != null && url1.isNotEmpty) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          NetworkImage(url1),
          size: const Size(200, 200),
        );
        final color = palette.vibrantColor?.color ??
            palette.dominantColor?.color ??
            _kDefaultColor1;
        if (mounted) setState(() => _color1 = color);
      } catch (_) {}
    }
    if (url2 != null && url2.isNotEmpty) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          NetworkImage(url2),
          size: const Size(200, 200),
        );
        final color = palette.vibrantColor?.color ??
            palette.dominantColor?.color ??
            _kDefaultColor2;
        if (mounted) setState(() => _color2 = color);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _nowPlayingSub?.cancel();
    _pulseController.dispose();
    _slideController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _selectAlbum(int index) {
    if (_selectedAlbum == index) return;
    setState(() => _selectedAlbum = index);
    _slideController.forward(from: 0);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    if (_selectedAlbum == index) return;
    setState(() => _selectedAlbum = index);
    _slideController.forward(from: 0);
  }

  /// Play current round: the lead track (from the album the user tapped, or
  /// album1 by default) plays first; the other album's track at the same index
  /// is queued immediately after. Index only advances once the second track finishes.
  Future<void> _handlePlay() async {
    final albums = _albums;
    if (albums == null || albums.length < 2) return;
    final roundIndex = _activeTrackIndex;

    // Determine lead vs follow based on which album tab was last tapped.
    final leadAlbum   = _leadAlbumIndex;
    final followAlbum = leadAlbum == 0 ? 1 : 0;

    final tLead   = albums[leadAlbum]?.tracks.elementAtOrNull(roundIndex);
    final tFollow = albums[followAlbum]?.tracks.elementAtOrNull(roundIndex);
    if (tLead == null || tFollow == null ||
        tLead.id.isEmpty || tFollow.id.isEmpty) return;

    setState(() => _isPlayLoading = true);
    try {
      // play(lead) → queue(follow) so both land in the same "Next in Queue"
      // bucket that Bomb also uses, preserving correct order.
      final played = await _api.playRoundTracks(tLead.uri, tFollow.uri);
      if (!played) return;

      // Track the follow-track to detect when index should advance.
      _currentRoundTrack1Id = tLead.id;
      _currentRoundTrack2Id = tFollow.id;
      _roundTrack2Started = false;
      _advanceOnTrackId = tFollow.id;
      _startNowPlayingIndexTracking();
      if (mounted) {
        setState(() => _playingTrackIndex = roundIndex);
      }
    } catch (e) {
      debugPrint('[Playground] _handlePlay error: $e');
    } finally {
      if (mounted) setState(() => _isPlayLoading = false);
    }
  }

  void _startNowPlayingIndexTracking() {
    _nowPlayingSub?.cancel();
    _nowPlayingSub = _api
        .pollNowPlaying(interval: const Duration(seconds: 2))
        .listen((nowPlaying) {
      final trackId = nowPlaying?.trackId;
      if (!mounted || trackId == null || trackId.isEmpty) return;

      final roundTrack2 = _currentRoundTrack2Id;
      if (roundTrack2 == null || _advanceOnTrackId == null) return;

      // Detect when round track2 actually starts.
      if (trackId == roundTrack2) {
        _roundTrack2Started = true;
        return;
      }

      // Once track2 has started, advance only when playback moves away from it.
      if (_roundTrack2Started && trackId != roundTrack2) {
        final albums = _albums;
        final total = math.min(
          albums?[0]?.tracks.length ?? 0,
          albums?[1]?.tracks.length ?? 0,
        );
        if (_activeTrackIndex < total - 1) {
          setState(() {
            _activeTrackIndex++;
            _playingTrackIndex = null;
          });
        } else {
          setState(() => _playingTrackIndex = null);
        }
        _advanceOnTrackId = null;
        _currentRoundTrack1Id = null;
        _currentRoundTrack2Id = null;
        _roundTrack2Started = false;
      }
    });
  }

  /// Queue both album tracks for a single round index.
  /// Returns true only if both tracks are queued successfully.
  Future<bool> _queueRoundAtIndex(int index) async {
    final albums = _albums;
    if (albums == null || albums.length < 2) return false;

    final a1Track = albums[0]?.tracks.elementAtOrNull(index);
    final a2Track = albums[1]?.tracks.elementAtOrNull(index);
    if (a1Track == null ||
        a2Track == null ||
        a1Track.id.isEmpty ||
        a2Track.id.isEmpty) {
      return false;
    }

    return _api.queueRoundTracks(a1Track.uri, a2Track.uri);
  }

  /// One-tap bomb: queue round pairs from the *next* index through the last
  /// (current index is already playing/queued via Play; we do not re-queue it).
  Future<void> _handleNext() async {
    if (_isBombLoading) return;
    final albums = _albums;
    if (albums == null || albums.length < 2) return;
    final a1Total = albums[0]?.tracks.length ?? 0;
    final a2Total = albums[1]?.tracks.length ?? 0;
    final total = math.min(a1Total, a2Total);
    if (total <= 0 || _activeTrackIndex >= total - 1) return;

    setState(() => _isBombLoading = true);
    try {
      for (int i = _activeTrackIndex + 1; i < total; i++) {
        final queued = await _queueRoundAtIndex(i);
        if (!queued) {
          debugPrint('[Playground] bomb queue stopped at index $i');
          break;
        }
      }
    } catch (e) {
      debugPrint('[Playground] _handleNext queue error: $e');
    } finally {
      if (mounted) setState(() => _isBombLoading = false);
    }
  }

  void _onVote(int trackIndex, int albumIndex) {
    setState(() {
      _votesByIndex[trackIndex] = albumIndex;
    });
  }

  /// Tap any row to jump the active round to that index AND remember which
  /// album tab was tapped so Play knows which track to start with.
  void _onTrackTapped(int trackIndex, int albumIndex) {
    _nowPlayingSub?.cancel();
    _nowPlayingSub = null;
    _advanceOnTrackId = null;
    _currentRoundTrack1Id = null;
    _currentRoundTrack2Id = null;
    _roundTrack2Started = false;
    setState(() {
      _activeTrackIndex = trackIndex;
      _leadAlbumIndex = albumIndex;
      _playingTrackIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authorUsername = widget.versus.author?.username;
    final authorLabel = (authorUsername != null && authorUsername.isNotEmpty)
        ? '@$authorUsername'
        : widget.versus.authorId;
    final avatarPath = widget.versus.author?.avatarPath;

    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<SpotifyAlbumWithTracks?>>(
        future: _albumsFuture,
        builder: (context, snapshot) {
          final album1 = snapshot.data?[0];
          final album2 = snapshot.data?[1];

          final a1Title = album1?.title ?? widget.versus.album1Name ?? 'Album 1';
          final a2Title = album2?.title ?? widget.versus.album2Name ?? 'Album 2';
          final a1Image = album1?.imageUrl ?? widget.versus.album1ImageUrl;
          final a2Image = album2?.imageUrl ?? widget.versus.album2ImageUrl;
          final a1Artist = album1?.artistName ?? widget.versus.album1ArtistName ?? '';
          final a2Artist = album2?.artistName ?? widget.versus.album2ArtistName ?? '';

          final isLoading = snapshot.connectionState == ConnectionState.waiting;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── App Bar ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildHeader(context, authorLabel, avatarPath),
              ),

              // ── VS Selector ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildVsSelector(
                  a1Title: a1Title,
                  a2Title: a2Title,
                  a1Image: a1Image,
                  a2Image: a2Image,
                  a1Artist: a1Artist,
                  a2Artist: a2Artist,
                  isLoading: isLoading,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // ── Swipe hint dots ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SwipeDot(isActive: _selectedAlbum == 0),
                      const SizedBox(width: 6),
                      _SwipeDot(isActive: _selectedAlbum == 1),
                    ],
                  ),
                ),
              ),

              // ── Track PageView ────────────────────────────────────────────
              SliverFillRemaining(
                child: isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: _color1),
                      )
                    : Column(
                        children: [
                          // ── Play button + Round indicator ──────────────────
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Row(
                              children: [
                                // Play button (green)
                                GestureDetector(
                                  onTap: _isPlayLoading ? null : _handlePlay,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _kSpotifyGreen.withOpacity(
                                          _isPlayLoading ? 0.12 : 0.25),
                                      border: Border.all(
                                        color: _kSpotifyGreen.withOpacity(
                                            _isPlayLoading ? 0.3 : 0.6),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: _isPlayLoading
                                        ? const Padding(
                                            padding: EdgeInsets.all(10),
                                            child: CircularProgressIndicator(
                                              color: _kSpotifyGreen,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.play_arrow_rounded,
                                            color: _kSpotifyGreen,
                                            size: 24,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Round pill (same design, green)
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 7, horizontal: 14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(99),
                                      color: _kSpotifyGreen.withOpacity(0.2),
                                      border: Border.all(
                                          color: _kSpotifyGreen.withOpacity(0.5),
                                          width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _kSpotifyGreen,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'ROUND ${_activeTrackIndex + 1}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                        if (_playingTrackIndex != null) ...[
                                          const SizedBox(width: 10),
                                          Text(
                                            'PLAY ${_playingTrackIndex! + 1}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.82),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.1,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Next button
                                GestureDetector(
                                  onTap: _isBombLoading ? null : _handleNext,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(99),
                                      color: _kSpotifyGreen.withOpacity(
                                          _isBombLoading ? 0.12 : 0.25),
                                      border: Border.all(
                                        color: _kSpotifyGreen.withOpacity(
                                            _isBombLoading ? 0.3 : 0.6),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_isBombLoading)
                                          const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.8,
                                              color: _kSpotifyGreen,
                                            ),
                                          )
                                        else
                                          const Text(
                                          'BOMB',
                                          style: TextStyle(
                                            color: _kSpotifyGreen,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                        SizedBox(width: 4),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          color: _kSpotifyGreen,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── Swipeable track lists ─────────────────────────
                          Expanded(
                            child: PageView(
                              controller: _pageController,
                              onPageChanged: _onPageChanged,
                              children: [
                                _TrackPage(
                                  album: album1,
                                  albumIndex: 0,
                                  fallbackTitle: a1Title,
                                  fallbackArtist: a1Artist,
                                  fallbackImageUrl: a1Image,
                                  slideAnim: _slideAnim,
                                  accentColor: _color1,
                                  isVisible: _selectedAlbum == 0,
                                  activeTrackIndex: _activeTrackIndex,
                                  voteAtActiveIndex: _votesByIndex[_activeTrackIndex],
                                  onVote: (int albumIndex) => _onVote(_activeTrackIndex, albumIndex),
                                  onTrackTap: (trackIndex, albumIndex) =>
                                      _onTrackTapped(trackIndex, albumIndex),
                                ),
                                _TrackPage(
                                  album: album2,
                                  albumIndex: 1,
                                  fallbackTitle: a2Title,
                                  fallbackArtist: a2Artist,
                                  fallbackImageUrl: a2Image,
                                  slideAnim: _slideAnim,
                                  accentColor: _color2,
                                  isVisible: _selectedAlbum == 1,
                                  activeTrackIndex: _activeTrackIndex,
                                  voteAtActiveIndex: _votesByIndex[_activeTrackIndex],
                                  onVote: (int albumIndex) => _onVote(_activeTrackIndex, albumIndex),
                                  onTrackTap: (trackIndex, albumIndex) =>
                                      _onTrackTapped(trackIndex, albumIndex),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    ),
    );
  }

  // ── Avatar helper ───────────────────────────────────────────────────────────
  /// Renders a local asset avatar (e.g. "avatar1.jpeg") or a network URL.
  Widget _resolveAvatarWidget(String avatarPath, double size) {
    final p = avatarPath.trim();
    if (p.isEmpty) {
      return Container(
        width: size, height: size,
        color: Colors.white.withOpacity(0.2),
        child: Icon(Icons.person_rounded,
            color: Colors.white.withOpacity(0.8), size: size * 0.55),
      );
    }
    // Network URL
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return Image.network(p, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(size));
    }
    // Local asset — normalise to "assets/images/<filename>"
    final assetPath = p.startsWith('assets/') ? p : 'assets/images/$p';
    return Image.asset(assetPath, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _avatarFallback(size));
  }

  Widget _avatarFallback(double size) => Container(
        width: size, height: size,
        color: Colors.white.withOpacity(0.2),
        child: Icon(Icons.person_rounded,
            color: Colors.white.withOpacity(0.8), size: size * 0.55),
      );

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(
      BuildContext context, String authorLabel, String? avatarPath) {
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 20,
        right: 20,
        bottom: 8,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
                border: Border.all(
                    color: Colors.white.withOpacity(0.2), width: 0.8),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          if (avatarPath != null && avatarPath.isNotEmpty)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.gradientEnd, width: 1.5),
              ),
              child: ClipOval(
                child: _resolveAvatarWidget(avatarPath, 34),
              ),
            ),
          if (avatarPath != null && avatarPath.isNotEmpty)
            const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ALBUMS',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'JraotHollow',
                  color: Color(0xFFF07012),
                  // fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                ),
              ),
              // Text(
              //   authorLabel,
              //   style: TextStyle(
              //     color: _color2.withOpacity(0.9),
              //     fontSize: 11,
              //     fontWeight: FontWeight.w500,
              //     letterSpacing: 0.3,
              //   ),
              // ),
            ],
          ),
        ],
      ),
    );
  }

  // ── VS Selector ────────────────────────────────────────────────────────────
  Widget _buildVsSelector({
    required String a1Title,
    required String a2Title,
    required String? a1Image,
    required String? a2Image,
    required String a1Artist,
    required String a2Artist,
    required bool isLoading,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Album 1
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectAlbum(0),
                  child: _AlbumCard(
                    title: a1Title,
                    artist: a1Artist,
                    imageUrl: a1Image,
                    isSelected: _selectedAlbum == 0,
                    accentColor: _color1,
                  ),
                ),
              ),
              const SizedBox(width: 52),
              // Album 2
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectAlbum(1),
                  child: _AlbumCard(
                    title: a2Title,
                    artist: a2Artist,
                    imageUrl: a2Image,
                    isSelected: _selectedAlbum == 1,
                    accentColor: _color2,
                  ),
                ),
              ),
            ],
          ),

          // VS Badge — uses both extracted colors
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnim.value,
              child: child,
            ),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_color1, _color2],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _color2.withOpacity(0.5),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

// ── Swipe Dot indicator ─────────────────────────────────────────────────────
class _SwipeDot extends StatelessWidget {
  final bool isActive;
  const _SwipeDot({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: isActive ? 20 : 6,
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: isActive
            ? Colors.white
            : Colors.white.withOpacity(0.3),
      ),
    );
  }
}

// ── Track Page (used inside PageView) ──────────────────────────────────────
class _TrackPage extends StatelessWidget {
  final SpotifyAlbumWithTracks? album;
  final int albumIndex; // 0 = album1, 1 = album2
  final String fallbackTitle;
  final String fallbackArtist;
  final String? fallbackImageUrl;
  final Animation<double> slideAnim;
  final Color accentColor;
  final bool isVisible;
  final int activeTrackIndex;
  final int? voteAtActiveIndex; // null = no vote, 0/1 = voted for that album
  final void Function(int albumIndex) onVote;
  final void Function(int trackIndex, int albumIndex) onTrackTap;

  const _TrackPage({
    required this.album,
    required this.albumIndex,
    required this.fallbackTitle,
    required this.fallbackArtist,
    required this.fallbackImageUrl,
    required this.slideAnim,
    required this.accentColor,
    required this.isVisible,
    required this.activeTrackIndex,
    required this.voteAtActiveIndex,
    required this.onVote,
    required this.onTrackTap,
  });

  @override
  Widget build(BuildContext context) {
    final tracks = album?.tracks ?? [];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
      physics: const BouncingScrollPhysics(),
      itemCount: tracks.isEmpty ? 2 : tracks.length + 1,
      itemBuilder: (context, index) {
        // Header
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'TRACKS',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${tracks.length}',
                  style: TextStyle(
                    color: accentColor.withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }

        if (tracks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              album == null ? 'Spotify data unavailable.' : 'No tracks found.',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 14),
            ),
          );
        }

        final trackIndex = index - 1;
        if (trackIndex >= tracks.length) return const SizedBox.shrink();
        final track = tracks[trackIndex];

        final isActive = trackIndex == activeTrackIndex;
        final isPast   = trackIndex < activeTrackIndex;
        final isLocked = trackIndex > activeTrackIndex;

        return AnimatedBuilder(
          animation: slideAnim,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              0,
              24 * (1 - slideAnim.value) * math.max(0, 1 - trackIndex * 0.05),
            ),
            child: Opacity(
              opacity: slideAnim.value.clamp(0.0, 1.0),
              child: child,
            ),
          ),
          child: _TrackRow(
            key: ValueKey('album-$albumIndex-track-$trackIndex'),
            track: track,
            index: trackIndex,
            accentColor: accentColor,
            isLast: trackIndex == tracks.length - 1,
            isActive: isActive,
            isPast: isPast,
            isLocked: isLocked,
            showVoteButton: isActive,
            isVoted: isActive && voteAtActiveIndex == albumIndex,
            isVoteDisabled: isActive &&
                voteAtActiveIndex != null &&
                voteAtActiveIndex != albumIndex,
            onVote: isActive ? () => onVote(albumIndex) : null,
            onTap: () => onTrackTap(trackIndex, albumIndex),
          ),
        );
      },
    );
  }
}

// ── Album Card ──────────────────────────────────────────────────────────────
class _AlbumCard extends StatelessWidget {
  final String title;
  final String artist;
  final String? imageUrl;
  final bool isSelected;
  final Color accentColor;

  const _AlbumCard({
    required this.title,
    required this.artist,
    required this.isSelected,
    required this.accentColor,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected
              ? accentColor.withOpacity(0.7)
              : Colors.white.withOpacity(0.06),
          width: isSelected ? 1.5 : 0.8,
        ),
        color: isSelected
            ? Colors.white.withOpacity(0.15)
            : Colors.white.withOpacity(0.07),
      ),
      child: Column(
        children: [
          // Album Art
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            child: AspectRatio(
              aspectRatio: 1,
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? Image.network(imageUrl!, fit: BoxFit.cover)
                  : Container(
                      color: Colors.white.withOpacity(0.06),
                      child: Icon(
                        Icons.album_rounded,
                        size: 40,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
            ),
          ),

          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (artist.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? accentColor.withOpacity(0.9)
                          : Colors.white.withOpacity(0.35),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Track Row ───────────────────────────────────────────────────────────────
class _TrackRow extends StatefulWidget {
  final SpotifyAlbumTrack track;
  final int index;
  final Color accentColor;
  final bool isLast;
  final bool isActive;
  final bool isPast;
  final bool isLocked;
  final bool showVoteButton;
  final bool isVoted;
  final bool isVoteDisabled;
  final VoidCallback? onVote;
  final VoidCallback? onTap;

  const _TrackRow({
    super.key,
    required this.track,
    required this.index,
    required this.accentColor,
    this.isLast = false,
    this.isActive = false,
    this.isPast = false,
    this.isLocked = false,
    this.showVoteButton = false,
    this.isVoted = false,
    this.isVoteDisabled = false,
    this.onVote,
    this.onTap,
  });

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _isNoteOpen = false;
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final isActive = widget.isActive;
    final isPast = widget.isPast;
    final isLocked = widget.isLocked;
    final accentColor = widget.accentColor;
    final showVoteButton = widget.showVoteButton;
    final isVoted = widget.isVoted;
    final isVoteDisabled = widget.isVoteDisabled;
    final onVote = widget.onVote;
    final onTap = widget.onTap;
    final isLast = widget.isLast;

    // visual state — increased visibility for disabled (locked) tracks
    final textOpacity = isActive ? 1.0 : isPast ? 0.6 : 0.52;
    final numberColor = isActive
        ? accentColor
        : isPast
            ? accentColor.withOpacity(0.5)
            : Colors.white.withOpacity(0.42);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isLocked ? 0.62 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
        children: [
          Container(
            decoration: isActive
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: accentColor.withOpacity(0.42),
                    border: Border.all(
                      color: accentColor.withOpacity(0.65),
                      width: 1.2,
                    ),
                  )
                : null,
            padding: isActive
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 2)
                : EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 11, 0, 9),
              child: Column(
                children: [
                  Row(
                    children: [
                  // Track number or checkmark
                  SizedBox(
                    width: 32,
                    child: isPast
                        ? Icon(Icons.check_rounded,
                            size: 15, color: accentColor.withOpacity(0.5))
                        : isLocked
                            ? Icon(Icons.lock_rounded,
                                size: 14, color: Colors.white.withOpacity(0.45))
                            : Text(
                                '${track.trackNumber}'.padLeft(2, '0'),
                                style: TextStyle(
                                  color: numberColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                  ),
                  const SizedBox(width: 12),
                  // Track info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(textOpacity),
                            fontSize: 14,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                            letterSpacing: -0.1,
                          ),
                        ),
                        if (track.artistName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            track.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(textOpacity * 0.6),
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Voting button (only when this track is the active round).
                  // Tappable on both tracks: tap the other track's button to switch vote.
                  if (showVoteButton) ...[
                    GestureDetector(
                      onTap: onVote,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: isVoted
                              ? _kSpotifyGreen.withOpacity(0.5)
                              : isVoteDisabled
                                  ? Colors.white.withOpacity(0.08)
                                  : _kSpotifyGreen.withOpacity(0.25),
                          border: Border.all(
                            color: isVoted
                                ? _kSpotifyGreen
                                : isVoteDisabled
                                    ? Colors.white.withOpacity(0.12)
                                    : _kSpotifyGreen.withOpacity(0.6),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isVoted
                                  ? Icons.check_rounded
                                  : Icons.how_to_vote_rounded,
                              size: 14,
                              color: isVoteDisabled
                                  ? Colors.white.withOpacity(0.3)
                                  : isVoted
                                      ? Colors.white
                                      : _kSpotifyGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isVoted ? 'Voted' : 'Vote',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: isVoteDisabled
                                    ? Colors.white.withOpacity(0.3)
                                    : isVoted
                                        ? Colors.white
                                        : _kSpotifyGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // Active badge OR duration
                  if (isActive)
                    GestureDetector(
                      onTap: () => setState(() => _isNoteOpen = !_isNoteOpen),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: _isNoteOpen
                              ? accentColor.withOpacity(0.75)
                              : accentColor.withOpacity(0.55),
                        ),
                        child: const Text(
                          'NOTE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.3,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      track.durationFormatted,
                      style: TextStyle(
                        color: Colors.white.withOpacity(textOpacity * 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    ],
                  ),
                  if (_isNoteOpen && isActive) ...[
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        color: Colors.white.withOpacity(0.12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.20),
                          width: 0.8,
                        ),
                      ),
                      child: TextField(
                        controller: _noteCtrl,
                        minLines: 1,
                        maxLines: 3,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Disclaimer...',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.42),
                            fontSize: 12,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!isLast)
            Divider(
              height: 0,
              indent: 44,
              color: Colors.white.withOpacity(0.06),
            ),
        ],
      ),
      ),
    );
  }
}