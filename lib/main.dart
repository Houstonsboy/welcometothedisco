import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'package:welcometothedisco/firebase_options.dart';
import 'package:welcometothedisco/config/app_config.dart';
import 'package:welcometothedisco/authentication/login.dart';
import 'package:welcometothedisco/authentication/onboarding.dart';
import 'package:welcometothedisco/features/splash/splash_screen.dart';
import 'package:welcometothedisco/HomeScreen.dart';
import 'package:welcometothedisco/Inbox.dart';
import 'package:welcometothedisco/SpotifyAPIplayer.dart';
import 'package:welcometothedisco/BottomNavBar.dart';
import 'package:welcometothedisco/friends/friendrequest.dart';
import 'package:welcometothedisco/userprofile.dart';
import 'package:welcometothedisco/notification/notification.dart';
import 'package:welcometothedisco/services/spotify_auth.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/notification/notification_service.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/theme/app_theme.dart';
import 'package:welcometothedisco/posts/view_posts.dart';
import 'package:welcometothedisco/posts/post_view.dart';
import 'package:welcometothedisco/versus/playground.dart';
import 'package:welcometothedisco/versus/artistplayground.dart';
import 'package:welcometothedisco/versus/collaboratorbackroom.dart';

/// Lets notification tap handling push screens without a BuildContext of its
/// own — set as the MaterialApp's navigatorKey below.
final navigatorKey = GlobalKey<NavigatorState>();

/// Token exchange for a Spotify login redirect that cold-started the app (the
/// process was killed while the user was in the browser). The app shell awaits
/// it before checking for Spotify tokens, so it doesn't start a second login
/// while this one is still completing.
Future<void>? spotifyColdStartExchange;

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Keep native splash visible until SplashScreen.initState() calls remove().
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  NotificationService.onNotificationTap = _handleNotificationTap;
  spotifyColdStartExchange = _handleSpotifyColdStartLink();

  // Nothing network-bound or user-facing may gate the first frame: a Firestore
  // write only completes on server ack (so offline it never would), and the
  // notification permission prompt waits on the user. Both run after this.
  runApp(const MyApp());
  unawaited(NotificationService.initialize());
}

Future<void> _handleSpotifyColdStartLink() async {
  try {
    final initialUri = await AppLinks().getInitialLink();
    if (initialUri == null ||
        !initialUri.toString().startsWith(AppConfig.spotifyRedirectUri)) {
      return;
    }
    debugPrint('[main] Cold-start Spotify redirect');
    final handled = await SpotifyAuth().handleCallbackUri(initialUri.toString());
    debugPrint('[main] handleCallbackUri result: $handled');
  } catch (e) {
    debugPrint('[main] cold-start Spotify redirect failed: $e');
  }
}

/// A tapped notification waits here until the signed-in app shell is on
/// screen. Taps that arrive earlier (cold-start launch, splash, login) would
/// otherwise be dropped, or pushed underneath the splash/login routes.
Map<String, dynamic>? _pendingNotificationTap;
bool _shellReady = false;

void _flushPendingNotificationTap() {
  final data = _pendingNotificationTap;
  _pendingNotificationTap = null;
  if (data != null) _handleNotificationTap(data);
}

/// Routes a tapped push notification (foreground banner, background tap, or
/// cold-start launch) to the right screen based on its `data` payload.
void _handleNotificationTap(Map<String, dynamic> data) {
  final navigator = navigatorKey.currentState;
  if (!_shellReady || navigator == null) {
    _pendingNotificationTap = data;
    return;
  }

  final type = data['type'] as String?;
  final id = data['id'] as String?;
  if (id == null || id.isEmpty) return;

  switch (type) {
    case 'follow':
      navigator.push(
        MaterialPageRoute(builder: (_) => const NotificationsPage()),
      );
      break;
    case 'invite':
      navigator.push(
        MaterialPageRoute(builder: (_) => CollaboratorBackroom(versusID: id)),
      );
      break;
    case 'versus':
      _openVersusFromNotification(navigator, id, data['versusType'] as String?);
      break;
    case 'post':
    case 'mention':
      _openPostFromNotification(navigator, id);
      break;
  }
}

Future<void> _openVersusFromNotification(
  NavigatorState navigator,
  String versusId,
  String? versusType,
) async {
  if (versusType == 'artist') {
    final model = await FirebaseService.getArtistVersusById(versusId);
    if (model == null) return;
    navigator.push(MaterialPageRoute(
      builder: (_) => ArtistVersusPlayground(versus: model, versusId: versusId),
    ));
    return;
  }

  final model = await FirebaseService.getAlbumVersusById(versusId);
  if (model == null) return;
  navigator.push(MaterialPageRoute(
    builder: (_) => VersusPlayground(versus: model, versusId: versusId),
  ));
}

Future<void> _openPostFromNotification(
  NavigatorState navigator,
  String postId,
) async {
  final post = await FirebaseService.getPostStream(postId).first;
  if (post == null) return;
  navigator.push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.appTheme(),
      initialRoute: '/splash',
      navigatorObservers: [inboxRouteObserver],
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/': (_) => const AuthGate(),
        '/onboarding': (_) => const OnboardingScreen(),
        '/spotify': (_) => const SpotifyAPIplayer(),
      },
    );
  }
}

/// Shows loading, then app shell (with top bar) if logged in, else LoginScreen.
///
/// Uses a StatefulWidget + manual stream subscription so that:
///   (a) currentUser is checked synchronously on initState — meaning a
///       Navigator.pushNamedAndRemoveUntil('/') from the login screen
///       immediately finds the already-signed-in user without waiting for the
///       stream to emit.
///   (b) Future sign-in/sign-out events (authStateChanges) still update the UI.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  User? _user;
  bool _initializing = true;
  late final StreamSubscription<User?> _authSub;

  @override
  void initState() {
    super.initState();
    // Synchronous read — available immediately after signInWithCredential.
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      _user = current;
      _initializing = false;
    }
    // Stream handles the current user (it emits immediately on listen) and
    // future sign-in / sign-out events.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) {
        setState(() {
          _user = user;
          _initializing = false;
        });
      }
      if (user != null) {
        unawaited(FirebaseService.ensureCurrentUserProfileCached());
        unawaited(NotificationService.saveTokenForUser(user.uid));
        NotificationService.startBadgeSync();
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _user != null ? const _AppShell() : const LoginScreen();
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

  bool _spotifyConnecting = false;
  int _selectedIndex = 0;
  DateTime? _lastBackExitPrompt;
  bool _exitHintVisible = false;
  Timer? _exitHintTimer;

  // Posts tab (index 0) is the first screen after login and loads eagerly;
  // Home/Friends only start building once the user actually visits them, so
  // their initial fetches (Spotify profile, open-versus inbox query) don't
  // compete with the posts feed load right after sign-in.
  final Set<int> _mountedTabs = {0};

  @override
  void initState() {
    super.initState();
    _shellReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushPendingNotificationTap();
      // Signed in and on screen: the earliest point the OS permission prompt
      // makes sense (and on iOS, the device token only exists after it).
      unawaited(NotificationService.requestPermissionAndSaveToken());
    });
    _initSpotify();
  }

  @override
  void dispose() {
    _shellReady = false;
    _exitHintTimer?.cancel();
    super.dispose();
  }

  Future<void> _initSpotify() async {
    await spotifyColdStartExchange;
    final hasTokens = await TokenStorageService.hasSpotifyTokens();
    if (hasTokens) {
      await _loadSpotifyProfile();
    } else {
      await _runSpotifyAuth();
    }
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
    // Warms the token/profile cache; the result isn't shown by this widget.
    await _spotifyApi.getCurrentUser();
  }

  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _mountedTabs.add(index);
    });
  }

  /// System back: pop any overlay route first; then leave search/friends for home;
  /// on home, require a second back within 2s to exit (Android-style).
  void _onShellPopInvoked(bool didPop, dynamic result) {
    if (didPop) return;

    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
      return;
    }

    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
      _lastBackExitPrompt = null;
      return;
    }

    final now = DateTime.now();
    final last = _lastBackExitPrompt;
    if (last == null || now.difference(last) > const Duration(seconds: 2)) {
      _lastBackExitPrompt = now;
      _showGlassExitHint();
      return;
    }

    SystemNavigator.pop();
  }

  void _showGlassExitHint() {
    _exitHintTimer?.cancel();
    setState(() => _exitHintVisible = true);
    _exitHintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _exitHintVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onShellPopInvoked,
      child: Container(
        decoration: AppTheme.backgroundDecoration,
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
                    fontSize: 11.0,
                    fontFamily: AppTheme.fontHeader,
                    color: Color(0xFF17B5EE),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _NotificationBell(),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const UserProfilePage(),
                            ),
                          ),
                          child: _FirebaseHeader(compact: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              body: IndexedStack(
                index: _selectedIndex,
                children: [
                  const ViewPostsScreen(),
                  _mountedTabs.contains(1)
                      ? const HomeScreenContent()
                      : const SizedBox.shrink(),
                  _mountedTabs.contains(2)
                      ? const FriendRequest()
                      : const SizedBox.shrink(),
                ],
              ),
              bottomNavigationBar: BottomNavBar(
                selectedIndex: _selectedIndex,
                onTap: _onTabTapped,
              ),
            ),
            _GlassExitHintOverlay(visible: _exitHintVisible),
            if (_spotifyConnecting) _spotifyConnectingOverlay(),
          ],
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
            color: Colors.black.withValues(alpha: 0.35),
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
                        color: Colors.white.withValues(alpha: 0.95),
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

/// Small glass pill above the bottom nav — double-back exit hint.
class _GlassExitHintOverlay extends StatelessWidget {
  final bool visible;

  const _GlassExitHintOverlay({required this.visible});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // BottomNavBar: SafeArea + ~18 bottom padding + ~68 bar height + gap.
    final lift = bottomInset + 96;

    return Positioned.fill(
      child: IgnorePointer(
        // Visual-only popup — must not steal taps from the shell beneath.
        ignoring: true,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            // Clip scaled fade so transforms cannot paint past chip bounds (avoids
            // stray overflow stripes below the banner during animation).
            return ClipRect(
              child: FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  alignment: Alignment.bottomCenter,
                  scale: Tween<double>(begin: 0.92, end: 1).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              ),
            );
          },
          child: visible
              ? Align(
                  key: const ValueKey('exit-hint-on'),
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(40, 0, 40, lift),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          clipBehavior: Clip.antiAlias,
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                gradient:
                                    AppTheme.glassNavGradient(opacity: 0.38),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  width: 0.85,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.22),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: SizedBox(
                                  height: 20,
                                  child: ClipRect(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.arrow_back_ios_new_rounded,
                                          size: 13,
                                          color: Colors.white
                                              .withValues(alpha: 0.72),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Press back again to exit',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
                                            textHeightBehavior:
                                                const TextHeightBehavior(
                                              applyHeightToFirstAscent: false,
                                              applyHeightToLastDescent: false,
                                              leadingDistribution:
                                                  TextLeadingDistribution
                                                      .proportional,
                                            ),
                                            strutStyle: StrutStyle(
                                              fontFamily: AppTheme.fontBody,
                                              fontSize: 12.5,
                                              height: 1.0,
                                              fontWeight: FontWeight.w600,
                                              forceStrutHeight: true,
                                              leading: 0,
                                            ),
                                            style: TextStyle(
                                              fontFamily: AppTheme.fontBody,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.12,
                                              height: 1.0,
                                              color: Colors.white
                                                  .withValues(alpha: 0.92),
                                            ),
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
                      },
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('exit-hint-off')),
        ),
      ),
    );
  }
}

// ── Bell icon that shows a pink dot when there are unread follow notifications ─
class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsPage()),
      ),
      child: StreamBuilder<bool>(
        stream: FirebaseService.hasUnreadNotificationsStream(),
        builder: (context, snapshot) {
          final hasUnread = snapshot.data ?? false;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                hasUnread
                    ? Icons.notifications_rounded
                    : Icons.notifications_outlined,
                color: Colors.white.withValues(alpha: hasUnread ? 1.0 : 0.65),
                size: 24,
              ),
              if (hasUnread)
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: AppTheme.gradientEnd,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          );
        },
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
            : (FirebaseAuth.instance.currentUser?.displayName
                        ?.trim()
                        .isNotEmpty ??
                    false)
                ? FirebaseAuth.instance.currentUser!.displayName!.trim()
                : 'Profile';
        final subtitle =
            FirebaseAuth.instance.currentUser?.email ?? 'Logged in';
        final assetPath = _assetPathFromAvatar(user?.avatarPath ?? '');

        return Padding(
          padding: compact
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: snapshot.connectionState == ConnectionState.waiting
                    ? Row(
                        mainAxisSize:
                            compact ? MainAxisSize.min : MainAxisSize.max,
                        children: [
                          SizedBox(
                            width: compact ? 16 : 20,
                            height: compact ? 16 : 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          SizedBox(width: compact ? 8 : 12),
                          Text(
                            compact ? '…' : 'Loading profile…',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: compact ? 12 : 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize:
                            compact ? MainAxisSize.min : MainAxisSize.max,
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
                                    color: Colors.white.withValues(alpha: 0.2),
                                    child: Icon(
                                      Icons.person_rounded,
                                      color: Colors.white.withValues(alpha: 0.8),
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
                                      color: Colors.white.withValues(alpha: 0.6),
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
                                  color: Colors.white.withValues(alpha: 0.62),
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
