import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

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

  // ── Initialise ────────────────────────────────────────────────────────────
  /// Call once from main() after Firebase.initializeApp().
  /// Requests permission, saves the device token, and wires message handlers.
  static Future<void> initialize() async {
    // Register the background handler before anything else.
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    // Request permission (iOS prompts the user; Android 13+ also needs this).
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] permission: ${settings.authorizationStatus}');

    // Persist token for the current user if already signed in.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await saveTokenForUser(uid);

    // Refresh token whenever FCM rotates it.
    _fcm.onTokenRefresh.listen((token) async {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        await _storeToken(currentUid, token);
      }
    });

    // Foreground message handler — show a local notification or update UI.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM foreground] ${message.notification?.title}');
      // TODO: plug in flutter_local_notifications here if you want
      // foreground banners (FCM auto-shows them in background/terminated).
    });

    // Notification tap when app was in background.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM opened] ${message.data}');
      // TODO: navigate based on message.data['type'] / message.data['id']
    });

    // Notification tap that launched the app from terminated state.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      debugPrint('[FCM launch] ${initial.data}');
      // TODO: same navigation handling
    }
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
    debugPrint('[FCM] token cleared for $uid');
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

    if (friendUids.isEmpty) return [];

    // Batch-fetch up to 30 friend docs (Firestore whereIn limit).
    final tokens = <String>[];
    for (int i = 0; i < friendUids.length; i += 30) {
      final batch = friendUids.sublist(
        i,
        (i + 30).clamp(0, friendUids.length),
      );
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

  // ── Notification triggers ─────────────────────────────────────────────────
  // These methods collect friend tokens and hand off to your Cloud Function.
  // Replace the TODO body with your actual sending logic once you set it up.

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
