import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:welcometothedisco/models/artist_versus_model.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/spotify_service.dart';

const _kPurple       = Color(0xFF1E3DE1);
const _kPink         = Color(0xFFf85187);
const _kSuccessGreen = Color(0xFF22C55E);
const _kSpotifyGreen = Color(0xFF17B560);

// ─────────────────────────────────────────────────────────────────────────────
// Entry gate — resolves current user + loads the versus doc from Firestore
// ─────────────────────────────────────────────────────────────────────────────

/// Navigate here from the notification tap, passing only the [versusID].
///
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => CollaboratorBackroom(versusID: notification.versusID),
/// ));
/// ```
class CollaboratorAcceptGate extends StatelessWidget {
  final String versusID;
  const CollaboratorAcceptGate({super.key, required this.versusID});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GateResult>(
      future: _load(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _gradientScaffold(
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        final result = snap.data;
        if (result == null) {
          return _gradientScaffold(
            Center(
              child: Text(
                'Failed to load versus.',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
              ),
            ),
          );
        }
        if (result.errorMessage != null) {
          return _gradientScaffold(
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  result.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
                ),
              ),
            ),
          );
        }
        if (result.currentUser == null) {
          return _gradientScaffold(
            Center(
              child: Text(
                'Sign in to collaborate.',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
              ),
            ),
          );
        }
        if (result.versus == null) {
          return _gradientScaffold(
            Center(
              child: Text(
                'Versus not found.',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
              ),
            ),
          );
        }
        return CollaboratorAcceptScreen(
          versus:      result.versus!,
          currentUser: result.currentUser!,
        );
      },
    );
  }

  Future<_GateResult> _load() async {
    final results = await Future.wait([
      FirebaseService.getArtistVersusById(versusID),
      FirebaseService.getCurrentUser(),
    ]);
    final versus = results[0] as ArtistVersusModel?;
    final currentUser = results[1] as UserModel?;

    if (versus == null) {
      return _GateResult(versus: null, currentUser: currentUser, errorMessage: null);
    }
    if (currentUser == null) {
      return _GateResult(versus: null, currentUser: null, errorMessage: null);
    }

    final uid = currentUser.id;
    if (versus.authorID == uid) {
      return _GateResult(
        versus: null,
        currentUser: currentUser,
        errorMessage:
            'You created this versus. Your collaborator opens it from their notification.',
      );
    }

    final invited = versus.collaboratorID?.trim() ?? '';
    if (invited.isEmpty) {
      return _GateResult(
        versus: null,
        currentUser: currentUser,
        errorMessage: 'This collaboration is not linked to an invited account yet.',
      );
    }
    if (invited != uid) {
      return _GateResult(
        versus: null,
        currentUser: currentUser,
        errorMessage: 'This invite is for another account.',
      );
    }

    return _GateResult(versus: versus, currentUser: currentUser, errorMessage: null);
  }

  Widget _gradientScaffold(Widget body) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1E3DE1), Color(0xFFf85187)],
      ),
    ),
    child: Scaffold(backgroundColor: Colors.transparent, body: body),
  );
}

class _GateResult {
  final ArtistVersusModel? versus;
  final UserModel?         currentUser;
  final String?            errorMessage;
  _GateResult({this.versus, this.currentUser, this.errorMessage});
}

/// Public entry matching the file name — loads [versusID] from Firestore and
/// shows [CollaboratorAcceptScreen] for the invited collaborator.
class CollaboratorBackroom extends StatelessWidget {
  final String versusID;
  const CollaboratorBackroom({super.key, required this.versusID});

  @override
  Widget build(BuildContext context) =>
      CollaboratorAcceptGate(versusID: versusID);
}

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

class CollaboratorAcceptScreen extends StatefulWidget {
  final ArtistVersusModel versus;
  final UserModel         currentUser;

  const CollaboratorAcceptScreen({
    super.key,
    required this.versus,
    required this.currentUser,
  });

  @override
  State<CollaboratorAcceptScreen> createState() =>
      _CollaboratorAcceptScreenState();
}

class _CollaboratorAcceptScreenState extends State<CollaboratorAcceptScreen>
    with TickerProviderStateMixin {
  final SpotifyApi _api = SpotifyService.api;

  // ── User1 (author) — read-only ─────────────────────────────────────────────
  List<SpotifyTrack> _user1Tracks = [];
  String?            _user1ImageUrl;
  bool               _isLoadingUser1 = true;

  // ── User2 (current user / collaborator) ───────────────────────────────────
  // Artist selection
  SpotifyArtistDetails? _myArtist;
  String?               _myArtistImageUrl;

  // Artist search
  final TextEditingController _artistSearchCtrl = TextEditingController();
  final FocusNode             _artistSearchFocus = FocusNode();
  Timer?                      _artistDebounce;
  List<SpotifyArtistDetails>  _artistResults   = [];
  bool                        _isSearchingArtist = false;
  String                      _lastArtistQuery  = '';

  // Track selection
  List<SpotifyTrack>  _myTopTracks       = [];
  List<SpotifyTrack>  _mySelectedTracks  = [];
  bool                _isLoadingMyTracks = false;

  // Track search
  final TextEditingController _trackSearchCtrl  = TextEditingController();
  final FocusNode             _trackSearchFocus  = FocusNode();
  Timer?                      _trackDebounce;
  List<SpotifyTrack>?         _trackSearchResults;
  bool                        _isSearchingTracks = false;
  String                      _trackFilterQuery  = '';

  // Comment
  final TextEditingController _commentCtrl = TextEditingController();
  static const int _maxCommentWords = 30;

  int get _commentWordCount {
    final t = _commentCtrl.text.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  // ── Submission ─────────────────────────────────────────────────────────────
  bool _isSubmitting = false;

  // ── Playback ───────────────────────────────────────────────────────────────
  int     _activeRound      = 0;
  int?    _playingRound;
  bool    _isPlayLoading    = false;
  bool    _isBombLoading    = false;
  StreamSubscription<NowPlaying?>? _nowPlayingSub;
  String? _advanceOnTrackId;
  String? _roundTrack1Id;
  String? _roundTrack2Id;
  bool    _roundTrack2Started = false;

  // ── Page / animation ───────────────────────────────────────────────────────
  late final PageController      _pageCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _slideCtrl;
  late final Animation<double>   _slideAnim;
  int _currentPage = 0; // 0 = user1 (author), 1 = me (collaborator)

  // ── Pre-fill: if artist2 already stored in the doc ─────────────────────────
  bool _artist2PreFilled = false;

  @override
  void initState() {
    super.initState();

    _pageCtrl = PageController();

    _shimmerCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400),
    )..repeat();

    _slideCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380),
    );
    _slideAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);

    _trackSearchCtrl.addListener(_onTrackFilterChanged);
    _commentCtrl.addListener(() { if (mounted) setState(() {}); });

    _loadUser1Tracks();
    _checkPrefilledArtist2();
  }

  @override
  void dispose() {
    _nowPlayingSub?.cancel();
    _artistDebounce?.cancel();
    _trackDebounce?.cancel();
    _artistSearchCtrl.dispose();
    _artistSearchFocus.dispose();
    _trackSearchCtrl.dispose();
    _trackSearchFocus.dispose();
    _commentCtrl.dispose();
    _pageCtrl.dispose();
    _shimmerCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  // ── Init helpers ────────────────────────────────────────────────────────────

  Future<void> _loadUser1Tracks() async {
    setState(() => _isLoadingUser1 = true);
    try {
      final results = await Future.wait([
        _api.getTracksByIds(widget.versus.artist1TrackIDs),
        _api.getArtistDetails(widget.versus.artist1ID),
      ]);
      if (!mounted) return;
      setState(() {
        _user1Tracks    = results[0] as List<SpotifyTrack>;
        _user1ImageUrl  = (results[1] as SpotifyArtistDetails?)?.imageUrl;
        _isLoadingUser1 = false;
      });
      _slideCtrl.forward(from: 0);
    } catch (e) {
      if (mounted) setState(() => _isLoadingUser1 = false);
    }
  }

  /// If the invite doc already has artist2 set (author pre-picked it),
  /// fetch Spotify details and auto-populate the collaborator slot.
  Future<void> _checkPrefilledArtist2() async {
    final id   = widget.versus.artist2ID.trim();
    final name = widget.versus.artist2Name.trim();
    if (id.isEmpty) return;
    try {
      final details = await _api.getArtistDetails(id);
      if (!mounted) return;
      setState(() {
        _myArtist       = SpotifyArtistDetails(
          id:       id,
          name:     name.isNotEmpty ? name : (details?.name ?? id),
          imageUrl: details?.imageUrl,
        );
        _myArtistImageUrl = details?.imageUrl;
        _artist2PreFilled = true;
      });
      _fetchMyTopTracks(id);
    } catch (_) {}
  }

  // ── Artist search (user2) ──────────────────────────────────────────────────

  void _onArtistSearchChanged(String query) {
    _artistDebounce?.cancel();
    final q = query.trim();
    if (q == _lastArtistQuery) return;
    if (q.isEmpty) {
      setState(() { _artistResults = []; _isSearchingArtist = false; _lastArtistQuery = ''; });
      return;
    }
    setState(() => _isSearchingArtist = true);
    _artistDebounce = Timer(const Duration(milliseconds: 380), () async {
      _lastArtistQuery = q;
      final results = await _api.searchArtists(q, limit: 12);
      if (!mounted) return;
      setState(() { _artistResults = results; _isSearchingArtist = false; });
    });
  }

  void _selectMyArtist(SpotifyArtistDetails artist) {
    setState(() {
      _myArtist         = artist;
      _myArtistImageUrl = artist.imageUrl;
      _myTopTracks      = [];
      _mySelectedTracks = [];
      _trackSearchResults = null;
      _trackSearchCtrl.clear();
      _trackFilterQuery = '';
      _artistSearchCtrl.clear();
      _artistResults    = [];
      _isSearchingArtist = false;
      _lastArtistQuery  = '';
    });
    _fetchMyTopTracks(artist.id);
  }

  Future<void> _fetchMyTopTracks(String artistId) async {
    if (_isLoadingMyTracks) return;
    setState(() => _isLoadingMyTracks = true);
    try {
      final tracks = await _api.getArtistTopTracks(artistId);
      if (!mounted) return;
      setState(() { _myTopTracks = tracks; });
      _slideCtrl.forward(from: 0);
    } finally {
      if (mounted) setState(() => _isLoadingMyTracks = false);
    }
  }

  // ── Track search (user2) ───────────────────────────────────────────────────

  void _onTrackFilterChanged() {
    final q = _trackSearchCtrl.text.trim();
    if (q == _trackFilterQuery) return;
    setState(() => _trackFilterQuery = q);
    _trackDebounce?.cancel();
    if (q.isEmpty) {
      setState(() { _trackSearchResults = null; _isSearchingTracks = false; });
      return;
    }
    setState(() => _isSearchingTracks = true);
    _trackDebounce = Timer(const Duration(milliseconds: 420), () async {
      final artist = _myArtist;
      if (artist == null || !mounted) return;
      final results = await _api.searchTracksByArtists(
        q,
        artist1Id: artist.id, artist1Name: artist.name,
        artist2Id: '', artist2Name: '',
        limitPerArtist: 20,
      );
      if (!mounted) return;
      setState(() {
        _trackSearchResults = results[artist.id] ?? [];
        _isSearchingTracks  = false;
      });
      _slideCtrl.forward(from: 0);
    });
  }

  void _toggleMyTrack(SpotifyTrack track) {
    setState(() {
      final idx = _mySelectedTracks.indexWhere((t) => t.id == track.id);
      if (idx >= 0) {
        _mySelectedTracks.removeAt(idx);
      } else {
        final cap = _authorSideTrackCount;
        if (cap > 0 && _mySelectedTracks.length >= cap) return;
        _mySelectedTracks.add(track);
      }
    });
  }

  void _removeMyTrack(String trackId) {
    setState(() => _mySelectedTracks.removeWhere((t) => t.id == trackId));
  }

  List<SpotifyTrack> get _myVisibleTracks {
    if (_trackFilterQuery.isNotEmpty && _trackSearchResults != null) {
      return _trackSearchResults!;
    }
    return _myTopTracks;
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  /// Play algorithm: at each round index, pick user1[i] and user2[i].
  /// If user2 has no track at index i, fall back to user1[i] again
  /// (so it still plays something for that round).
  Future<void> _handlePlay() async {
    if (_user1Tracks.isEmpty) return;
    final t1 = _user1Tracks.elementAtOrNull(_activeRound);
    if (t1 == null || t1.id.isEmpty) return;

    final t2 = _mySelectedTracks.elementAtOrNull(_activeRound);
    // If user2 has no track at this round, play t1 twice (back-to-back).
    final uri2 = (t2 != null && t2.id.isNotEmpty) ? t2.uri : t1.uri;
    final id2  = (t2 != null && t2.id.isNotEmpty) ? t2.id  : t1.id;

    setState(() => _isPlayLoading = true);
    try {
      final played = await _api.playRoundTracks(t1.uri, uri2);
      if (!played) return;
      _roundTrack1Id     = t1.id;
      _roundTrack2Id     = id2;
      _roundTrack2Started = false;
      _advanceOnTrackId  = id2;
      _startNowPlayingTracking();
      if (mounted) setState(() => _playingRound = _activeRound);
    } catch (e) {
      debugPrint('[CollaboratorAcceptScreen] _handlePlay error: $e');
    } finally {
      if (mounted) setState(() => _isPlayLoading = false);
    }
  }

  void _startNowPlayingTracking() {
    _nowPlayingSub?.cancel();
    _nowPlayingSub = _api
        .pollNowPlaying(interval: const Duration(seconds: 2))
        .listen((np) {
      final trackId = np?.trackId;
      if (!mounted || trackId == null || trackId.isEmpty) return;
      final rt2 = _roundTrack2Id;
      if (rt2 == null || _advanceOnTrackId == null) return;

      if (trackId == rt2) { _roundTrack2Started = true; return; }

      if (_roundTrack2Started && trackId != rt2) {
        final total = math.max(_user1Tracks.length, _mySelectedTracks.length);
        if (_activeRound < total - 1) {
          setState(() { _activeRound++; _playingRound = null; });
        } else {
          setState(() => _playingRound = null);
        }
        _advanceOnTrackId = null;
        _roundTrack1Id    = null;
        _roundTrack2Id    = null;
        _roundTrack2Started = false;
      }
    });
  }

  Future<void> _handleBomb() async {
    if (_isBombLoading || _user1Tracks.isEmpty) return;
    final total = math.max(_user1Tracks.length, _mySelectedTracks.length);
    if (_activeRound >= total - 1) return;

    setState(() => _isBombLoading = true);
    try {
      for (int i = _activeRound + 1; i < total; i++) {
        final t1   = _user1Tracks.elementAtOrNull(i);
        final t2   = _mySelectedTracks.elementAtOrNull(i);
        if (t1 == null) break;
        final uri2 = (t2 != null && t2.id.isNotEmpty) ? t2.uri : t1.uri;
        final ok   = await _api.queueRoundTracks(t1.uri, uri2);
        if (!ok) { debugPrint('[CollaboratorAcceptScreen] bomb stopped at $i'); break; }
      }
    } catch (e) {
      debugPrint('[CollaboratorAcceptScreen] _handleBomb error: $e');
    } finally {
      if (mounted) setState(() => _isBombLoading = false);
    }
  }

  void _onTrackTapped(int roundIndex) {
    _nowPlayingSub?.cancel();
    _nowPlayingSub      = null;
    _advanceOnTrackId   = null;
    _roundTrack1Id      = null;
    _roundTrack2Id      = null;
    _roundTrack2Started = false;
    setState(() { _activeRound = roundIndex; _playingRound = null; });
  }

  // ── Submission ─────────────────────────────────────────────────────────────

  /// Author side (artist1) track count — collaborator must match this.
  int get _authorSideTrackCount => widget.versus.artist1TrackIDs.length;

  bool get _canSubmit =>
      _myArtist != null &&
      _authorSideTrackCount > 0 &&
      _mySelectedTracks.length == _authorSideTrackCount;

  String? get _submitHint {
    if (_myArtist == null) return null;
    final need = _authorSideTrackCount;
    final have = _mySelectedTracks.length;
    if (need == 0) {
      return 'Their side has no tracks yet — wait for the host to finish their picks';
    }
    if (have == 0) {
      return 'Select $need track${need == 1 ? '' : 's'} to match their side';
    }
    if (have < need) {
      final n = need - have;
      return 'Select $n more track${n == 1 ? '' : 's'} to match their side';
    }
    if (have > need) {
      final n = have - need;
      return 'Remove $n track${n == 1 ? '' : 's'} to match their side';
    }
    return null;
  }

  String get _submitLabel {
    if (_myArtist == null) return 'PICK YOUR ARTIST FIRST';
    if (_authorSideTrackCount == 0) return 'THEIR SIDE INCOMPLETE';
    if (_mySelectedTracks.isEmpty) return 'SELECT YOUR TRACKS FIRST';
    if (_mySelectedTracks.length != _authorSideTrackCount) {
      return 'SELECT EQUAL TRACKS';
    }
    return 'CONFIRM & GO LIVE';
  }

  Future<void> _handleSubmit() async {
    if (!_canSubmit || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await FirebaseService.acceptCollaborationInvite(
        versusID:       widget.versus.id,
        artist2ID:      _myArtist!.id,
        artist2Name:    _myArtist!.name,
        artist2TrackIDs: _mySelectedTracks.map((t) => t.id).toList(),
        collaboratorComment: _commentCtrl.text.trim().isEmpty
            ? null
            : _commentCtrl.text.trim(),
        collaboratorUsername: widget.currentUser.username.trim(),
        collaboratorAvatarPath: widget.currentUser.avatarPath.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Versus is now live! 🔥'),
          backgroundColor: _kSuccessGreen.withOpacity(0.92),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: Colors.red.withOpacity(0.85),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Page navigation ────────────────────────────────────────────────────────

  void _goToPage(int index) {
    if (_currentPage == index) return;
    setState(() => _currentPage = index);
    _pageCtrl.animateToPage(index,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    _slideCtrl.forward(from: 0);
  }

  void _onPageChanged(int index) {
    if (_currentPage == index) return;
    setState(() => _currentPage = index);
    _slideCtrl.forward(from: 0);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showArtistOverlay = _artistSearchCtrl.text.trim().isNotEmpty || _isSearchingArtist;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1E3DE1), Color(0xFFf85187)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(children: [
          _buildHeader(context),
          _buildArtistSlots(),
          _buildPlaybackBar(),
          _buildSliderDots(),
          Expanded(
            child: Stack(children: [
              PageView(
                controller: _pageCtrl,
                onPageChanged: _onPageChanged,
                children: [
                  _buildUser1TrackList(),
                  _buildMyTrackList(),
                ],
              ),
              // Artist search overlay on top of page 1
              if (showArtistOverlay && _currentPage == 1)
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF1E3DE1), Color(0xFFf85187)],
                      ),
                    ),
                    child: _buildArtistSearchResults(),
                  ),
                ),
            ]),
          ),
          if (_myArtist != null) _buildSubmitBar(),
        ]),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final authorName = widget.versus.author?.username.trim() ?? widget.versus.authorID;

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        left: 20, right: 20, bottom: 10,
      ),
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
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 16),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('COLLAB INVITE', style: TextStyle(
                color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w900, letterSpacing: 3.5,
              )),
              Text(
                '@$authorName invited you to battle',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55), fontSize: 11,
                  fontWeight: FontWeight.w500, letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        if (_myArtist != null &&
            (_authorSideTrackCount > 0 || _mySelectedTracks.isNotEmpty)) ...[
          const SizedBox(width: 8),
          _buildTrackCountBadge(),
        ],
        const SizedBox(width: 8),
        _buildMyChip(),
      ]),
    );
  }

  /// Host track count vs yours — mirrors artist lockeroom balance chip.
  Widget _buildTrackCountBadge() {
    final c1 = _authorSideTrackCount;
    final c2 = _mySelectedTracks.length;
    final balanced = c1 == c2 && c1 > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: balanced
            ? Colors.white.withOpacity(0.15)
            : Colors.orange.withOpacity(0.2),
        border: Border.all(
          color: balanced
              ? Colors.white.withOpacity(0.3)
              : Colors.orange.withOpacity(0.5),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$c1',
            style: TextStyle(
              color: balanced ? Colors.white : _kPurple,
              fontSize: 12, fontWeight: FontWeight.w800,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('vs',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 10, fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$c2',
            style: TextStyle(
              color: balanced ? Colors.white : _kPink,
              fontSize: 12, fontWeight: FontWeight.w800,
            ),
          ),
          if (balanced) ...[
            const SizedBox(width: 5),
            Icon(Icons.check_circle_rounded,
                color: Colors.white.withOpacity(0.7), size: 13),
          ],
        ],
      ),
    );
  }

  Widget _buildMyChip() {
    final username = widget.currentUser.username.trim().isNotEmpty
        ? widget.currentUser.username.trim()
        : 'you';
    const size = 32.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [_kPurple.withOpacity(0.40), _kPink.withOpacity(0.40)],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: size, height: size,
              child: _resolveAvatar(widget.currentUser.avatarPath, size),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Text(username,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Artist slots (top strip) ───────────────────────────────────────────────

  Widget _buildArtistSlots() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: [
        // User1 slot — always filled, read-only
        Expanded(
          child: _SlotChip(
            artist: _SlotArtistData(
              name:     widget.versus.artist1Name,
              imageUrl: _user1ImageUrl,
            ),
            label:       'THEIR ARTIST',
            accentColor: _kPurple,
            isActive:    _currentPage == 0,
            trackCount:  widget.versus.artist1TrackIDs.length,
            isReadOnly:  true,
            onTap:       () => _goToPage(0),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('VS', style: TextStyle(
            color: Colors.white.withOpacity(0.6), fontSize: 13,
            fontWeight: FontWeight.w900, letterSpacing: 2,
          )),
        ),
        // My slot
        Expanded(
          child: _myArtist != null
              ? _SlotChip(
                  artist: _SlotArtistData(
                    name:     _myArtist!.name,
                    imageUrl: _myArtistImageUrl,
                  ),
                  label:       'YOUR ARTIST',
                  accentColor: _kPink,
                  isActive:    _currentPage == 1,
                  trackCount:  _mySelectedTracks.length,
                  isReadOnly:  false,
                  onTap:       () => _goToPage(1),
                  onRemove:    () => setState(() {
                    _myArtist         = null;
                    _myArtistImageUrl = null;
                    _myTopTracks      = [];
                    _mySelectedTracks = [];
                    _trackSearchResults = null;
                    _trackFilterQuery = '';
                    _trackSearchCtrl.clear();
                    _artist2PreFilled = false;
                  }),
                )
              : _SlotChip(
                  artist: null,
                  label:       'YOUR ARTIST',
                  accentColor: _kPink,
                  isActive:    _currentPage == 1,
                  trackCount:  0,
                  isReadOnly:  false,
                  onTap:       () => _goToPage(1),
                ),
        ),
      ]),
    );
  }

  // ── Playback bar ───────────────────────────────────────────────────────────

  Widget _buildPlaybackBar() {
    final canPlay = _user1Tracks.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(children: [
        // Play
        GestureDetector(
          onTap: (!canPlay || _isPlayLoading) ? null : _handlePlay,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kSpotifyGreen.withOpacity(canPlay ? 0.25 : 0.10),
              border: Border.all(
                color: _kSpotifyGreen.withOpacity(canPlay ? 0.6 : 0.25),
                width: 1.2,
              ),
            ),
            child: _isPlayLoading
                ? const Padding(padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(color: _kSpotifyGreen, strokeWidth: 2))
                : Icon(Icons.play_arrow_rounded,
                    color: _kSpotifyGreen.withOpacity(canPlay ? 1 : 0.35), size: 24),
          ),
        ),
        const SizedBox(width: 10),
        // Round pill
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: _kSpotifyGreen.withOpacity(0.2),
              border: Border.all(color: _kSpotifyGreen.withOpacity(0.5), width: 0.8),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: _kSpotifyGreen),
              ),
              const SizedBox(width: 8),
              Text('ROUND ${_activeRound + 1}', style: const TextStyle(
                color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w800, letterSpacing: 2,
              )),
              if (_playingRound != null) ...[
                const SizedBox(width: 10),
                Text('PLAY ${_playingRound! + 1}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1,
                  ),
                ),
              ],
            ]),
          ),
        ),
        const SizedBox(width: 10),
        // Bomb
        GestureDetector(
          onTap: (!canPlay || _isBombLoading) ? null : _handleBomb,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: _kSpotifyGreen.withOpacity(canPlay ? 0.25 : 0.10),
              border: Border.all(
                color: _kSpotifyGreen.withOpacity(canPlay ? 0.6 : 0.25),
                width: 1.2,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_isBombLoading)
                const SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: _kSpotifyGreen))
              else
                Text('BOMB', style: TextStyle(
                  color: _kSpotifyGreen.withOpacity(canPlay ? 1 : 0.35),
                  fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2,
                )),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded,
                  color: _kSpotifyGreen.withOpacity(canPlay ? 1 : 0.35), size: 16),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Slider dots ────────────────────────────────────────────────────────────

  Widget _buildSliderDots() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(
          onTap: () => _goToPage(0),
          child: _SwipeDot(isActive: _currentPage == 0, color: _kPurple),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => _goToPage(1),
          child: _SwipeDot(isActive: _currentPage == 1, color: _kPink),
        ),
      ]),
    );
  }

  // ── Page 0: User1 track list (read-only) ───────────────────────────────────

  Widget _buildUser1TrackList() {
    if (_isLoadingUser1) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: 8,
        itemBuilder: (_, i) => _ShimmerTrackRow(
            shimmerController: _shimmerCtrl, accentColor: _kPurple),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildTrackListHeader(
          name:     widget.versus.artist1Name,
          imageUrl: _user1ImageUrl,
          roleLabel: 'THEIR TRACKS',
          accentColor: _kPurple,
          alignRight: false,
        ),
        // Author comment strip (read-only)
        if (widget.versus.authorComment != null &&
            widget.versus.authorComment!.isNotEmpty)
          _buildReadOnlyCommentStrip(
            username:   widget.versus.author?.username ?? widget.versus.authorID,
            avatarPath: widget.versus.author?.avatarPath,
            comment:    widget.versus.authorComment!,
            accentColor: _kPurple,
            roleLabel:  'author',
          ),
        const SizedBox(height: 10),
        if (_user1Tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(child: Text('No tracks yet.',
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13))),
          )
        else
          ..._user1Tracks.asMap().entries.map((e) {
            final i     = e.key;
            final track = e.value;
            final isActive = i == _activeRound;
            final isPast   = i < _activeRound;
            final isLast   = i == _user1Tracks.length - 1;
            return AnimatedBuilder(
              animation: _slideAnim,
              builder: (_, child) => Transform.translate(
                offset: Offset(0,
                    20 * (1 - _slideAnim.value) * math.max(0, 1 - i * 0.06)),
                child: Opacity(opacity: _slideAnim.value.clamp(0.0, 1.0), child: child),
              ),
              child: _ReadOnlyTrackRow(
                track:      track,
                index:      i,
                accentColor: _kPurple,
                isActive:   isActive,
                isPast:     isPast,
                isLast:     isLast,
                onTap:      () => _onTrackTapped(i),
              ),
            );
          }),
      ],
    );
  }

  // ── Page 1: My track list (interactive) ───────────────────────────────────

  Widget _buildMyTrackList() {
    // No artist yet — show search prompt
    if (_myArtist == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _buildMyArtistSearchBar(),
          const SizedBox(height: 24),
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_search_rounded,
                color: Colors.white.withOpacity(0.25), size: 44),
            const SizedBox(height: 10),
            Text('Search for your artist above',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 13,
                  fontWeight: FontWeight.w500)),
          ])),
        ],
      );
    }

    if (_isLoadingMyTracks) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: 8,
        itemBuilder: (_, i) => _ShimmerTrackRow(
            shimmerController: _shimmerCtrl, accentColor: _kPink),
      );
    }

    final tracks       = _myVisibleTracks;
    final picked       = _mySelectedTracks;
    final isSearchMode = _trackFilterQuery.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        // Artist header + optional search-change chip
        _buildTrackListHeader(
          name:        _myArtist!.name,
          imageUrl:    _myArtistImageUrl,
          roleLabel:   'YOUR TRACKS',
          accentColor: _kPink,
          alignRight:  true,
          trailing: GestureDetector(
            onTap: () {
              setState(() {
                _myArtist         = null;
                _myArtistImageUrl = null;
                _myTopTracks      = [];
                _mySelectedTracks = [];
                _trackSearchResults = null;
                _trackFilterQuery = '';
                _trackSearchCtrl.clear();
                _artist2PreFilled = false;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: _kPink.withOpacity(0.18),
                border: Border.all(color: _kPink.withOpacity(0.40), width: 0.8),
              ),
              child: Text('change', style: TextStyle(
                color: _kPink.withOpacity(0.9),
                fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8,
              )),
            ),
          ),
        ),
        // Artist search bar (visible when no artist pre-filled — edge case)
        _buildMyArtistSearchBar(),
        const SizedBox(height: 4),
        // Track search bar
        _buildMyTrackSearchBar(),
        const SizedBox(height: 8),
        // My comment strip (editable)
        _buildEditableCommentStrip(),
        const SizedBox(height: 10),

        // Selected tracks section
        if (picked.isNotEmpty) ...[
          _buildSectionLabel(
            icon: Icons.playlist_add_check_rounded,
            label: 'SELECTED', count: picked.length, accentColor: _kPink,
          ),
          ...picked.map((track) => _SelectedTrackTile(
            track: track, accentColor: _kPink,
            onRemove: () => _removeMyTrack(track.id),
          )),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Container(
              height: 0.8,
              decoration: BoxDecoration(gradient: LinearGradient(colors: [
                _kPink.withOpacity(0.0),
                _kPink.withOpacity(0.4),
                _kPink.withOpacity(0.0),
              ])),
            )),
          ]),
          const SizedBox(height: 10),
        ],

        // Top tracks / search results
        if (tracks.isNotEmpty)
          _buildSectionLabel(
            icon: isSearchMode ? Icons.manage_search_rounded : Icons.star_rounded,
            label: isSearchMode ? 'RESULTS' : 'TOP TRACKS',
            count: tracks.length, accentColor: _kPink,
            dimmed: picked.isNotEmpty,
          ),

        if (tracks.isEmpty && isSearchMode)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(child: Text('No tracks found for "${_myArtist!.name}"',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13))),
          )
        else if (tracks.isEmpty && !isSearchMode && !_isLoadingMyTracks)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(child: Text('No top tracks available',
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13))),
          )
        else
          ...tracks.asMap().entries.map((entry) {
            final i     = entry.key;
            final track = entry.value;
            final alreadyPicked = picked.any((t) => t.id == track.id);
            final cap = widget.versus.artist1TrackIDs.length;
            final atCap =
                cap > 0 && picked.length >= cap && !alreadyPicked;
            return AnimatedBuilder(
              animation: _slideAnim,
              builder: (_, child) => Transform.translate(
                offset: Offset(0,
                    20 * (1 - _slideAnim.value) * math.max(0, 1 - i * 0.06)),
                child: Opacity(opacity: _slideAnim.value.clamp(0.0, 1.0), child: child),
              ),
              child: _SelectableTrackRow(
                track:        track,
                accentColor:  _kPink,
                isLast:       i == tracks.length - 1,
                dimmed:       alreadyPicked || picked.isNotEmpty,
                isSelected:   alreadyPicked,
                onAdd:        (alreadyPicked || atCap)
                    ? null
                    : () => _toggleMyTrack(track),
              ),
            );
          }),
      ],
    );
  }

  // ── Artist search results overlay ──────────────────────────────────────────

  Widget _buildArtistSearchResults() {
    if (_isSearchingArtist) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 16,
          crossAxisSpacing: 12, childAspectRatio: 0.78,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => _ShimmerArtistCard(shimmerController: _shimmerCtrl),
      );
    }
    if (_artistResults.isEmpty && _lastArtistQuery.isNotEmpty) {
      return Center(child: Text('No artists found',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)));
    }
    if (_artistResults.isEmpty) {
      return Center(child: Text('Start typing to search',
        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14)));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, mainAxisSpacing: 16,
        crossAxisSpacing: 12, childAspectRatio: 0.78,
      ),
      itemCount: _artistResults.length,
      itemBuilder: (context, i) {
        final artist = _artistResults[i];
        final isSelected = _myArtist?.id == artist.id;
        return _ArtistGridCard(
          artist: artist, isSelected: isSelected,
          accentColor: _kPink,
          onTap: () => _selectMyArtist(artist),
        );
      },
    );
  }

  // ── Sub-widgets ────────────────────────────────────────────────────────────

  Widget _buildMyArtistSearchBar() {
    // Hide once an artist is selected
    if (_myArtist != null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.12),
              border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.8),
            ),
            child: TextField(
              controller: _artistSearchCtrl,
              focusNode: _artistSearchFocus,
              onChanged: _onArtistSearchChanged,
              autofocus: _myArtist == null,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              cursorColor: _kPink,
              decoration: InputDecoration(
                hintText: 'Search your artist...',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.35), fontSize: 15),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Colors.white.withOpacity(0.5), size: 20),
                suffixIcon: _artistSearchCtrl.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _artistSearchCtrl.clear(); _onArtistSearchChanged(''); },
                        child: Icon(Icons.close_rounded,
                            color: Colors.white.withOpacity(0.4), size: 18),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMyTrackSearchBar() {
    final inSearchMode = _trackFilterQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: inSearchMode
                  ? Colors.white.withOpacity(0.14)
                  : Colors.white.withOpacity(0.09),
              border: Border.all(
                color: inSearchMode
                    ? Colors.white.withOpacity(0.28)
                    : Colors.white.withOpacity(0.14),
                width: 0.8,
              ),
            ),
            child: TextField(
              controller: _trackSearchCtrl,
              focusNode: _trackSearchFocus,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              cursorColor: _kPink,
              decoration: InputDecoration(
                hintText: inSearchMode
                    ? 'Searching Spotify...'
                    : 'Search your artist\'s tracks...',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.3), fontSize: 13),
                prefixIcon: _isSearchingTracks
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.8, color: Colors.white.withOpacity(0.5))),
                      )
                    : Icon(
                        inSearchMode
                            ? Icons.manage_search_rounded
                            : Icons.queue_music_rounded,
                        color: Colors.white.withOpacity(0.4), size: 18),
                suffixIcon: _trackFilterQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _trackSearchCtrl.clear(); _trackSearchFocus.unfocus(); },
                        child: Icon(Icons.close_rounded,
                            color: Colors.white.withOpacity(0.35), size: 16),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditableCommentStrip() {
    final username = widget.currentUser.username.trim().isNotEmpty
        ? widget.currentUser.username.trim()
        : 'you';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: _kPink.withOpacity(0.22), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _MiniAvatar(
              avatarPath: widget.currentUser.avatarPath,
              accentColor: _kPink, size: 24,
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _kPink.withOpacity(0.18),
              ),
              child: const Text('collab', style: TextStyle(
                color: _kPink, fontSize: 9, fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              )),
            ),
            const SizedBox(width: 6),
            Text(username, style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 11, fontWeight: FontWeight.w700,
            )),
            const SizedBox(width: 5),
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 11, fontWeight: FontWeight.w400,
                ),
                minLines: 1, maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                cursorColor: _kPink,
                inputFormatters: [_MaxWordsInputFormatter(_maxCommentWords)],
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Your take on this side (max $_maxCommentWords words)…',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.38),
                    fontSize: 11, fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 4),
            child: Text('$_commentWordCount / $_maxCommentWords words',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withOpacity(0.32),
                fontSize: 10, fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyCommentStrip({
    required String username,
    required String? avatarPath,
    required String comment,
    required Color accentColor,
    required String roleLabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: accentColor.withOpacity(0.22), width: 0.8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        _MiniAvatar(avatarPath: avatarPath, accentColor: accentColor, size: 22),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: accentColor.withOpacity(0.18),
          ),
          child: Text(roleLabel, style: TextStyle(
            color: accentColor, fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 0.8,
          )),
        ),
        const SizedBox(width: 6),
        Text('@$username',
          style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(width: 5),
        Expanded(child: Text(comment,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11, fontWeight: FontWeight.w400))),
      ]),
    );
  }

  Widget _buildTrackListHeader({
    required String  name,
    required String? imageUrl,
    required String  roleLabel,
    required Color   accentColor,
    required bool    alignRight,
    Widget?          trailing,
  }) {
    final profile = Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor.withOpacity(0.7), width: 1.5),
        boxShadow: [BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 8)],
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl.isNotEmpty
            ? Image.network(imageUrl, fit: BoxFit.cover)
            : Container(color: accentColor.withOpacity(0.3),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 16)),
      ),
    );

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: accentColor.withOpacity(0.2),
        border: Border.all(color: accentColor.withOpacity(0.4), width: 0.8),
      ),
      child: Text(roleLabel, style: TextStyle(
        color: accentColor.withOpacity(0.9),
        fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5,
      )),
    );

    final nameWidget = Flexible(
      child: Text(name,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: const TextStyle(color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.w700, letterSpacing: 0.2)),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 4),
      child: Row(
        mainAxisAlignment:
            alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: alignRight
            ? [
                badge,
                const SizedBox(width: 8),
                nameWidget,
                const SizedBox(width: 10),
                profile,
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ]
            : [
                profile,
                const SizedBox(width: 10),
                nameWidget,
                const SizedBox(width: 8),
                badge,
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
      ),
    );
  }

  Widget _buildSectionLabel({
    required IconData icon,
    required String label,
    required int count,
    required Color accentColor,
    bool dimmed = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Row(children: [
        Icon(icon, size: 13, color: accentColor.withOpacity(dimmed ? 0.35 : 0.7)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
          color: Colors.white.withOpacity(dimmed ? 0.3 : 0.5),
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2,
        )),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: accentColor.withOpacity(dimmed ? 0.1 : 0.2),
          ),
          child: Text('$count', style: TextStyle(
            color: accentColor.withOpacity(dimmed ? 0.4 : 0.9),
            fontSize: 9, fontWeight: FontWeight.w800,
          )),
        ),
      ]),
    );
  }

  // ── Submit bar ─────────────────────────────────────────────────────────────

  Widget _buildSubmitBar() {
    final hint = _submitHint;
    final need = _authorSideTrackCount;
    final have = _mySelectedTracks.length;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: hint != null
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          need > 0 && have > 0 && have != need
                              ? Icons.balance_rounded
                              : Icons.info_outline_rounded,
                          color: Colors.white.withOpacity(0.45),
                          size: 13,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            hint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          GestureDetector(
            onTap: _canSubmit && !_isSubmitting ? _handleSubmit : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: _canSubmit
                    ? const LinearGradient(colors: [_kPurple, _kPink])
                    : null,
                color: _canSubmit ? null : Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: _canSubmit
                      ? Colors.transparent
                      : Colors.white.withOpacity(0.12),
                  width: 0.8,
                ),
                boxShadow: _canSubmit
                    ? [BoxShadow(
                        color: _kPink.withOpacity(0.35),
                        blurRadius: 18, offset: const Offset(0, 5))]
                    : [],
              ),
              child: Center(
                child: _isSubmitting
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          _canSubmit
                              ? Icons.rocket_launch_rounded
                              : Icons.lock_outline_rounded,
                          color: _canSubmit
                              ? Colors.white
                              : Colors.white.withOpacity(0.3),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(_submitLabel, style: TextStyle(
                          color: _canSubmit
                              ? Colors.white
                              : Colors.white.withOpacity(0.3),
                          fontSize: 13, fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        )),
                      ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _resolveAvatar(String avatarPath, double size) {
    final p = avatarPath.trim();
    if (p.isEmpty) return _avatarFallback(size);
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(p, width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _avatarFallback(size)),
      );
    }
    final asset = p.startsWith('assets/') ? p : 'assets/images/$p';
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.asset(asset, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(size)),
    );
  }

  Widget _avatarFallback(double size) => ClipRRect(
    borderRadius: BorderRadius.circular(size / 2),
    child: Container(
      width: size, height: size, color: Colors.white.withOpacity(0.2),
      child: Icon(Icons.person_rounded,
          color: Colors.white.withOpacity(0.8), size: size * 0.55),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SlotArtistData {
  final String  name;
  final String? imageUrl;
  const _SlotArtistData({required this.name, this.imageUrl});
}

class _SlotChip extends StatelessWidget {
  final _SlotArtistData? artist;
  final String       label;
  final Color        accentColor;
  final bool         isActive;
  final int          trackCount;
  final bool         isReadOnly;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _SlotChip({
    required this.artist,
    required this.label,
    required this.accentColor,
    required this.isActive,
    required this.trackCount,
    required this.isReadOnly,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: artist != null
                  ? accentColor.withOpacity(isActive ? 0.30 : 0.18)
                  : Colors.white.withOpacity(0.07),
              border: Border.all(
                color: artist != null
                    ? accentColor.withOpacity(isActive ? 0.8 : 0.45)
                    : Colors.white.withOpacity(0.10),
                width: isActive ? 1.5 : 1.0,
              ),
            ),
            child: artist == null
                ? Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.15), width: 1)),
                      child: Icon(Icons.add_rounded,
                          color: Colors.white.withOpacity(0.25), size: 14),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label, style: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1.2,
                    ))),
                  ])
                : Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accentColor, width: 1.5)),
                      child: ClipOval(
                        child: artist!.imageUrl != null &&
                                artist!.imageUrl!.isNotEmpty
                            ? Image.network(artist!.imageUrl!, fit: BoxFit.cover)
                            : Container(color: accentColor.withOpacity(0.3),
                                child: const Icon(Icons.person_rounded,
                                    color: Colors.white, size: 14)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(artist!.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 12, fontWeight: FontWeight.w700))),
                    if (trackCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: accentColor.withOpacity(0.35),
                        ),
                        child: Text('$trackCount',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 9, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (!isReadOnly && onRemove != null)
                      GestureDetector(
                        onTap: onRemove,
                        child: Icon(Icons.close_rounded,
                            color: Colors.white.withOpacity(0.45), size: 14),
                      )
                    else if (isReadOnly)
                      Icon(Icons.lock_rounded,
                          color: accentColor.withOpacity(0.55), size: 13),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// Read-only track row for user1's side — shows active/past/locked state
/// and is tappable to set the active round.
class _ReadOnlyTrackRow extends StatelessWidget {
  final SpotifyTrack track;
  final int          index;
  final Color        accentColor;
  final bool         isActive, isPast, isLast;
  final VoidCallback onTap;

  const _ReadOnlyTrackRow({
    required this.track,
    required this.index,
    required this.accentColor,
    required this.onTap,
    this.isActive = false,
    this.isPast   = false,
    this.isLast   = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLocked    = !isActive && !isPast;
    final textOpacity = isActive ? 1.0 : isPast ? 0.6 : 0.52;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(children: [
        Container(
          decoration: isActive
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: accentColor.withOpacity(0.42),
                  border: Border.all(
                      color: accentColor.withOpacity(0.65), width: 1.2))
              : null,
          padding: isActive
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 2)
              : EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(children: [
              SizedBox(
                width: 32,
                child: isPast
                    ? Icon(Icons.check_rounded,
                        size: 15, color: accentColor.withOpacity(0.5))
                    : isLocked
                        ? Icon(Icons.lock_rounded,
                            size: 14, color: Colors.white.withOpacity(0.45))
                        : Text('${index + 1}'.padLeft(2, '0'),
                            style: TextStyle(
                              color: isActive
                                  ? accentColor
                                  : Colors.white.withOpacity(0.42),
                              fontSize: 12, fontWeight: FontWeight.w700,
                            )),
              ),
              const SizedBox(width: 8),
              if (track.albumArtUrl != null && track.albumArtUrl!.isNotEmpty)
                Container(
                  width: 40, height: 40,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.2), blurRadius: 5)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(track.albumArtUrl!, fit: BoxFit.cover),
                  ),
                ),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(textOpacity),
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    )),
                  if (track.artistName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(track.artistName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withOpacity(textOpacity * 0.6),
                          fontSize: 12, fontWeight: FontWeight.w400)),
                  ],
                ],
              )),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: accentColor.withOpacity(0.55),
                  ),
                  child: const Text('NOW', style: TextStyle(
                    color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.w800, letterSpacing: 1.5,
                  )),
                ),
            ]),
          ),
        ),
        if (!isLast)
          Divider(height: 0, indent: 44, color: Colors.white.withOpacity(0.06)),
      ]),
    );
  }
}

class _SelectedTrackTile extends StatelessWidget {
  final SpotifyTrack track;
  final Color        accentColor;
  final VoidCallback onRemove;

  const _SelectedTrackTile({
    required this.track,
    required this.accentColor,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: accentColor.withOpacity(0.18),
              border: Border.all(color: accentColor.withOpacity(0.45), width: 1.0),
              boxShadow: [BoxShadow(
                  color: accentColor.withOpacity(0.15),
                  blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                if (track.albumArtUrl != null && track.albumArtUrl!.isNotEmpty)
                  Container(
                    width: 38, height: 38,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: accentColor.withOpacity(0.3), width: 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.network(track.albumArtUrl!, fit: BoxFit.cover),
                    ),
                  ),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 13, fontWeight: FontWeight.w700,
                          letterSpacing: -0.1)),
                    if (track.artistName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(track.artistName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: accentColor.withOpacity(0.8),
                            fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ],
                )),
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withOpacity(0.2),
                      border: Border.all(
                          color: accentColor.withOpacity(0.35), width: 0.8),
                    ),
                    child: Icon(Icons.remove_rounded,
                        color: Colors.white.withOpacity(0.8), size: 14),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectableTrackRow extends StatelessWidget {
  final SpotifyTrack  track;
  final Color         accentColor;
  final bool          isLast, dimmed, isSelected;
  final VoidCallback? onAdd;

  const _SelectableTrackRow({
    required this.track,
    required this.accentColor,
    this.isLast    = false,
    this.dimmed    = false,
    this.isSelected = false,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isSelected ? 0.35 : (dimmed ? 0.5 : 1.0),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            if (track.albumArtUrl != null && track.albumArtUrl!.isNotEmpty)
              Container(
                width: 46, height: 46,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.2), blurRadius: 6)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.network(track.albumArtUrl!, fit: BoxFit.cover),
                ),
              ),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w600, letterSpacing: -0.1,
                    decoration: isSelected ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white.withOpacity(0.4),
                  )),
                if (track.artistName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(track.artistName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 12, fontWeight: FontWeight.w400)),
                ],
              ],
            )),
            const SizedBox(width: 8),
            if (!isSelected)
              GestureDetector(
                onTap: onAdd,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withOpacity(0.22),
                    border: Border.all(
                        color: accentColor.withOpacity(0.55), width: 1.0),
                    boxShadow: [BoxShadow(
                        color: accentColor.withOpacity(0.2), blurRadius: 8)],
                  ),
                  child: Icon(Icons.add_rounded,
                      color: Colors.white.withOpacity(0.9), size: 16),
                ),
              )
            else
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withOpacity(0.15),
                  border: Border.all(
                      color: accentColor.withOpacity(0.3), width: 0.8),
                ),
                child: Icon(Icons.check_rounded,
                    color: accentColor.withOpacity(0.5), size: 14),
              ),
          ]),
        ),
        if (!isLast)
          Divider(height: 0, color: Colors.white.withOpacity(0.06)),
      ]),
    );
  }
}

class _ArtistGridCard extends StatelessWidget {
  final SpotifyArtistDetails artist;
  final bool       isSelected;
  final Color      accentColor;
  final VoidCallback onTap;

  const _ArtistGridCard({
    required this.artist,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: LayoutBuilder(builder: (_, constraints) {
            final side = math.min(constraints.maxWidth, constraints.maxHeight);
            return Stack(alignment: Alignment.topRight, children: [
              SizedBox(width: side, height: side,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? accentColor.withOpacity(0.8)
                          : Colors.white.withOpacity(0.12),
                      width: isSelected ? 2.5 : 1,
                    ),
                    boxShadow: isSelected ? [BoxShadow(
                        color: accentColor.withOpacity(0.45),
                        blurRadius: 18, spreadRadius: 2)] : [],
                  ),
                  child: ClipOval(
                    child: artist.imageUrl != null && artist.imageUrl!.isNotEmpty
                        ? Image.network(artist.imageUrl!, fit: BoxFit.cover)
                        : Container(
                            color: Colors.white.withOpacity(0.08),
                            child: Icon(Icons.person_rounded,
                                size: side * 0.45,
                                color: Colors.white.withOpacity(0.3))),
                  ),
                ),
              ),
              if (isSelected)
                Positioned(top: 0, right: 0,
                  child: Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor,
                      boxShadow: [BoxShadow(
                          color: accentColor.withOpacity(0.6), blurRadius: 8)],
                    ),
                    child: const Center(child: Icon(Icons.check_rounded,
                        color: Colors.white, size: 11)),
                  ),
                ),
            ]);
          })),
          const SizedBox(height: 8),
          Text(artist.name,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.8),
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              height: 1.3,
            )),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final String? avatarPath;
  final Color   accentColor;
  final double  size;

  const _MiniAvatar({required this.accentColor, this.avatarPath, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor.withOpacity(0.5), width: 1),
      ),
      child: ClipOval(child: _resolveChild()),
    );
  }

  Widget _resolveChild() {
    final p = avatarPath?.trim() ?? '';
    if (p.isEmpty) return _fallback();
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return Image.network(p, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback());
    }
    final asset = p.startsWith('assets/') ? p : 'assets/images/$p';
    return Image.asset(asset, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback());
  }

  Widget _fallback() => Container(
    color: accentColor.withOpacity(0.25),
    child: Icon(Icons.person_rounded,
        color: Colors.white.withOpacity(0.7), size: size * 0.55),
  );
}

class _ShimmerTrackRow extends StatelessWidget {
  final AnimationController shimmerController;
  final Color               accentColor;

  const _ShimmerTrackRow({required this.shimmerController, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerController,
      builder: (_, __) {
        final s = shimmerController.value;
        LinearGradient shimmerGrad(double opacity) => LinearGradient(
          begin: Alignment(-1 + s * 2, 0), end: Alignment(s * 2, 0),
          colors: [
            Colors.white.withOpacity(opacity * 0.5),
            Colors.white.withOpacity(opacity),
            Colors.white.withOpacity(opacity * 0.5),
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7), gradient: shimmerGrad(0.12))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 12, decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4), gradient: shimmerGrad(0.14))),
              const SizedBox(height: 5),
              Container(height: 9, width: 80, decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4), gradient: shimmerGrad(0.08))),
            ])),
            const SizedBox(width: 8),
            Container(width: 30, height: 30, decoration: BoxDecoration(
                shape: BoxShape.circle, gradient: shimmerGrad(0.10))),
          ]),
        );
      },
    );
  }
}

class _ShimmerArtistCard extends StatelessWidget {
  final AnimationController shimmerController;
  const _ShimmerArtistCard({required this.shimmerController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerController,
      builder: (_, __) {
        final s = shimmerController.value;
        LinearGradient shimmerGrad() => LinearGradient(
          begin: Alignment(-1 + s * 2, 0), end: Alignment(s * 2, 0),
          colors: [Colors.white.withOpacity(0.06),
            Colors.white.withOpacity(0.14), Colors.white.withOpacity(0.06)],
        );
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Expanded(child: Center(child: AspectRatio(aspectRatio: 1,
            child: Container(decoration: BoxDecoration(
              shape: BoxShape.circle, gradient: shimmerGrad()))))),
          const SizedBox(height: 6),
          Container(height: 8, decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6), gradient: shimmerGrad())),
          const SizedBox(height: 4),
          Container(height: 8, width: 40, decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6), gradient: shimmerGrad())),
        ]);
      },
    );
  }
}

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

class _MaxWordsInputFormatter extends TextInputFormatter {
  final int maxWords;
  const _MaxWordsInputFormatter(this.maxWords);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text  = newValue.text;
    if (text.isEmpty) return newValue;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= maxWords) return newValue;
    final clamped = words.take(maxWords).join(' ');
    return TextEditingValue(
      text: clamped,
      selection: TextSelection.collapsed(offset: clamped.length),
    );
  }
}