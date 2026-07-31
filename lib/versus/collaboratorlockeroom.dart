import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:welcometothedisco/models/post_model.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/versus/collaboratorinvitebanner.dart';
import 'package:welcometothedisco/versus/playable_album_cover.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kPurple       = AppTheme.gradientStart;
const _kPink         = AppTheme.gradientEnd;
const _kSuccessGreen = AppTheme.successGreen;

/// Entry point for Collaborator VS — author picks both artists, selects tracks
/// only for artist1, then invites a collaborator to handle artist2.
class CollaboratorLockeroom extends StatelessWidget {
  // Author profile — injected from session/auth context.
  final String authorUsername;
  final String? authorAvatarPath;

  const CollaboratorLockeroom({
    super.key,
    required this.authorUsername,
    this.authorAvatarPath,
  });

  @override
  Widget build(BuildContext context) {
    return CollaboratorSearchScreen(
      authorUsername:   authorUsername,
      authorAvatarPath: authorAvatarPath,
      onCreateVersus:
          (artist1, artist2, selectedTracks1, authorComment) async {
        try {
          // Rankings are NOT written here when artist2 is still empty — only after
          // the backroom submit ([acceptCollaborationInvite]) when versus is open|active
          // with both artists. If both artists are chosen up front, [createArtistVersus]
          // stubs both immediately.
          await FirebaseService.createCollaboratorVersus(
            artist1ID:       artist1.id,
            artist1Name:     artist1.name,
            artist1TrackIDs: selectedTracks1.map((t) => t.id).toList(),
            artist2ID:       artist2?.id ?? '',
            artist2Name:     artist2?.name ?? '',
            artist2TrackIDs: [],   // collaborator fills this in later
            authorComment:   authorComment,
            artist1ImageUrl: artist1.imageUrl ?? '',
            artist2ImageUrl: artist2?.imageUrl ?? '',
          );
          if (context.mounted) Navigator.of(context).pop();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to create versus: $e'),
              backgroundColor: Colors.red.withOpacity(0.85),
            ));
          }
        }
      },
    );
  }
}

class CollaboratorSearchScreen extends StatefulWidget {
  final String  authorUsername;
  final String? authorAvatarPath;

  final Future<void> Function(
    SpotifyArtistDetails  artist1,
    SpotifyArtistDetails? artist2,      // nullable — artist2 optional
    List<SpotifyTrack>    selectedTracks1,
    String                authorComment,
  ) onCreateVersus;

  const CollaboratorSearchScreen({
    super.key,
    required this.authorUsername,
    required this.onCreateVersus,
    this.authorAvatarPath,
  });

  @override
  State<CollaboratorSearchScreen> createState() =>
      _CollaboratorSearchScreenState();
}

class _CollaboratorSearchScreenState extends State<CollaboratorSearchScreen>
    with TickerProviderStateMixin {
  final SpotifyApi _api = SpotifyApi();
  final TextEditingController _searchController   = TextEditingController();
  final FocusNode             _focusNode          = FocusNode();

  // ── Artist search ──────────────────────────────────────────────────────────
  Timer? _debounce;
  List<SpotifyArtistDetails> _results     = [];
  bool                       _isSearching = false;
  String                     _lastQuery   = '';

  // slots: 0 = author's artist (purple), 1 = collaborator's artist (pink)
  final List<SpotifyArtistDetails?> _selected = [null, null];

  // ── Top tracks ─────────────────────────────────────────────────────────────
  List<List<SpotifyTrack>> _topTracks      = [[], []];
  bool                     _isLoadingTracks = false;

  // ── Discography for author's artist (lazy background load) ─────────────────
  List<SpotifyTrack> _discographyTracks0 = [];
  bool               _isLoadingDiscography = false;

  // ── Author-only selected tracks (slot 0 only) ──────────────────────────────
  final List<SpotifyTrack> _selectedTracks1 = [];

  // ── Firebase submission state ──────────────────────────────────────────────
  bool _isSubmitting = false;

  /// Set to true once [FirebaseService.createCollaborationInvite] succeeds.
  /// Cleared only when the artist selection changes (not on track changes).
  bool _collaborationInviteSent = false;

  /// The Firestore doc ID returned by [FirebaseService.createCollaborationInvite].
  /// On CREATE, this doc is updated with final tracks; status stays `incomplete` until
  /// the collaborator finishes in the backroom (`acceptCollaborationInvite` → `open`).
  String? _collaborationVersusID;

  // ── Author comment ─────────────────────────────────────────────────────────
  final TextEditingController _authorCommentController =
      TextEditingController();
  static const int _authorCommentMaxWords = 30;

  String get authorComment => _authorCommentController.text.trim();

  int get _authorCommentWordCount {
    final t = _authorCommentController.text.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  // ── Track search (slot 0 only) ─────────────────────────────────────────────
  final TextEditingController _trackFilterController = TextEditingController();
  final FocusNode             _trackFilterFocus      = FocusNode();
  String                       _trackFilterQuery     = '';
  Timer?                       _trackDebounce;
  List<SpotifyTrack>?          _trackSearchResults1;
  bool                         _isSearchingTracks   = false;

  // ── Page / animation ───────────────────────────────────────────────────────
  late final AnimationController _shimmerController;
  late final AnimationController _slideController;
  late final Animation<double>   _slideAnim;
  late final PageController      _pageController;
  int _selectedArtistPage = 0;

  @override
  void initState() {
    super.initState();

    _shimmerController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400),
    )..repeat();

    _slideController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380),
    );
    _slideAnim = CurvedAnimation(
      parent: _slideController, curve: Curves.easeOutCubic,
    );

    _pageController = PageController();
    _trackFilterController.addListener(_onTrackFilterChanged);
    _authorCommentController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _trackDebounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _shimmerController.dispose();
    _slideController.dispose();
    _pageController.dispose();
    _trackFilterController.removeListener(_onTrackFilterChanged);
    _trackFilterController.dispose();
    _trackFilterFocus.dispose();
    _authorCommentController.dispose();
    super.dispose();
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  /// Artist 1 selected — enough to enter track selection mode.
  bool get _artist1Selected  => _selected[0] != null;

  /// Both artists selected — enables the collaborator page tab.
  bool get _canCreate        => _selected[0] != null && _selected[1] != null;

  /// Tracks + successful collaborator invite (with or without artist2 yet).
  bool get _canSubmit {
    if (!_artist1Selected || _selectedTracks1.isEmpty) return false;
    if (!_collaborationInviteSent) return false;
    return true;
  }

  /// True once collaborator's artist (slot 1) is chosen.
  bool get _artist2Locked    => _selected[1] != null;

  String get _displayAuthorName {
    var s = widget.authorUsername.trim();
    if (s.startsWith('@')) s = s.substring(1);
    return s.isEmpty ? 'Profile' : s;
  }

  Widget _headerAvatarFallback(double size) => Container(
        width: size,
        height: size,
        color: Colors.white.withOpacity(0.2),
        child: Icon(
          Icons.person_rounded,
          color: Colors.white.withOpacity(0.8),
          size: 18,
        ),
      );

  Widget _headerProfileAvatar(double size) {
    final p = widget.authorAvatarPath?.trim() ?? '';
    if (p.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: _headerAvatarFallback(size),
      );
    }
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(
          p,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _headerAvatarFallback(size),
        ),
      );
    }
    final assetPath = p.startsWith('assets/')
        ? p
        : p.startsWith('/')
            ? p.substring(1)
            : 'assets/images/$p';
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _headerAvatarFallback(size),
      ),
    );
  }

  String? get _submitHint {
    if (!_artist1Selected) return null;
    if (_selectedTracks1.isEmpty) {
      return 'Select at least one track for ${_selected[0]?.name ?? 'your artist'}';
    }
    if (!_collaborationInviteSent) {
      return 'Use Invite on the friend\'s artist slot or collab card before you can create';
    }
    return null;
  }

  String get _submitBarButtonLabel {
    if (_canSubmit) {
      return _canCreate ? 'CREATE VERSUS' : 'CREATE — ADD COLLAB LATER';
    }
    if (!_artist1Selected || _selectedTracks1.isEmpty) {
      return 'SELECT YOUR TRACKS FIRST';
    }
    if (!_collaborationInviteSent) {
      return 'SEND INVITE FIRST';
    }
    return 'SELECT YOUR TRACKS FIRST';
  }

  // ── Artist search ──────────────────────────────────────────────────────────
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q == _lastQuery) return;
    if (q.isEmpty) {
      setState(() { _results = []; _isSearching = false; _lastQuery = ''; });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 380), () async {
      _lastQuery = q;
      final results = await _api.searchArtists(q, limit: 12);
      if (!mounted) return;
      setState(() { _results = results; _isSearching = false; });
    });
  }

  void _onArtistTap(SpotifyArtistDetails artist) {
    setState(() {
      if (_selected[0]?.id == artist.id) {
        // Tapping the already-selected artist1 deselects it and resets everything.
        _selected[0] = null;
        _topTracks[0] = [];
        _selectedTracks1.clear();
        _trackSearchResults1 = null;
        _discographyTracks0 = [];
        _collaborationInviteSent = false;
        _collaborationVersusID = null;
        if (_selected[1] != null) {
          _selected[1] = null;
          _topTracks[1] = [];
        }
        return;
      }
      if (_selected[1]?.id == artist.id) {
        // Collaborator artist is fixed after selection — no tap-to-clear from grid.
        return;
      }
      if (_selected[0] == null) {
        // First artist slot is empty — fill it and immediately enter track mode.
        _selected[0] = artist;
      } else if (_selected[1] == null) {
        // Artist1 already picked, now picking artist2.
        _selected[1] = artist;
        _collaborationInviteSent = false;
        _collaborationVersusID = null;
      } else {
        // Both filled: only replace artist1; artist2 stays locked.
        _selected[0] = artist;
        _topTracks[0] = [];
        _selectedTracks1.clear();
        _trackSearchResults1 = null;
        _discographyTracks0 = [];
        _collaborationInviteSent = false;
        _collaborationVersusID = null;
      }

      // Close the artist search overlay after a selection.
      _searchController.clear();
      _results = [];
      _isSearching = false;
      _lastQuery = '';
    });
    _maybeFetchTopTracks();
  }

  int? _slotFor(String artistId) {
    if (_selected[0]?.id == artistId) return 0;
    if (_selected[1]?.id == artistId) return 1;
    return null;
  }

  // ── Top tracks fetch ───────────────────────────────────────────────────────
  /// Fetches top tracks as soon as artist1 is set.
  /// If artist2 is also set, fetches both together (1 extra call saved vs 2 separate).
  Future<void> _maybeFetchTopTracks() async {
    final a1 = _selected[0];
    if (a1 == null) return;
    if (_isLoadingTracks) return;

    setState(() {
      _isLoadingTracks = true;
      _discographyTracks0 = []; // reset on new artist
    });
    try {
      final a2 = _selected[1];
      if (a2 != null) {
        // Both selected — batch fetch.
        final both = await _api.getBothArtistsTopTracks(a1.id, a2.id);
        if (!mounted) return;
        setState(() {
          _topTracks = [both[0], both[1]];
          _trackSearchResults1 = null;
          _trackFilterController.clear();
          _trackFilterQuery = '';
        });
      } else {
        // Only artist1 — fetch just their tracks.
        final tracks = await _api.getArtistTopTracks(a1.id);
        if (!mounted) return;
        setState(() {
          _topTracks = [tracks, []];
          _trackSearchResults1 = null;
          _trackFilterController.clear();
          _trackFilterQuery = '';
        });
      }
      _slideController.forward(from: 0);
      // Background-load full discography for author's artist
      unawaited(_loadDiscographyForAuthor(a1));
    } finally {
      if (mounted) setState(() => _isLoadingTracks = false);
    }
  }

  Future<void> _loadDiscographyForAuthor(SpotifyArtistDetails a1) async {
    if (!mounted) return;
    setState(() => _isLoadingDiscography = true);
    try {
      final tracks = await _api.getArtistDiscographyTracks(a1.id);
      if (!mounted) return;
      if (_selected[0]?.id != a1.id) return; // stale — artist changed
      setState(() => _discographyTracks0 = tracks);
      _slideController.forward(from: 0);
    } catch (e) {
      debugPrint('[CollaboratorLockeroom] discography load failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDiscography = false);
    }
  }

  bool get _isShowingDiscographyForAuthor =>
      _trackFilterQuery.isEmpty && _discographyTracks0.isNotEmpty;

  // ── Track search (artist1 / slot-0 only) ───────────────────────────────────
  void _onTrackFilterChanged() {
    final q = _trackFilterController.text.trim();
    if (q == _trackFilterQuery) return;
    setState(() => _trackFilterQuery = q);

    _trackDebounce?.cancel();

    if (q.isEmpty) {
      setState(() { _trackSearchResults1 = null; _isSearchingTracks = false; });
      return;
    }

    setState(() => _isSearchingTracks = true);
    _trackDebounce = Timer(const Duration(milliseconds: 420), () async {
      final a1 = _selected[0];
      if (a1 == null || !mounted) return;

      final results = await _api.searchTracksByArtists(
        q,
        artist1Id: a1.id, artist1Name: a1.name,
        artist2Id: '', artist2Name: '',
        limitPerArtist: 20,
      );
      if (!mounted) return;
      setState(() {
        _trackSearchResults1 = results[a1.id] ?? [];
        _isSearchingTracks   = false;
      });
      _slideController.forward(from: 0);
    });
  }

  // ── Track selection (slot 0 only) ──────────────────────────────────────────
  void _toggleTrackSelection1(SpotifyTrack track) {
    setState(() {
      final idx = _selectedTracks1.indexWhere((t) => t.id == track.id);
      if (idx >= 0) {
        _selectedTracks1.removeAt(idx);
      } else {
        _selectedTracks1.add(track);
      }
    });
  }

  void _removeSelectedTrack1(String trackId) {
    setState(() => _selectedTracks1.removeWhere((t) => t.id == trackId));
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _handleSubmit() async {
    if (!_canSubmit || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final existingID = _collaborationVersusID;
      if (existingID != null) {
        // Patch the draft with final artist1 tracks; status remains incomplete until collaborator accepts.
        await FirebaseService.openCollaborationVersus(
          versusID: existingID,
          artist1TrackIDs: _selectedTracks1.map((t) => t.id).toList(),
          artist2ID: _selected[1]?.id,
          artist2Name: _selected[1]?.name,
          authorComment: authorComment,
        );
        if (mounted) Navigator.of(context).pop();
      } else {
        // Fallback: create a fresh doc (no prior invite doc to upgrade).
        await widget.onCreateVersus(
          _selected[0]!,
          _selected[1],
          _selectedTracks1,
          authorComment,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to create versus: $e'),
          backgroundColor: Colors.red.withOpacity(0.85),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Track list for page ────────────────────────────────────────────────────
  List<SpotifyTrack> _tracksForPage(int pageIndex) {
    if (pageIndex == 1) return _topTracks[1];
    final a1 = _selected[0];
    if (a1 == null) return [];
    if (_trackFilterQuery.isNotEmpty && _trackSearchResults1 != null) {
      return _trackSearchResults1!;
    }
    if (_discographyTracks0.isNotEmpty) return _discographyTracks0;
    return _topTracks[0];
  }

  void _onArtistPageChanged(int index) {
    if (_selectedArtistPage == index) return;
    setState(() => _selectedArtistPage = index);
    _slideController.forward(from: 0);
  }

  void _goToArtistPage(int index) {
    if (_selectedArtistPage == index) return;
    setState(() => _selectedArtistPage = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    _slideController.forward(from: 0);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final showArtistResultsOverlay =
        _searchController.text.trim().isNotEmpty || _isSearching;

    // Trigger track fetch when artist1 is selected and tracks haven't loaded yet.
    if (_artist1Selected &&
        _topTracks[0].isEmpty &&
        !_isLoadingTracks) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeFetchTopTracks());
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.gradientStart, AppTheme.gradientEnd],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildHeader(context),
            // Show artist search bar when we haven't entered track mode yet,
            // OR when we're in track mode but artist2 is not yet picked
            // (so user can still add the second artist).
            _buildArtistSearchBar(),
            _buildSelectedSlots(),
            if (_artist1Selected) ...[
              // Track search bar only relevant for page 0 (author's artist)
              if (_selectedArtistPage == 0) _buildTrackSearchBar(),
              if (_canCreate) _buildSliderDots(),
              Expanded(
                child: Stack(
                  children: [
                    _buildArtistSlider(),
                    if (showArtistResultsOverlay)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppTheme.gradientStart, AppTheme.gradientEnd],
                            ),
                          ),
                          child: _buildResults(),
                        ),
                      ),
                  ],
                ),
              ),
              _buildSubmitBar(),
            ] else
              Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    // Subtitle adapts to current state.
    String subtitle;
    if (!_artist1Selected) {
      subtitle = 'search and pick your artist first';
    } else if (!_artist2Locked) {
      subtitle = 'search to add your friend\'s artist (optional)';
    } else {
      subtitle = 'friend\'s artist is set — select your tracks';
    }

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        left: 20, right: 20, bottom: 10,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('COLLAB VS', style: TextStyle(
                  color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w900, letterSpacing: 3.5,
                )),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildAuthorChip(),
        ],
      ),
    );
  }

  Widget _buildAuthorChip() {
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
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.gradientStart.withOpacity(0.40),
                AppTheme.gradientEnd.withOpacity(0.40),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.18),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: _headerProfileAvatar(size),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  _displayAuthorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Submit bar ─────────────────────────────────────────────────────────────
  Widget _buildSubmitBar() {
    final hint = _submitHint;
    final buttonLabel = _submitBarButtonLabel;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: hint != null
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: Colors.white.withOpacity(0.4), size: 13),
                          const SizedBox(width: 6),
                          Flexible(child: Text(hint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11, fontWeight: FontWeight.w500,
                            ),
                          )),
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
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _canSubmit
                                  ? Icons.send_rounded
                                  : Icons.lock_outline_rounded,
                              color: _canSubmit
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              buttonLabel,
                              style: TextStyle(
                                color: _canSubmit
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.3),
                                fontSize: 13, fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Artist search bar ──────────────────────────────────────────────────────
  Widget _buildArtistSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.12),
              border: Border.all(
                  color: Colors.white.withOpacity(0.18), width: 0.8),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              onChanged: _onSearchChanged,
              autofocus: !_artist1Selected, // only autofocus before artist1 picked
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              cursorColor: _kPink,
              decoration: InputDecoration(
                hintText: _artist1Selected
                    ? 'Search your friend\'s artist...'
                    : 'Search artists...',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.35), fontSize: 15),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Colors.white.withOpacity(0.5), size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
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

  // ── Track search bar (author / slot-0 only) ────────────────────────────────
  Widget _buildTrackSearchBar() {
    final bool inSearchMode = _trackFilterQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
              controller: _trackFilterController,
              focusNode: _trackFilterFocus,
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
                        child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      )
                    : Icon(
                        inSearchMode
                            ? Icons.manage_search_rounded
                            : Icons.queue_music_rounded,
                        color: Colors.white.withOpacity(0.4), size: 18,
                      ),
                suffixIcon: _trackFilterQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _trackFilterController.clear();
                          _trackFilterFocus.unfocus();
                        },
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

  // ── Selected slots ─────────────────────────────────────────────────────────
  Widget _buildSelectedSlots() {
    final hasAny = _selected[0] != null || _selected[1] != null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: hasAny
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _SelectedSlot(
                      artist: _selected[0],
                      label: 'YOUR ARTIST',
                      accentColor: _kPurple,
                      trackCount: _selectedTracks1.length,
                      onRemove: () => setState(() {
                        _selected[0] = null;
                        _topTracks[0] = [];
                        _selectedTracks1.clear();
                        _trackSearchResults1 = null;
                        _discographyTracks0 = [];
                        _collaborationInviteSent = false;
                        _collaborationVersusID = null;
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('VS', style: TextStyle(
                      color: Colors.white.withOpacity(0.6), fontSize: 13,
                      fontWeight: FontWeight.w900, letterSpacing: 2,
                    )),
                  ),
                  Expanded(
                    child: _SelectedSlot(
                      artist: _selected[1],
                      label: "",
                      accentColor: _kPink,
                      trackCount: 0,
                      showTrackCount: false,
                      trailingWidgets: [
                        _buildInvitePill(),
                      ],
                      onRemove: () => setState(() {
                        _selected[1] = null;
                        _topTracks[1] = [];
                        _collaborationInviteSent = false;
                        _collaborationVersusID = null;
                      }),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ── Slider dots — only shown when both artists are selected ────────────────
  Widget _buildSliderDots() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _goToArtistPage(0),
            child: _SwipeDot(isActive: _selectedArtistPage == 0, color: _kPurple),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _goToArtistPage(1),
            child: _SwipeDot(isActive: _selectedArtistPage == 1, color: _kPink),
          ),
        ],
      ),
    );
  }

  // ── Artist track slider ────────────────────────────────────────────────────
  Widget _buildArtistSlider() {
    // When only artist1 is selected, just show their track list (no page view).
    if (!_canCreate) {
      return _buildAuthorTrackList();
    }
    return PageView(
      controller: _pageController,
      onPageChanged: _onArtistPageChanged,
      children: [
        _buildAuthorTrackList(),
        _buildCollaboratorPlaceholder(),
      ],
    );
  }

  // ── Page 0: author track list (full interaction) ───────────────────────────
  Widget _buildAuthorTrackList() {
    final artist = _selected[0];
    if (artist == null) return const SizedBox.shrink();

    if (_isLoadingTracks) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: 8,
        itemBuilder: (_, i) => _ShimmerTrackRow(
          shimmerController: _shimmerController, accentColor: _kPurple),
      );
    }

    if (_isSearchingTracks) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: 5,
        itemBuilder: (_, i) => _ShimmerTrackRow(
          shimmerController: _shimmerController, accentColor: _kPurple),
      );
    }

    final tracks  = _tracksForPage(0);
    final picked  = _selectedTracks1;
    final isSearchMode = _trackFilterQuery.isNotEmpty;
    final isDiscography = _isShowingDiscographyForAuthor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildTrackListHeader(
          artist: artist, accentColor: _kPurple,
          isSecondArtist: false, isSearchMode: isSearchMode,
          isDiscography: isDiscography,
        ),

        _buildAuthorCommentStrip(),
        const SizedBox(height: 10),

        if (picked.isNotEmpty) ...[
          _buildSectionLabel(
            icon: Icons.playlist_add_check_rounded,
            label: 'SELECTED',
            count: picked.length,
            accentColor: _kPurple,
          ),
          ...picked.map((track) => AnimatedBuilder(
                animation: _slideAnim,
                builder: (_, child) => child!,
                child: _SelectedTrackTile(
                  track: track,
                  accentColor: _kPurple,
                  onRemove: () => _removeSelectedTrack1(track.id),
                ),
              )),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Container(
              height: 0.8,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  _kPurple.withOpacity(0.0),
                  _kPurple.withOpacity(0.4),
                  _kPurple.withOpacity(0.0),
                ]),
              ),
            )),
          ]),
          const SizedBox(height: 10),
        ],

        if (tracks.isNotEmpty)
          _buildSectionLabel(
            icon: isSearchMode
                ? Icons.manage_search_rounded
                : (isDiscography ? Icons.library_music_rounded : Icons.star_rounded),
            label: isSearchMode
                ? 'SEARCH RESULTS'
                : (isDiscography ? 'DISCOGRAPHY' : 'TOP TRACKS'),
            count: tracks.length,
            accentColor: _kPurple,
            dimmed: picked.isNotEmpty,
          ),

        if (tracks.isEmpty && isSearchMode)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.search_off_rounded,
                  color: Colors.white.withOpacity(0.25), size: 36),
              const SizedBox(height: 10),
              Text('No tracks found for "${artist.name}"',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 13)),
            ])),
          )
        else if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(child: Text('No top tracks available',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.35), fontSize: 13))),
          )
        else
          ...tracks.asMap().entries.map((entry) {
            final i     = entry.key;
            final track = entry.value;
            final alreadyPicked = picked.any((t) => t.id == track.id);
            return AnimatedBuilder(
              animation: _slideAnim,
              builder: (context, child) => Transform.translate(
                offset: Offset(0,
                    20 * (1 - _slideAnim.value) * math.max(0, 1 - i * 0.06)),
                child: Opacity(
                    opacity: _slideAnim.value.clamp(0.0, 1.0), child: child),
              ),
              child: _TopTrackRow(
                track: track,
                accentColor: _kPurple,
                isLast: i == tracks.length - 1,
                dimmed: alreadyPicked || picked.isNotEmpty,
                isSelected: alreadyPicked,
                onAdd: alreadyPicked
                    ? null
                    : () => _toggleTrackSelection1(track),
              ),
            );
          }),

        // Loading indicator while discography loads in the background
        if (_isLoadingDiscography && !isSearchMode && !isDiscography)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: _kPurple.withOpacity(0.4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'loading full discography...',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.28),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Author identity micro-strip ────────────────────────────────────────────
  Widget _buildAuthorCommentStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: _kPurple.withOpacity(0.22), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CommentAvatar(
                avatarPath:  widget.authorAvatarPath,
                accentColor: _kPurple,
                size:        24,
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: _kPurple.withOpacity(0.18),
                ),
                child: const Text('author', style: TextStyle(
                  color: _kPurple,
                  fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8,
                )),
              ),
              const SizedBox(width: 6),
              Text(
                _displayAuthorName,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 11, fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: TextField(
                  controller: _authorCommentController,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: _kPink,
                  inputFormatters: [
                    _MaxWordsInputFormatter(_authorCommentMaxWords),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Note for this side (max $_authorCommentMaxWords words)…',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.38),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 4),
            child: Text(
              '$_authorCommentWordCount / $_authorCommentMaxWords words',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withOpacity(0.32),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Page 1: collaborator placeholder (locked / invite) ─────────────────────
  Widget _buildCollaboratorPlaceholder() {
    final artist = _selected[1];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        if (artist != null)
          _buildTrackListHeader(
            artist: artist, accentColor: _kPink,
            isSecondArtist: true, isSearchMode: false,
          ),

        if (artist != null) ...[
          _buildCollaboratorInviteCard(),
          const SizedBox(height: 16),
        ],

        if (artist != null) ...[
          _buildSectionLabel(
            icon: Icons.lock_rounded,
            label: 'TRACKS',
            count: 0,
            accentColor: _kPink,
          ),
          const SizedBox(height: 4),
          ..._buildGhostTrackRows(5),
        ],
      ],
    );
  }

  void _showCollaboratorInviteBanner() {
    final artist1 = _selected[0];
    if (artist1 == null) return;

    final artist2 = _selected[1];
    CollaboratorInviteBanner.show(
      context,
      artistName: artist2?.name ?? 'this artist',
      artistImageUrl: artist2?.imageUrl,
      onInviteSent: (FriendEntry? selectedFriend) async {
        String? versusID;
        try {
          // Versus is `incomplete` — no `rankings` docs until backroom confirms and
          // [FirebaseService.acceptCollaborationInvite] sets status open|active.
          versusID = await FirebaseService.createCollaborationInvite(
            artist1ID: artist1.id,
            artist1Name: artist1.name,
            artist1TrackIDs: _selectedTracks1.map((t) => t.id).toList(),
            artist2ID: artist2?.id,
            artist2Name: artist2?.name,
            artist1ImageUrl: artist1.imageUrl ?? '',
            artist2ImageUrl: artist2?.imageUrl ?? '',
            authorComment: authorComment,
            collaboratorUID: selectedFriend?.uid,
            collaboratorUsername: selectedFriend?.username,
            collaboratorAvatarPath: selectedFriend?.avatarPath,
          );
        } catch (e) {
          debugPrint(
              '[CollaboratorLockeroom] createCollaborationInvite failed: $e');
        }

        if (!context.mounted) return;
        final ok = versusID != null;
        if (ok) {
          setState(() {
            _collaborationInviteSent = true;
            _collaborationVersusID = versusID;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Invite sent!' : 'Invite sent (offline)'),
            backgroundColor: ok
                ? _kSuccessGreen.withOpacity(0.92)
                : const Color(0xFFD97706).withOpacity(0.92),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  Widget _buildInvitePill() {
    return GestureDetector(
      onTap: _showCollaboratorInviteBanner,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: _kPink.withOpacity(0.22),
          border: Border.all(color: _kPink.withOpacity(0.55), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: _kPink.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.person_add_alt_1_rounded, color: _kPink, size: 12),
          const SizedBox(width: 4),
          const Text(
            'INVITE',
            style: TextStyle(
              color: _kPink,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _buildGhostTrackRows(int count) {
    return List.generate(count, (i) {
      final isFirst = i == 0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Column(children: [
          Opacity(
            opacity: math.max(0.08, 0.35 - i * 0.06),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Container(
                  width: 46, height: 46,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    color: _kPink.withOpacity(0.12),
                    border: Border.all(
                        color: _kPink.withOpacity(0.15), width: 0.8),
                  ),
                  child: Icon(Icons.music_note_rounded,
                      color: _kPink.withOpacity(0.3), size: 18),
                ),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isFirst)
                      Row(children: [
                        Icon(Icons.group_add_rounded,
                            color: _kPink.withOpacity(0.5), size: 13),
                        const SizedBox(width: 5),
                        Text(
                          'collaborator will add tracks',
                          style: TextStyle(
                            color: _kPink.withOpacity(0.7),
                            fontSize: 12, fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ])
                    else
                      Container(
                        height: 10, width: double.infinity * (0.8 - i * 0.1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    const SizedBox(height: 5),
                    Container(
                      height: 8, width: 70 - i * 6.0,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.white.withOpacity(0.05),
                      ),
                    ),
                  ],
                )),
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kPink.withOpacity(0.08),
                    border: Border.all(
                        color: _kPink.withOpacity(0.2), width: 0.8),
                  ),
                  child: Icon(Icons.lock_rounded,
                      color: _kPink.withOpacity(0.3), size: 13),
                ),
              ]),
            ),
          ),
          if (i < count - 1)
            Divider(height: 0, color: Colors.white.withOpacity(0.04)),
        ]),
      );
    });
  }

  Widget _buildCollaboratorInviteCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: _kPink.withOpacity(0.10),
            border: Border.all(
                color: _kPink.withOpacity(0.28), width: 0.9),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kPink.withOpacity(0.15),
                  border: Border.all(
                      color: _kPink.withOpacity(0.35), width: 1.2),
                ),
                child: Icon(Icons.person_add_alt_1_rounded,
                    color: _kPink.withOpacity(0.7), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _kPink.withOpacity(0.2),
                        ),
                        child: Text('collab', style: TextStyle(
                          color: _kPink.withOpacity(0.9),
                          fontSize: 9, fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        )),
                      ),
                      const SizedBox(width: 6),
                      Text('pending invitation',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11, fontWeight: FontWeight.w500,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text('They\'ll pick the tracks for this side',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.32),
                        fontSize: 10, fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _showCollaboratorInviteBanner,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: _kPink.withOpacity(0.22),
                    border: Border.all(
                        color: _kPink.withOpacity(0.55), width: 1.0),
                    boxShadow: [BoxShadow(
                        color: _kPink.withOpacity(0.2),
                        blurRadius: 10, offset: const Offset(0, 2))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_add_alt_1_rounded,
                        color: _kPink, size: 13),
                    const SizedBox(width: 5),
                    const Text('INVITE', style: TextStyle(
                      color: _kPink, fontSize: 10,
                      fontWeight: FontWeight.w800, letterSpacing: 1.2,
                    )),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared header/section widgets ──────────────────────────────────────────
  Widget _buildTrackListHeader({
    required SpotifyArtistDetails artist,
    required Color accentColor,
    required bool isSecondArtist,
    required bool isSearchMode,
    bool isDiscography = false,
  }) {
    final profile = Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor.withOpacity(0.7), width: 1.5),
        boxShadow: [BoxShadow(
            color: accentColor.withOpacity(0.3), blurRadius: 8)],
      ),
      child: ClipOval(
        child: artist.imageUrl != null && artist.imageUrl!.isNotEmpty
            ? Image.network(artist.imageUrl!, fit: BoxFit.cover)
            : Container(color: accentColor.withOpacity(0.3),
                child: const Icon(Icons.person_rounded,
                    color: Colors.white, size: 16)),
      ),
    );

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: accentColor.withOpacity(0.2),
        border: Border.all(color: accentColor.withOpacity(0.4), width: 0.8),
      ),
      child: Text(
        isSecondArtist ? "COLLAB'S" : (isSearchMode ? 'SEARCH' : (isDiscography ? 'DISCOGRAPHY' : 'TOP TRACKS')),
        style: TextStyle(color: accentColor.withOpacity(0.9),
            fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5),
      ),
    );

    final nameWidget = Flexible(
      child: Text(artist.name,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        textAlign: isSecondArtist ? TextAlign.right : TextAlign.left,
        style: const TextStyle(color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 4),
      child: Row(
        mainAxisAlignment:
            isSecondArtist ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: isSecondArtist
            ? [badge, const SizedBox(width: 8), nameWidget,
               const SizedBox(width: 10), profile]
            : [profile, const SizedBox(width: 10), nameWidget,
               const SizedBox(width: 8), badge],
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
        Icon(icon, size: 13,
            color: accentColor.withOpacity(dimmed ? 0.35 : 0.7)),
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

  // ── Results grid ───────────────────────────────────────────────────────────
  Widget _buildResults() {
    if (_isSearching) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 16,
          crossAxisSpacing: 12, childAspectRatio: 0.78,
        ),
        itemCount: 6,
        itemBuilder: (_, __) =>
            _ShimmerArtistCard(shimmerController: _shimmerController),
      );
    }

    if (_results.isEmpty && _lastQuery.isNotEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off_rounded,
            color: Colors.white.withOpacity(0.25), size: 40),
        const SizedBox(height: 10),
        Text('No artists found', style: TextStyle(
          color: Colors.white.withOpacity(0.4), fontSize: 14,
          fontWeight: FontWeight.w500,
        )),
      ]));
    }

    if (_results.isEmpty) {
      return Center(child: Text('Start typing to search', style: TextStyle(
        color: Colors.white.withOpacity(0.3), fontSize: 14,
        fontWeight: FontWeight.w500,
      )));
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, mainAxisSpacing: 16,
        crossAxisSpacing: 12, childAspectRatio: 0.78,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final artist = _results[i];
        final slot   = _slotFor(artist.id);
        return _ArtistCard(
          artist: artist, selectedSlot: slot,
          onTap: () => _onArtistTap(artist),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CommentAvatar extends StatelessWidget {
  final String? avatarPath;
  final Color   accentColor;
  final double  size;

  const _CommentAvatar({
    required this.accentColor,
    this.avatarPath,
    this.size = 24,
  });

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
    final assetPath = p.startsWith('assets/') ? p : 'assets/images/$p';
    return Image.asset(assetPath, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback());
  }

  Widget _fallback() => Container(
    color: accentColor.withOpacity(0.25),
    child: Icon(Icons.person_rounded,
        color: Colors.white.withOpacity(0.7), size: size * 0.55),
  );
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
              border: Border.all(
                  color: accentColor.withOpacity(0.45), width: 1.0),
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
                      boxShadow: [BoxShadow(
                          color: accentColor.withOpacity(0.2), blurRadius: 6)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.network(
                          track.albumArtUrl!, fit: BoxFit.cover),
                    ),
                  ),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 13, fontWeight: FontWeight.w700,
                          letterSpacing: -0.1),
                    ),
                    if (track.artistName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(track.artistName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: accentColor.withOpacity(0.8),
                            fontSize: 11, fontWeight: FontWeight.w500),
                      ),
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

class _TopTrackRow extends StatelessWidget {
  final SpotifyTrack  track;
  final Color         accentColor;
  final bool          isLast, dimmed, isSelected;
  final VoidCallback? onAdd;
  final VoidCallback? onCoverTap;
  final bool          isPreviewPlaying;
  final bool          isPreviewLoading;

  const _TopTrackRow({
    required this.track,
    required this.accentColor,
    this.isLast          = false,
    this.dimmed          = false,
    this.isSelected      = false,
    this.onAdd,
    this.onCoverTap,
    this.isPreviewPlaying = false,
    this.isPreviewLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final contentOpacity = isSelected ? 0.35 : (dimmed ? 0.5 : 1.0);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: contentOpacity,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            if (track.albumArtUrl != null && track.albumArtUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: onCoverTap != null
                    ? PlayableAlbumCover(
                        imageUrl:        track.albumArtUrl!,
                        size:            46,
                        borderRadius:    7,
                        accentColor:     accentColor,
                        isPlaying:       isPreviewPlaying,
                        isLoading:       isPreviewLoading,
                        onTap:           onCoverTap!,
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.network(track.albumArtUrl!,
                            width: 46, height: 46, fit: BoxFit.cover),
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
                  ),
                ),
                if (track.artistName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(track.artistName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 12, fontWeight: FontWeight.w400),
                  ),
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

class _ShimmerTrackRow extends StatelessWidget {
  final AnimationController shimmerController;
  final Color               accentColor;

  const _ShimmerTrackRow({
    required this.shimmerController, required this.accentColor,
  });

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
              borderRadius: BorderRadius.circular(7),
              gradient: shimmerGrad(0.12),
            )),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 12, decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: shimmerGrad(0.14),
                )),
                const SizedBox(height: 5),
                Container(height: 9, width: 80, decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: shimmerGrad(0.08),
                )),
              ],
            )),
            const SizedBox(width: 8),
            Container(width: 30, height: 30, decoration: BoxDecoration(
              shape: BoxShape.circle, gradient: shimmerGrad(0.10),
            )),
          ]),
        );
      },
    );
  }
}

class _SelectedSlot extends StatelessWidget {
  final SpotifyArtistDetails? artist;
  final String       label;
  final Color        accentColor;
  final int          trackCount;
  final bool         showTrackCount;
  final bool         locked;
  final List<Widget> trailingWidgets;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  const _SelectedSlot({
    required this.artist,
    required this.label,
    required this.accentColor,
    required this.trackCount,
    required this.onRemove,
    this.showTrackCount = true,
    this.locked = false,
    this.trailingWidgets = const [],
    this.onTap,
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
                ? accentColor.withOpacity(0.22)
                : Colors.white.withOpacity(0.07),
            border: Border.all(
              color: artist != null
                  ? accentColor.withOpacity(0.55)
                  : Colors.white.withOpacity(0.10),
              width: 1.0,
            ),
          ),
          child: artist == null
              ? Row(children: [
                  Container(width: 28, height: 28,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.15), width: 1)),
                    child: Icon(Icons.add_rounded,
                        color: Colors.white.withOpacity(0.25), size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label, style: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1.2,
                    )),
                  ),
                  if (trailingWidgets.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ...trailingWidgets,
                  ],
                ])
              : Row(children: [
                  Container(width: 28, height: 28,
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
                        fontSize: 12, fontWeight: FontWeight.w700),
                  )),
                  if (showTrackCount && trackCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: accentColor.withOpacity(0.35),
                      ),
                      child: Text('$trackCount',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 9, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (trailingWidgets.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    ...trailingWidgets,
                    const SizedBox(width: 4),
                  ],
                  if (locked)
                    Icon(Icons.lock_rounded,
                        color: accentColor.withOpacity(0.75), size: 14)
                  else
                    GestureDetector(
                      onTap: onRemove,
                      child: Icon(Icons.close_rounded,
                          color: Colors.white.withOpacity(0.45), size: 14),
                    ),
                ]),
        ),
      ),
    ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final SpotifyArtistDetails artist;
  final int?         selectedSlot;
  final VoidCallback onTap;

  const _ArtistCard({
    required this.artist,
    required this.selectedSlot,
    required this.onTap,
  });

  Color get _slotColor => selectedSlot == 0 ? _kPurple : _kPink;

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedSlot != null;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: LayoutBuilder(builder: (_, constraints) {
            final side = math.min(
                constraints.maxWidth, constraints.maxHeight);
            return Stack(alignment: Alignment.topRight, children: [
              SizedBox(width: side, height: side,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? _slotColor.withOpacity(0.8)
                          : Colors.white.withOpacity(0.12),
                      width: isSelected ? 2.5 : 1,
                    ),
                    boxShadow: isSelected ? [BoxShadow(
                        color: _slotColor.withOpacity(0.45),
                        blurRadius: 18, spreadRadius: 2)] : [],
                  ),
                  child: ClipOval(
                    child: artist.imageUrl != null &&
                            artist.imageUrl!.isNotEmpty
                        ? Image.network(artist.imageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(side))
                        : _placeholder(side),
                  ),
                ),
              ),
              if (isSelected)
                Positioned(top: 0, right: 0,
                  child: Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _slotColor,
                      boxShadow: [BoxShadow(
                          color: _slotColor.withOpacity(0.6), blurRadius: 8)],
                    ),
                    child: Center(child: Text('${selectedSlot! + 1}',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 10, fontWeight: FontWeight.w900),
                    )),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(double size) => Container(
    color: Colors.white.withOpacity(0.08),
    child: Icon(Icons.person_rounded,
        size: size * 0.45, color: Colors.white.withOpacity(0.3)),
  );
}

class _ShimmerArtistCard extends StatelessWidget {
  final AnimationController shimmerController;
  const _ShimmerArtistCard({required this.shimmerController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerController,
      builder: (context, _) {
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

// ── Gate widget ───────────────────────────────────────────────────────────────
class CollaboratorLockeroomGate extends StatelessWidget {
  const CollaboratorLockeroomGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: FirebaseService.getCurrentUser(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.gradientStart, AppTheme.gradientEnd],
              ),
            ),
            child: const Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return Container(
            decoration: AppTheme.backgroundDecoration,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              body: Center(
                child: Text(
                  'Sign in to collaborate',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }
        final name = user.username.trim().isNotEmpty
            ? user.username.trim()
            : user.email.trim().isNotEmpty
                ? user.email.trim()
                : 'user';
        return CollaboratorLockeroom(
          authorUsername: name,
          authorAvatarPath: user.avatarPath,
        );
      },
    );
  }
}

class _MaxWordsInputFormatter extends TextInputFormatter {
  _MaxWordsInputFormatter(this.maxWords);
  final int maxWords;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= maxWords) return newValue;
    final clamped = words.take(maxWords).join(' ');
    return TextEditingValue(
      text: clamped,
      selection: TextSelection.collapsed(offset: clamped.length),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POST REMIX LOCKER-ROOM
// Entry point for remixing a post.  The left side is locked to the post's
// artist + tracklist; the right side is the current user's remix pick.
// ─────────────────────────────────────────────────────────────────────────────

/// Gate widget — loads the current user then shows [PostRemixScreen].
class PostRemixLockeroom extends StatelessWidget {
  final PostModel post;

  const PostRemixLockeroom({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: FirebaseService.getCurrentUser(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.gradientStart, AppTheme.gradientEnd],
              ),
            ),
            child: const Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
          );
        }
        final user = snap.data;
        final username = (user?.username.trim().isNotEmpty == true)
            ? user!.username.trim()
            : (user?.email.trim().isNotEmpty == true
                ? user!.email.trim().split('@').first
                : 'you');
        return PostRemixScreen(
          post: post,
          remixerUsername: username,
          remixerAvatarPath: user?.avatarPath,
        );
      },
    );
  }
}

/// Remix screen — two pages:
///   Page 0: POST side (locked — post artist + tracklist)
///   Page 1: REMIX side (editable — same or different artist + track selection)
class PostRemixScreen extends StatefulWidget {
  final PostModel post;
  final String    remixerUsername;
  final String?   remixerAvatarPath;

  const PostRemixScreen({
    super.key,
    required this.post,
    required this.remixerUsername,
    this.remixerAvatarPath,
  });

  @override
  State<PostRemixScreen> createState() => _PostRemixScreenState();
}

class _PostRemixScreenState extends State<PostRemixScreen>
    with TickerProviderStateMixin {
  final SpotifyApi _api = SpotifyApi();

  // ── Right-side artist / tracks ────────────────────────────────────────────
  SpotifyArtistDetails? _rightArtist;
  List<SpotifyTrack>   _rightTopTracks           = [];
  List<SpotifyTrack>   _rightDiscographyTracks   = [];
  final List<SpotifyTrack> _rightSelected        = [];
  bool _isLoadingRightTracks      = false;
  bool _isLoadingRightDiscography = false;
  bool _isSubmitting              = false;

  // ── Artist search (only used in 'different' mode) ─────────────────────────
  final TextEditingController _searchCtrl  = TextEditingController();
  final FocusNode             _searchFocus = FocusNode();
  Timer? _searchDebounce;
  List<SpotifyArtistDetails> _searchResults = [];
  bool   _isSearching = false;
  String _lastQuery   = '';

  // ── Track search (right side) ─────────────────────────────────────────────
  final TextEditingController _trackCtrl = TextEditingController();
  final FocusNode _trackFocus            = FocusNode();
  Timer? _trackDebounce;
  List<SpotifyTrack>? _trackSearchResults;
  bool   _isSearchingTracks = false;
  String _trackFilterQuery  = '';

  // ── Track preview playback ────────────────────────────────────────────────
  String? _previewPlayingTrackId;
  String? _previewLoadingTrackId;

  // ── Animation / page ──────────────────────────────────────────────────────
  late final PageController      _pageCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _slideCtrl;
  late final Animation<double>   _slideAnim;
  int _currentPage = 0;

  // ── Accessors ─────────────────────────────────────────────────────────────
  PostModel get post => widget.post;
  bool get _isSameMode => post.remixEnabled == RemixEnabled.same;
  int  get _trackLimit => post.tracklist.isEmpty ? 5 : post.tracklist.length;
  bool get _canSubmit  =>
      _rightArtist != null && _rightSelected.isNotEmpty;

  List<SpotifyTrack> get _visibleRightTracks {
    if (_trackFilterQuery.isNotEmpty && _trackSearchResults != null) {
      return _trackSearchResults!;
    }
    if (_rightDiscographyTracks.isNotEmpty) return _rightDiscographyTracks;
    return _rightTopTracks;
  }

  @override
  void initState() {
    super.initState();
    _pageCtrl    = PageController();
    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _slideAnim = CurvedAnimation(
        parent: _slideCtrl, curve: Curves.easeOutCubic);
    _trackCtrl.addListener(_onTrackFilterChanged);

    // In 'same' mode auto-load the post's artist on first frame.
    if (_isSameMode) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadSameArtist());
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _shimmerCtrl.dispose();
    _slideCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _searchDebounce?.cancel();
    _trackCtrl.removeListener(_onTrackFilterChanged);
    _trackCtrl.dispose();
    _trackFocus.dispose();
    _trackDebounce?.cancel();
    super.dispose();
  }

  // ── Track preview playback ────────────────────────────────────────────────
  void _stopPreviewPlayback() {
    if (mounted) {
      setState(() {
        _previewPlayingTrackId = null;
        _previewLoadingTrackId = null;
      });
    }
  }

  void _showPlaybackSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.black.withValues(alpha: 0.88),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  /// Unified toggle: play or pause any track by its Spotify URI.
  Future<void> _togglePreview(String trackId, String uri) async {
    if (trackId.isEmpty || uri.isEmpty) return;

    if (_previewPlayingTrackId == trackId) {
      setState(() => _previewLoadingTrackId = trackId);
      try {
        final paused = await _api.pause();
        if (!mounted) return;
        if (paused) {
          _stopPreviewPlayback();
        } else {
          _showPlaybackSnack(
              'Could not pause — open Spotify on a device and try again.');
        }
      } finally {
        if (mounted) setState(() => _previewLoadingTrackId = null);
      }
      return;
    }

    setState(() => _previewLoadingTrackId = trackId);
    try {
      final played = await _api.play(uri);
      if (!mounted) return;
      if (!played) {
        _showPlaybackSnack(
            'Open Spotify on a phone, speaker, or desktop, then try again.');
        return;
      }
      setState(() => _previewPlayingTrackId = trackId);
    } catch (e) {
      debugPrint('[PostRemixScreen] preview error: $e');
      if (mounted) _showPlaybackSnack('Playback failed. Check Spotify is active.');
    } finally {
      if (mounted) setState(() => _previewLoadingTrackId = null);
    }
  }

  /// Cover-tap handler for a full SpotifyTrack.
  Future<void> _toggleTrackPreview(SpotifyTrack track) {
    final uri = track.uri.trim().isNotEmpty
        ? track.uri.trim()
        : 'spotify:track:${track.id}';
    return _togglePreview(track.id, uri);
  }

  /// Cover-tap handler for a locked post TrackItem (uses its spotifyID).
  Future<void> _toggleLockedTrackPreview(String spotifyID) {
    if (spotifyID.isEmpty) return Future.value();
    return _togglePreview(spotifyID, 'spotify:track:$spotifyID');
  }

  // ── Same-mode: auto-populate artist from post ─────────────────────────────
  Future<void> _loadSameArtist() async {
    final artist = SpotifyArtistDetails(
      id:       post.artistID,
      name:     post.artistName,
      imageUrl: post.artistImageUrl.isNotEmpty ? post.artistImageUrl : null,
    );
    setState(() {
      _rightArtist          = artist;
      _isLoadingRightTracks = true;
    });
    try {
      final tracks = await _api.getArtistTopTracks(post.artistID);
      if (!mounted) return;
      setState(() {
        _rightTopTracks       = tracks;
        _isLoadingRightTracks = false;
      });
      _slideCtrl.forward(from: 0);
      unawaited(_loadRightDiscography(post.artistID));
    } catch (_) {
      if (mounted) setState(() => _isLoadingRightTracks = false);
    }
  }

  Future<void> _loadRightDiscography(String artistId) async {
    if (!mounted) return;
    setState(() => _isLoadingRightDiscography = true);
    try {
      final tracks = await _api.getArtistDiscographyTracks(artistId);
      if (!mounted) return;
      if (_rightArtist?.id != artistId) return;
      setState(() => _rightDiscographyTracks = tracks);
      _slideCtrl.forward(from: 0);
    } catch (e) {
      debugPrint('[PostRemixScreen] discography load failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingRightDiscography = false);
    }
  }

  // ── Artist search (different mode) ───────────────────────────────────────
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final q = query.trim();
    if (q == _lastQuery) return;
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching   = false;
        _lastQuery     = '';
      });
      return;
    }
    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 380), () async {
      _lastQuery = q;
      final results = await _api.searchArtists(q, limit: 12);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching   = false;
      });
    });
  }

  void _onArtistTap(SpotifyArtistDetails artist) {
    if (artist.id == post.artistID) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'This remix requires a different artist than ${post.artistName}.'),
        backgroundColor: Colors.red.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    setState(() {
      _rightArtist              = artist;
      _rightTopTracks           = [];
      _rightDiscographyTracks   = [];
      _rightSelected.clear();
      _trackSearchResults       = null;
      _trackFilterQuery         = '';
      _trackCtrl.clear();
      _searchCtrl.clear();
      _searchResults            = [];
      _lastQuery                = '';
      _isLoadingRightTracks     = true;
    });
    _api.getArtistTopTracks(artist.id).then((tracks) {
      if (!mounted) return;
      setState(() {
        _rightTopTracks       = tracks;
        _isLoadingRightTracks = false;
      });
      _slideCtrl.forward(from: 0);
      unawaited(_loadRightDiscography(artist.id));
    });
  }

  // ── Track filter ──────────────────────────────────────────────────────────
  void _onTrackFilterChanged() {
    _trackDebounce?.cancel();
    final q = _trackCtrl.text.trim();
    if (q == _trackFilterQuery) return;
    setState(() => _trackFilterQuery = q);
    if (q.isEmpty) {
      setState(() {
        _trackSearchResults = null;
        _isSearchingTracks  = false;
      });
      return;
    }
    setState(() => _isSearchingTracks = true);
    _trackDebounce = Timer(const Duration(milliseconds: 420), () async {
      final artist = _rightArtist;
      if (artist == null || !mounted) return;
      final res = await _api.searchTracksByArtists(
        q,
        artist1Id: artist.id, artist1Name: artist.name,
        artist2Id: '', artist2Name: '',
        limitPerArtist: 20,
      );
      if (!mounted) return;
      setState(() {
        _trackSearchResults = res[artist.id] ?? [];
        _isSearchingTracks  = false;
      });
    });
  }

  // ── Track toggle ──────────────────────────────────────────────────────────
  void _toggleTrack(SpotifyTrack track) {
    setState(() {
      final idx = _rightSelected.indexWhere((t) => t.id == track.id);
      if (idx >= 0) {
        _rightSelected.removeAt(idx);
      } else {
        if (_rightSelected.length >= _trackLimit) return;
        _rightSelected.add(track);
      }
    });
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_canSubmit || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await FirebaseService.createPostRemixVersus(
        sourcePostID:    post.id,
        postAuthorID:    post.authorID,
        artist1ID:       post.artistID,
        artist1Name:     post.artistName,
        artist1ImageUrl: post.artistImageUrl,
        artist1TrackIDs: post.tracklist
            .map((t) => t.spotifyID)
            .where((id) => id.isNotEmpty)
            .toList(),
        artist2ID:       _rightArtist!.id,
        artist2Name:     _rightArtist!.name,
        artist2ImageUrl: _rightArtist!.imageUrl ?? '',
        artist2TrackIDs: _rightSelected.map((t) => t.id).toList(),
        remixPolicy:     post.remixEnabled.firestoreValue.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Remix saved!'),
        backgroundColor: AppTheme.successGreen.withOpacity(0.92),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to save remix: $e'),
        backgroundColor: Colors.red.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _goToPage(int index) {
    if (_currentPage == index) return;
    setState(() => _currentPage = index);
    _pageCtrl.animateToPage(index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
    _slideCtrl.forward(from: 0);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Overlay only fires when the inline artist search bar (on page 1) is active.
    final showSearchOverlay =
        !_isSameMode &&
        _currentPage == 1 &&
        (_searchCtrl.text.trim().isNotEmpty || _isSearching);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.gradientStart, AppTheme.gradientEnd],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildHeader(context),
            // Two artist slot chips — mirrors CollaboratorBackroom layout
            _buildArtistSlots(),
            _buildPageDots(),
            Expanded(
              child: Stack(
                children: [
                  PageView(
                    controller: _pageCtrl,
                    onPageChanged: (i) {
                      if (_currentPage != i) {
                        setState(() => _currentPage = i);
                        _slideCtrl.forward(from: 0);
                      }
                    },
                    children: [
                      _buildPostPage(),
                      _buildRemixPage(),
                    ],
                  ),
                  // Artist search results overlay (covers remix page only)
                  if (showSearchOverlay)
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.gradientStart,
                              AppTheme.gradientEnd
                            ],
                          ),
                        ),
                        child: _buildSearchResults(),
                      ),
                    ),
                ],
              ),
            ),
            _buildSubmitBar(),
          ],
        ),
      ),
    );
  }

  // ── Artist slots row (mirrors CollaboratorBackroom._buildArtistSlots) ─────
  Widget _buildArtistSlots() {
    final postImageUrl =
        post.artistImageUrl.isNotEmpty ? post.artistImageUrl : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          // Left — locked post artist
          Expanded(
            child: _SelectedSlot(
              artist: SpotifyArtistDetails(
                id:       post.artistID,
                name:     post.artistName.isNotEmpty
                    ? post.artistName
                    : 'Original Artist',
                imageUrl: postImageUrl,
              ),
              label:      'POST ARTIST',
              accentColor: _kPurple,
              trackCount:  post.tracklist.length,
              locked:      true,
              onRemove:    () {},
              onTap:       () => _goToPage(0),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'VS',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
          // Right — remix artist (empty until selected; locked in same-mode)
          Expanded(
            child: _SelectedSlot(
              artist:      _rightArtist,
              label:       'YOUR REMIX',
              accentColor: _kPink,
              trackCount:  _rightSelected.length,
              locked:      _isSameMode,
              onRemove:    () => setState(() {
                _rightArtist        = null;
                _rightTopTracks     = [];
                _rightSelected.clear();
                _trackSearchResults = null;
                _trackFilterQuery   = '';
                _trackCtrl.clear();
              }),
              onTap: () => _goToPage(1),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    final subtitle = _isSameMode
        ? 'remix with the same artist'
        : 'remix with a different artist';
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        left: 20, right: 20, bottom: 10,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40, height: 40,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('REMIX', style: TextStyle(
                  color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w900, letterSpacing: 3.5,
                )),
                Text(subtitle,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11, fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _RemixUserChip(
            username: widget.remixerUsername,
            avatarPath: widget.remixerAvatarPath,
          ),
        ],
      ),
    );
  }

  // ── Artist search bar — embedded inside the remix page ListView ───────────
  Widget _buildArtistSearchBar() {
    if (_rightArtist != null) return const SizedBox.shrink();
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
              border: Border.all(
                  color: Colors.white.withOpacity(0.18), width: 0.8),
            ),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              autofocus: _rightArtist == null,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.w500),
              cursorColor: _kPink,
              decoration: InputDecoration(
                hintText: 'Search for your remix artist…',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.35), fontSize: 15),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Colors.white.withOpacity(0.5), size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                        child: Icon(Icons.close_rounded,
                            color: Colors.white.withOpacity(0.4), size: 18),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Page dots ─────────────────────────────────────────────────────────────
  Widget _buildPageDots() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _goToPage(0),
            child: _SwipeDot(isActive: _currentPage == 0, color: _kPurple),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _goToPage(1),
            child: _SwipeDot(isActive: _currentPage == 1, color: _kPink),
          ),
        ],
      ),
    );
  }

  // ── Page 0: locked post side ──────────────────────────────────────────────
  Widget _buildPostPage() {
    final tracks = post.tracklist;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        // Artist header
        _buildLockedArtistHeader(),
        const SizedBox(height: 16),
        // Track count label
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(Icons.lock_rounded,
                color: _kPurple.withOpacity(0.6), size: 13),
            const SizedBox(width: 6),
            Text('POST TRACKS',
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: _kPurple.withOpacity(0.2),
              ),
              child: Text('${tracks.length}',
                style: TextStyle(
                  color: _kPurple.withOpacity(0.9),
                  fontSize: 9, fontWeight: FontWeight.w800,
                )),
            ),
          ]),
        ),
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No tracks on this post',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.3), fontSize: 13))),
          )
        else
          ...tracks.asMap().entries.map((e) {
            final track = e.value;
            return _LockedTrackRow(
              name:        track.trackName,
              artist:      track.trackArtist,
              coverUrl:    track.trackCover,
              spotifyID:   track.spotifyID,
              isLast:      e.key == tracks.length - 1,
              accentColor: _kPurple,
              onCoverTap:  track.spotifyID.isNotEmpty
                  ? () => _toggleLockedTrackPreview(track.spotifyID)
                  : null,
              isPreviewPlaying: _previewPlayingTrackId == track.spotifyID,
              isPreviewLoading: _previewLoadingTrackId == track.spotifyID,
            );
          }),
      ],
    );
  }

  Widget _buildLockedArtistHeader() {
    final imageUrl = post.artistImageUrl.isNotEmpty ? post.artistImageUrl : null;
    return Row(
      children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _kPurple.withOpacity(0.7), width: 1.5),
            boxShadow: [
              BoxShadow(color: _kPurple.withOpacity(0.3), blurRadius: 10)
            ],
          ),
          child: ClipOval(
            child: imageUrl != null
                ? Image.network(imageUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _artistFallback())
                : _artistFallback(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(post.artistName,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w700, letterSpacing: 0.1),
              ),
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: _kPurple.withOpacity(0.2),
                    border: Border.all(
                        color: _kPurple.withOpacity(0.4), width: 0.8),
                  ),
                  child: Text('ORIGINAL POST',
                    style: TextStyle(
                      color: _kPurple.withOpacity(0.9),
                      fontSize: 9, fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
        Icon(Icons.lock_rounded,
            color: _kPurple.withOpacity(0.5), size: 18),
      ],
    );
  }

  Widget _artistFallback() => Container(
        color: _kPurple.withOpacity(0.25),
        child: const Icon(Icons.person_rounded,
            color: Colors.white, size: 22),
      );

  // ── Page 1: remix side ────────────────────────────────────────────────────
  Widget _buildRemixPage() {
    if (_isSameMode) {
      return _buildSameModeRemixPage();
    }
    return _buildDifferentModeRemixPage();
  }

  Widget _buildSameModeRemixPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildRemixArtistHeader(locked: true),
        const SizedBox(height: 8),
        // Track search bar — same placement as CollaboratorBackroom
        _buildTrackFilterBar(),
        const SizedBox(height: 6),
        _buildTrackLimitBadge(),
        const SizedBox(height: 10),
          if (_rightSelected.isNotEmpty) ...[
          _buildSectionLabel(
            icon: Icons.playlist_add_check_rounded,
            label: 'SELECTED',
            count: _rightSelected.length,
            accentColor: _kPink,
          ),
          ..._rightSelected.map((t) => _RemixSelectedTrackTile(
                track: t,
                accentColor: _kPink,
                onRemove: () => setState(() => _rightSelected.remove(t)),
                onCoverTap: () => _toggleTrackPreview(t),
                isPreviewPlaying: _previewPlayingTrackId == t.id,
                isPreviewLoading: _previewLoadingTrackId == t.id,
              )),
          const SizedBox(height: 10),
          Divider(height: 0,
              color: _kPink.withOpacity(0.15)),
          const SizedBox(height: 10),
        ],
        if (_isLoadingRightTracks)
          ..._buildShimmers()
        else if (_visibleRightTracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No tracks available',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.3), fontSize: 13))),
          )
        else ...[
          _buildSectionLabel(
            icon: _rightDiscographyTracks.isNotEmpty
                ? Icons.library_music_rounded
                : Icons.star_rounded,
            label: _rightDiscographyTracks.isNotEmpty
                ? 'DISCOGRAPHY'
                : 'TOP TRACKS',
            count: _visibleRightTracks.length,
            accentColor: _kPink,
            dimmed: _rightSelected.isNotEmpty,
          ),
          ..._visibleRightTracks.asMap().entries.map((e) {
            final track    = e.value;
            final picked   = _rightSelected.any((t) => t.id == track.id);
            final atLimit  = _rightSelected.length >= _trackLimit;
            return AnimatedBuilder(
              animation: _slideAnim,
              builder: (ctx, child) => Transform.translate(
                offset: Offset(0,
                    20 * (1 - _slideAnim.value) *
                        math.max(0.0, 1 - e.key * 0.06)),
                child: Opacity(
                    opacity: _slideAnim.value.clamp(0.0, 1.0),
                    child: child),
              ),
              child: _TopTrackRow(
                track: track,
                accentColor: _kPink,
                isLast: e.key == _visibleRightTracks.length - 1,
                dimmed: picked || (atLimit && !picked),
                isSelected: picked,
                onAdd: (picked || atLimit) ? null : () => _toggleTrack(track),
                onCoverTap: () => _toggleTrackPreview(track),
                isPreviewPlaying: _previewPlayingTrackId == track.id,
                isPreviewLoading: _previewLoadingTrackId == track.id,
              ),
            );
          }),
          if (_isLoadingRightDiscography && _rightDiscographyTracks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Center(child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kPink),
              )),
            ),
        ],
      ],
    );
  }

  Widget _buildDifferentModeRemixPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        // Artist search bar lives inside the page (mirrors CollaboratorBackroom)
        _buildArtistSearchBar(),
        if (_rightArtist == null) ...[
          const SizedBox(height: 20),
          Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_search_rounded,
                  color: Colors.white.withOpacity(0.2), size: 44),
              const SizedBox(height: 10),
              Text('Search for your remix artist',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 13, fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text('Must be different from ${post.artistName}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.22),
                  fontSize: 12,
                ),
              ),
            ],
          )),
        ] else ...[
          _buildRemixArtistHeader(locked: false),
          const SizedBox(height: 8),
          // Track filter bar — same placement as CollaboratorBackroom
          _buildTrackFilterBar(),
          const SizedBox(height: 4),
          _buildTrackLimitBadge(),
          const SizedBox(height: 10),
          if (_rightSelected.isNotEmpty) ...[
            _buildSectionLabel(
              icon: Icons.playlist_add_check_rounded,
              label: 'SELECTED',
              count: _rightSelected.length,
              accentColor: _kPink,
            ),
            ..._rightSelected.map((t) => _RemixSelectedTrackTile(
                  track: t,
                  accentColor: _kPink,
                  onRemove: () => setState(() => _rightSelected.remove(t)),
                  onCoverTap: () => _toggleTrackPreview(t),
                  isPreviewPlaying: _previewPlayingTrackId == t.id,
                  isPreviewLoading: _previewLoadingTrackId == t.id,
                )),
            const SizedBox(height: 10),
            Divider(height: 0, color: _kPink.withOpacity(0.15)),
            const SizedBox(height: 10),
          ],
          if (_isLoadingRightTracks || _isSearchingTracks)
            ..._buildShimmers()
          else if (_visibleRightTracks.isEmpty && _trackFilterQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No tracks found',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 13))),
            )
          else if (_visibleRightTracks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No tracks available',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 13))),
            )
          else ...[
            _buildSectionLabel(
              icon: _trackFilterQuery.isNotEmpty
                  ? Icons.manage_search_rounded
                  : (_rightDiscographyTracks.isNotEmpty
                      ? Icons.library_music_rounded
                      : Icons.star_rounded),
              label: _trackFilterQuery.isNotEmpty
                  ? 'SEARCH RESULTS'
                  : (_rightDiscographyTracks.isNotEmpty
                      ? 'DISCOGRAPHY'
                      : 'TOP TRACKS'),
              count: _visibleRightTracks.length,
              accentColor: _kPink,
              dimmed: _rightSelected.isNotEmpty,
            ),
            ..._visibleRightTracks.asMap().entries.map((e) {
              final track   = e.value;
              final picked  = _rightSelected.any((t) => t.id == track.id);
              final atLimit = _rightSelected.length >= _trackLimit;
              return AnimatedBuilder(
                animation: _slideAnim,
                builder: (ctx, child) => Transform.translate(
                  offset: Offset(0,
                      20 * (1 - _slideAnim.value) *
                          math.max(0.0, 1 - e.key * 0.06)),
                  child: Opacity(
                      opacity: _slideAnim.value.clamp(0.0, 1.0),
                      child: child),
                ),
                child: _TopTrackRow(
                  track: track,
                  accentColor: _kPink,
                  isLast: e.key == _visibleRightTracks.length - 1,
                  dimmed: picked || (atLimit && !picked),
                  isSelected: picked,
                  onAdd: (picked || atLimit) ? null : () => _toggleTrack(track),
                  onCoverTap: () => _toggleTrackPreview(track),
                  isPreviewPlaying: _previewPlayingTrackId == track.id,
                  isPreviewLoading: _previewLoadingTrackId == track.id,
                ),
              );
            }),
            if (_isLoadingRightDiscography &&
                _trackFilterQuery.isEmpty &&
                _rightDiscographyTracks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Center(child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _kPink),
                )),
              ),
          ],
        ],
      ],
    );
  }

  Widget _buildRemixArtistHeader({required bool locked}) {
    final artist = _rightArtist;
    if (artist == null) return const SizedBox.shrink();
    return Row(
      children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _kPink.withOpacity(0.7), width: 1.5),
            boxShadow: [
              BoxShadow(color: _kPink.withOpacity(0.3), blurRadius: 10)
            ],
          ),
          child: ClipOval(
            child: artist.imageUrl != null && artist.imageUrl!.isNotEmpty
                ? Image.network(artist.imageUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _remixArtistFallback())
                : _remixArtistFallback(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(artist.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w700, letterSpacing: 0.1),
              ),
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: _kPink.withOpacity(0.2),
                    border: Border.all(
                        color: _kPink.withOpacity(0.4), width: 0.8),
                  ),
                  child: Text('YOUR REMIX',
                    style: TextStyle(
                      color: _kPink.withOpacity(0.9),
                      fontSize: 9, fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
        if (locked)
          Icon(Icons.lock_rounded,
              color: _kPink.withOpacity(0.5), size: 18)
        else
          GestureDetector(
            onTap: () => setState(() {
              _rightArtist  = null;
              _rightTopTracks = [];
              _rightSelected.clear();
              _trackSearchResults = null;
              _trackFilterQuery   = '';
              _trackCtrl.clear();
            }),
            child: Icon(Icons.close_rounded,
                color: Colors.white.withOpacity(0.45), size: 20),
          ),
      ],
    );
  }

  Widget _remixArtistFallback() => Container(
        color: _kPink.withOpacity(0.25),
        child: const Icon(Icons.person_rounded,
            color: Colors.white, size: 22),
      );

  Widget _buildTrackFilterBar() {
    final inSearch = _trackFilterQuery.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: inSearch
                ? Colors.white.withOpacity(0.14)
                : Colors.white.withOpacity(0.09),
            border: Border.all(
              color: inSearch
                  ? Colors.white.withOpacity(0.28)
                  : Colors.white.withOpacity(0.14),
              width: 0.8,
            ),
          ),
          child: TextField(
            controller: _trackCtrl,
            focusNode: _trackFocus,
            style: const TextStyle(
                color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w500),
            cursorColor: _kPink,
            decoration: InputDecoration(
              hintText: 'Search tracks…',
              hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.3), fontSize: 13),
              prefixIcon: _isSearchingTracks
                  ? Padding(
                      padding: const EdgeInsets.all(11),
                      child: SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: Colors.white.withOpacity(0.5)),
                      ),
                    )
                  : Icon(
                      inSearch
                          ? Icons.manage_search_rounded
                          : Icons.queue_music_rounded,
                      color: Colors.white.withOpacity(0.4), size: 18),
              suffixIcon: _trackFilterQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _trackCtrl.clear();
                        _trackFocus.unfocus();
                      },
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
    );
  }

  Widget _buildTrackLimitBadge() {
    final picked = _rightSelected.length;
    final limit  = _trackLimit;
    final full   = picked >= limit;
    return Row(children: [
      Icon(
        full ? Icons.check_circle_rounded : Icons.info_outline_rounded,
        color: full
            ? AppTheme.successGreen.withOpacity(0.8)
            : Colors.white.withOpacity(0.35),
        size: 13,
      ),
      const SizedBox(width: 6),
      Text(
        full
            ? 'Track limit reached ($limit / $limit)'
            : 'Select up to $limit track${limit == 1 ? '' : 's'} '
              '($picked / $limit selected)',
        style: TextStyle(
          color: full
              ? AppTheme.successGreen.withOpacity(0.85)
              : Colors.white.withOpacity(0.38),
          fontSize: 11, fontWeight: FontWeight.w500,
        ),
      ),
    ]);
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
        Icon(icon, size: 13,
            color: accentColor.withOpacity(dimmed ? 0.35 : 0.7)),
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

  List<Widget> _buildShimmers() => List.generate(5, (_) => _ShimmerTrackRow(
        shimmerController: _shimmerCtrl,
        accentColor: _kPink,
      ));

  // ── Search results overlay ─────────────────────────────────────────────────
  Widget _buildSearchResults() {
    if (_isSearching) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 16,
          crossAxisSpacing: 12, childAspectRatio: 0.78,
        ),
        itemCount: 6,
        itemBuilder: (_, __) =>
            _ShimmerArtistCard(shimmerController: _shimmerCtrl),
      );
    }
    if (_searchResults.isEmpty && _lastQuery.isNotEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off_rounded,
            color: Colors.white.withOpacity(0.25), size: 40),
        const SizedBox(height: 10),
        Text('No artists found', style: TextStyle(
          color: Colors.white.withOpacity(0.4), fontSize: 14,
          fontWeight: FontWeight.w500,
        )),
      ]));
    }
    if (_searchResults.isEmpty) {
      return Center(child: Text('Type to search artists', style: TextStyle(
        color: Colors.white.withOpacity(0.3), fontSize: 14,
        fontWeight: FontWeight.w500,
      )));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, mainAxisSpacing: 16,
        crossAxisSpacing: 12, childAspectRatio: 0.78,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) {
        final artist = _searchResults[i];
        final isSameAsPost = artist.id == post.artistID;
        return _ArtistCard(
          artist: artist,
          selectedSlot: _rightArtist?.id == artist.id ? 1 : null,
          onTap: () => _onArtistTap(artist),
        );
      },
    );
  }

  // ── Submit bar ─────────────────────────────────────────────────────────────
  Widget _buildSubmitBar() {
    final hint = !_canSubmit
        ? (_rightArtist == null
            ? (_isSameMode ? null : 'Pick your artist first')
            : 'Select at least one track for your remix')
        : null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: Colors.white.withOpacity(0.4), size: 13),
                    const SizedBox(width: 6),
                    Flexible(child: Text(hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11, fontWeight: FontWeight.w500,
                      ),
                    )),
                  ],
                ),
              ),
            GestureDetector(
              onTap: _canSubmit && !_isSubmitting ? _submit : null,
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
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _canSubmit
                                  ? Icons.shuffle_rounded
                                  : Icons.lock_outline_rounded,
                              color: _canSubmit
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _canSubmit ? 'SAVE REMIX' : 'COMPLETE YOUR SIDE',
                              style: TextStyle(
                                color: _canSubmit
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.3),
                                fontSize: 13, fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Locked track row (post side — no interaction) ──────────────────────────
class _LockedTrackRow extends StatelessWidget {
  final String        name;
  final String        artist;
  final String        coverUrl;
  final String        spotifyID;
  final bool          isLast;
  final Color         accentColor;
  final VoidCallback? onCoverTap;
  final bool          isPreviewPlaying;
  final bool          isPreviewLoading;

  const _LockedTrackRow({
    required this.name,
    required this.artist,
    required this.coverUrl,
    required this.accentColor,
    this.spotifyID       = '',
    this.isLast          = false,
    this.onCoverTap,
    this.isPreviewPlaying = false,
    this.isPreviewLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: coverUrl.isNotEmpty && onCoverTap != null
                ? PlayableAlbumCover(
                    imageUrl:     coverUrl,
                    size:         46,
                    borderRadius: 7,
                    accentColor:  accentColor,
                    isPlaying:    isPreviewPlaying,
                    isLoading:    isPreviewLoading,
                    onTap:        onCoverTap!,
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: coverUrl.isNotEmpty
                        ? Image.network(coverUrl,
                            width: 46, height: 46, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallback())
                        : _fallback(),
                  ),
          ),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13.5, fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
              if (artist.isNotEmpty)
                Text(artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11, fontWeight: FontWeight.w400),
                ),
            ],
          )),
          Icon(Icons.lock_rounded,
              color: accentColor.withOpacity(0.35), size: 14),
        ]),
      ),
      if (!isLast)
        Divider(height: 0, color: Colors.white.withOpacity(0.06)),
    ]);
  }

  Widget _fallback() => SizedBox(
        width: 46, height: 46,
        child: Container(
          color: _kPurple.withOpacity(0.15),
          child: const Icon(Icons.music_note_rounded,
              color: Colors.white54, size: 20),
        ),
      );
}

// ── Remix selected track tile (removable) ─────────────────────────────────
class _RemixSelectedTrackTile extends StatelessWidget {
  final SpotifyTrack  track;
  final Color         accentColor;
  final VoidCallback  onRemove;
  final VoidCallback? onCoverTap;
  final bool          isPreviewPlaying;
  final bool          isPreviewLoading;

  const _RemixSelectedTrackTile({
    required this.track,
    required this.accentColor,
    required this.onRemove,
    this.onCoverTap,
    this.isPreviewPlaying = false,
    this.isPreviewLoading = false,
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
              border: Border.all(
                  color: accentColor.withOpacity(0.45), width: 1.0),
              boxShadow: [BoxShadow(
                  color: accentColor.withOpacity(0.15),
                  blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                if (track.albumArtUrl != null && track.albumArtUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: onCoverTap != null
                        ? PlayableAlbumCover(
                            imageUrl:     track.albumArtUrl!,
                            size:         38,
                            borderRadius: 6,
                            accentColor:  accentColor,
                            isPlaying:    isPreviewPlaying,
                            isLoading:    isPreviewLoading,
                            onTap:        onCoverTap!,
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(track.albumArtUrl!,
                                width: 38, height: 38, fit: BoxFit.cover),
                          ),
                  ),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 13, fontWeight: FontWeight.w700,
                          letterSpacing: -0.1),
                    ),
                    if (track.artistName.isNotEmpty)
                      Text(track.artistName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: accentColor.withOpacity(0.8),
                            fontSize: 11, fontWeight: FontWeight.w500),
                      ),
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

// ── Remixer user chip (header) ─────────────────────────────────────────────
class _RemixUserChip extends StatelessWidget {
  final String  username;
  final String? avatarPath;

  const _RemixUserChip({required this.username, this.avatarPath});

  @override
  Widget build(BuildContext context) {
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
              colors: [
                AppTheme.gradientStart.withOpacity(0.40),
                AppTheme.gradientEnd.withOpacity(0.40),
              ],
            ),
            border: Border.all(
                color: Colors.white.withOpacity(0.18), width: 0.8),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20, offset: const Offset(0, 6))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: size, height: size,
              child: _avatar(size),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                username,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _avatar(double size) {
    final p = avatarPath?.trim() ?? '';
    Widget img;
    if (p.isEmpty) {
      img = Icon(Icons.person_rounded,
          color: Colors.white.withOpacity(0.8), size: size * 0.55);
    } else if (p.startsWith('http')) {
      img = Image.network(p, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.person_rounded, size: size * 0.55));
    } else {
      final asset = p.startsWith('assets/') ? p : 'assets/images/$p';
      img = Image.asset(asset, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.person_rounded, size: size * 0.55));
    }
    return ClipOval(
      child: Container(
        width: size, height: size,
        color: Colors.white.withOpacity(0.15),
        child: img,
      ),
    );
  }
}