import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/InboxedSongs.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/spotify_api.dart';

class Inbox extends StatefulWidget {
  const Inbox({super.key});

  @override
  State<Inbox> createState() => _InboxState();
}

class _InboxState extends State<Inbox> {
  late final Future<List<VersusModel>> _versusFuture;
  final SpotifyApi _spotifyApi = SpotifyApi();

  @override
  void initState() {
    super.initState();
    _versusFuture = _loadVersusWithSpotify();
  }

  Future<List<VersusModel>> _loadVersusWithSpotify() async {
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
                    child: Text(
                      'Could not load versus albums right now.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
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
