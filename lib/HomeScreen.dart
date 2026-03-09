import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/BottomNavBar.dart';
import 'package:welcometothedisco/Inbox.dart';
import 'package:welcometothedisco/Searchicon.dart';
import 'package:welcometothedisco/StoriesTemplate.dart';
import 'package:welcometothedisco/services/spotify_auth.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';
import 'package:welcometothedisco/versus/lockeroom.dart';

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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3DE1), Color(0xFFf85187)],
        ),
      ),
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
              color: Color.fromARGB(255, 159, 181, 63),
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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1E3DE1).withOpacity(0.40),
                  const Color(0xFFf85187).withOpacity(0.40),
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
class HomeScreenContent extends StatelessWidget {
  const HomeScreenContent({super.key});

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
        SliverToBoxAdapter(child: SizedBox(height: 10.0)),
        SliverToBoxAdapter(child: SearchIcon()),
        const SliverToBoxAdapter(child: SizedBox(height: 10.0)),
        SliverToBoxAdapter(
          child: _CreateButton(),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 14.0)),
        SliverToBoxAdapter(
          child: RepaintBoundary(child: Inbox()),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20.0)),
      ],
    );
  }
}

/// Sleek create button between search bar and Inbox — purple theme, compact.
class _CreateButton extends StatelessWidget {
  const _CreateButton();

  static const _purple = Color(0xFF1E3DE1);
  static const _pink = Color(0xFFf85187);
  /// Same green as Stories.dart username text.
  static const _createGreen = Color.fromARGB(255, 30, 222, 37);

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
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const Lockeroom()),
                    );
                  },
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
