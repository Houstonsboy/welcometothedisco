import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:app_links/app_links.dart';

import 'package:welcometothedisco/firebase_options.dart';
import 'package:welcometothedisco/config/app_config.dart';
import 'package:welcometothedisco/authentication/login.dart';
import 'package:welcometothedisco/HomeScreen.dart';
import 'package:welcometothedisco/Inbox.dart';
import 'package:welcometothedisco/SpotifyAPIplayer.dart';
import 'package:welcometothedisco/BottomNavBar.dart';
import 'package:welcometothedisco/friends/friendrequest.dart';
import 'package:welcometothedisco/dev.dart';
import 'package:welcometothedisco/services/spotify_auth.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/models/users_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Cold-start: app opened by Spotify redirect URI.
  final appLinks = AppLinks();
  Uri? initialUri;
  try {
    initialUri = await appLinks.getInitialLink();
  } catch (_) {}

  if (initialUri != null &&
      initialUri.toString().startsWith(AppConfig.spotifyRedirectUri)) {
    debugPrint('[main] Cold-start deep link: $initialUri');
    final auth = SpotifyAuth();
    final handled = await auth.handleCallbackUri(initialUri.toString());
    debugPrint('[main] handleCallbackUri result: $handled');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      navigatorObservers: [inboxRouteObserver],
      routes: {
        '/': (_) => const _AuthGate(),
        '/spotify': (_) => const SpotifyAPIplayer(),
      },
    );
  }
}

/// Shows loading, then app shell (with top bar) if logged in, else LoginScreen.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const _AppShell();
        }
        return const LoginScreen();
      },
    );
  }
}

/// App shell: gradient, top bar ("Welcome to the Disco" + Spotify profile), body pages, bottom nav.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final SpotifyAuth _spotifyAuth = SpotifyAuth();
  final SpotifyApi _spotifyApi = SpotifyApi();

  SpotifyUser? _spotifyUser;
  bool _spotifyLoading = true;
  bool _spotifyConnecting = false;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _initSpotify();
  }

  Future<void> _initSpotify() async {
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

  void _onTabTapped(int index) {
    setState(() => _selectedIndex = index);
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
      child: Stack(
        children: [
          Scaffold(
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
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _FirebaseHeader(compact: true),
                ),
              ],
            ),
            body: IndexedStack(
              index: _selectedIndex,
              children: const [
                HomeScreenContent(),
                SpotifyAPIplayer(embedded: true),
                FriendRequest(),
                DevPage(),
              ],
            ),
            bottomNavigationBar: BottomNavBar(
              selectedIndex: _selectedIndex,
              onTap: _onTabTapped,
            ),
          ),
          if (_spotifyConnecting) _spotifyConnectingOverlay(),
        ],
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

/// Placeholder for nav tabs that haven't been built yet.
class _ComingSoonPage extends StatelessWidget {
  const _ComingSoonPage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sports_mma_rounded,
            size: 52,
            color: Colors.white.withOpacity(0.18),
          ),
          const SizedBox(height: 14),
          Text(
            'COMING SOON',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Glass-style header showing Firebase user profile from users collection.
/// Uses avatar_path as local asset filename from assets/images/.
class _FirebaseHeader extends StatelessWidget {
  final bool compact;

  const _FirebaseHeader({this.compact = false});

  String? _assetPathFromAvatar(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('assets/')) return p;
    if (p.startsWith('/')) return p.substring(1);
    return 'assets/images/$p';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final size = compact ? 32.0 : 40.0;
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);

    return FutureBuilder<UserModel?>(
      future: FirebaseService.getCurrentUser(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final displayName = (user?.username.trim().isNotEmpty ?? false)
            ? user!.username.trim()
            : (FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty ?? false)
                ? FirebaseAuth.instance.currentUser!.displayName!.trim()
                : 'Profile';
        final subtitle = (user?.email.trim().isNotEmpty ?? false)
            ? user!.email.trim()
            : (FirebaseAuth.instance.currentUser?.email ?? 'Logged in');
        final assetPath = _assetPathFromAvatar(user?.avatarPath ?? '');

        return Padding(
          padding:
              compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
                child: snapshot.connectionState == ConnectionState.waiting
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
                            compact ? '…' : 'Loading profile…',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: compact ? 12 : 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(size / 2),
                            child: assetPath != null
                                ? Image.asset(
                                    assetPath,
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
                                    'Account',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    displayName,
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
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (!compact)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.62),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
