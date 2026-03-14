import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:welcometothedisco/services/spotify_api.dart';

const _kPurple = Color(0xFF1E3DE1);
const _kPink = Color(0xFFf85187);

/// Entry point for Artist VS — pick two artists, then create versus.
class ArtistLockeroom extends StatelessWidget {
  const ArtistLockeroom({super.key});

  @override
  Widget build(BuildContext context) {
    return ArtistSearchScreen(
      onCreateVersus: (artist1, artist2) {
        // TODO: wire to Firebase createArtistVersus + navigate to playground
        Navigator.of(context).pop();
      },
    );
  }
}

class ArtistSearchScreen extends StatefulWidget {
  final void Function(SpotifyArtistDetails artist1, SpotifyArtistDetails artist2) onCreateVersus;

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

  // ── Track filter search bar ───────────────────────────────────────────────
  final TextEditingController _trackFilterController = TextEditingController();
  final FocusNode _trackFilterFocus = FocusNode();
  String _trackFilter = '';

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
    _trackFilterController.addListener(() {
      setState(() => _trackFilter = _trackFilterController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _shimmerController.dispose();
    _slideController.dispose();
    _pageController.dispose();
    _trackFilterController.dispose();
    _trackFilterFocus.dispose();
    super.dispose();
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
      if (_selected[0]?.id == artist.id) { _selected[0] = null; _topTracks[0] = []; return; }
      if (_selected[1]?.id == artist.id) { _selected[1] = null; _topTracks[1] = []; return; }
      if (_selected[0] == null) {
        _selected[0] = artist;
      } else if (_selected[1] == null) {
        _selected[1] = artist;
      } else {
        _selected[1] = artist;
        _topTracks[1] = [];
      }
    });
    _maybeFetchTopTracks();
  }

  int? _slotFor(String artistId) {
    if (_selected[0]?.id == artistId) return 0;
    if (_selected[1]?.id == artistId) return 1;
    return null;
  }

  bool get _canCreate => _selected[0] != null && _selected[1] != null;

  // ── Top tracks fetch (SpotifyApi.getBothArtistsTopTracks) ───────────────────
  /// Fetches top tracks for both selected artists from Spotify and updates
  /// [_topTracks]. Called when the second artist is selected or when the
  /// slider is shown with both selected but tracks not yet loaded.
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
        _trackFilter = '';
        _trackFilterController.clear();
      });
      _slideController.forward(from: 0);
    } finally {
      if (mounted) setState(() => _isLoadingTracks = false);
    }
  }

  void _onArtistPageChanged(int index) {
    if (_selectedArtistPage == index) return;
    setState(() => _selectedArtistPage = index);
    _slideController.forward(from: 0);
  }

  // ── Filtered tracks for current page ─────────────────────────────────────
  List<SpotifyTrack> _filteredTracks(int pageIndex) {
    final tracks = _topTracks[pageIndex];
    if (_trackFilter.isEmpty) return tracks;
    return tracks.where((t) =>
        t.name.toLowerCase().contains(_trackFilter) ||
        t.artistName.toLowerCase().contains(_trackFilter)).toList();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // When both artists are selected but top tracks not yet loaded, fetch once.
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
              _buildTrackFilterBar(),
              _buildSliderDots(),
              Expanded(child: _buildArtistSlider()),
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
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ARTIST VS', style: TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 3.5,
              )),
              Text('pick two artists', style: TextStyle(
                color: Colors.white.withOpacity(0.55), fontSize: 11,
                fontWeight: FontWeight.w500, letterSpacing: 0.3,
              )),
            ],
          ),
          const Spacer(),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: _canCreate ? 1.0 : 0.0,
            child: GestureDetector(
              onTap: _canCreate
                  ? () => widget.onCreateVersus(_selected[0]!, _selected[1]!)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: const LinearGradient(colors: [_kPurple, _kPink]),
                  boxShadow: [BoxShadow(color: _kPink.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: const Text('CREATE VS', style: TextStyle(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 1.5,
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Artist search bar ─────────────────────────────────────────────────────
  Widget _buildArtistSearchBar() {
    // Hide once both artists are picked and tracks are loaded
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
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              cursorColor: _kPink,
              decoration: InputDecoration(
                hintText: 'Search artists...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 15),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.5), size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _searchController.clear(); _onSearchChanged(''); },
                        child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.4), size: 18),
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

  // ── Track filter bar (shown below selected slots once both artists picked) ──
  Widget _buildTrackFilterBar() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: Colors.white.withOpacity(0.09),
                border: Border.all(color: Colors.white.withOpacity(0.14), width: 0.8),
              ),
              child: TextField(
                controller: _trackFilterController,
                focusNode: _trackFilterFocus,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                cursorColor: _kPink,
                decoration: InputDecoration(
                  hintText: 'Filter tracks...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                  prefixIcon: Icon(Icons.queue_music_rounded, color: Colors.white.withOpacity(0.4), size: 18),
                  suffixIcon: _trackFilter.isNotEmpty
                      ? GestureDetector(
                          onTap: () { _trackFilterController.clear(); _trackFilterFocus.unfocus(); },
                          child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.35), size: 16),
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
                  Expanded(child: _SelectedSlot(
                    artist: _selected[0], label: 'ARTIST 1', accentColor: _kPurple,
                    onRemove: () => setState(() { _selected[0] = null; _topTracks[0] = []; }),
                  )),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('VS', style: TextStyle(
                      color: Colors.white.withOpacity(0.6), fontSize: 13,
                      fontWeight: FontWeight.w900, letterSpacing: 2,
                    )),
                  ),
                  Expanded(child: _SelectedSlot(
                    artist: _selected[1], label: 'ARTIST 2', accentColor: _kPink,
                    onRemove: () => setState(() { _selected[1] = null; _topTracks[1] = []; }),
                  )),
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
          _SwipeDot(isActive: _selectedArtistPage == 0, color: _kPurple),
          const SizedBox(width: 6),
          _SwipeDot(isActive: _selectedArtistPage == 1, color: _kPink),
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
          shimmerController: _shimmerController,
          accentColor: accentColor,
        ),
      );
    }

    final filtered = _filteredTracks(pageIndex);

    if (filtered.isEmpty && _trackFilter.isNotEmpty) {
      return Center(
        child: Text('No tracks match "$_trackFilter"',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Text('No top tracks available',
          style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const BouncingScrollPhysics(),
      itemCount: filtered.length + 1,
      itemBuilder: (context, index) {
        // Header row
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: Row(
              children: [
                // Artist avatar
                Container(
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
                            child: const Icon(Icons.person_rounded, color: Colors.white, size: 16)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w700, letterSpacing: 0.2,
                    ),
                  ),
                ),
                Container(
                  width: 3, height: 16,
                  decoration: BoxDecoration(
                    color: accentColor, borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 8),
                Text('TOP TRACKS', style: TextStyle(
                  color: Colors.white.withOpacity(0.45), fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 2,
                )),
                const SizedBox(width: 6),
                Text('${filtered.length}', style: TextStyle(
                  color: accentColor.withOpacity(0.9), fontSize: 10, fontWeight: FontWeight.w700,
                )),
              ],
            ),
          );
        }

        final trackIndex = index - 1;
        final track = filtered[trackIndex];
        return AnimatedBuilder(
          animation: _slideAnim,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 20 * (1 - _slideAnim.value) * math.max(0, 1 - trackIndex * 0.06)),
            child: Opacity(opacity: _slideAnim.value.clamp(0.0, 1.0), child: child),
          ),
          child: _TopTrackRow(
            track: track,
            index: trackIndex,
            accentColor: accentColor,
            isLast: trackIndex == filtered.length - 1,
          ),
        );
      },
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
        itemBuilder: (_, __) => _ShimmerArtistCard(shimmerController: _shimmerController),
      );
    }

    if (_results.isEmpty && _lastQuery.isNotEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, color: Colors.white.withOpacity(0.25), size: 40),
          const SizedBox(height: 10),
          Text('No artists found', style: TextStyle(
            color: Colors.white.withOpacity(0.4), fontSize: 14, fontWeight: FontWeight.w500,
          )),
        ],
      ));
    }

    if (_results.isEmpty) {
      return Center(child: Text('Start typing to search', style: TextStyle(
        color: Colors.white.withOpacity(0.3), fontSize: 14, fontWeight: FontWeight.w500,
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
          artist: artist, selectedSlot: slot, onTap: () => _onArtistTap(artist),
        );
      },
    );
  }
}

// ── Top Track Row ─────────────────────────────────────────────────────────────
class _TopTrackRow extends StatelessWidget {
  final SpotifyTrack track;
  final int index;
  final Color accentColor;
  final bool isLast;

  const _TopTrackRow({
    required this.track,
    required this.index,
    required this.accentColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              // Track number
              SizedBox(
                width: 28,
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: TextStyle(
                    color: accentColor.withOpacity(0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Album art thumbnail
              if (track.albumArtUrl != null && track.albumArtUrl!.isNotEmpty)
                Container(
                  width: 40, height: 40,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(track.albumArtUrl!, fit: BoxFit.cover),
                  ),
                ),
              // Track info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w600, letterSpacing: -0.1,
                      ),
                    ),
                    if (track.artistName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(track.artistName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 12, fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Rank indicator for top 3
              if (index < 3)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: accentColor.withOpacity(0.25),
                    border: Border.all(color: accentColor.withOpacity(0.5), width: 0.8),
                  ),
                  child: Text(
                    index == 0 ? '🔥' : index == 1 ? '★' : '♪',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 0, indent: 48, color: Colors.white.withOpacity(0.06)),
      ],
    );
  }
}

// ── Shimmer track row skeleton ────────────────────────────────────────────────
class _ShimmerTrackRow extends StatelessWidget {
  final AnimationController shimmerController;
  final Color accentColor;

  const _ShimmerTrackRow({required this.shimmerController, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerController,
      builder: (_, __) {
        final s = shimmerController.value;
        shimmerGrad(double opacity) => LinearGradient(
          begin: Alignment(-1 + s * 2, 0), end: Alignment(s * 2, 0),
          colors: [
            Colors.white.withOpacity(opacity * 0.5),
            Colors.white.withOpacity(opacity),
            Colors.white.withOpacity(opacity * 0.5),
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(width: 22, height: 10, decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4), gradient: shimmerGrad(0.12),
              )),
              const SizedBox(width: 10),
              Container(width: 40, height: 40, decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6), gradient: shimmerGrad(0.12),
              )),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 12, decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4), gradient: shimmerGrad(0.14),
                  )),
                  const SizedBox(height: 5),
                  Container(height: 9, width: 80, decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4), gradient: shimmerGrad(0.08),
                  )),
                ],
              )),
            ],
          ),
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
  final VoidCallback onRemove;

  const _SelectedSlot({
    required this.artist, required this.label,
    required this.accentColor, required this.onRemove,
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
            color: artist != null ? accentColor.withOpacity(0.22) : Colors.white.withOpacity(0.07),
            border: Border.all(
              color: artist != null ? accentColor.withOpacity(0.55) : Colors.white.withOpacity(0.10),
              width: 1.0,
            ),
          ),
          child: artist == null
              ? Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                    ),
                    child: Icon(Icons.add_rounded, color: Colors.white.withOpacity(0.25), size: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(
                    color: Colors.white.withOpacity(0.3), fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 1.2,
                  )),
                ])
              : Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor, width: 1.5),
                    ),
                    child: ClipOval(
                      child: artist!.imageUrl != null && artist!.imageUrl!.isNotEmpty
                          ? Image.network(artist!.imageUrl!, fit: BoxFit.cover)
                          : Container(color: accentColor.withOpacity(0.3),
                              child: const Icon(Icons.person_rounded, color: Colors.white, size: 14)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(artist!.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  )),
                  GestureDetector(
                    onTap: onRemove,
                    child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.45), size: 14),
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

  const _ArtistCard({required this.artist, required this.selectedSlot, required this.onTap});

  Color get _slotColor => selectedSlot == 0 ? _kPurple : _kPink;

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedSlot != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: isSelected ? _slotColor.withOpacity(0.18) : Colors.white.withOpacity(0.07),
          border: Border.all(
            color: isSelected ? _slotColor.withOpacity(0.65) : Colors.white.withOpacity(0.08),
            width: isSelected ? 1.5 : 0.8,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: _slotColor.withOpacity(0.3), blurRadius: 16, spreadRadius: 1)]
              : [],
        ),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: LayoutBuilder(builder: (_, constraints) {
                final side = math.min(constraints.maxWidth, constraints.maxHeight);
                return Stack(
                  alignment: Alignment.topRight,
                  children: [
                    SizedBox(width: side, height: side,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? _slotColor.withOpacity(0.8) : Colors.white.withOpacity(0.12),
                            width: isSelected ? 2.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: _slotColor.withOpacity(0.45), blurRadius: 18, spreadRadius: 2)]
                              : [],
                        ),
                        child: ClipOval(
                          child: artist.imageUrl != null && artist.imageUrl!.isNotEmpty
                              ? Image.network(artist.imageUrl!, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _placeholder())
                              : _placeholder(),
                        ),
                      ),
                    ),
                    if (isSelected)
                      Positioned(
                        top: 0, right: 0,
                        child: Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle, color: _slotColor,
                            boxShadow: [BoxShadow(color: _slotColor.withOpacity(0.6), blurRadius: 8)],
                          ),
                          child: Center(child: Text('${selectedSlot! + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                          )),
                        ),
                      ),
                  ],
                );
              }),
            ),
            const SizedBox(height: 8),
            Flexible(child: Text(artist.name,
              maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.8),
                fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, height: 1.3,
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: Colors.white.withOpacity(0.08),
    child: Icon(Icons.person_rounded, size: 36, color: Colors.white.withOpacity(0.3)),
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
        shimmerGrad() => LinearGradient(
          begin: Alignment(-1 + s * 2, 0), end: Alignment(s * 2, 0),
          colors: [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.14), Colors.white.withOpacity(0.06)],
        );
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.8),
          ),
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Expanded(child: Center(child: AspectRatio(aspectRatio: 1,
              child: Container(decoration: BoxDecoration(shape: BoxShape.circle, gradient: shimmerGrad()))))),
            const SizedBox(height: 6),
            Container(height: 8, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), gradient: shimmerGrad())),
            const SizedBox(height: 4),
            Container(height: 8, width: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), gradient: shimmerGrad())),
          ]),
        );
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
      width: isActive ? 20 : 6,
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: isActive ? color : Colors.white.withOpacity(0.3),
      ),
    );
  }
}