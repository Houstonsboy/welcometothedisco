import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:welcometothedisco/HomeScreen.dart';
import 'package:welcometothedisco/SpotifyAPIplayer.dart';
import 'package:welcometothedisco/services/spotify_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cold-start case: app was opened by the Spotify redirect URI.
  // The app_links stream won't fire for this — only getInitialLink() does.
  // login() handles the live-app case via its own uriLinkStream subscription.
  final appLinks = AppLinks();
  Uri? initialUri;
  try {
    initialUri = await appLinks.getInitialLink();
  } catch (_) {}

  if (initialUri != null &&
      initialUri.toString().startsWith('welcometothedisco://callback')) {
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
        '/': (_) => const HomeScreen(),
        '/spotify': (_) => const SpotifyAPIplayer(),
      },
    );
  }
}
