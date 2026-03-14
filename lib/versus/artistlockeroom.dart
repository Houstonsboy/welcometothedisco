import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/spotify_api.dart';

const _kPurple = Color(0xFF1E3DE1);
const _kPink = Color(0xFFf85187);

/// Entry point for Artist VS — pick two artists, then create versus.
class ArtistLockeroom extends StatelessWidget {
  const ArtistLockeroom({super.key});

  @override
  Widget build(BuildContext context) {
    return ArtistSearchScreen(
      onCreateVersus: (artist1, artist2, selectedTracks1, selectedTracks2) async {
        try {
          await FirebaseService.createArtistVersus(
            artist1ID:       artist1.id,
            artist1Name:     artist1.name,
            artist1TrackIDs: selectedTracks1.map((t) => t.id).toList(),
            artist2ID:       artist2.id,
            artist2Name:     artist2.name,
            artist2TrackIDs: selectedTracks2.map((t) => t.id).toList(),
          );
          if (context.mounted) Navigator.of(context).pop();
        } catch (e) {
          debugPrint('[ArtistLockeroom] createArtistVersus failed: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to create versus: $e'),
                backgroundColor: Colors.red.withOpacity(0.85),
              ),
            );
          }
        }
      },
    );
  }
}

class ArtistSearchScreen extends StatefulWidget {
  final Future<void> Function(
    SpotifyArtistDetails artist1,
    SpotifyArtistDetails artist2,
    List<SpotifyTrack> selectedTracks1,
    List<SpotifyTrack> selectedTracks2,
  ) onCreateVersus;

  const ArtistSearchScreen({super.key, required this.onCreateVersus});

  @override
  State<ArtistSearchScreen> createState() => _ArtistSearchScreenState();
}

class _ArtistSearchScreenState extends State<ArtistSearchScreen>
    with TickerProviderStateMixin {
  final SpotifyApi _api = SpotifyApi();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // ── Artist search ─────────────────────────────────────────────────────────
  Timer? _debounce;
  List<SpotifyArtistDetails> _results = [];
  bool _isSearching = false;
  String _lastQuery = '';

  final List<SpotifyArtistDetails?> _selected = [null, null];

  // ── Top tracks ────────────────────────────────────────────────────────────
  List<List<SpotifyTrack>> _topTracks = [[], []];
  bool _isLoadingTracks = false;

  // ── Selected tracks per artist slot ──────────────────────────────────────
  final List<List<SpotifyTrack>> _selectedTracks = [[], []];

  // ── Firebase submission state ─────────────────────────────────────────────
  bool _isSubmitting = false;

  // ── Track search ──────────────────────────────────────────────────────────
  final TextEditingController _trackFilterController = TextEditingController();
  final FocusNode _trackFilterFocus = FocusNode();
  String _trackFilterQuery = '';
  Timer? _trackDebounce;
  Map<String, List<SpotifyTrack>>? _trackSearchResults;
  bool _isSearchingTracks = false;

  // ── Page / animation ──────────────────────────────────────────────────────
  late final AnimationController _shimmerController;
  late final AnimationController _slideController;
  late final Animation<double> _slideAnim;
  late final PageController _pageController;
  int _selectedArtistPage = 0;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnim = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );

    _pageController = PageController();
    _trackFilterController.addListener(_onTrackFilterChanged);
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
    super.dispose();
  }

  // ── Validation ────────────────────────────────────────────────────────────
  bool get _canCreate => _selected[0] != null && _selected[1] != null;

  /// Both artists must have at least one track selected AND counts must match.
  bool get _canSubmit {
    final c1 = _selectedTracks[0].length;
    final c2 = _selectedTracks[1].length;
    return c1 > 0 && c2 > 0 && c1 == c2;
  }

  /// Human-readable hint shown below the button explaining what's missing.
  String? get _submitHint {
    if (!_canCreate) return null;
    final c1 = _selectedTracks[0].length;
    final c2 = _selectedTracks[1].length;
    if (c1 == 0 && c2 == 0) return 'Select tracks for both artists to continue';
    if (c1 == 0) return 'Select tracks for ${_selected[0]?.name ?? 'Artist 1'}';
    if (c2 == 0) return 'Select tracks for ${_selected[1]?.name ?? 'Artist 2'}';
    if (c1 != c2) {
      final diff = (c1 - c2).abs();
      final behind = c1 < c2 ? _selected[0]?.name : _selected[1]?.name;
      return '$behind needs $diff more track${diff == 1 ? '' : 's'} to match';
    }
    return null;
  }

  // ── Artist search ─────────────────────────────────────────────────────────
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
        _selected[0] = null; _topTracks[0] = []; _selectedTracks[0] = [];
        _trackSearchResults = null; return;
      }
      if (_selected[1]?.id == artist.id) {
        _selected[1] = null; _topTracks[1] = []; _selectedTracks[1] = [];
        _trackSearchResults = null; return;
      }
      if (_selected[0] == null) {
        _selected[0] = artist;
      } else if (_selected[1] == null) {
        _selected[1] = artist;
      } else {
        _selected[1] = artist;
        _topTracks[1] = []; _selectedTracks[1] = [];
        _trackSearchResults = null;
      }
    });
    _maybeFetchTopTracks();
  }

  int? _slotFor(String artistId) {
    if (_selected[0]?.id == artistId) return 0;
    if (_selected[1]?.id == artistId) return 1;
    return null;
  }

  // ── Top tracks fetch ──────────────────────────────────────────────────────
  Future<void> _maybeFetchTopTracks() async {
    final a1 = _selected[0];
    final a2 = _selected[1];
    if (a1 == null || a2 == null) return;
    if (_isLoadingTracks) return;

    setState(() => _isLoadingTracks = true);
    try {
      final both = await _api.getBothArtistsTopTracks(a1.id, a2.id);
      if (!mounted) return;
      setState(() {
        _topTracks = [both[0], both[1]];
        _trackSearchResults = null;
        _trackFilterController.clear();
        _trackFilterQuery = '';
      });
      _slideController.forward(from: 0);
    } finally {
      if (mounted) setState(() => _isLoadingTracks = false);
    }
  }

  // ── Track search ──────────────────────────────────────────────────────────
  void _onTrackFilterChanged() {
    final q = _trackFilterController.text.trim();
    if (q == _trackFilterQuery) return;
    setState(() => _trackFilterQuery = q);

    _trackDebounce?.cancel();

    if (q.isEmpty) {
      setState(() { _trackSearchResults = null; _isSearchingTracks = false; });
      return;
    }

    setState(() => _isSearchingTracks = true);
    _trackDebounce = Timer(const Duration(milliseconds: 420), () async {
      final a1 = _selected[0];
      final a2 = _selected[1];
      if (a1 == null || a2 == null || !mounted) return;

      final results = await _api.searchTracksByArtists(
        q,
        artist1Id: a1.id, artist1Name: a1.name,
        artist2Id: a2.id, artist2Name: a2.name,
        limitPerArtist: 20,
      );
      if (!mounted) return;
      setState(() { _trackSearchResults = results; _isSearchingTracks = false; });
      _slideController.forward(from: 0);
    });
  }

  // ── Track selection ───────────────────────────────────────────────────────
  int? _artistSlotForTrack(SpotifyTrack track) {
    final a1 = _selected[0];
    final a2 = _selected[1];
    if (a1 != null && track.hasArtist(id: a1.id, name: a1.name)) return 0;
    if (a2 != null && track.hasArtist(id: a2.id, name: a2.name)) return 1;
    return null;
  }

  void _toggleTrackSelection(SpotifyTrack track) {
    final slot = _artistSlotForTrack(track);
    if (slot == null) return;
    setState(() {
      final already = _selectedTracks[slot].indexWhere((t) => t.id == track.id);
      if (already >= 0) {
        _selectedTracks[slot].removeAt(already);
      } else {
        _selectedTracks[slot].add(track);
      }
    });
  }

  void _removeSelectedTrack(int slot, String trackId) {
    setState(() => _selectedTracks[slot].removeWhere((t) => t.id == trackId));
  }

  // ── Submit to Firebase ────────────────────────────────────────────────────
  Future<void> _handleSubmit() async {
    if (!_canSubmit || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.onCreateVersus(
        _selected[0]!,
        _selected[1]!,
        _selectedTracks[0],
        _selectedTracks[1],
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Track list for page ───────────────────────────────────────────────────
  List<SpotifyTrack> _tracksForPage(int pageIndex) {
    final artist = _selected[pageIndex];
    if (artist == null) return [];
    if (_trackFilterQuery.isNotEmpty && _trackSearchResults != null) {
      return _trackSearchResults![artist.id] ?? [];
    }
    return _topTracks[pageIndex];
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_canCreate &&
        _topTracks[0].isEmpty &&
        _topTracks[1].isEmpty &&
        !_isLoadingTracks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFetchTopTracks());
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3DE1), Color(0xFFf85187)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildHeader(context),
            _buildArtistSearchBar(),
            _buildSelectedSlots(),
            if (_canCreate) ...[
              _buildTrackSearchBar(),
              _buildSliderDots(),
              Expanded(child: _buildArtistSlider()),
              _buildSubmitBar(),
            ] else
              Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
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
                border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.8),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ARTIST VS', style: TextStyle(
                color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w900, letterSpacing: 3.5,
              )),
              Text('pick two artists', style: TextStyle(
                color: Colors.white.withOpacity(0.55), fontSize: 11,
                fontWeight: FontWeight.w500, letterSpacing: 0.3,
              )),
            ],
          ),
          const Spacer(),
          // Track count balance indicator — visible once any track is picked
          if (_canCreate && (_selectedTracks[0].isNotEmpty || _selectedTracks[1].isNotEmpty))
            _buildTrackCountBadge(),
        ],
      ),
    );
  }

  /// Shows "3 vs 3" or "2 vs 3" in the header so user always knows the balance.
  Widget _buildTrackCountBadge() {
    final c1 = _selectedTracks[0].length;
    final c2 = _selectedTracks[1].length;
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

  // ── Submit bar (bottom — replaces header button) ──────────────────────────
  /// Shown only once both artists are selected. The button itself is only
  /// active when [_canSubmit] is true (both have tracks and counts match).
  Widget _buildSubmitBar() {
    final hint = _submitHint;
    final c1 = _selectedTracks[0].length;
    final c2 = _selectedTracks[1].length;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hint text — explains what's needed to unlock the button
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
                            c1 != c2 && c1 > 0 && c2 > 0
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

            // Submit button
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
                  color: _canSubmit
                      ? null
                      : Colors.white.withOpacity(0.08),
                  border: Border.all(
                    color: _canSubmit
                        ? Colors.transparent
                        : Colors.white.withOpacity(0.12),
                    width: 0.8,
                  ),
                  boxShadow: _canSubmit
                      ? [
                          BoxShadow(
                            color: _kPink.withOpacity(0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                            Text(
                              _canSubmit ? 'CREATE VERSUS' : 'SELECT EQUAL TRACKS',
                              style: TextStyle(
                                color: _canSubmit
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.3),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
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

  // ── Artist search bar ─────────────────────────────────────────────────────
  Widget _buildArtistSearchBar() {
    if (_canCreate && !_isLoadingTracks && _topTracks.any((l) => l.isNotEmpty)) {
      return const SizedBox.shrink();
    }
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
              border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.8),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              onChanged: _onSearchChanged,
              autofocus: true,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              cursorColor: _kPink,
              decoration: InputDecoration(
                hintText: 'Search artists...',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.35), fontSize: 15),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Colors.white.withOpacity(0.5), size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _searchController.clear(); _onSearchChanged(''); },
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

  // ── Track search bar ──────────────────────────────────────────────────────
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
                    : 'Search tracks from these artists...',
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

  // ── Selected slots ────────────────────────────────────────────────────────
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
                      label: 'ARTIST 1',
                      accentColor: _kPurple,
                      trackCount: _selectedTracks[0].length,
                      onRemove: () => setState(() {
                        _selected[0] = null; _topTracks[0] = [];
                        _selectedTracks[0] = []; _trackSearchResults = null;
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
                      label: 'ARTIST 2',
                      accentColor: _kPink,
                      trackCount: _selectedTracks[1].length,
                      onRemove: () => setState(() {
                        _selected[1] = null; _topTracks[1] = [];
                        _selectedTracks[1] = []; _trackSearchResults = null;
                      }),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ── Slider dots ───────────────────────────────────────────────────────────
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

  // ── Artist track slider ───────────────────────────────────────────────────
  Widget _buildArtistSlider() {
    return PageView(
      controller: _pageController,
      onPageChanged: _onArtistPageChanged,
      children: [
        _buildTrackList(pageIndex: 0, accentColor: _kPurple),
        _buildTrackList(pageIndex: 1, accentColor: _kPink),
      ],
    );
  }

  Widget _buildTrackList({required int pageIndex, required Color accentColor}) {
    final artist = _selected[pageIndex];
    if (artist == null) return const SizedBox.shrink();

    if (_isLoadingTracks) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: 8,
        itemBuilder: (_, i) => _ShimmerTrackRow(
          shimmerController: _shimmerController, accentColor: accentColor),
      );
    }

    if (_isSearchingTracks) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: 5,
        itemBuilder: (_, i) => _ShimmerTrackRow(
          shimmerController: _shimmerController, accentColor: accentColor),
      );
    }

    final tracks = _tracksForPage(pageIndex);
    final picked = _selectedTracks[pageIndex];
    final isSearchMode = _trackFilterQuery.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildTrackListHeader(
          artist: artist, accentColor: accentColor,
          pageIndex: pageIndex, isSearchMode: isSearchMode,
          trackCount: tracks.length,
        ),

        // ── Selected tracks section ──────────────────────────────────────
        if (picked.isNotEmpty) ...[
          _buildSectionLabel(
            icon: Icons.playlist_add_check_rounded,
            label: 'SELECTED',
            count: picked.length,
            accentColor: accentColor,
          ),
          ...picked.map((track) => AnimatedBuilder(
                animation: _slideAnim,
                builder: (_, child) => child!,
                child: _SelectedTrackTile(
                  track: track,
                  accentColor: accentColor,
                  onRemove: () => _removeSelectedTrack(pageIndex, track.id),
                ),
              )),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Container(
                height: 0.8,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    accentColor.withOpacity(0.0),
                    accentColor.withOpacity(0.4),
                    accentColor.withOpacity(0.0),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
        ],

        // ── Suggested / search results section ───────────────────────────
        if (tracks.isNotEmpty)
          _buildSectionLabel(
            icon: isSearchMode ? Icons.manage_search_rounded : Icons.star_rounded,
            label: isSearchMode ? 'SEARCH RESULTS' : 'TOP TRACKS',
            count: tracks.length,
            accentColor: accentColor,
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
            final i = entry.key;
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
                accentColor: accentColor,
                isLast: i == tracks.length - 1,
                dimmed: alreadyPicked || picked.isNotEmpty,
                isSelected: alreadyPicked,
                onAdd: alreadyPicked ? null : () => _toggleTrackSelection(track),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildTrackListHeader({
    required SpotifyArtistDetails artist,
    required Color accentColor,
    required int pageIndex,
    required bool isSearchMode,
    required int trackCount,
  }) {
    final isSecondArtist = pageIndex == 1;
    final profile = Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor.withOpacity(0.7), width: 1.5),
        boxShadow: [BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 8)],
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
        isSearchMode ? 'SEARCH' : 'TOP TRACKS',
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

  // ── Results grid ──────────────────────────────────────────────────────────
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
        final slot = _slotFor(artist.id);
        return _ArtistCard(
          artist: artist, selectedSlot: slot,
          onTap: () => _onArtistTap(artist),
        );
      },
    );
  }
}

// ── Selected Track Tile ───────────────────────────────────────────────────────
class _SelectedTrackTile extends StatelessWidget {
  final SpotifyTrack track;
  final Color accentColor;
  final VoidCallback onRemove;

  const _SelectedTrackTile({
    required this.track, required this.accentColor, required this.onRemove,
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
                      boxShadow: [BoxShadow(
                          color: accentColor.withOpacity(0.2), blurRadius: 6)],
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
                      style: const TextStyle(color: Colors.white, fontSize: 13,
                          fontWeight: FontWeight.w700, letterSpacing: -0.1),
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

// ── Top Track Row ─────────────────────────────────────────────────────────────
class _TopTrackRow extends StatelessWidget {
  final SpotifyTrack track;
  final Color accentColor;
  final bool isLast, dimmed, isSelected;
  final VoidCallback? onAdd;

  const _TopTrackRow({
    required this.track, required this.accentColor,
    this.isLast = false, this.dimmed = false,
    this.isSelected = false, this.onAdd,
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
                  ),
                ),
                if (track.artistName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(track.artistName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withOpacity(0.45),
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
          Divider(height: 0, indent: 0,
              color: Colors.white.withOpacity(0.06)),
      ]),
    );
  }
}

// ── Shimmer track row ─────────────────────────────────────────────────────────
class _ShimmerTrackRow extends StatelessWidget {
  final AnimationController shimmerController;
  final Color accentColor;

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

// ── Selected Slot ─────────────────────────────────────────────────────────────
class _SelectedSlot extends StatelessWidget {
  final SpotifyArtistDetails? artist;
  final String label;
  final Color accentColor;
  final int trackCount;
  final VoidCallback onRemove;

  const _SelectedSlot({
    required this.artist, required this.label,
    required this.accentColor, required this.trackCount,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
                  Text(label, style: TextStyle(
                    color: Colors.white.withOpacity(0.3), fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1.2,
                  )),
                ])
              : Row(children: [
                  Container(width: 28, height: 28,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(color: accentColor, width: 1.5)),
                    child: ClipOval(
                      child: artist!.imageUrl != null && artist!.imageUrl!.isNotEmpty
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
                  // Track count pill on the slot chip
                  if (trackCount > 0) ...[
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
                  GestureDetector(
                    onTap: onRemove,
                    child: Icon(Icons.close_rounded,
                        color: Colors.white.withOpacity(0.45), size: 14),
                  ),
                ]),
        ),
      ),
    );
  }
}

// ── Artist Card ───────────────────────────────────────────────────────────────
class _ArtistCard extends StatelessWidget {
  final SpotifyArtistDetails artist;
  final int? selectedSlot;
  final VoidCallback onTap;

  const _ArtistCard({
    required this.artist, required this.selectedSlot, required this.onTap,
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
            final side = math.min(constraints.maxWidth, constraints.maxHeight);
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
                    child: artist.imageUrl != null && artist.imageUrl!.isNotEmpty
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
                    decoration: BoxDecoration(shape: BoxShape.circle,
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

// ── Shimmer artist card ───────────────────────────────────────────────────────
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

// ── Swipe indicator dot ───────────────────────────────────────────────────────
class _SwipeDot extends StatelessWidget {
  final bool isActive;
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