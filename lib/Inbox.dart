import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/InboxedSongs.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/services/spotify_auth.dart';
import 'package:welcometothedisco/services/token_storage_service.dart';

class Inbox extends StatefulWidget {
  const Inbox({super.key});

  @override
  State<Inbox> createState() => _InboxState();
}

class _InboxState extends State<Inbox> with RouteAware {
  final SpotifyApi _spotifyApi = SpotifyApi();
  final SpotifyAuth _spotifyAuth = SpotifyAuth();

  Future<List<VersusModel>>? _versusFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to the route so we know when we come back to this page.
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      inboxRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    inboxRouteObserver.unsubscribe(this);
    super.dispose();
  }

  // Called by RouteAware when a pushed route is popped and this page re-appears.
  @override
  void didPopNext() {
    _refresh();
  }

  // ── Token check + data load ────────────────────────────────────────────────
  void _refresh() {
    setState(() {
      _versusFuture = _loadWithTokenRefresh();
    });
  }

  Future<List<VersusModel>> _loadWithTokenRefresh() async {
    // Ensure Spotify token is valid; silently re-auth if missing.
    final hasToken = await TokenStorageService.hasSpotifyTokens();
    if (!hasToken) {
      try {
        debugPrint('[Inbox] No Spotify token — attempting silent re-auth');
        await _spotifyAuth.login();
      } catch (e) {
        debugPrint('[Inbox] Silent re-auth failed: $e');
      }
    }

    // Pull a fresh access token (auto-refreshes if expired).
    await TokenStorageService.getAccessToken();

    // Fetch versus list from Firestore.
    try {
      final List<VersusModel> versus = await FirebaseService.getVersusList();
      try {
        return await _spotifyApi.enrichVersusList(versus);
      } catch (e) {
        debugPrint('[Inbox] Spotify enrichment failed, showing Firestore data: $e');
        return versus;
      }
    } catch (e) {
      debugPrint('[Inbox] Failed to load versus list: $e');
      rethrow;
    }
  }

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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1E3DE1).withOpacity(0.45),
                  const Color(0xFFf85187).withOpacity(0.45),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.18),
                width: 0.8,
              ),
            ),
            child: FutureBuilder<List<VersusModel>>(
              future: _versusFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Could not load versus albums right now.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _refresh,
                          child: Text(
                            'Tap to retry',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final versus = snapshot.data ?? [];
                if (versus.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'No versus entries yet.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: versus.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 0,
                    indent: 16,
                    endIndent: 16,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  itemBuilder: (context, index) {
                    return InboxedSongs(versus: versus[index]);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Global RouteObserver that Inbox subscribes to so it refreshes when
/// the user navigates back to the home screen from any pushed route.
final RouteObserver<PageRoute> inboxRouteObserver = RouteObserver<PageRoute>();
