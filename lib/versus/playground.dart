import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/vote_doc_template_model.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/services/user_profile_cache_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kDefaultColor1 = AppTheme.gradientStart;
const _kDefaultColor2 = AppTheme.gradientEnd;
const _kSpotifyGreen  = AppTheme.spotifyGreen;

// ── Album Track Vote Detail ───────────────────────────────────────────────────
class AlbumTrackVoteDetail {
  final String album1trackID;
  final String album2trackID;
  final String winnerTrackID;
  final String album1trackName;
  final String album2trackName;
  String voterComment;
  final bool isBonus;

  AlbumTrackVoteDetail({
    required this.album1trackID,
    required this.album2trackID,
    required this.winnerTrackID,
    required this.album1trackName,
    required this.album2trackName,
    this.voterComment = '',
    this.isBonus = false,
  });

  Map<String, dynamic> toMap() => {
    'artist1trackID':   album1trackID,
    'artist2trackID':   album2trackID,
    'Winner':           winnerTrackID,
    'voter_comment':    voterComment,
    'artist1trackName': album1trackName,
    'artist2trackName': album2trackName,
    'isBonus':          isBonus,
  };
}

class VersusPlayground extends StatefulWidget {
  final VersusModel versus;
  final String? versusId;

  const VersusPlayground({
    super.key,
    required this.versus,
    this.versusId,
  });

  @override
  State<VersusPlayground> createState() => _VersusPlaygroundState();
}

class _VersusPlaygroundState extends State<VersusPlayground>
    with TickerProviderStateMixin {
  final SpotifyApi _api = SpotifyApi();

  String get _resolvedVersusId {
    final routeId = widget.versusId?.trim() ?? '';
    if (routeId.isNotEmpty) return routeId;
    return widget.versus.id.trim();
  }

  // ── Voter identity ────────────────────────────────────────────────────────
  String _voterId   = '';
  String _voterName = '';
  String _voterAvatar = '';

  // ── Albums future + resolved data ────────────────────────────────────────
  late final Future<List<SpotifyAlbumWithTracks?>> _albumsFuture;
  List<SpotifyAlbumWithTracks?>? _albums;

  // ── Palette ───────────────────────────────────────────────────────────────
  Color _color1 = _kDefaultColor1;
  Color _color2 = _kDefaultColor2;

  // ── Animations ────────────────────────────────────────────────────────────
  late final AnimationController _pulseController;
  late final AnimationController _slideController;
  late final Animation<double>   _pulseAnim;
  late final Animation<double>   _slideAnim;
  late final PageController      _pageController;

  // ── UI state ──────────────────────────────────────────────────────────────
  int  _selectedAlbum    = 0;
  int  _activeTrackIndex = 0;
  int? _playingTrackIndex;
  int  _leadAlbumIndex   = 0;

  // ── Playback ──────────────────────────────────────────────────────────────
  bool _isPlayLoading = false;
  bool _isBombLoading = false;
  StreamSubscription<NowPlaying?>? _nowPlayingSub;
  String? _advanceOnTrackId;
  String? _currentRoundTrack1Id;
  String? _currentRoundTrack2Id;
  bool    _roundTrack2Started = false;

  // ── Vote state ────────────────────────────────────────────────────────────
  final Map<int, int>                  _votesByIndex = {};
  final Map<int, AlbumTrackVoteDetail> _trackDetails = {};

  // ── Comment controllers (state-level so they survive rebuilds & are syncable)
  final Map<int, TextEditingController> _commentControllers = {};

  TextEditingController _commentCtrlAt(int index) =>
      _commentControllers.putIfAbsent(index, () => TextEditingController());

  // ── Debounce ──────────────────────────────────────────────────────────────
  Timer? _pollDebounce;

  // ── Derived counts ────────────────────────────────────────────────────────
  int get _pairedRoundCount {
    final a = _albums;
    return math.min(
      a?[0]?.tracks.length ?? 0,
      a?[1]?.tracks.length ?? 0,
    );
  }

  int? get _longerSideAlbumIndex {
    final a  = _albums;
    final a1 = a?[0]?.tracks.length ?? 0;
    final a2 = a?[1]?.tracks.length ?? 0;
    if (a1 == a2) return null;
    return a1 > a2 ? 0 : 1;
  }

  bool get _isVotingCompleteForPairs =>
      _votesByIndex.length >= _pairedRoundCount;

  int get _bonusVoteForLongerSide =>
      (_longerSideAlbumIndex != null && _isVotingCompleteForPairs) ? 1 : 0;

  int get _album1VoteCount {
    final base  = _votesByIndex.values.where((v) => v == 0).length;
    final bonus = _longerSideAlbumIndex == 0 ? _bonusVoteForLongerSide : 0;
    return base + bonus;
  }

  int get _album2VoteCount {
    final base  = _votesByIndex.values.where((v) => v == 1).length;
    final bonus = _longerSideAlbumIndex == 1 ? _bonusVoteForLongerSide : 0;
    return base + bonus;
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    debugPrint('[VersusPlayground] opened | versus_id: ${_resolvedVersusId.isEmpty ? "(missing)" : _resolvedVersusId}');

    _pageController  = PageController();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _slideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _slideAnim = CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic);
    _slideController.forward();

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

    unawaited(_hydrateVoterContext());
  }

  // ── Voter context + session restore ──────────────────────────────────────
  Future<void> _hydrateVoterContext() async {
    final uid = FirebaseAuth.instance.currentUser?.uid?.trim() ?? '';
    if (uid.isEmpty) return;

    var cached = await UserProfileCacheService.readUser(expectedUid: uid);
    if (cached == null) {
      await FirebaseService.ensureCurrentUserProfileCached();
      cached = await UserProfileCacheService.readUser(expectedUid: uid);
    }
    if (!mounted) return;

    setState(() {
      _voterId    = uid;
      _voterName  = cached?.username.trim() ?? '';
      _voterAvatar = cached?.avatarPath.trim() ?? '';
    });

    await _restoreExistingPoll();
  }

  Future<void> _restoreExistingPoll() async {
    if (_voterId.isEmpty || _resolvedVersusId.isEmpty) return;

    // Wait for albums to be resolved — we need track data for restore.
    if (_albums == null) {
      int waited = 0;
      while (_albums == null && waited < 8000) {
        await Future.delayed(const Duration(milliseconds: 100));
        waited += 100;
      }
      if (_albums == null) {
        debugPrint('[VersusPlayground] _restoreExistingPoll → timed out waiting for albums');
        return;
      }
    }

    final data = await FirebaseService.getExistingAlbumPoll(
      versusId: _resolvedVersusId,
      voterId:  _voterId,
    );
    if (data == null || !mounted) return;

    final rawDetails = data['track_details'] as Map<String, dynamic>?;
    if (rawDetails == null || rawDetails.isEmpty) return;

    final restoredVotes   = <int, int>{};
    final restoredDetails = <int, AlbumTrackVoteDetail>{};

    for (final entry in rawDetails.entries) {
      final roundIndex = int.tryParse(entry.key);
      if (roundIndex == null) continue;

      final round   = entry.value as Map<String, dynamic>?;
      if (round == null) continue;

      final isBonus = round['isBonus'] as bool? ?? false;
      if (isBonus) continue;

      // Note: we stored these under artist1trackID/artist2trackID keys
      // to match the shared poll schema.
      final album1trackID   = round['artist1trackID']   as String? ?? '';
      final album2trackID   = round['artist2trackID']   as String? ?? '';
      final winnerId        = round['Winner']            as String? ?? '';
      final album1trackName = round['artist1trackName'] as String? ?? '';
      final album2trackName = round['artist2trackName'] as String? ?? '';
      final comment         = round['voter_comment']    as String? ?? '';

      if (winnerId.isEmpty || album1trackID.isEmpty || album2trackID.isEmpty) continue;

      final int winnerAlbumIndex;
      if (winnerId == album1trackID)      { winnerAlbumIndex = 0; }
      else if (winnerId == album2trackID) { winnerAlbumIndex = 1; }
      else { continue; }

      restoredVotes[roundIndex] = winnerAlbumIndex;
      restoredDetails[roundIndex] = AlbumTrackVoteDetail(
        album1trackID:   album1trackID,
        album2trackID:   album2trackID,
        winnerTrackID:   winnerId,
        album1trackName: album1trackName,
        album2trackName: album2trackName,
        voterComment:    comment,
        isBonus:         false,
      );
    }

    if (restoredVotes.isEmpty || !mounted) return;

    setState(() {
      _votesByIndex.addAll(restoredVotes);
      _trackDetails.addAll(restoredDetails);
    });

    for (final entry in restoredDetails.entries) {
      if (entry.value.voterComment.isNotEmpty) {
        _commentCtrlAt(entry.key).text = entry.value.voterComment;
      }
    }

    debugPrint('[VersusPlayground] _restoreExistingPoll → restored ${restoredVotes.length} round(s)');
  }

  // ── Poll sync ─────────────────────────────────────────────────────────────
  void _schedulePollSync() {
    _pollDebounce?.cancel();
    _pollDebounce = Timer(const Duration(milliseconds: 800), _syncPollToFirestore);
  }

  Future<void> _syncPollToFirestore() async {
    if (_voterId.isEmpty || _resolvedVersusId.isEmpty) return;
    final albums = _albums;
    if (albums == null || albums.length < 2) return;

    // Sync latest comment text into details before building payload.
    for (final entry in _commentControllers.entries) {
      final detail = _trackDetails[entry.key];
      if (detail != null) detail.voterComment = entry.value.text.trim();
    }

    final totalRounds = _pairedRoundCount;
    final votedCount  = _votesByIndex.length;
    final unvoted     = totalRounds > votedCount ? totalRounds - votedCount : 0;
    final completion  = totalRounds == 0
        ? 0.0
        : ((votedCount / totalRounds) * 100).clamp(0, 100).toDouble();

    // Build track_details — include bonus rounds for longer album.
    final details = <int, Map<String, dynamic>>{
      for (final e in _trackDetails.entries) e.key: e.value.toMap(),
    };

    final longerIndex = _longerSideAlbumIndex;
    if (longerIndex != null && _isVotingCompleteForPairs) {
      final longerTracks = albums[longerIndex]?.tracks ?? <SpotifyAlbumTrack>[];
      for (int i = _pairedRoundCount; i < longerTracks.length; i++) {
        final t = longerTracks[i];
        details[i] = {
          'artist1trackID':   longerIndex == 0 ? t.id   : null,
          'artist2trackID':   longerIndex == 1 ? t.id   : null,
          'Winner':           t.id,
          'voter_comment':    '',
          'artist1trackName': longerIndex == 0 ? t.name : null,
          'artist2trackName': longerIndex == 1 ? t.name : null,
          'isBonus':          true,
        };
      }
    }

    final album1 = albums[0];
    final album2 = albums[1];

    await FirebaseService.upsertAlbumPoll(
      versusId:  _resolvedVersusId,
      versusType: widget.versus.type.trim(),
      voterId:   _voterId,
      voterName: _voterName,
      voterAvatar: _voterAvatar,
      album1ID:   widget.versus.album1ID,
      album1Name: album1?.title ?? widget.versus.album1Name ?? '',
      album1Vote: _album1VoteCount,
      album2ID:   widget.versus.album2ID,
      album2Name: album2?.title ?? widget.versus.album2Name ?? '',
      album2Vote: _album2VoteCount,
      trackDetails: details,
      completionPercentage: completion,
      unvotedCount: unvoted,
    );
  }

  // ── Vote logic ────────────────────────────────────────────────────────────
  void _onVote(int trackIndex, int albumIndex) {
    if (trackIndex >= _pairedRoundCount) return;
    final albums = _albums;
    final t1 = albums?[0]?.tracks.elementAtOrNull(trackIndex);
    final t2 = albums?[1]?.tracks.elementAtOrNull(trackIndex);
    if (t1 == null || t2 == null) return;

    final current = _votesByIndex[trackIndex];
    if (current == albumIndex) {
      // Toggle off
      setState(() {
        _votesByIndex.remove(trackIndex);
        _trackDetails.remove(trackIndex);
      });
    } else {
      final winnerTrack = albumIndex == 0 ? t1 : t2;
      final comment     = _commentCtrlAt(trackIndex).text.trim();
      final detail      = AlbumTrackVoteDetail(
        album1trackID:   t1.id,
        album2trackID:   t2.id,
        winnerTrackID:   winnerTrack.id,
        album1trackName: t1.name,
        album2trackName: t2.name,
        voterComment:    comment,
        isBonus:         false,
      );
      setState(() {
        _votesByIndex[trackIndex] = albumIndex;
        _trackDetails[trackIndex] = detail;
      });

      debugPrint('[AlbumVote] Round $trackIndex → ${detail.toMap()}');
      debugPrint('[Tally] Album1: $_album1VoteCount | Album2: $_album2VoteCount');
    }

    _schedulePollSync();
  }

  void _onCommentChanged(int trackIndex, String text) {
    final detail = _trackDetails[trackIndex];
    if (detail != null) {
      setState(() => detail.voterComment = text);
      _schedulePollSync();
    }
  }

  // ── Palette ───────────────────────────────────────────────────────────────
  Future<void> _extractPalette(String? url1, String? url2) async {
    if (url1 != null && url1.isNotEmpty) {
      try {
        final p = await PaletteGenerator.fromImageProvider(NetworkImage(url1), size: const Size(200, 200));
        final c = p.vibrantColor?.color ?? p.dominantColor?.color ?? _kDefaultColor1;
        if (mounted) setState(() => _color1 = c);
      } catch (_) {}
    }
    if (url2 != null && url2.isNotEmpty) {
      try {
        final p = await PaletteGenerator.fromImageProvider(NetworkImage(url2), size: const Size(200, 200));
        final c = p.vibrantColor?.color ?? p.dominantColor?.color ?? _kDefaultColor2;
        if (mounted) setState(() => _color2 = c);
      } catch (_) {}
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _selectAlbum(int index) {
    if (_selectedAlbum == index) return;
    setState(() => _selectedAlbum = index);
    _slideController.forward(from: 0);
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  void _onPageChanged(int index) {
    if (_selectedAlbum == index) return;
    setState(() => _selectedAlbum = index);
    _slideController.forward(from: 0);
  }

  void _onTrackTapped(int trackIndex, int albumIndex) {
    _nowPlayingSub?.cancel();
    _nowPlayingSub        = null;
    _advanceOnTrackId     = null;
    _currentRoundTrack1Id = null;
    _currentRoundTrack2Id = null;
    _roundTrack2Started   = false;
    setState(() {
      _activeTrackIndex  = trackIndex;
      _leadAlbumIndex    = albumIndex;
      _playingTrackIndex = null;
    });
  }

  // ── Playback ──────────────────────────────────────────────────────────────
  Future<void> _handlePlay() async {
    final albums = _albums;
    if (albums == null || albums.length < 2) return;
    final roundIndex  = _activeTrackIndex;
    final leadAlbum   = _leadAlbumIndex;
    final followAlbum = leadAlbum == 0 ? 1 : 0;
    final tLead   = albums[leadAlbum]?.tracks.elementAtOrNull(roundIndex);
    final tFollow = albums[followAlbum]?.tracks.elementAtOrNull(roundIndex);
    if (tLead == null || tFollow == null || tLead.id.isEmpty || tFollow.id.isEmpty) return;

    setState(() => _isPlayLoading = true);
    try {
      final played = await _api.playRoundTracks(tLead.uri, tFollow.uri);
      if (!played) return;
      _currentRoundTrack1Id = tLead.id;
      _currentRoundTrack2Id = tFollow.id;
      _roundTrack2Started   = false;
      _advanceOnTrackId     = tFollow.id;
      _startNowPlayingIndexTracking();
      if (mounted) setState(() => _playingTrackIndex = roundIndex);
    } catch (e) {
      debugPrint('[VersusPlayground] _handlePlay error: $e');
    } finally {
      if (mounted) setState(() => _isPlayLoading = false);
    }
  }

  void _startNowPlayingIndexTracking() {
    _nowPlayingSub?.cancel();
    _nowPlayingSub = _api.pollNowPlaying(interval: const Duration(seconds: 2)).listen((nowPlaying) {
      final trackId = nowPlaying?.trackId;
      if (!mounted || trackId == null || trackId.isEmpty) return;
      final roundTrack2 = _currentRoundTrack2Id;
      if (roundTrack2 == null || _advanceOnTrackId == null) return;
      if (trackId == roundTrack2) { _roundTrack2Started = true; return; }
      if (_roundTrack2Started && trackId != roundTrack2) {
        final total = math.min(_albums?[0]?.tracks.length ?? 0, _albums?[1]?.tracks.length ?? 0);
        if (_activeTrackIndex < total - 1) {
          setState(() { _activeTrackIndex++; _playingTrackIndex = null; });
        } else {
          setState(() => _playingTrackIndex = null);
        }
        _advanceOnTrackId = null; _currentRoundTrack1Id = null;
        _currentRoundTrack2Id = null; _roundTrack2Started = false;
      }
    });
  }

  Future<bool> _queueRoundAtIndex(int index) async {
    final a = _albums;
    if (a == null || a.length < 2) return false;
    final t1 = a[0]?.tracks.elementAtOrNull(index);
    final t2 = a[1]?.tracks.elementAtOrNull(index);
    if (t1 == null || t2 == null || t1.id.isEmpty || t2.id.isEmpty) return false;
    return _api.queueRoundTracks(t1.uri, t2.uri);
  }

  Future<void> _handleBomb() async {
    if (_isBombLoading) return;
    final a = _albums;
    if (a == null || a.length < 2) return;
    final total = math.min(a[0]?.tracks.length ?? 0, a[1]?.tracks.length ?? 0);
    if (total <= 0 || _activeTrackIndex >= total - 1) return;
    setState(() => _isBombLoading = true);
    try {
      for (int i = _activeTrackIndex + 1; i < total; i++) {
        if (!await _queueRoundAtIndex(i)) break;
      }
    } catch (e) {
      debugPrint('[VersusPlayground] _handleBomb error: $e');
    } finally {
      if (mounted) setState(() => _isBombLoading = false);
    }
  }

  // ── Avatar helpers ────────────────────────────────────────────────────────
  Widget _resolveAvatarWidget(String avatarPath, double size) {
    final p = avatarPath.trim();
    if (p.isEmpty) return _avatarFallback(size);
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return Image.network(p, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(size));
    }
    final assetPath = p.startsWith('assets/') ? p : 'assets/images/$p';
    return Image.asset(assetPath, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _avatarFallback(size));
  }

  Widget _avatarFallback(double size) => Container(
    width: size, height: size,
    color: Colors.white.withOpacity(0.2),
    child: Icon(Icons.person_rounded, color: Colors.white.withOpacity(0.8), size: size * 0.55),
  );

  @override
  void dispose() {
    _pollDebounce?.cancel();
    _nowPlayingSub?.cancel();
    _pulseController.dispose();
    _slideController.dispose();
    _pageController.dispose();
    for (final c in _commentControllers.values) { c.dispose(); }
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final authorUsername = widget.versus.author?.username;
    final authorLabel    = (authorUsername != null && authorUsername.isNotEmpty)
        ? '@$authorUsername'
        : widget.versus.authorId;
    final avatarPath = widget.versus.author?.avatarPath;

    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 12),
          child: FutureBuilder<List<SpotifyAlbumWithTracks?>>(
            future: _albumsFuture,
            builder: (context, snapshot) {
              final album1   = snapshot.data?[0];
              final album2   = snapshot.data?[1];
              final a1Title  = album1?.title    ?? widget.versus.album1Name ?? 'Album 1';
              final a2Title  = album2?.title    ?? widget.versus.album2Name ?? 'Album 2';
              final a1Image  = album1?.imageUrl ?? widget.versus.album1ImageUrl;
              final a2Image  = album2?.imageUrl ?? widget.versus.album2ImageUrl;
              final a1Artist = album1?.artistName ?? widget.versus.album1ArtistName ?? '';
              final a2Artist = album2?.artistName ?? widget.versus.album2ArtistName ?? '';
              final isLoading = snapshot.connectionState == ConnectionState.waiting;

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context, authorLabel, avatarPath)),
                  SliverToBoxAdapter(child: _buildVsSelector(
                    a1Title: a1Title, a2Title: a2Title,
                    a1Image: a1Image, a2Image: a2Image,
                    a1Artist: a1Artist, a2Artist: a2Artist,
                    isLoading: isLoading,
                  )),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _SwipeDot(isActive: _selectedAlbum == 0, color: _color1),
                          const SizedBox(width: 6),
                          _SwipeDot(isActive: _selectedAlbum == 1, color: _color2),
                        ],
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    child: isLoading
                        ? Center(child: CircularProgressIndicator(color: _color1))
                        : Column(children: [
                            // ── Playback controls ────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Row(children: [
                                GestureDetector(
                                  onTap: _isPlayLoading ? null : _handlePlay,
                                  child: Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _kSpotifyGreen.withOpacity(_isPlayLoading ? 0.12 : 0.25),
                                      border: Border.all(color: _kSpotifyGreen.withOpacity(_isPlayLoading ? 0.3 : 0.6), width: 1.2),
                                    ),
                                    child: _isPlayLoading
                                        ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: _kSpotifyGreen, strokeWidth: 2))
                                        : const Icon(Icons.play_arrow_rounded, color: _kSpotifyGreen, size: 24),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(99),
                                      color: _kSpotifyGreen.withOpacity(0.2),
                                      border: Border.all(color: _kSpotifyGreen.withOpacity(0.5), width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: _kSpotifyGreen)),
                                        const SizedBox(width: 8),
                                        Text('ROUND ${_activeTrackIndex + 1}',
                                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2)),
                                        if (_playingTrackIndex != null) ...[
                                          const SizedBox(width: 10),
                                          Text('PLAY ${_playingTrackIndex! + 1}',
                                              style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: _isBombLoading ? null : _handleBomb,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(99),
                                      color: _kSpotifyGreen.withOpacity(_isBombLoading ? 0.12 : 0.25),
                                      border: Border.all(color: _kSpotifyGreen.withOpacity(_isBombLoading ? 0.3 : 0.6), width: 1.2),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      if (_isBombLoading)
                                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8, color: _kSpotifyGreen))
                                      else
                                        const Text('BOMB', style: TextStyle(color: _kSpotifyGreen, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.arrow_forward_rounded, color: _kSpotifyGreen, size: 16),
                                    ]),
                                  ),
                                ),
                              ]),
                            ),

                            // ── Track PageView ───────────────────────────────
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
                                    activeTrackIndex: _activeTrackIndex,
                                    votableRoundCount: _pairedRoundCount,
                                    votesByIndex: _votesByIndex,
                                    onVote: (albumIndex) => _onVote(_activeTrackIndex, albumIndex),
                                    onTrackTap: _onTrackTapped,
                                    getCommentCtrl: _commentCtrlAt,
                                    onCommentChanged: _onCommentChanged,
                                  ),
                                  _TrackPage(
                                    album: album2,
                                    albumIndex: 1,
                                    fallbackTitle: a2Title,
                                    fallbackArtist: a2Artist,
                                    fallbackImageUrl: a2Image,
                                    slideAnim: _slideAnim,
                                    accentColor: _color2,
                                    activeTrackIndex: _activeTrackIndex,
                                    votableRoundCount: _pairedRoundCount,
                                    votesByIndex: _votesByIndex,
                                    onVote: (albumIndex) => _onVote(_activeTrackIndex, albumIndex),
                                    onTrackTap: _onTrackTapped,
                                    getCommentCtrl: _commentCtrlAt,
                                    onCommentChanged: _onCommentChanged,
                                  ),
                                ],
                              ),
                            ),
                          ]),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, String authorLabel, String? avatarPath) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, left: 20, right: 20, bottom: 8),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.15),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.8),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
          ),
        ),
        const SizedBox(width: 14),
        if (avatarPath != null && avatarPath.isNotEmpty) ...[
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.gradientEnd, width: 1.5)),
            child: ClipOval(child: _resolveAvatarWidget(avatarPath, 34)),
          ),
          const SizedBox(width: 10),
        ],
        const Text('ALBUMS', style: TextStyle(fontSize: 13, fontFamily: AppTheme.fontHeader, color: Color(0xFFF07012), letterSpacing: 2.5)),
      ]),
    );
  }

  // ── VS Selector ───────────────────────────────────────────────────────────
  Widget _buildVsSelector({
    required String a1Title, required String a2Title,
    required String? a1Image, required String? a2Image,
    required String a1Artist, required String a2Artist,
    required bool isLoading,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(alignment: Alignment.center, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: GestureDetector(
            onTap: () => _selectAlbum(0),
            child: _AlbumCard(
              title: a1Title, artist: a1Artist, imageUrl: a1Image,
              isSelected: _selectedAlbum == 0, accentColor: _color1,
              voteCount: _album1VoteCount,
            ),
          )),
          const SizedBox(width: 52),
          Expanded(child: GestureDetector(
            onTap: () => _selectAlbum(1),
            child: _AlbumCard(
              title: a2Title, artist: a2Artist, imageUrl: a2Image,
              isSelected: _selectedAlbum == 1, accentColor: _color2,
              voteCount: _album2VoteCount,
            ),
          )),
        ]),
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, child) => Transform.scale(scale: _pulseAnim.value, child: child),
          child: Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_color1, _color2]),
              boxShadow: [BoxShadow(color: _color2.withOpacity(0.5), blurRadius: 18, spreadRadius: 2)],
            ),
            child: const Center(child: Text('VS', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5))),
          ),
        ),
      ]),
    );
  }
}

// ── Swipe Dot ─────────────────────────────────────────────────────────────────
class _SwipeDot extends StatelessWidget {
  final bool  isActive;
  final Color color;
  const _SwipeDot({required this.isActive, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: isActive ? 20 : 6, height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: isActive ? color : Colors.white.withOpacity(0.3),
      ),
    );
  }
}

// ── Album Card ────────────────────────────────────────────────────────────────
class _AlbumCard extends StatelessWidget {
  final String  title;
  final String  artist;
  final String? imageUrl;
  final bool    isSelected;
  final Color   accentColor;
  final int     voteCount;

  const _AlbumCard({
    required this.title,
    required this.artist,
    required this.isSelected,
    required this.accentColor,
    required this.voteCount,
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
          color: isSelected ? accentColor.withOpacity(0.7) : Colors.white.withOpacity(0.06),
          width: isSelected ? 1.5 : 0.8,
        ),
        color: isSelected ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.07),
      ),
      child: Column(children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
          child: AspectRatio(
            aspectRatio: 1,
            child: imageUrl != null && imageUrl!.isNotEmpty
                ? Image.network(imageUrl!, fit: BoxFit.cover)
                : Container(color: Colors.white.withOpacity(0.06),
                    child: Icon(Icons.album_rounded, size: 40, color: Colors.white.withOpacity(0.3))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
                    fontSize: 13, fontWeight: FontWeight.w700, height: 1.3)),
            if (artist.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? accentColor.withOpacity(0.9) : Colors.white.withOpacity(0.35),
                    fontSize: 11, fontWeight: FontWeight.w500)),
            ],
            // Live vote badge — mirrors artist card behaviour
            if (voteCount > 0) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: accentColor.withOpacity(0.22),
                  border: Border.all(color: accentColor.withOpacity(0.55), width: 0.9),
                ),
                child: Text('$voteCount',
                    style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ── Track Page ────────────────────────────────────────────────────────────────
class _TrackPage extends StatelessWidget {
  final SpotifyAlbumWithTracks? album;
  final int     albumIndex;
  final String  fallbackTitle;
  final String  fallbackArtist;
  final String? fallbackImageUrl;
  final Animation<double> slideAnim;
  final Color   accentColor;
  final int     activeTrackIndex;
  final int     votableRoundCount;
  final Map<int, int> votesByIndex;
  final void Function(int albumIndex)              onVote;
  final void Function(int trackIndex, int albumIndex) onTrackTap;
  final TextEditingController Function(int)        getCommentCtrl;
  final void Function(int roundIndex, String text) onCommentChanged;

  const _TrackPage({
    required this.album,
    required this.albumIndex,
    required this.fallbackTitle,
    required this.fallbackArtist,
    required this.fallbackImageUrl,
    required this.slideAnim,
    required this.accentColor,
    required this.activeTrackIndex,
    required this.votableRoundCount,
    required this.votesByIndex,
    required this.onVote,
    required this.onTrackTap,
    required this.getCommentCtrl,
    required this.onCommentChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tracks = album?.tracks ?? <SpotifyAlbumTrack>[];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
      physics: const BouncingScrollPhysics(),
      itemCount: tracks.isEmpty ? 2 : tracks.length + 1,
      itemBuilder: (context, index) {
        // Header
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: Row(children: [
              Container(width: 3, height: 16,
                  decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(99))),
              const SizedBox(width: 10),
              Text('TRACKS', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
              const SizedBox(width: 8),
              Text('${tracks.length}', style: TextStyle(color: accentColor.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          );
        }

        if (tracks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(album == null ? 'Spotify data unavailable.' : 'No tracks found.',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)),
          );
        }

        final trackIndex   = index - 1;
        if (trackIndex >= tracks.length) return const SizedBox.shrink();
        final track        = tracks[trackIndex];
        final isActive     = trackIndex == activeTrackIndex;
        final isPast       = trackIndex <  activeTrackIndex;
        final isLocked     = trackIndex >  activeTrackIndex;
        final isBonusIndex = trackIndex >= votableRoundCount;

        final votedAlbum      = votesByIndex[trackIndex];
        final isVotedForMe    = votedAlbum == albumIndex;
        final isVoteDisabled  = isBonusIndex || (votedAlbum != null && votedAlbum != albumIndex);

        return AnimatedBuilder(
          animation: slideAnim,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 24 * (1 - slideAnim.value) * math.max(0, 1 - trackIndex * 0.05)),
            child: Opacity(opacity: slideAnim.value.clamp(0.0, 1.0), child: child),
          ),
          child: _TrackRow(
            key:               ValueKey('album-$albumIndex-track-$trackIndex'),
            track:             track,
            index:             trackIndex,
            accentColor:       accentColor,
            isLast:            trackIndex == tracks.length - 1,
            isActive:          isActive,
            isPast:            isPast,
            isLocked:          isLocked,
            showVoteButton:    isActive || isVotedForMe,
            isVoted:           isVotedForMe,
            isVoteDisabled:    isVoteDisabled,
            commentController: getCommentCtrl(trackIndex),
            onVote:            isActive && !isBonusIndex ? () => onVote(albumIndex) : null,
            onCommentChanged:  (text) => onCommentChanged(trackIndex, text),
            onTap:             () => onTrackTap(trackIndex, albumIndex),
          ),
        );
      },
    );
  }
}

// ── Track Row ─────────────────────────────────────────────────────────────────
class _TrackRow extends StatelessWidget {
  final SpotifyAlbumTrack          track;
  final int                        index;
  final Color                      accentColor;
  final bool                       isLast, isActive, isPast, isLocked;
  final bool                       showVoteButton, isVoted, isVoteDisabled;
  final TextEditingController      commentController;
  final VoidCallback?              onVote;
  final void Function(String)      onCommentChanged;
  final VoidCallback?              onTap;

  const _TrackRow({
    super.key,
    required this.track,
    required this.index,
    required this.accentColor,
    required this.commentController,
    required this.onCommentChanged,
    this.isLast         = false,
    this.isActive       = false,
    this.isPast         = false,
    this.isLocked       = false,
    this.showVoteButton = false,
    this.isVoted        = false,
    this.isVoteDisabled = false,
    this.onVote,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textOpacity = isActive ? 1.0 : isPast ? 0.6 : 0.52;
    final numberColor = isActive
        ? accentColor
        : isPast ? accentColor.withOpacity(0.5) : Colors.white.withOpacity(0.42);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isLocked ? 0.62 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(children: [
          Container(
            decoration: isActive ? BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: accentColor.withOpacity(0.42),
              border: Border.all(color: accentColor.withOpacity(0.65), width: 1.2),
            ) : null,
            padding: isActive ? const EdgeInsets.symmetric(horizontal: 10, vertical: 2) : EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 11, 0, 9),
              child: Column(children: [
                Row(children: [
                  // Track number / state icon
                  SizedBox(width: 32,
                    child: isPast
                        ? Icon(Icons.check_rounded, size: 15, color: accentColor.withOpacity(0.5))
                        : isLocked
                            ? Icon(Icons.lock_rounded, size: 14, color: Colors.white.withOpacity(0.45))
                            : Text('${track.trackNumber}'.padLeft(2, '0'),
                                style: TextStyle(color: numberColor, fontSize: 12, fontWeight: FontWeight.w700,
                                    fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                  const SizedBox(width: 12),

                  // Track info
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withOpacity(textOpacity), fontSize: 14,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, letterSpacing: -0.1)),
                    if (track.artistName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(track.artistName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(textOpacity * 0.6), fontSize: 12, fontWeight: FontWeight.w400)),
                    ],
                  ])),
                  const SizedBox(width: 12),

                  // Vote button
                  if (showVoteButton) ...[
                    GestureDetector(
                      onTap: isVoteDisabled ? null : onVote,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: isVoted
                              ? _kSpotifyGreen.withOpacity(0.5)
                              : isVoteDisabled
                                  ? Colors.white.withOpacity(0.06)
                                  : _kSpotifyGreen.withOpacity(0.25),
                          border: Border.all(
                            color: isVoted ? _kSpotifyGreen
                                : isVoteDisabled ? Colors.white.withOpacity(0.1)
                                : _kSpotifyGreen.withOpacity(0.6),
                            width: 1,
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(isVoted ? Icons.check_rounded : Icons.how_to_vote_rounded,
                              size: 14,
                              color: isVoteDisabled ? Colors.white.withOpacity(0.2)
                                  : isVoted ? Colors.white : _kSpotifyGreen),
                          const SizedBox(width: 4),
                          Text(isVoted ? 'Voted' : 'Vote',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5,
                                  color: isVoteDisabled ? Colors.white.withOpacity(0.2)
                                      : isVoted ? Colors.white : _kSpotifyGreen)),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],

                  // Duration on non-active rows; NOTE badge on voted rows
                  if (isVoted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99), color: accentColor.withOpacity(0.75)),
                      child: const Text('NOTE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
                    )
                  else if (!isActive)
                    Text(track.durationFormatted,
                        style: TextStyle(color: Colors.white.withOpacity(textOpacity * 0.5), fontSize: 12,
                            fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
                ]),

                // Comment field — visible when voted
                if (isVoted) ...[
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: Colors.white.withOpacity(0.12),
                      border: Border.all(color: Colors.white.withOpacity(0.20), width: 0.8),
                    ),
                    child: TextField(
                      controller: commentController,
                      onChanged: onCommentChanged,
                      minLines: 1, maxLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Disclaimer...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.42), fontSize: 12),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          if (!isLast)
            Divider(height: 0, indent: 44, color: Colors.white.withOpacity(0.06)),
        ]),
      ),
    );
  }
}