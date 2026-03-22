import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';

const _kPurple = Color(0xFF1E3DE1);
const _kPink = Color(0xFFf85187);

// ── Data model ────────────────────────────────────────────────────────────────

class FollowNotification {
  final String id;
  final String followerID;
  final String followerUsername;
  final String followerAvatar;
  final String followerBio;
  final DateTime? timestamp;
  final bool read;

  const FollowNotification({
    required this.id,
    required this.followerID,
    required this.followerUsername,
    required this.followerAvatar,
    required this.followerBio,
    this.timestamp,
    required this.read,
  });

  factory FollowNotification.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return FollowNotification(
      id: doc.id,
      followerID: d['followerID'] as String? ?? '',
      followerUsername: d['follower_username'] as String? ?? '',
      followerAvatar: d['follower_avatar'] as String? ?? '',
      followerBio: d['follower_bio'] as String? ?? '',
      timestamp: (d['timestamp'] as Timestamp?)?.toDate(),
      read: d['read'] as bool? ?? false,
    );
  }
}

// ── Page ──────────────────────────────────────────────────────────────────────

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  StreamSubscription<UserModel?>? _userSub;

  List<FollowNotification> _notifications = [];
  Set<String> _followedUids = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _notifSub = FirebaseService.getNotificationsStream().listen((snap) {
      if (!mounted) return;
      setState(() {
        _notifications =
            snap.docs.map((d) => FollowNotification.fromDoc(d)).toList();
        _loading = false;
      });
    });

    _userSub = FirebaseService.getCurrentUserStream().listen((user) {
      if (!mounted) return;
      final ids = user?.friends.map((f) => f.uid).toSet() ?? {};
      if (ids.length != _followedUids.length ||
          !ids.every(_followedUids.contains)) {
        setState(() => _followedUids = ids);
      }
    });

    // Mark all notifications as read when this page is opened.
    FirebaseService.markAllNotificationsRead();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }

  static String? _assetPath(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('assets/')) return p;
    if (p.startsWith('/')) return p.substring(1);
    return 'assets/images/$p';
  }

  int get _unreadCount => _notifications.where((n) => !n.read).length;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPurple, _kPink],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'NOTIFICATIONS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.5,
            ),
          ),
          actions: [
            if (_unreadCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '$_unreadCount new',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.notifications_off_outlined,
                color: Colors.white.withOpacity(0.5),
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No notifications yet',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'When someone follows you, they\'ll appear here',
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          physics: const BouncingScrollPhysics(),
          itemCount: _notifications.length,
          separatorBuilder: (_, __) => Divider(
            height: 0,
            indent: 72,
            color: Colors.white.withOpacity(0.08),
          ),
          itemBuilder: (context, i) {
            final n = _notifications[i];
            return _NotificationRow(
              key: ValueKey(n.id),
              notification: n,
              assetPath: _assetPath(n.followerAvatar),
              isFollowing: _followedUids.contains(n.followerID),
              onFollowBack: () => FirebaseService.addFriend(
                friendUid: n.followerID,
                friendUsername: n.followerUsername,
                friendAvatarPath: n.followerAvatar,
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Notification row ──────────────────────────────────────────────────────────

class _NotificationRow extends StatefulWidget {
  final FollowNotification notification;
  final String? assetPath;
  final bool isFollowing;
  final Future<void> Function() onFollowBack;

  const _NotificationRow({
    super.key,
    required this.notification,
    required this.isFollowing,
    required this.onFollowBack,
    this.assetPath,
  });

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _added = false;
  bool _loading = false;

  bool get _isFollowing => widget.isFollowing || _added;

  Future<void> _handleFollowBack() async {
    if (_isFollowing || _loading) return;
    setState(() => _loading = true);
    try {
      await widget.onFollowBack();
      if (mounted) setState(() => _added = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not follow back: $e',
              style: const TextStyle(fontSize: 13)),
          backgroundColor: _kPink.withOpacity(0.85),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    final isUnread = !n.read;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Avatar ──────────────────────────────────────────────────────
          _NotifAvatar(assetPath: widget.assetPath, isUnread: isUnread),
          const SizedBox(width: 12),

          // ── Info ─────────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        n.followerUsername.isNotEmpty
                            ? n.followerUsername
                            : 'Unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    if (isUnread) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: _kPink,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                if (n.followerBio.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    n.followerBio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.42),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  'started following you · ${_formatTime(n.timestamp)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.32),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // ── Follow back button ────────────────────────────────────────────
          GestureDetector(
            onTap: _handleFollowBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: _isFollowing
                    ? const LinearGradient(
                        colors: [_kPurple, _kPink],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: _isFollowing || _loading
                    ? null
                    : Colors.white.withOpacity(0.15),
                border: Border.all(
                  color: _isFollowing
                      ? Colors.transparent
                      : Colors.white.withOpacity(0.3),
                  width: 0.8,
                ),
                boxShadow: _isFollowing
                    ? [
                        BoxShadow(
                          color: _kPink.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : [],
              ),
              child: _loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: Colors.white.withOpacity(0.65),
                      ),
                    )
                  : Text(
                      _isFollowing ? 'Following' : 'Follow Back',
                      style: TextStyle(
                        color: Colors.white
                            .withOpacity(_isFollowing ? 1.0 : 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _NotifAvatar extends StatelessWidget {
  final String? assetPath;
  final bool isUnread;

  const _NotifAvatar({this.assetPath, required this.isUnread});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isUnread
            ? const LinearGradient(
                colors: [_kPurple, _kPink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isUnread ? null : Colors.white.withOpacity(0.15),
        border: isUnread
            ? null
            : Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(isUnread ? 2.5 : 0),
        child: CircleAvatar(
          backgroundColor: Colors.white.withOpacity(0.1),
          backgroundImage:
              assetPath != null ? AssetImage(assetPath!) : null,
          child: assetPath == null
              ? Icon(Icons.person_rounded,
                  color: Colors.white.withOpacity(0.6), size: 28)
              : null,
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatTime(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${(diff.inDays / 7).floor()}w ago';
}
