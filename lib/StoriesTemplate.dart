import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';

const _kBlue = Color(0xFF1E3DE1);
const _kPink = Color(0xFFf85187);
const _kGreen = Color.fromARGB(255, 30, 222, 37);

/// Horizontal friends-strip shown at the top of the home feed.
/// Streams the current user's document so the list stays live —
/// any friend added in the Find Friends tab appears here instantly
/// without a manual refresh.
class StoriesTemplate extends StatelessWidget {
  const StoriesTemplate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserModel?>(
      stream: FirebaseService.getCurrentUserStream(),
      builder: (context, snapshot) {
        final friends = snapshot.data?.friends ?? const <FriendEntry>[];
        final loading = snapshot.connectionState == ConnectionState.waiting;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                height: 145,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _kBlue.withOpacity(0.40),
                      _kPink.withOpacity(0.40),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      spreadRadius: 0,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: loading
                    ? _buildLoading()
                    : friends.isEmpty
                        ? _buildEmpty()
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: friends.length,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            itemBuilder: (context, index) =>
                                _FriendBubble(friend: friends[index]),
                          ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoading() {
    return Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white.withOpacity(0.45),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 28,
            color: Colors.white.withOpacity(0.25),
          ),
          const SizedBox(height: 6),
          Text(
            'Find friends to see them here',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single friend bubble ──────────────────────────────────────────────────────
class _FriendBubble extends StatelessWidget {
  final FriendEntry friend;

  const _FriendBubble({required this.friend});

  static String? _assetPath(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('assets/')) return p;
    if (p.startsWith('/')) return p.substring(1);
    return 'assets/images/$p';
  }

  @override
  Widget build(BuildContext context) {
    final path = _assetPath(friend.avatarPath);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Avatar circle ──────────────────────────────────────────────
            ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  height: 72,
                  width: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 12,
                        spreadRadius: 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: path != null
                      ? Image.asset(
                          path,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackAvatar(),
                        )
                      : _fallbackAvatar(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // ── Username label ─────────────────────────────────────────────
            Text(
              friend.username.isNotEmpty ? friend.username : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kGreen,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackAvatar() => Container(
        color: _kBlue.withOpacity(0.35),
        child: Icon(
          Icons.person_rounded,
          color: Colors.white.withOpacity(0.6),
          size: 32,
        ),
      );
}
