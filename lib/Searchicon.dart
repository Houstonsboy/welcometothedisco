import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/Ranking/entity_profile.dart';
import 'package:welcometothedisco/Ranking/entity_search.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

// ─── Tappable search bar ──────────────────────────────────────────────────────

class SearchIcon extends StatelessWidget {
  const SearchIcon({Key? key}) : super(key: key);

  void _open(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => const _SearchOverlay(),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.13),
                    Colors.white.withOpacity(0.07),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: Colors.white.withOpacity(0.45),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Search artists or albums…',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.36),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Overlay ─────────────────────────────────────────────────────────────────

class _SearchOverlay extends StatefulWidget {
  const _SearchOverlay();

  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<_SearchOverlay> {
  final SpotifyApi _api = SpotifyApi();
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  Timer? _debounce;
  bool _loading = false;
  String _lastQuery = '';
  List<_Result> _results = [];
  bool _artistMode = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _lastQuery = '';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _lastQuery = q;
    });
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (_artistMode) {
        final artists = await _api.searchArtists(q, limit: 14);
        if (!mounted || _lastQuery != q) return;
        setState(() {
          _results = artists
              .map((a) => _Result(
                    id: a.id,
                    title: a.name,
                    subtitle: 'Artist',
                    imageUrl: a.imageUrl,
                    isArtist: true,
                  ))
              .toList();
          _loading = false;
        });
      } else {
        final albums = await _api.searchAlbums(q, limit: 14);
        if (!mounted || _lastQuery != q) return;
        setState(() {
          _results = albums
              .map((a) => _Result(
                    id: a.id,
                    title: a.title,
                    subtitle: a.artistName.isEmpty ? 'Album' : a.artistName,
                    imageUrl: a.imageUrl,
                    isArtist: false,
                  ))
              .toList();
          _loading = false;
        });
      }
    });
  }

  void _toggleMode() {
    setState(() {
      _artistMode = !_artistMode;
      _results = [];
      _loading = false;
    });
    if (_ctrl.text.trim().isNotEmpty) _onChanged(_ctrl.text);
  }

  void _onSelect(_Result item) {
    if (item.isArtist) {
      EntityHistorySelectionStore.selectedArtistId = item.id;
      EntityHistorySelectionStore.selectedArtistName = item.title;
    } else {
      EntityHistorySelectionStore.selectedAlbumId = item.id;
      EntityHistorySelectionStore.selectedAlbumTitle = item.title;
    }
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntityProfileScreen(
          entityId: item.id,
          initialTitle: item.title,
          initialImageUrl: item.imageUrl,
          isArtist: item.isArtist,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── Blurred backdrop ──────────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(color: Colors.black.withOpacity(0.60)),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────
          Positioned(
            top: topPad + 12,
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              children: [
                _buildBar(),
                const SizedBox(height: 6),
                Expanded(child: _buildResults()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // ── Text field ───────────────────────────────────────────────
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withOpacity(0.13),
              ),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: _onChanged,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: AppTheme.gradientEnd,
                decoration: InputDecoration(
                  hintText: _artistMode
                      ? 'Search Spotify artists…'
                      : 'Search Spotify albums…',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.32),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  prefixIcon: _loading
                      ? Padding(
                          padding: const EdgeInsets.all(13),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white.withOpacity(0.50),
                            ),
                          ),
                        )
                      : Icon(
                          Icons.search_rounded,
                          color: Colors.white.withOpacity(0.40),
                          size: 20,
                        ),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _ctrl.clear();
                            _onChanged('');
                          },
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withOpacity(0.35),
                            size: 18,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // ── Artist / Album toggle ────────────────────────────────────
          GestureDetector(
            onTap: _toggleMode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.13),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _artistMode ? Icons.person_rounded : Icons.album_rounded,
                    color: Colors.white.withOpacity(0.85),
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _artistMode ? 'Artist' : 'Album',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.90),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty && _lastQuery.isEmpty) {
      return Center(
        child: Text(
          'Search Spotify artists & albums',
          style: TextStyle(
            color: Colors.white.withOpacity(0.28),
            fontSize: 14,
          ),
        ),
      );
    }
    if (_results.isEmpty && !_loading) {
      return Center(
        child: Text(
          'No results',
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 14,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      physics: const BouncingScrollPhysics(),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final item = _results[i];
        return GestureDetector(
          onTap: () => _onSelect(item),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                _Thumb(item: item),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.42),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.22),
                  size: 18,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Data ─────────────────────────────────────────────────────────────────────

class _Result {
  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final bool isArtist;

  const _Result({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.isArtist,
  });
}

// ─── Thumbnail ────────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});
  final _Result item;

  @override
  Widget build(BuildContext context) {
    final circle = item.isArtist;
    final br = circle ? BorderRadius.circular(99) : BorderRadius.circular(8);
    final hasImg = item.imageUrl != null && item.imageUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: br,
      child: hasImg
          ? Image.network(
              item.imageUrl!,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(circle),
            )
          : _fallback(circle),
    );
  }

  Widget _fallback(bool circle) {
    return Container(
      width: 46,
      height: 46,
      color: AppTheme.gradientStart.withOpacity(0.25),
      child: Icon(
        circle ? Icons.person_rounded : Icons.album_rounded,
        color: Colors.white.withOpacity(0.50),
        size: 22,
      ),
    );
  }
}
