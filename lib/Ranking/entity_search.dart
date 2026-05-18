import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/Ranking/entity_profile.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kBlue = AppTheme.gradientStart;
const _kPink = AppTheme.gradientEnd;

class EntitySelectionResult {
  final String id;
  final String title;
  final String? imageUrl;
  final bool isArtist;

  const EntitySelectionResult({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.isArtist,
  });
}

/// In-memory selection store for follow-up flows in this session.
class EntityHistorySelectionStore {
  static String? selectedArtistId;
  static String? selectedArtistName;
  static String? selectedAlbumId;
  static String? selectedAlbumTitle;
}

class EntityHistoryScreen extends StatefulWidget {
  /// When this screen is shown inside the main shell tab stack (not pushed),
  /// use this instead of [Navigator.pop] so back jumps to the home tab.
  final VoidCallback? onBackToHome;

  const EntityHistoryScreen({super.key, this.onBackToHome});

  @override
  State<EntityHistoryScreen> createState() => _EntityHistoryScreenState();
}

class _EntityHistoryScreenState extends State<EntityHistoryScreen> {
  final SpotifyApi _api = SpotifyApi();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  bool _isSearching = false;
  String _lastQuery = '';
  List<_EntitySearchItem> _results = [];
  _SearchMode _searchMode = _SearchMode.artist;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _lastQuery = '';
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _lastQuery = q;
    });

    _debounce = Timer(const Duration(milliseconds: 420), () async {
      if (_searchMode == _SearchMode.artist) {
        final artists = await _api.searchArtists(q, limit: 12);
        if (!mounted || _lastQuery != q) return;
        setState(() {
          _results = artists.map(_EntitySearchItem.fromArtist).toList();
          _isSearching = false;
        });
        return;
      }

      final albums = await _api.searchAlbums(q, limit: 12);
      if (!mounted || _lastQuery != q) return;
      setState(() {
        _results = albums.map(_EntitySearchItem.fromAlbum).toList();
        _isSearching = false;
      });
    });
  }

  void _toggleSearchMode() {
    setState(() {
      _searchMode = _searchMode == _SearchMode.artist
          ? _SearchMode.album
          : _SearchMode.artist;
      _results = [];
      _isSearching = false;
    });
    final current = _searchController.text.trim();
    if (current.isNotEmpty) {
      _onSearchChanged(current);
    }
  }

  void _onItemTap(_EntitySearchItem item) {
    final isArtist = item.type == _EntityType.artist;

    if (isArtist) {
      EntityHistorySelectionStore.selectedArtistId = item.id;
      EntityHistorySelectionStore.selectedArtistName = item.title;
    } else {
      EntityHistorySelectionStore.selectedAlbumId = item.id;
      EntityHistorySelectionStore.selectedAlbumTitle = item.title;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntityProfileScreen(
          entityId: item.id,
          initialTitle: item.title,
          initialImageUrl: item.imageUrl,
          isArtist: isArtist,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        body: Column(
          children: [
            _buildHeader(context),
            _buildSearchBar(),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        left: 20,
        right: 20,
        bottom: 10,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              final goHome = widget.onBackToHome;
              if (goHome != null) {
                goHome();
                return;
              }
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
                border:
                    Border.all(color: Colors.white.withOpacity(0.2), width: 0.8),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ARTIST LEADERSHIP BOARD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.8,
                ),
              ),
              Text(
                'search artists or albums to see their rank',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
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
              autofocus: true,
              onChanged: _onSearchChanged,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: _kPink,
              decoration: InputDecoration(
                hintText: _searchMode == _SearchMode.artist
                    ? 'Search Spotify artists...'
                    : 'Search Spotify albums...',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 15,
                ),
                prefixIcon: _isSearching
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.search_rounded,
                        color: Colors.white.withOpacity(0.5),
                        size: 20,
                      ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: Colors.white.withOpacity(0.12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.24),
                            width: 0.8,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(99),
                            onTap: _toggleSearchMode,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _searchMode == _SearchMode.artist
                                        ? Icons.person_rounded
                                        : Icons.album_rounded,
                                    color: Colors.white.withOpacity(0.85),
                                    size: 13,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _searchMode == _SearchMode.artist
                                        ? 'Artist'
                                        : 'Album',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withOpacity(0.4),
                            size: 18,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty && _lastQuery.isEmpty) {
      return Center(
        child: Text(
          'Start typing to search',
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    if (_results.isEmpty && !_isSearching) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final item = _results[i];
        return _EntityResultGridCard(
          item: item,
          onTap: () => _onItemTap(item),
        );
      },
    );
  }
}

enum _EntityType { artist, album }

enum _SearchMode { artist, album }

class _EntitySearchItem {
  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final _EntityType type;

  const _EntitySearchItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.type,
  });

  factory _EntitySearchItem.fromArtist(SpotifyArtistDetails artist) {
    return _EntitySearchItem(
      id: artist.id,
      title: artist.name,
      subtitle: 'Artist',
      imageUrl: artist.imageUrl,
      type: _EntityType.artist,
    );
  }

  factory _EntitySearchItem.fromAlbum(SpotifyAlbumDetails album) {
    return _EntitySearchItem(
      id: album.id,
      title: album.title,
      subtitle: album.artistName.isEmpty ? 'Album' : album.artistName,
      imageUrl: album.imageUrl,
      type: _EntityType.album,
    );
  }
}

class _EntityResultGridCard extends StatelessWidget {
  final _EntitySearchItem item;
  final VoidCallback onTap;

  const _EntityResultGridCard({
    required this.item,
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
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final side = constraints.maxWidth;
                return SizedBox(
                  width: side,
                  height: side,
                  child: _cover(),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cover() {
    final accent = item.type == _EntityType.artist ? _kBlue : _kPink;
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final borderRadius = item.type == _EntityType.artist
        ? BorderRadius.circular(99)
        : BorderRadius.circular(10);

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: accent.withOpacity(0.55), width: 1),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: hasImage
            ? Image.network(item.imageUrl!, fit: BoxFit.cover)
            : Container(
                color: accent.withOpacity(0.25),
                child: Icon(
                  item.type == _EntityType.artist
                      ? Icons.person_rounded
                      : Icons.album_rounded,
                  color: Colors.white.withOpacity(0.65),
                  size: 22,
                ),
              ),
      ),
    );
  }
}
