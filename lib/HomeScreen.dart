import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/BottomNavBar.dart';
import 'package:welcometothedisco/Inbox.dart';
import 'package:welcometothedisco/Searchicon.dart';
import 'package:welcometothedisco/StoriesTemplate.dart';
import 'package:welcometothedisco/Ranking/entity_profile.dart';
import 'package:welcometothedisco/Ranking/entity_search.dart';
import 'package:welcometothedisco/services/spotify_auth.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';
import 'package:welcometothedisco/versus/artistlockeroom.dart';
import 'package:welcometothedisco/versus/collaboratorlockeroom.dart';
import 'package:welcometothedisco/versus/lockeroom.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SpotifyAuth _spotifyAuth = SpotifyAuth();
  final SpotifyApi _spotifyApi = SpotifyApi();

  SpotifyUser? _spotifyUser;
  bool _spotifyLoading = true;   // initial load / fetching profile
  bool _spotifyConnecting = false; // login flow in progress

  @override
  void initState() {
    super.initState();
    _initSpotify();
  }

  Future<void> _initSpotify() async {
    // Only run full Spotify OAuth when no tokens exist (first time after Firebase login,
    // or after tokens were removed / app data cleared). Otherwise just load profile;
    // TokenStorageService.getAccessToken() refreshes expired tokens automatically.
    final hasTokens = await TokenStorageService.hasSpotifyTokens();
    if (hasTokens) {
      await _loadSpotifyProfile();
    } else {
      await _runSpotifyAuth();
    }
    if (mounted) setState(() => _spotifyLoading = false);
  }

  Future<void> _runSpotifyAuth() async {
    if (!mounted) return;
    setState(() => _spotifyConnecting = true);
    try {
      final result = await _spotifyAuth.login();
      if (!mounted) return;
      if (result.isSuccess) {
        await _loadSpotifyProfile();
      }
    } finally {
      if (mounted) setState(() => _spotifyConnecting = false);
    }
  }

  Future<void> _loadSpotifyProfile() async {
    final user = await _spotifyApi.getCurrentUser();
    if (mounted) setState(() => _spotifyUser = user);
  }

  void _onTabTapped(BuildContext context, int index) {
    if (index == 0) return;
    if (index == 1) {
      Navigator.pushReplacementNamed(context, '/spotify');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            "Welcome to the Disco",
            style: TextStyle(
              fontSize: 22.0,
              fontFamily: 'Honk-Regular-VariableFont_MORF,SHLN',
              color: AppTheme.titleAccent,
            ),
          ),
        ),
        body: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: SpotifyHeader(
                    user: _spotifyUser,
                    loading: _spotifyLoading,
                    connecting: _spotifyConnecting,
                    onConnect: _runSpotifyAuth,
                    compact: false,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10.0)),
                SliverToBoxAdapter(
                  child: RepaintBoundary(child: StoriesTemplate()),
                ),
                SliverToBoxAdapter(child: SizedBox(height: 10.0)),
                SliverToBoxAdapter(child: SearchIcon()),
                SliverToBoxAdapter(child: SizedBox(height: 25.0)),
                SliverToBoxAdapter(
                  child: RepaintBoundary(child: Inbox()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20.0)),
              ],
            ),
            if (_spotifyConnecting) _spotifyConnectingOverlay(),
          ],
        ),
        bottomNavigationBar: BottomNavBar(
          selectedIndex: 0,
          onTap: (index) => _onTabTapped(context, index),
        ),
      ),
    );
  }

  Widget _spotifyConnectingOverlay() {
    return Positioned.fill(
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            color: Colors.black.withOpacity(0.35),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 20),
                    Text(
                      'Connecting to Spotify…\nComplete login in the browser.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 15,
                        height: 1.4,
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

/// Glass-style header showing Spotify profile or Connect button.
/// [compact] true for use in app bar (smaller chip).
class SpotifyHeader extends StatelessWidget {
  final SpotifyUser? user;
  final bool loading;
  final bool connecting;
  final VoidCallback onConnect;
  final bool compact;

  const SpotifyHeader({
    required this.user,
    required this.loading,
    required this.connecting,
    required this.onConnect,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 32.0 : 40.0;
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    return Padding(
      padding: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 20 : 16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 20 : 16),
              gradient: AppTheme.glassPanelGradient(opacity: 0.40),
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
            child: loading
                ? Row(
                    mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                    children: [
                      SizedBox(
                        width: compact ? 16 : 20,
                        height: compact ? 16 : 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      SizedBox(width: compact ? 8 : 12),
                      Text(
                        compact ? '…' : 'Loading Spotify…',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: compact ? 12 : 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : user != null
                    ? Row(
                        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(size / 2),
                            child: user!.imageUrl != null
                                ? Image.network(
                                    user!.imageUrl!,
                                    width: size,
                                    height: size,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: size,
                                    height: size,
                                    color: Colors.white.withOpacity(0.2),
                                    child: Icon(
                                      Icons.person_rounded,
                                      color: Colors.white.withOpacity(0.8),
                                      size: compact ? 18 : 24,
                                    ),
                                  ),
                          ),
                          SizedBox(width: compact ? 8 : 12),
                          if (!compact)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Spotify',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    user!.displayName.isNotEmpty
                                        ? user!.displayName
                                        : 'Logged in',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Text(
                              user!.displayName.isNotEmpty
                                  ? user!.displayName
                                  : 'Spotify',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          Icon(
                            Icons.check_circle_rounded,
                            color: const Color(0xFF1DB954).withOpacity(0.95),
                            size: compact ? 18 : 22,
                          ),
                        ],
                      )
                    : GestureDetector(
                        onTap: connecting ? null : onConnect,
                        child: Row(
                          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                          children: [
                            Icon(
                              Icons.queue_music_rounded,
                              color: Colors.white.withOpacity(0.7),
                              size: compact ? 22 : 28,
                            ),
                            SizedBox(width: compact ? 6 : 12),
                            Text(
                              compact ? 'Connect' : 'Connect to Spotify',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: compact ? 12 : 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!compact)
                              Icon(
                                Icons.login_rounded,
                                color: Colors.white.withOpacity(0.7),
                                size: 22,
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

/// Content-only home view (no app bar, no Spotify header, no bottom nav).
/// Used inside [main.dart] app shell so the top bar is shared across all pages.
class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({super.key});

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  // ── versus filter ──────────────────────────────────────────────────────────
  String? _versusTypeFilter;

  // ── search state ───────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final SpotifyApi _searchApi = SpotifyApi();
  Timer? _searchDebounce;
  bool _searchLoading = false;
  String _searchLastQuery = '';
  List<_VsSearchResult> _searchResults = [];
  bool _artistMode = true;

  bool get _showResults => _searchLastQuery.isNotEmpty || _searchLoading;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchLastQuery = '';
        _searchLoading = false;
      });
      return;
    }
    setState(() {
      _searchLoading = true;
      _searchLastQuery = q;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (_artistMode) {
        final artists = await _searchApi.searchArtists(q, limit: 14);
        if (!mounted || _searchLastQuery != q) return;
        setState(() {
          _searchResults = artists
              .map((a) => _VsSearchResult(
                    id: a.id,
                    title: a.name,
                    subtitle: 'Artist',
                    imageUrl: a.imageUrl,
                    isArtist: true,
                  ))
              .toList();
          _searchLoading = false;
        });
      } else {
        final albums = await _searchApi.searchAlbums(q, limit: 14);
        if (!mounted || _searchLastQuery != q) return;
        setState(() {
          _searchResults = albums
              .map((a) => _VsSearchResult(
                    id: a.id,
                    title: a.title,
                    subtitle: a.artistName.isEmpty ? 'Album' : a.artistName,
                    imageUrl: a.imageUrl,
                    isArtist: false,
                  ))
              .toList();
          _searchLoading = false;
        });
      }
    });
  }

  void _toggleSearchMode() {
    setState(() {
      _artistMode = !_artistMode;
      _searchResults = [];
      _searchLoading = false;
    });
    if (_searchCtrl.text.trim().isNotEmpty) _onSearchChanged(_searchCtrl.text);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() {
      _searchResults = [];
      _searchLastQuery = '';
      _searchLoading = false;
    });
  }

  void _onSelectResult(_VsSearchResult item) {
    if (item.isArtist) {
      EntityHistorySelectionStore.selectedArtistId = item.id;
      EntityHistorySelectionStore.selectedArtistName = item.title;
    } else {
      EntityHistorySelectionStore.selectedAlbumId = item.id;
      EntityHistorySelectionStore.selectedAlbumTitle = item.title;
    }
    _clearSearch();
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
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 10.0)),
        SliverToBoxAdapter(
          child: RepaintBoundary(child: StoriesTemplate()),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10.0)),
        // ── Inline glass search bar ───────────────────────────────────────
        SliverToBoxAdapter(
          child: _VersusSearchBar(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            loading: _searchLoading,
            artistMode: _artistMode,
            onChanged: _onSearchChanged,
            onToggleMode: _toggleSearchMode,
            onClear: _clearSearch,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10.0)),
        SliverToBoxAdapter(
          child: _InboxFilterRow(
            typeFilter: _versusTypeFilter,
            onFilterChanged: (v) => setState(() => _versusTypeFilter = v),
            createButton: const _CreateButton(),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14.0)),
        // ── Inbox OR search results (in same glass frame) ─────────────────
        SliverToBoxAdapter(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _showResults
                ? _VersusSearchResults(
                    key: const ValueKey('vs-results'),
                    results: _searchResults,
                    loading: _searchLoading,
                    lastQuery: _searchLastQuery,
                    onSelect: _onSelectResult,
                  )
                : RepaintBoundary(
                    key: const ValueKey('vs-inbox'),
                    child: Inbox(typeFilter: _versusTypeFilter),
                  ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20.0)),
      ],
    );
  }
}

/// Filter chips (All | Album | Artist) to the left of the Create button.
class _InboxFilterRow extends StatelessWidget {
  final String? typeFilter;
  final ValueChanged<String?> onFilterChanged;
  final Widget createButton;

  const _InboxFilterRow({
    required this.typeFilter,
    required this.onFilterChanged,
    required this.createButton,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FilterChip(
                    label: 'All',
                    isSelected: typeFilter == null,
                    onTap: () => onFilterChanged(null),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Album',
                    isSelected: typeFilter == 'album',
                    onTap: () => onFilterChanged('album'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Artist',
                    isSelected: typeFilter == 'artist',
                    onTap: () => onFilterChanged('artist'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          createButton,
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isSelected
                ? Colors.white.withOpacity(0.22)
                : Colors.white.withOpacity(0.08),
            border: Border.all(
              color: isSelected
                  ? Colors.white.withOpacity(0.4)
                  : Colors.white.withOpacity(0.18),
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(isSelected ? 0.95 : 0.7),
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Sleek create button between search bar and Inbox — tap shows floating options: AlbumVs / ArtistVs.
class _CreateButton extends StatelessWidget {
  const _CreateButton();

  static const _purple      = AppTheme.gradientStart;
  static const _pink        = AppTheme.gradientEnd;
  static const _createGreen = AppTheme.createGreen;

  void _showCreateOptions(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (context) => _CreateOptionsPopup(
        onAlbumVs: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const Lockeroom()),
          );
        },
        onArtistVs: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ArtistLockeroom()),
          );
        },
        onCollaborateFriend: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CollaboratorLockeroomGate(),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20.0),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showCreateOptions(context),
                  borderRadius: BorderRadius.circular(20.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20.0),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _purple.withOpacity(0.5),
                          _pink.withOpacity(0.4),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'Create',
                      style: TextStyle(
                        color: _createGreen,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
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
}

/// Floating popup with Album VS / Artist VS options — glassy style with glow tiles.
class _CreateOptionsPopup extends StatelessWidget {
  final VoidCallback onAlbumVs;
  final VoidCallback onArtistVs;
  final VoidCallback onCollaborateFriend;

  const _CreateOptionsPopup({
    required this.onAlbumVs,
    required this.onArtistVs,
    required this.onCollaborateFriend,
  });

  static const _purple = AppTheme.gradientStart;
  static const _pink   = AppTheme.gradientEnd;
  static const _green  = AppTheme.createGreen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _purple.withOpacity(0.55),
                  _pink.withOpacity(0.45),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.18),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: _purple.withOpacity(0.35),
                  blurRadius: 40,
                  offset: const Offset(-8, 8),
                ),
                BoxShadow(
                  color: _pink.withOpacity(0.30),
                  blurRadius: 40,
                  offset: const Offset(8, 16),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top accent bar
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    gradient: LinearGradient(
                      colors: [_purple, _pink],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _pink,
                        boxShadow: [
                          BoxShadow(
                            color: _pink.withOpacity(0.8),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'CREATE',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _purple.withOpacity(0.8),
                        boxShadow: [
                          BoxShadow(
                            color: _purple.withOpacity(0.8),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Option tiles
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      _GlowOptionTile(
                        label: 'Album VS',
                        icon: Icons.album_rounded,
                        glowColor: _purple,
                        onTap: onAlbumVs,
                      ),
                      const SizedBox(height: 8),
                      _GlowOptionTile(
                        label: 'Artist VS',
                        icon: Icons.person_rounded,
                        glowColor: _pink,
                        onTap: onArtistVs,
                      ),
                      const SizedBox(height: 8),
                      _GlowOptionTile(
                        label: 'Collaborate',
                        icon: Icons.group_rounded,
                        glowColor: _green,
                        onTap: onCollaborateFriend,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowOptionTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color glowColor;
  final VoidCallback onTap;

  const _GlowOptionTile({
    required this.label,
    required this.icon,
    required this.glowColor,
    required this.onTap,
  });

  @override
  State<_GlowOptionTile> createState() => _GlowOptionTileState();
}

class _GlowOptionTileState extends State<_GlowOptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) => setState(() => _hovered = false),
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _hovered
              ? Colors.white.withOpacity(0.18)
              : Colors.white.withOpacity(0.08),
          border: Border.all(
            color: _hovered
                ? widget.glowColor.withOpacity(0.6)
                : Colors.white.withOpacity(0.10),
            width: 1.0,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: widget.glowColor.withOpacity(0.4),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.glowColor.withOpacity(0.7),
                    widget.glowColor.withOpacity(0.4),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.glowColor.withOpacity(0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                widget.icon,
                color: Colors.white.withOpacity(0.95),
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              widget.label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withOpacity(0.35),
              size: 12,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Inline glass search bar ──────────────────────────────────────────────────

class _VersusSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final bool artistMode;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggleMode;
  final VoidCallback onClear;

  const _VersusSearchBar({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.artistMode,
    required this.onChanged,
    required this.onToggleMode,
    required this.onClear,
  });

  @override
  State<_VersusSearchBar> createState() => _VersusSearchBarState();
}

class _VersusSearchBarState extends State<_VersusSearchBar> {
  bool _focused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    _hasText = widget.controller.text.isNotEmpty;
    widget.focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  void _onTextChange() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText && mounted) setState(() => _hasText = hasText);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(_focused ? 0.16 : 0.12),
                  Colors.white.withOpacity(_focused ? 0.08 : 0.05),
                ],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    onChanged: widget.onChanged,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: AppTheme.gradientEnd,
                    decoration: InputDecoration(
                      hintText: widget.artistMode
                          ? 'Search artists…'
                          : 'Search albums…',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.32),
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      prefixIcon: widget.loading
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
                              color: Colors.white.withOpacity(
                                  _focused ? 0.60 : 0.38),
                              size: 20,
                            ),
                    ),
                  ),
                ),
                // Artist / Album toggle — visible when focused or has text
                if (_focused || _hasText) ...[
                  GestureDetector(
                    onTap: widget.onToggleMode,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white.withOpacity(0.12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.artistMode
                                  ? Icons.person_rounded
                                  : Icons.album_rounded,
                              color: Colors.white.withOpacity(0.80),
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.artistMode ? 'Artist' : 'Album',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                // Clear button — only when text is present
                if (_hasText)
                  GestureDetector(
                    onTap: widget.onClear,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12, left: 4),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withOpacity(0.38),
                        size: 18,
                      ),
                    ),
                  )
                else if (!_focused)
                  const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Data class ───────────────────────────────────────────────────────────────

class _VsSearchResult {
  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final bool isArtist;

  const _VsSearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.isArtist,
  });
}

// ─── Results panel — same glass frame as Inbox ────────────────────────────────

class _VersusSearchResults extends StatelessWidget {
  final List<_VsSearchResult> results;
  final bool loading;
  final String lastQuery;
  final ValueChanged<_VsSearchResult> onSelect;

  const _VersusSearchResults({
    super.key,
    required this.results,
    required this.loading,
    required this.lastQuery,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20.0),
              gradient: AppTheme.glassPanelGradient(),
              border: Border.all(
                color: Colors.white.withOpacity(0.18),
                width: 0.8,
              ),
            ),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (loading && results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(
            color: Colors.white54,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (results.isEmpty && lastQuery.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'No results for "$lastQuery"',
            style: TextStyle(
              color: Colors.white.withOpacity(0.40),
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: results.length,
      separatorBuilder: (_, __) => Divider(
        height: 0,
        indent: 16,
        endIndent: 16,
        color: Colors.white.withOpacity(0.08),
      ),
      itemBuilder: (_, i) {
        final item = results[i];
        return GestureDetector(
          onTap: () => onSelect(item),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                _ResultThumb(item: item),
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
                  color: Colors.white.withOpacity(0.20),
                  size: 16,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResultThumb extends StatelessWidget {
  const _ResultThumb({required this.item});
  final _VsSearchResult item;

  @override
  Widget build(BuildContext context) {
    final br = item.isArtist
        ? BorderRadius.circular(99)
        : BorderRadius.circular(8);
    final hasImg = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: br,
      child: hasImg
          ? Image.network(
              item.imageUrl!,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() {
    return Container(
      width: 44,
      height: 44,
      color: AppTheme.gradientStart.withOpacity(0.25),
      child: Icon(
        item.isArtist ? Icons.person_rounded : Icons.album_rounded,
        color: Colors.white.withOpacity(0.50),
        size: 20,
      ),
    );
  }
}
