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
import 'package:welcometothedisco/SpotifyAPIplayer.dart';
import 'package:welcometothedisco/BottomNavBar.dart';
import 'package:welcometothedisco/services/spotify_auth.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';

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
                  child: SpotifyHeader(
                    user: _spotifyUser,
                    loading: _spotifyLoading,
                    connecting: _spotifyConnecting,
                    onConnect: _runSpotifyAuth,
                    compact: true,
                  ),
                ),
              ],
            ),
            body: IndexedStack(
              index: _selectedIndex,
              children: const [
                HomeScreenContent(),
                SpotifyAPIplayer(embedded: true),
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
