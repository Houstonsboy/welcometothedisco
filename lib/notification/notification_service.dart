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
  /// Call once from main() right after runApp(); never await it there.
  /// Wires message handlers only. The permission prompt and token save happen
  /// in [requestPermissionAndSaveToken] once a signed-in user is on screen,
  /// and AuthGate saves the token / starts badge sync on every sign-in.
  static Future<void> initialize() async {
    // Register the background handler before anything else.
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    await _initLocalNotifications();

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
  /// Asks for notification permission (the OS only shows its prompt once;
  /// later calls just return the current status), then saves the device
  /// token — on iOS no usable token exists until the user allows
  /// notifications. Call when a signed-in user is on screen, never at startup.
  static Future<void> requestPermissionAndSaveToken() async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[FCM] permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('[FCM] permission request failed: $e');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await saveTokenForUser(uid);
  }

  /// Fetch the current device token and save it to Firestore.
  /// Call after sign-in and after sign-up. Never throws, and callers should
  /// not await it on a user-visible path: the Firestore write only completes
  /// on server ack, so offline it stays pending.
  static Future<void> saveTokenForUser(String uid) async {
    try {
      final token = await _fcm.getToken();
      if (token == null || uid.isEmpty) return;
      await _storeToken(uid, token);
    } catch (e) {
      debugPrint('[FCM] failed to save token for $uid: $e');
    }
  }

  // Tokens live in an owner-only subcollection (see firestore.rules) so other
  // users can't read them off the public profile doc.
  static DocumentReference<Map<String, dynamic>> _tokenDoc(String uid) =>
      _db.collection('users').doc(uid).collection('private').doc('messaging');

  static Future<void> _storeToken(String uid, String token) async {
    await _tokenDoc(uid).set({
      'fcm_token': token,
      'updated_at': FieldValue.serverTimestamp(),
    });
    // Remove the legacy world-readable copy from the profile doc, if any.
    await _db
        .collection('users')
        .doc(uid)
        .update({'fcm_token': FieldValue.delete()})
        .catchError((_) {});
    debugPrint('[FCM] token saved for $uid');
  }

  /// Clear the token on sign-out so the user stops receiving notifications
  /// on this device.
  ///
  /// Best effort and bounded: offline, the Firestore delete would never
  /// complete and sign-out would hang. If it doesn't finish, this device may
  /// keep getting the previous user's pushes until the next sign-in here
  /// overwrites the token, or FCM reports it unregistered and
  /// sendFriendNotification prunes it.
  static Future<void> clearTokenForUser(String uid) async {
    if (uid.isEmpty) return;
    stopBadgeSync();
    try {
      await Future.wait([
        _tokenDoc(uid).delete(),
        _fcm.deleteToken(),
      ]).timeout(const Duration(seconds: 4));
      debugPrint('[FCM] token cleared for $uid');
    } catch (e) {
      debugPrint('[FCM] token clear incomplete for $uid: $e');
    }
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

  // ── Notification triggers ─────────────────────────────────────────────────
  // Each call names an event the current user just caused. The
  // sendFriendNotification Cloud Function verifies it, picks the recipients,
  // looks up their tokens and writes the notification text server-side.

  /// Call this right after FirebaseService._sendFollowNotification() writes
  /// the inbox doc, to also push to the followed user's device.
  static Future<void> notifyFriendNewFollow({
    required String recipientUid,
    required String followerUid,
  }) =>
      _callSendFunction({
        'type': 'follow',
        'id': followerUid,
        'recipientUid': recipientUid,
      });

  /// Call this right after FirebaseService.createCollaborationInvite() writes
  /// the inbox doc, to also push to the invited collaborator's device.
  static Future<void> notifyFriendNewInvite({
    required String recipientUid,
    required String versusId,
  }) =>
      _callSendFunction({
        'type': 'invite',
        'id': versusId,
        'recipientUid': recipientUid,
      });

  /// Call this right after FirebaseService._sendMentionNotifications() writes
  /// the inbox docs, to also push to each tagged friend's device.
  static Future<void> notifyUsersMentionedInPost({
    required List<String> recipientUids,
    required String postId,
  }) async {
    final uids = recipientUids.where((u) => u.isNotEmpty).toSet().toList();
    if (uids.isEmpty) return;
    await _callSendFunction({
      'type': 'mention',
      'id': postId,
      'recipientUids': uids,
    });
  }

  /// Call this right after FirebaseService.createPost() succeeds.
  static Future<void> notifyFriendsNewPost({required String postId}) =>
      _callSendFunction({'type': 'post', 'id': postId});

  /// Call this right after FirebaseService.createVersus() /
  /// createArtistVersus() succeeds.
  static Future<void> notifyFriendsNewVersus({required String versusId}) =>
      _callSendFunction({'type': 'versus', 'id': versusId});

  // ── Internal helpers ──────────────────────────────────────────────────────

  static Future<void> _callSendFunction(Map<String, dynamic> payload) async {
    try {
      final result = await _functions
          .httpsCallable('sendFriendNotification')
          .call<Map<String, dynamic>>(payload);
      debugPrint('[FCM] sent — success:${result.data['successCount']} '
          'fail:${result.data['failureCount']}');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[FCM] sendFriendNotification error: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('[FCM] sendFriendNotification unexpected error: $e');
    }
  }
}
