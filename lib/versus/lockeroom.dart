import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/services/firebase_service.dart';

// ── Constants ────────────────────────────────────────────────────────────────
const _kBlue = Color(0xFF1E3DE1);
const _kPink = Color(0xFFf85187);

// ── Album result model ────────────────────────────────────────────────────────
class AlbumResult {
  final String id;
  final String name;
  final String artistName;
  final String? imageUrl;
  final List<TrackResult> tracks;

  AlbumResult({
    required this.id,
    required this.name,
    required this.artistName,
    this.imageUrl,
    this.tracks = const [],
  });
}

class TrackResult {
  final String id;
  final String name;
  final int trackNumber;
  final String durationFormatted;

  TrackResult({
    required this.id,
    required this.name,
    required this.trackNumber,
    required this.durationFormatted,
  });
}

// ── Lockeroom page ────────────────────────────────────────────────────────────
class Lockeroom extends StatefulWidget {
  const Lockeroom({super.key});

  @override
  State<Lockeroom> createState() => _LockeroomState();
}

class _LockeroomState extends State<Lockeroom> with TickerProviderStateMixin {
  final SpotifyApi _spotifyApi = SpotifyApi();

  // ── Search ─────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  List<AlbumResult> _searchResults = [];
  bool _isSearching = false;
  String _searchQuery = '';

  // ── Selection ──────────────────────────────────────────────────────────────
  AlbumResult? _album1;
  AlbumResult? _album2;

  // ── Save ───────────────────────────────────────────────────────────────────
  bool _isSaving = false;

  // ── Animations ─────────────────────────────────────────────────────────────
  late final AnimationController _vsController;
  late final Animation<double> _vsAnim;

  @override
  void initState() {
    super.initState();
    _vsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _vsAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _vsController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    _vsController.dispose();
    super.dispose();
  }

  // ── Search logic ───────────────────────────────────────────────────────────
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    setState(() => _searchQuery = query);
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 420), () => _fetchResults(query));
  }

  Future<void> _fetchResults(String query) async {
    setState(() => _isSearching = true);
    try {
      final albums = await _spotifyApi.searchAlbums(query, limit: 12);
      final results = albums.map(_fromDetails).toList();
      if (mounted && _searchQuery == query) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  AlbumResult _fromDetails(SpotifyAlbumDetails a) => AlbumResult(
        id: a.id,
        name: a.title,
        artistName: a.artistName,
        imageUrl: a.imageUrl,
      );

  AlbumResult _withTracks(AlbumResult base, SpotifyAlbumWithTracks full) =>
      AlbumResult(
        id: base.id,
        name: base.name,
        artistName: base.artistName,
        imageUrl: base.imageUrl,
        tracks: full.tracks
            .map((t) => TrackResult(
                  id: t.id,
                  name: t.name,
                  trackNumber: t.trackNumber,
                  durationFormatted: t.durationFormatted,
                ))
            .toList(),
      );

  // ── Selection ──────────────────────────────────────────────────────────────
  Future<void> _selectAlbum(AlbumResult album) async {
    final full = await _spotifyApi.getAlbumWithTracks(album.id);
    final selected = full == null ? album : _withTracks(album, full);
    if (!mounted) return;
    setState(() {
      if (_album1 == null) {
        _album1 = selected;
      } else if (_album2 == null && album.id != _album1!.id) {
        _album2 = selected;
      }
      _searchController.clear();
      _searchResults = [];
      _searchQuery = '';
    });
  }

  void _clearAlbum(int slot) {
    setState(() {
      if (slot == 1) _album1 = null;
      if (slot == 2) _album2 = null;
    });
  }

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<void> _saveVersus() async {
    if (_album1 == null || _album2 == null) return;
    setState(() => _isSaving = true);
    try {
      await FirebaseService.createVersusFromLockeroom(
        album1ID: _album1!.id,
        album1Name: _album1!.name,
        album2ID: _album2!.id,
        album2Name: _album2!.name,
      );
      if (mounted) {
        _showSnack('Versus created!', _kBlue, Icons.check_circle_rounded);
        setState(() {
          _album1 = null;
          _album2 = null;
        });
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', _kPink, Icons.error_rounded);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, Color bg, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasAlbum1 = _album1 != null;
    final hasAlbum2 = _album2 != null;
    final bothSelected = hasAlbum1 && hasAlbum2;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBlue, _kPink],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverToBoxAdapter(child: _buildAlbumSlots(hasAlbum1, hasAlbum2)),
            if (!bothSelected)
              SliverToBoxAdapter(child: _buildSearchBar()),
            if (_isSearching && !bothSelected)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2,
                    ),
                  ),
                ),
              ),
            if (_searchResults.isNotEmpty && !bothSelected)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _AlbumResultTile(
                      album: _searchResults[i],
                      onTap: () => _selectAlbum(_searchResults[i]),
                      accentColor:
                          hasAlbum1 ? _kPink : _kBlue,
                    ),
                    childCount: _searchResults.length,
                  ),
                ),
              ),
            if (bothSelected)
              SliverToBoxAdapter(child: _buildTrackPreviews()),
            if (bothSelected)
              SliverToBoxAdapter(child: _buildSaveButton()),
            const SliverToBoxAdapter(child: SizedBox(height: 60)),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Back button — glass pill
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.15),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.22),
                          width: 0.8,
                        ),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 15),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Label pill
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: Colors.white.withOpacity(0.12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'LOCKER ROOM',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Set up\nyour versus.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _album1 == null
                ? 'Search and pick the first album.'
                : _album2 == null
                    ? 'Now pick the challenger.'
                    : 'Review the battle. Save when ready.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ── Album slots ────────────────────────────────────────────────────────────
  Widget _buildAlbumSlots(bool hasAlbum1, bool hasAlbum2) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AlbumSlot(
                  album: _album1,
                  label: 'ALBUM 1',
                  accentColor: _kBlue,
                  isEmpty: !hasAlbum1,
                  onClear: () => _clearAlbum(1),
                ),
              ),
              const SizedBox(width: 56),
              Expanded(
                child: _AlbumSlot(
                  album: _album2,
                  label: 'ALBUM 2',
                  accentColor: _kPink,
                  isEmpty: !hasAlbum2,
                  onClear: () => _clearAlbum(2),
                ),
              ),
            ],
          ),
          // VS badge — pulsing, glass + gradient
          AnimatedBuilder(
            animation: _vsAnim,
            builder: (_, child) =>
                Transform.scale(scale: _vsAnim.value, child: child),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_kBlue, _kPink],
                    ),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: _kPink.withOpacity(0.45),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'VS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    final isAlbum2Phase = _album1 != null;
    final accent = isAlbum2Phase ? _kPink : _kBlue;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.12),
              border: Border.all(
                  color: accent.withOpacity(0.45), width: 1),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.search_rounded,
                    color: Colors.white.withOpacity(0.6), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: isAlbum2Phase
                          ? 'Search challenger album...'
                          : 'Search albums or artists...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(Icons.close_rounded,
                          color: Colors.white.withOpacity(0.4), size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Track previews ─────────────────────────────────────────────────────────
  Widget _buildTrackPreviews() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _TrackPreviewCard(album: _album1!, accentColor: _kBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _TrackPreviewCard(album: _album2!, accentColor: _kPink),
          ),
        ],
      ),
    );
  }

  // ── Save button ────────────────────────────────────────────────────────────
  Widget _buildSaveButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: GestureDetector(
        onTap: _isSaving ? null : _saveVersus,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: _isSaving
                      ? [
                          Colors.white.withOpacity(0.1),
                          Colors.white.withOpacity(0.1)
                        ]
                      : [
                          _kBlue.withOpacity(0.85),
                          _kPink.withOpacity(0.85),
                        ],
                ),
                border: Border.all(
                  color: Colors.white
                      .withOpacity(_isSaving ? 0.1 : 0.25),
                  width: 0.8,
                ),
                boxShadow: _isSaving
                    ? []
                    : [
                        BoxShadow(
                          color: _kPink.withOpacity(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'START THE VERSUS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Album Slot ────────────────────────────────────────────────────────────────
class _AlbumSlot extends StatelessWidget {
  final AlbumResult? album;
  final String label;
  final Color accentColor;
  final bool isEmpty;
  final VoidCallback onClear;

  const _AlbumSlot({
    required this.album,
    required this.label,
    required this.accentColor,
    required this.isEmpty,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isEmpty
                ? Colors.white.withOpacity(0.08)
                : accentColor.withOpacity(0.18),
            border: Border.all(
              color: isEmpty
                  ? Colors.white.withOpacity(0.14)
                  : accentColor.withOpacity(0.55),
              width: isEmpty ? 0.8 : 1.5,
            ),
          ),
          child: isEmpty
              ? _EmptySlot(label: label, accentColor: accentColor)
              : _FilledSlot(
                  album: album!, accentColor: accentColor, onClear: onClear),
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final String label;
  final Color accentColor;
  const _EmptySlot({required this.label, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withOpacity(0.06),
              border: Border.all(
                  color: Colors.white.withOpacity(0.1), width: 0.8),
            ),
            child: Icon(Icons.add_rounded,
                color: Colors.white.withOpacity(0.25), size: 28),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilledSlot extends StatelessWidget {
  final AlbumResult album;
  final Color accentColor;
  final VoidCallback onClear;

  const _FilledSlot({
    required this.album,
    required this.accentColor,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: album.imageUrl != null
                      ? Image.network(album.imageUrl!, fit: BoxFit.cover)
                      : Container(
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.album_rounded,
                              color: accentColor.withOpacity(0.6),
                              size: 32),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                album.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accentColor.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: onClear,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kPink.withOpacity(0.9),
                boxShadow: [
                  BoxShadow(
                      color: _kPink.withOpacity(0.4), blurRadius: 8),
                ],
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 13),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Album Result Tile ─────────────────────────────────────────────────────────
class _AlbumResultTile extends StatelessWidget {
  final AlbumResult album;
  final VoidCallback onTap;
  final Color accentColor;

  const _AlbumResultTile({
    required this.album,
    required this.onTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withOpacity(0.1),
              border: Border.all(
                  color: Colors.white.withOpacity(0.15), width: 0.8),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: album.imageUrl != null
                        ? Image.network(album.imageUrl!, fit: BoxFit.cover)
                        : Container(
                            color: accentColor.withOpacity(0.2),
                            child: Icon(Icons.album_rounded,
                                color: accentColor.withOpacity(0.6),
                                size: 24),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        album.artistName,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: accentColor.withOpacity(0.2),
                    border: Border.all(
                        color: accentColor.withOpacity(0.5), width: 0.8),
                  ),
                  child: Text(
                    'PICK',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Track Preview Card ────────────────────────────────────────────────────────
class _TrackPreviewCard extends StatelessWidget {
  final AlbumResult album;
  final Color accentColor;

  const _TrackPreviewCard(
      {required this.album, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final visible = album.tracks.take(6).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(0.1),
            border: Border.all(
                color: accentColor.withOpacity(0.4), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: album.imageUrl != null
                      ? Image.network(album.imageUrl!, fit: BoxFit.cover)
                      : Container(
                          color: accentColor.withOpacity(0.18),
                          child: Icon(Icons.album_rounded,
                              color: accentColor.withOpacity(0.5),
                              size: 40),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: Text(
                  album.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 12,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'TRACKS',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${album.tracks.length}',
                      style: TextStyle(
                        color: accentColor.withOpacity(0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              ...List.generate(
                visible.length,
                (i) => _PreviewTrackRow(
                  track: visible[i],
                  accentColor: accentColor,
                  isLast: i == visible.length - 1 &&
                      album.tracks.length <= 6,
                ),
              ),
              if (album.tracks.length > 6)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Text(
                    '+${album.tracks.length - 6} more tracks',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else
                const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewTrackRow extends StatelessWidget {
  final TrackResult track;
  final Color accentColor;
  final bool isLast;

  const _PreviewTrackRow({
    required this.track,
    required this.accentColor,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${track.trackNumber}',
                  style: TextStyle(
                    color: accentColor.withOpacity(0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                track.durationFormatted,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
              height: 0,
              indent: 42,
              color: Colors.white.withOpacity(0.08)),
      ],
    );
  }
}
