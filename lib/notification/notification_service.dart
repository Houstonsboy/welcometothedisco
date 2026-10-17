import 'dart:async';
import 'dart:convert';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Top-level handler required by FCM for background messages.
// Must be a top-level function (not a class method).
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  debugPrint('[FCM background] ${message.notification?.title} — ${message.data}');
}

class NotificationService {
  static final FirebaseMessaging  _fcm       = FirebaseMessaging.instance;
  static final FirebaseFirestore  _db        = FirebaseFirestore.instance;
  static final FirebaseFunctions  _functions = FirebaseFunctions.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'high_importance_channel',
    'Notifications',
    description: 'Friend activity: follows, invites, posts, and versus battles.',
    importance: Importance.high,
  );

  /// Set by main.dart to a function that routes a tapped notification's
  /// `data` payload to the right screen via a global navigatorKey — this
  /// service has no BuildContext of its own.
  static void Function(Map<String, dynamic> data)? onNotificationTap;

  // ── Initialise ────────────────────────────────────────────────────────────
  /// Call once from main() after Firebase.initializeApp().
  /// Requests permission, saves the device token, and wires message handlers.
  static Future<void> initialize() async {
    // Register the background handler before anything else.
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    await _initLocalNotifications();

    // Request permission (iOS prompts the user; Android 13+ also needs this).
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] permission: ${settings.authorizationStatus}');

    // Persist token for the current user if already signed in.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await saveTokenForUser(uid);
      startBadgeSync();
    }

    // Refresh token whenever FCM rotates it.
    _fcm.onTokenRefresh.listen((token) async {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        await _storeToken(currentUid, token);
      }
    });

    // Foreground message handler — FCM only auto-shows a banner when the app
    // is backgrounded/terminated, so show one ourselves while it's open.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM foreground] ${message.notification?.title}');
      _showLocalNotification(message);
    });

    // Notification tap when app was in background.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM opened] ${message.data}');
      _handleNotificationTap(message.data);
    });

    // Notification tap that launched the app from terminated state.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      debugPrint('[FCM launch] ${initial.data}');
      _handleNotificationTap(initial.data);
    }
  }

  // ── Local notification display (foreground FCM banners) ────────────────────
  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      // FCM's requestPermission() above already asks for alert/badge/sound.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  // Tap on a local banner shown while the app was in the foreground.
  @pragma('vm:entry-point')
  static void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _handleNotificationTap(data);
    } catch (e) {
      debugPrint('[FCM] failed to decode local notification payload: $e');
    }
  }

  static void _handleNotificationTap(Map<String, dynamic> data) {
    onNotificationTap?.call(data);
  }

  // ── Token management ──────────────────────────────────────────────────────
  /// Fetch the current device token and save it to Firestore.
  /// Call after sign-in and after sign-up.
  static Future<void> saveTokenForUser(String uid) async {
    final token = await _fcm.getToken();
    if (token == null || uid.isEmpty) return;
    await _storeToken(uid, token);
  }

  static Future<void> _storeToken(String uid, String token) async {
    await _db.collection('users').doc(uid).set(
      {'fcm_token': token},
      SetOptions(merge: true),
    );
    debugPrint('[FCM] token saved for $uid');
  }

  /// Clear the token on sign-out so the user stops receiving notifications
  /// on this device.
  static Future<void> clearTokenForUser(String uid) async {
    if (uid.isEmpty) return;
    await _db.collection('users').doc(uid).update({'fcm_token': FieldValue.delete()});
    await _fcm.deleteToken();
    stopBadgeSync();
    debugPrint('[FCM] token cleared for $uid');
  }

  // ── OS app-icon badge ─────────────────────────────────────────────────────
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _badgeSub;

  /// Keeps the app-icon badge in sync with the signed-in user's unread
  /// notification count for as long as the app process is alive. Call on
  /// sign-in (also called from initialize() if already signed in).
  static void startBadgeSync() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _badgeSub?.cancel();
    _badgeSub = _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) => _updateBadge(snap.docs.length));
  }

  /// Call on sign-out so the badge doesn't keep showing the previous user's
  /// unread count.
  static void stopBadgeSync() {
    _badgeSub?.cancel();
    _badgeSub = null;
    _updateBadge(0);
  }

  static Future<void> _updateBadge(int count) async {
    try {
      if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(count);
      }
    } catch (e) {
      debugPrint('[FCM] badge update failed: $e');
    }
  }

  // ── Friend token lookup ───────────────────────────────────────────────────
  /// Returns the FCM tokens of all friends of [uid] who have one stored.
  static Future<List<String>> _getFriendTokens(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    if (!userDoc.exists) return [];

    final rawFriends = userDoc.data()?['friends'] as List<dynamic>? ?? [];
    final friendUids = rawFriends
        .map((e) {
          if (e is Map) return e['uid'] as String?;
          if (e is String) return e;
          return null;
        })
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    return _getTokensForUids(friendUids);
  }

  // Returns the stored FCM tokens for an arbitrary list of uids (batched to
  // respect Firestore's 30-value whereIn limit).
  static Future<List<String>> _getTokensForUids(List<String> uids) async {
    if (uids.isEmpty) return [];

    final tokens = <String>[];
    for (int i = 0; i < uids.length; i += 30) {
      final batch = uids.sublist(i, (i + 30).clamp(0, uids.length));
      final snap = await _db
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      for (final doc in snap.docs) {
        final token = doc.data()['fcm_token'] as String?;
        if (token != null && token.isNotEmpty) tokens.add(token);
      }
    }
    return tokens;
  }

  // Returns the FCM token stored on a single user's doc, if any.
  static Future<String?> _getUserToken(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final token = doc.data()?['fcm_token'] as String?;
    return (token != null && token.isNotEmpty) ? token : null;
  }

  // ── Notification triggers ─────────────────────────────────────────────────
  // These methods collect friend tokens and hand off to your Cloud Function.
  // Replace the TODO body with your actual sending logic once you set it up.

  /// Call this right after FirebaseService._sendFollowNotification() writes
  /// the inbox doc, to also push to the followed user's device.
  static Future<void> notifyFriendNewFollow({
    required String recipientUid,
    required String followerUid,
    required String followerName,
  }) async {
    final token = await _getUserToken(recipientUid);
    if (token == null) return;

    await _callSendFunction(
      tokens: [token],
      title: '$followerName followed you',
      body: 'Check out their profile',
      data: {'type': 'follow', 'id': followerUid},
    );
  }

  /// Call this right after FirebaseService.createCollaborationInvite() writes
  /// the inbox doc, to also push to the invited collaborator's device.
  static Future<void> notifyFriendNewInvite({
    required String recipientUid,
    required String senderUid,
    required String senderName,
    required String versusId,
  }) async {
    final token = await _getUserToken(recipientUid);
    if (token == null) return;

    await _callSendFunction(
      tokens: [token],
      title: '$senderName invited you to a versus',
      body: 'Join the battle',
      data: {'type': 'invite', 'id': versusId},
    );
  }

  /// Call this right after FirebaseService._sendMentionNotifications() writes
  /// the inbox docs, to also push to each tagged friend's device.
  static Future<void> notifyUsersMentionedInPost({
    required List<String> recipientUids,
    required String authorUid,
    required String authorName,
    required String postId,
  }) async {
    final uids = recipientUids
        .where((u) => u.isNotEmpty && u != authorUid)
        .toSet()
        .toList();
    if (uids.isEmpty) return;

    final tokens = await _getTokensForUids(uids);
    if (tokens.isEmpty) return;

    await _callSendFunction(
      tokens: tokens,
      title: '$authorName mentioned you in a post',
      body: 'Tap to view the post',
      data: {'type': 'mention', 'id': postId},
    );
  }

  /// Call this right after FirebaseService.createPost() succeeds.
  static Future<void> notifyFriendsNewPost({
    required String authorUid,
    required String authorName,
    required String postId,
  }) async {
    final tokens = await _tokensWithSelf(authorUid);
    if (tokens.isEmpty) return;

    debugPrint('[FCM] notifyFriendsNewPost → ${tokens.length} token(s)');

    await _callSendFunction(
      tokens: tokens,
      title: '$authorName posted',
      body: 'Check out their latest post',
      data: {'type': 'post', 'id': postId},
    );
  }

  /// Call this right after FirebaseService.createVersus() /
  /// createArtistVersus() succeeds.
  static Future<void> notifyFriendsNewVersus({
    required String creatorUid,
    required String creatorName,
    required String versusId,
    required String versusType, // "album" | "artist"
    required String entityName1,
    required String entityName2,
  }) async {
    final tokens = await _tokensWithSelf(creatorUid);
    if (tokens.isEmpty) return;

    debugPrint('[FCM] notifyFriendsNewVersus → ${tokens.length} token(s)');

    await _callSendFunction(
      tokens: tokens,
      title: '$creatorName started a versus',
      body: '$entityName1 vs $entityName2',
      data: {'type': 'versus', 'id': versusId, 'versusType': versusType},
    );
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  // Combines friend tokens with the creator's own device token so that the
  // sender also receives the notification (useful for single-device debugging).
  static Future<List<String>> _tokensWithSelf(String uid) async {
    final results = await Future.wait([
      _getFriendTokens(uid),
      _fcm.getToken(),
    ]);
    final friendTokens = results[0] as List<String>;
    final ownToken = results[1] as String?;
    final all = {...friendTokens};
    if (ownToken != null && ownToken.isNotEmpty) all.add(ownToken);
    return all.toList();
  }

  static Future<void> _callSendFunction({
    required List<String> tokens,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('sendFriendNotification')
          .call<Map<String, dynamic>>({
        'tokens': tokens,
        'title': title,
        'body': body,
        'data': data,
      });
      debugPrint('[FCM] sent — success:${result.data['successCount']} '
          'fail:${result.data['failureCount']}');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FCM] sendFriendNotification error: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('[FCM] sendFriendNotification unexpected error: $e');
    }
  }
}
