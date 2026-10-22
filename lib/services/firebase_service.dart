// lib/services/firebase_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:welcometothedisco/models/artist_versus_model.dart';
import 'package:welcometothedisco/models/inbox_versus_entry.dart';
import 'package:welcometothedisco/models/post_model.dart';
import 'package:welcometothedisco/models/pair_model.dart';
import 'package:welcometothedisco/models/ranking_model.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/notification/notification_service.dart';
import 'package:welcometothedisco/services/user_profile_cache_service.dart';
import 'package:welcometothedisco/utils/pair_utils.dart';

/// Thrown when a profile write tries to use a username another user owns.
class UsernameTakenException implements Exception {
  UsernameTakenException(this.username);
  final String username;

  @override
  String toString() => 'The username "$username" is already taken.';
}

class FirebaseService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static Future<UserModel?> _fetchCurrentUserFromFirestore(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      final user = UserModel.fromFirestore(doc.data()!, doc.id);
      await UserProfileCacheService.saveUser(user);
      return user;
    } catch (e) {
      debugPrint('[FirebaseService] _fetchCurrentUserFromFirestore($uid) failed: $e');
      return null;
    }
  }

  /// Ensures secure-storage cache exists for the authenticated user.
  /// If cache is missing (e.g. app storage cleared), it refetches from Firestore.
  static Future<void> ensureCurrentUserProfileCached() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return;

    final cached = await UserProfileCacheService.readUser(expectedUid: uid);
    if (cached != null) return;

    debugPrint(
      '[FirebaseService] user profile cache missing; refetching from Firestore for uid=$uid',
    );
    await _fetchCurrentUserFromFirestore(uid);
  }

  // ── Fetch user by UID ─────────────────────────────────────────────────────
  static Future<UserModel?> getUserById(String uid) async {
    if (uid.trim().isEmpty) return null;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc.data()!, doc.id);
    } catch (e) {
      debugPrint('[FirebaseService] getUserById($uid) failed: $e');
      return null;
    }
  }

  // ── Fetch current logged in user ──────────────────────────────────────────
  static Future<UserModel?> getCurrentUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final cached = await UserProfileCacheService.readUser(expectedUid: uid);
    if (cached != null) {
      // Refresh cache in background so data self-heals if profile changed.
      unawaited(_fetchCurrentUserFromFirestore(uid));
      return cached;
    }
    return _fetchCurrentUserFromFirestore(uid);
  }

  // ── Live stream of current user's document ────────────────────────────────
  /// Emits a new [UserModel] whenever the user's Firestore doc changes —
  /// friends list, username, avatar, etc. update in real-time with no
  /// extra fetch needed.
  static Stream<UserModel?> getCurrentUserStream() async* {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      yield null;
      return;
    }

    final cached = await UserProfileCacheService.readUser(expectedUid: uid);
    if (cached != null) {
      yield cached;
    }

    yield* _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .asyncMap((snap) async {
          if (!snap.exists || snap.data() == null) return null;
          final user = UserModel.fromFirestore(snap.data()!, snap.id);
          await UserProfileCacheService.saveUser(user);
          return user;
        });
  }

  // ── Add a friend to the current user's friends array ─────────────────────
  /// Appends `{ uid, username, avatar_path }` to the logged-in user's
  /// [friends] array using [FieldValue.arrayUnion] — idempotent, so calling
  /// it twice with the same UID will not create a duplicate entry.
  /// Also writes a follow notification doc to the followed user's subcollection.
  static Future<void> addFriend({
    required String friendUid,
    required String friendUsername,
    required String friendAvatarPath,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');
    if (friendUid == uid) throw Exception('You cannot follow yourself');

    await _firestore.collection('users').doc(uid).update({
      'friends': FieldValue.arrayUnion([
        {
          'uid': friendUid,
          'username': friendUsername,
          'avatar_path': friendAvatarPath,
        }
      ]),
    });

    // Best-effort: send follow notification. Does not fail the follow action.
    try {
      await _sendFollowNotification(
        recipientUid: friendUid,
        followerUid: uid,
      );
    } catch (e) {
      debugPrint('[FirebaseService] addFriend → notification write failed: $e');
    }

    debugPrint('[FirebaseService] addFriend → followed $friendUid');
  }

  // ── Write a follow notification to the followed user's subcollection ───────
  /// Uses the follower's UID as the doc ID so one follower can only ever
  /// produce a single notification doc per recipient (no duplicates).
  static Future<void> _sendFollowNotification({
    required String recipientUid,
    required String followerUid,
  }) async {
    final follower = await getUserById(followerUid);
    if (follower == null) return;

    await _firestore
        .collection('users')
        .doc(recipientUid)
        .collection('notifications')
        .doc(followerUid)
        .set({
      'followerID': followerUid,
      'follower_username': follower.username,
      'follower_avatar': follower.avatarPath,
      'follower_bio': follower.bio,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'follow',
      'read': false,
    });

    debugPrint(
        '[FirebaseService] _sendFollowNotification → $followerUid → $recipientUid');

    await NotificationService.notifyFriendNewFollow(
      recipientUid: recipientUid,
      followerUid: followerUid,
    );
  }

  // ── Real-time stream: true if current user has any unread notifications ────
  static Stream<bool> hasUnreadNotificationsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty);
  }

  // ── Real-time stream: all notifications for current user ──────────────────
  static Stream<QuerySnapshot<Map<String, dynamic>>> getNotificationsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  // ── Mark all unread notifications as read ─────────────────────────────────
  static Future<void> markAllNotificationsRead() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
      debugPrint(
          '[FirebaseService] markAllNotificationsRead → ${snap.docs.length} marked');
    } catch (e) {
      debugPrint('[FirebaseService] markAllNotificationsRead failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ALBUM VERSUS
  // ══════════════════════════════════════════════════════════════════════════

  // ── Enrich album versus list with author data ─────────────────────────────
  static Future<List<VersusModel>> _enrichWithAuthors(
      List<VersusModel> versusList) async {
    final authorIds = versusList
        .map((v) => v.authorId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final authorMap = <String, UserModel?>{};
    await Future.wait(
      authorIds.map((id) async {
        try {
          authorMap[id] = await getUserById(id);
        } catch (e) {
          debugPrint('[FirebaseService] author enrichment failed for $id: $e');
          authorMap[id] = null;
        }
      }),
    );

    for (final versus in versusList) {
      versus.author = authorMap[versus.authorId];
    }

    return versusList;
  }

  // ── Album versus realtime stream ──────────────────────────────────────────
  static Stream<List<VersusModel>> getVersusStream() {
    return _firestore
        .collection('versus')
        .where('type', isEqualTo: 'album')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final versusList = snapshot.docs
              .map((doc) => VersusModel.fromFirestore(doc.data(), doc.id))
              .toList();
          return _enrichWithAuthors(versusList);
        });
  }

  // ── Album versus one-time fetch ───────────────────────────────────────────
  static Future<List<VersusModel>> getVersusList() async {
    final snapshot = await _firestore
        .collection('versus')
        .where('type', isEqualTo: 'album')
        .orderBy('timestamp', descending: true)
        .get();

    final versusList = snapshot.docs
        .map((doc) => VersusModel.fromFirestore(doc.data(), doc.id))
        .toList();

    return _enrichWithAuthors(versusList);
  }

  // ── Artist versus one-time fetch ───────────────────────────────────────────
  static Future<List<ArtistVersusModel>> getArtistVersusList() async {
    final snapshot = await _firestore
        .collection('versus')
        .where('type', isEqualTo: 'artist')
        .orderBy('timestamp', descending: true)
        .get();

    final list = snapshot.docs
        .map((doc) => ArtistVersusModel.fromFirestore(doc.data(), doc.id))
        .toList();

    return _enrichArtistVersusWithUsers(list);
  }

  /// Inbox: all [versus] docs with `status == "open"` (album, artist, collaboration).
  /// Collaboration rows use the artist inbox tile; [typeFilter] `artist` includes them.
  /// Optional [typeFilter] 'album' | 'artist' | null (all).
  static Future<List<InboxVersusEntry>> getInboxVersusList({
    String? typeFilter,
  }) async {
    // No orderBy here — avoids the composite index requirement.
    // Docs are sorted client-side after enrichment.
    final snapshot = await _firestore
        .collection('versus')
        .where('status', isEqualTo: 'open')
        .get();

    final albums = <VersusModel>[];
    final artists = <ArtistVersusModel>[];
    final entries = <InboxVersusEntry>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final type = (data['type'] as String?)?.trim() ?? 'album';

      if (type == 'album') {
        final v = VersusModel.fromFirestore(data, doc.id);
        if (!v.isEligibleForInboxDisplay) continue;
        albums.add(v);
        entries.add(InboxVersusEntry(
          type: 'album',
          timestamp: v.timestamp,
          albumVersus: v,
        ));
      } else if (type == 'artist' || type == 'collaboration' ||
          type == 'collaborator') {
        final v = ArtistVersusModel.fromFirestore(data, doc.id);
        if (!v.isEligibleForInboxDisplay) continue;
        artists.add(v);
        entries.add(InboxVersusEntry(
          type: 'artist',
          timestamp: v.timestamp,
          artistVersus: v,
        ));
      }
    }

    await Future.wait([
      if (albums.isNotEmpty) _enrichWithAuthors(albums),
      if (artists.isNotEmpty) _enrichArtistVersusWithUsers(artists),
    ]);

    // Sort by timestamp descending (newest first) after enrichment.
    entries.sort((a, b) {
      final ta = a.timestamp?.millisecondsSinceEpoch ?? 0;
      final tb = b.timestamp?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });

    if (typeFilter == 'album') {
      return entries.where((e) => e.isAlbum).toList();
    }
    if (typeFilter == 'artist') {
      return entries.where((e) => e.isArtist).toList();
    }
    return entries;
  }

  // ── Lazy image backfill — write Spotify images back to old versus docs ───────

  /// Writes missing image/artist-name fields back into an album versus doc so
  /// subsequent inbox loads never need a Spotify call for that doc.
  static Future<void> backfillAlbumVersusImages(
    String versusId, {
    String? album1ImageUrl,
    String? album1ArtistName,
    String? album2ImageUrl,
    String? album2ArtistName,
  }) async {
    final fields = <String, dynamic>{};
    if (album1ImageUrl?.isNotEmpty ?? false) fields['album1ImageUrl'] = album1ImageUrl;
    if (album1ArtistName?.isNotEmpty ?? false) fields['album1ArtistName'] = album1ArtistName;
    if (album2ImageUrl?.isNotEmpty ?? false) fields['album2ImageUrl'] = album2ImageUrl;
    if (album2ArtistName?.isNotEmpty ?? false) fields['album2ArtistName'] = album2ArtistName;
    if (fields.isEmpty) return;
    try {
      await _firestore.collection('versus').doc(versusId).update(fields);
      debugPrint('[FirebaseService] backfilled album images → $versusId');
    } catch (e) {
      debugPrint('[FirebaseService] album backfill failed $versusId: $e');
    }
  }

  /// Writes missing artist image URLs back into an artist/collaboration versus doc.
  static Future<void> backfillArtistVersusImages(
    String versusId, {
    String? artist1ImageUrl,
    String? artist2ImageUrl,
  }) async {
    final fields = <String, dynamic>{};
    if (artist1ImageUrl?.isNotEmpty ?? false) fields['artist1ImageUrl'] = artist1ImageUrl;
    if (artist2ImageUrl?.isNotEmpty ?? false) fields['artist2ImageUrl'] = artist2ImageUrl;
    if (fields.isEmpty) return;
    try {
      await _firestore.collection('versus').doc(versusId).update(fields);
      debugPrint('[FirebaseService] backfilled artist images → $versusId');
    } catch (e) {
      debugPrint('[FirebaseService] artist backfill failed $versusId: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  /// Fetch ranking profile for one entity from `rankings/{entityId}`.
  ///
  /// Returns null when the ID is empty or the document does not exist.
  static Future<RankingModel?> getRankingProfile(String entityId) async {
    final id = entityId.trim();
    if (id.isEmpty) return null;

    try {
      final doc = await _firestore.collection('rankings').doc(id).get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('[getRankingProfile] no doc for $id');
        return null;
      }
      final model = RankingModel.fromFirestore(doc.data()!, doc.id);
      debugPrint('[getRankingProfile] $id → ${model.entityName} (provisional=${model.provisional})');
      return model;
    } catch (e) {
      debugPrint('[getRankingProfile] $id failed: $e');
      return null;
    }
  }

  // ── Create album versus ───────────────────────────────────────────────────
  /// Returns the new versus document ID.
  static Future<String> createVersus({
    required String type,
    required String album1ID,
    required String album1Name,
    required String album2ID,
    required String album2Name,
    String album1ImageUrl = '',
    String album2ImageUrl = '',
    String album1ArtistName = '',
    String album2ArtistName = '',
    List<Map<String, dynamic>>? album1Tracklist,
    List<Map<String, dynamic>>? album2Tracklist,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    final selfMatchup = isSelfMatchup(album1ID, album2ID);
    final ref = await _firestore.collection('versus').add({
      'type': type,
      'status': 'open',
      'Author': uid,
      'album1ID': album1ID,
      'album1Name': album1Name,
      'album2ID': album2ID,
      'album2Name': album2Name,
      'is_self_matchup': selfMatchup,
      'entity_type': 'album',
      if (!selfMatchup) 'pair_key': makePairKey(album1ID, album2ID),
      'timestamp': FieldValue.serverTimestamp(),
      // Denormalized at creation — inbox renders immediately, no Spotify call needed.
      if (album1ImageUrl.trim().isNotEmpty) 'album1ImageUrl': album1ImageUrl.trim(),
      if (album2ImageUrl.trim().isNotEmpty) 'album2ImageUrl': album2ImageUrl.trim(),
      if (album1ArtistName.trim().isNotEmpty) 'album1ArtistName': album1ArtistName.trim(),
      if (album2ArtistName.trim().isNotEmpty) 'album2ArtistName': album2ArtistName.trim(),
      if (album1Tracklist != null && album1Tracklist.isNotEmpty)
        'album1Tracklist': album1Tracklist,
      if (album2Tracklist != null && album2Tracklist.isNotEmpty)
        'album2Tracklist': album2Tracklist,
    });

    return ref.id;
  }

  /// Returns the new versus document ID.
  static Future<String> createVersusFromLockeroom({
    required String album1ID,
    required String album1Name,
    required String album2ID,
    required String album2Name,
    String album1ImageUrl = '',
    String album2ImageUrl = '',
    String album1ArtistName = '',
    String album2ArtistName = '',
    List<Map<String, dynamic>>? album1Tracklist,
    List<Map<String, dynamic>>? album2Tracklist,
  }) {
    return createVersus(
      type: 'album',
      album1ID: album1ID.trim(),
      album1Name: album1Name.trim(),
      album2ID: album2ID.trim(),
      album2Name: album2Name.trim(),
      album1ImageUrl: album1ImageUrl,
      album2ImageUrl: album2ImageUrl,
      album1ArtistName: album1ArtistName,
      album2ArtistName: album2ArtistName,
      album1Tracklist: album1Tracklist,
      album2Tracklist: album2Tracklist,
    );
  }

  // ── Album versus by author ────────────────────────────────────────────────
  static Stream<List<VersusModel>> getVersusByAuthor(String authorId) {
    return _firestore
        .collection('versus')
        .where('Author', isEqualTo: authorId)
        .where('type', isEqualTo: 'album')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final versusList = snapshot.docs
              .map((doc) => VersusModel.fromFirestore(doc.data(), doc.id))
              .toList();
          return _enrichWithAuthors(versusList);
        });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ARTIST VERSUS
  // ══════════════════════════════════════════════════════════════════════════

  // ── Enrich artist versus list with author + collaborator data ─────────────
  static Future<List<ArtistVersusModel>> _enrichArtistVersusWithUsers(
      List<ArtistVersusModel> list) async {
    // Collect all unique UIDs needed (authors + collaborators)
    final uids = <String>{};
    for (final v in list) {
      if (v.authorID.isNotEmpty) uids.add(v.authorID);
      if (v.collaboratorID != null && v.collaboratorID!.isNotEmpty) {
        uids.add(v.collaboratorID!);
      }
    }

    // Fetch all in parallel
    final userMap = <String, UserModel?>{};
    await Future.wait(
      uids.map((id) async {
        try {
          userMap[id] = await getUserById(id);
        } catch (e) {
          debugPrint(
              '[FirebaseService] artist versus user enrichment failed for $id: $e');
          userMap[id] = null;
        }
      }),
    );

    // Attach to models
    for (final versus in list) {
      versus.author = userMap[versus.authorID];
      if (versus.collaboratorID != null) {
        versus.collaborator = userMap[versus.collaboratorID!];
      }
    }

    return list;
  }

  // ── Create artist versus ──────────────────────────────────────────────────
  /// Writes a new artist versus document using [ArtistVersusModel.toFirestore].
  /// Only Firestore-safe fields are persisted — Spotify metadata and user
  /// objects are excluded by the model's [toFirestore] method.
  static Future<String> createArtistVersus({
    required String artist1ID,
    required String artist1Name,
    required List<String> artist1TrackIDs,
    required String artist2ID,
    required String artist2Name,
    required List<String> artist2TrackIDs,
    String? authorComment,
    String artist1ImageUrl = '',
    String artist2ImageUrl = '',
    List<Map<String, dynamic>>? artist1Tracklist,
    List<Map<String, dynamic>>? artist2Tracklist,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    final comment = authorComment?.trim();
    // Build the model — toFirestore() ensures only safe fields are written
    final model = ArtistVersusModel(
      id: '', // assigned by Firestore on add
      artist1ID: artist1ID.trim(),
      artist1Name: artist1Name.trim(),
      artist1TrackIDs: artist1TrackIDs.map((e) => e.trim()).toList(),
      artist2ID: artist2ID.trim(),
      artist2Name: artist2Name.trim(),
      artist2TrackIDs: artist2TrackIDs.map((e) => e.trim()).toList(),
      authorID: uid,
      status: 'open',
      authorComment: (comment == null || comment.isEmpty) ? null : comment,
      // Denormalized cover images — written by toFirestore() so inbox renders
      // immediately without a Spotify API call.
      artist1ImageUrl: artist1ImageUrl.trim().isNotEmpty ? artist1ImageUrl.trim() : null,
      artist2ImageUrl: artist2ImageUrl.trim().isNotEmpty ? artist2ImageUrl.trim() : null,
      artist1Tracklist: artist1Tracklist,
      artist2Tracklist: artist2Tracklist,
    );

    final a1 = artist1ID.trim();
    final a2 = artist2ID.trim();
    final selfMatchup = a1.isNotEmpty && a2.isNotEmpty && isSelfMatchup(a1, a2);
    final payload = {
      ...model.toFirestore(),
      'entity_type': 'artist',
      'is_self_matchup': selfMatchup,
      if (!selfMatchup && a1.isNotEmpty && a2.isNotEmpty)
        'pair_key': makePairKey(a1, a2),
    };
    final ref = await _firestore.collection('versus').add(payload);

    debugPrint('[FirebaseService] createArtistVersus → doc: ${ref.id}');

    return ref.id;
  }

  /// Collaborator invite flow: same as [createArtistVersus] but [artist2TrackIDs]
  /// is empty — the joining collaborator fills their tracks later.
  static Future<String> createCollaboratorVersus({
    required String artist1ID,
    required String artist1Name,
    required List<String> artist1TrackIDs,
    required String artist2ID,
    required String artist2Name,
    required List<String> artist2TrackIDs,
    String? authorComment,
    String artist1ImageUrl = '',
    String artist2ImageUrl = '',
    List<Map<String, dynamic>>? artist1Tracklist,
  }) {
    return createArtistVersus(
      artist1ID: artist1ID,
      artist1Name: artist1Name,
      artist1TrackIDs: artist1TrackIDs,
      artist2ID: artist2ID,
      artist2Name: artist2Name,
      artist2TrackIDs: artist2TrackIDs,
      authorComment: authorComment,
      artist1ImageUrl: artist1ImageUrl,
      artist2ImageUrl: artist2ImageUrl,
      artist1Tracklist: artist1Tracklist,
    );
  }

  // ── Create post-remix versus (type: collaborator, status: open) ──────────
  /// Saves a remix of an existing post as a versus document.
  /// artist1 = the original post's locked side; artist2 = the remixer's pick.
  /// The remixer (current user) is stored as [collaboratorID].
  static Future<void> createPostRemixVersus({
    required String sourcePostID,
    required String postAuthorID,
    required String artist1ID,
    required String artist1Name,
    required String artist1ImageUrl,
    required List<String> artist1TrackIDs,
    required String artist2ID,
    required String artist2Name,
    required String artist2ImageUrl,
    required List<String> artist2TrackIDs,
    required String remixPolicy, // 'same' | 'different'
    List<Map<String, dynamic>>? artist1Tracklist,
    List<Map<String, dynamic>>? artist2Tracklist,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not logged in');

    // Fetch both users in parallel — remixer (me) + post author
    final results = await Future.wait([
      getCurrentUser(),
      getUserById(postAuthorID),
    ]);
    final me         = results[0];
    final postAuthor = results[1];

    final a1 = artist1ID.trim();
    final a2 = artist2ID.trim();
    final selfMatchup = isSelfMatchup(a1, a2);

    await _firestore.collection('versus').add({
      'type':           'collaborator',
      'status':         'open',
      'sourcePostID':   sourcePostID,
      'remixPolicy':    remixPolicy,
      // artist 1 — original post side (locked)
      'artist1ID':       a1,
      'artist1Name':     artist1Name.trim(),
      'artist1TrackIDs': artist1TrackIDs,
      // artist 2 — remixer's pick
      'artist2ID':       a2,
      'artist2Name':     artist2Name.trim(),
      'artist2TrackIDs': artist2TrackIDs,
      // ownership: post author is the "author", current user is collaborator
      'authorID':              postAuthorID,
      'author_username':       postAuthor?.username ?? '',
      'author_avatar':         postAuthor?.avatarPath ?? '',
      'collaboratorID':        uid,
      'collaborator_username': me?.username ?? '',
      'collaborator_avatar':   me?.avatarPath ?? '',
      'timestamp':             FieldValue.serverTimestamp(),
      // Ranking metadata — same as artist lockeroom so polls/rankings work.
      'entity_type':    'artist',
      'is_self_matchup': selfMatchup,
      if (!selfMatchup) 'pair_key': makePairKey(a1, a2),
      // Denormalized cover images — inbox renders immediately, no Spotify call.
      if (artist1ImageUrl.trim().isNotEmpty) 'artist1ImageUrl': artist1ImageUrl.trim(),
      if (artist2ImageUrl.trim().isNotEmpty) 'artist2ImageUrl': artist2ImageUrl.trim(),
      // Full track details — enables rendering without Spotify API calls.
      if (artist1Tracklist != null && artist1Tracklist.isNotEmpty)
        'artist1Tracklist': artist1Tracklist,
      if (artist2Tracklist != null && artist2Tracklist.isNotEmpty)
        'artist2Tracklist': artist2Tracklist,
    });

    // Increment remix count on the source post.
    final pid = sourcePostID.trim();
    if (pid.isNotEmpty) {
      _firestore.collection('posts').doc(pid).update({
        'Remixcount': FieldValue.increment(1),
      }).catchError((Object e) {
        debugPrint('[FirebaseService] createPostRemixVersus → Remixcount increment failed for post $pid: $e');
      });
    }

  }

  // ── Create collaboration invite versus (status: incomplete) ──────────────
  /// Creates the versus document for the collab-lockeroom flow then, if a
  /// collaborator was chosen, drops an invite notification in their
  /// `users/{collaboratorUID}/notifications` subcollection.
  ///
  /// Returns the new versus doc ID.
  static Future<String> createCollaborationInvite({
    // Author's Spotify artist
    required String artist1ID,
    required String artist1Name,
    required List<String> artist1TrackIDs,
    // Collaborator's artist (nullable — may not be chosen yet)
    String? artist2ID,
    String? artist2Name,
    String artist1ImageUrl = '',
    String artist2ImageUrl = '',
    // Author note from the comment strip
    String? authorComment,
    // Selected recipient from invite banner (nullable)
    String? collaboratorUID,
    String? collaboratorUsername,
    String? collaboratorAvatarPath,
    List<Map<String, dynamic>>? artist1Tracklist,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    final author = await getUserById(uid);
    final comment = authorComment?.trim();

    // ── 1. Build Firestore doc ────────────────────────────────────────────────
    final Map<String, dynamic> versusData = {
      'type':   'collaboration',
      'status': 'incomplete',
      'timestamp': FieldValue.serverTimestamp(),

      // Author details
      'authorID':       uid,
      'author_username': author?.username ?? '',
      'author_avatar':  author?.avatarPath ?? '',

      // Artist 1 (author's pick)
      'artist1ID':       artist1ID.trim(),
      'artist1Name':     artist1Name.trim(),
      'artist1TrackIDs': artist1TrackIDs.map((e) => e.trim()).toList(),

      // Artist 2 (collaborator's pick — may be null)
      if (artist2ID != null && artist2ID.trim().isNotEmpty)
        'artist2ID': artist2ID.trim(),
      if (artist2Name != null && artist2Name.trim().isNotEmpty)
        'artist2Name': artist2Name.trim(),
      'artist2TrackIDs': [],

      // Denormalized cover images — stored now so inbox renders without Spotify calls.
      if (artist1ImageUrl.trim().isNotEmpty) 'artist1ImageUrl': artist1ImageUrl.trim(),
      if (artist2ImageUrl.trim().isNotEmpty)
        'artist2ImageUrl': artist2ImageUrl.trim(),

      // Full track details — enables rendering without Spotify API calls.
      if (artist1Tracklist != null && artist1Tracklist.isNotEmpty)
        'artist1Tracklist': artist1Tracklist,

      // Optional author note
      if (comment != null && comment.isNotEmpty)
        'authorComment': comment,

      // Collaborator slot (filled when the recipient accepts)
      'collaboratorComment': null,

      // Invited collaborator — filled if recipient was chosen from the banner
      if (collaboratorUID != null && collaboratorUID.trim().isNotEmpty)
        'collaboratorID': collaboratorUID.trim(),
    };

    final ref = await _firestore.collection('versus').add(versusData);
    final versusID = ref.id;
    debugPrint('[FirebaseService] createCollaborationInvite → doc: $versusID');
    // Rankings: deferred until versus is live (open|active) with both artists —
    // see [_ensureRankingStubsForVersusDocIfLive] after [acceptCollaborationInvite].

    // ── 2. Send invite notification if a recipient was chosen ─────────────────
    if (collaboratorUID != null && collaboratorUID.trim().isNotEmpty) {
      try {
        await _firestore
            .collection('users')
            .doc(collaboratorUID.trim())
            .collection('notifications')
            .add({
          'type':        'invite',
          'read':        false,
          'timestamp':   FieldValue.serverTimestamp(),
          // Who sent the invite
          'authorID':      uid,
          'authorName':    author?.username ?? '',
          'author_avatar': author?.avatarPath ?? '',
          // The versus that was just created
          'versusID':    versusID,
          'artist1ID':   artist1ID.trim(),
          'artist1Name': artist1Name.trim(),
          'artist2Name': artist2Name?.trim() ?? '',
          if (artist2ID != null && artist2ID.trim().isNotEmpty)
            'artist2ID': artist2ID.trim(),

        });
        debugPrint(
            '[FirebaseService] createCollaborationInvite → invite sent to $collaboratorUID');

        await NotificationService.notifyFriendNewInvite(
          recipientUid: collaboratorUID.trim(),
          versusId: versusID,
        );
      } catch (e) {
        debugPrint(
            '[FirebaseService] createCollaborationInvite → notification failed: $e');
      }
    }

    return versusID;
  }

  // ── Notify author that collaborator added more tracks (needs to match) ────
  static Future<void> sendTracksNeededNotification({
    required String authorUID,
    required String versusID,
    required String artist1ID,
    required String artist1Name,
    required String artist2ID,
    required String artist2Name,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid == authorUID) return;
    final sender = await getCurrentUser();
    try {
      await _firestore
          .collection('users')
          .doc(authorUID)
          .collection('notifications')
          .add({
        'type': 'tracks_needed',
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
        'authorID': uid,
        'authorName': sender?.username ?? '',
        'author_avatar': sender?.avatarPath ?? '',
        'versusID': versusID,
        'artist1ID': artist1ID,
        'artist1Name': artist1Name,
        'artist2ID': artist2ID,
        'artist2Name': artist2Name,
      });
      await NotificationService.notifyAuthorTracksNeeded(
        recipientUid: authorUID,
        versusId: versusID,
      );
    } catch (e) {
      debugPrint('[FirebaseService] sendTracksNeededNotification failed: $e');
    }
  }

  // ── Fetch single artist versus by doc ID ──────────────────────────────────
  static Future<ArtistVersusModel?> getArtistVersusById(
      String documentId) async {
    if (documentId.trim().isEmpty) return null;
    try {
      final doc =
          await _firestore.collection('versus').doc(documentId).get();
      if (!doc.exists || doc.data() == null) return null;
      final model =
          ArtistVersusModel.fromFirestore(doc.data()!, doc.id);
      final enriched =
          await _enrichArtistVersusWithUsers([model]);
      return enriched.first;
    } catch (e) {
      debugPrint(
          '[FirebaseService] getArtistVersusById($documentId) failed: $e');
      return null;
    }
  }

  // ── Fetch single album versus by doc ID ───────────────────────────────────
  static Future<VersusModel?> getAlbumVersusById(String documentId) async {
    final id = documentId.trim();
    if (id.isEmpty) return null;
    try {
      final doc = await _firestore.collection('versus').doc(id).get();
      if (!doc.exists || doc.data() == null) return null;
      final data = doc.data()!;
      final type = (data['type'] as String?)?.trim().toLowerCase() ?? '';
      if (type != 'album') return null;
      final model = VersusModel.fromFirestore(data, doc.id);
      return model;
    } catch (e) {
      debugPrint('[FirebaseService] getAlbumVersusById($id) failed: $e');
      return null;
    }
  }

  // ── Artist versus realtime stream (all) ───────────────────────────────────
  static Stream<List<ArtistVersusModel>> getArtistVersusStream() {
    return _firestore
        .collection('versus')
        .where('type', isEqualTo: 'artist')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final list = snapshot.docs
              .map((doc) =>
                  ArtistVersusModel.fromFirestore(doc.data(), doc.id))
              .toList();
          return _enrichArtistVersusWithUsers(list);
        });
  }

  // ── Artist versus realtime stream (open / joinable) ───────────────────────
  /// Returns only documents with status == "open" — i.e. artist2 slot
  /// is unclaimed. Use this to show a lobby of joinable sessions.
  static Stream<List<ArtistVersusModel>> getOpenArtistVersusStream() {
    return _firestore
        .collection('versus')
        .where('type', isEqualTo: 'artist')
        .where('status', isEqualTo: 'open')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final list = snapshot.docs
              .map((doc) =>
                  ArtistVersusModel.fromFirestore(doc.data(), doc.id))
              .toList();
          return _enrichArtistVersusWithUsers(list);
        });
  }

  // ── Artist versus by author ───────────────────────────────────────────────
  static Stream<List<ArtistVersusModel>> getArtistVersusByAuthor(
      String authorId) {
    return _firestore
        .collection('versus')
        .where('type', isEqualTo: 'artist')
        .where('authorID', isEqualTo: authorId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final list = snapshot.docs
              .map((doc) =>
                  ArtistVersusModel.fromFirestore(doc.data(), doc.id))
              .toList();
          return _enrichArtistVersusWithUsers(list);
        });
  }

  // ── Artist versus by collaborator ─────────────────────────────────────────
  /// Returns sessions where [collaboratorId] joined as the artist2 player.
  static Stream<List<ArtistVersusModel>> getArtistVersusByCollaborator(
      String collaboratorId) {
    return _firestore
        .collection('versus')
        .where('type', isEqualTo: 'artist')
        .where('collaboratorID', isEqualTo: collaboratorId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final list = snapshot.docs
              .map((doc) =>
                  ArtistVersusModel.fromFirestore(doc.data(), doc.id))
              .toList();
          return _enrichArtistVersusWithUsers(list);
        });
  }

  // ── Claim artist2 slot (collaboration) ───────────────────────────────────
  /// Called when a second user joins an open artist versus session.
  /// Updates the collaboratorID and flips status to "active".
  /// Throws if the document is no longer open (race condition guard).
  static Future<void> joinArtistVersus({
    required String documentId,
    required String artist2ID,
    required String artist2Name,
    required List<String> artist2TrackIDs,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    final ref = _firestore.collection('versus').doc(documentId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Versus not found');

      final data = snap.data()!;
      if ((data['status'] as String?) != 'open') {
        throw Exception('This versus is no longer open to join');
      }
      if ((data['authorID'] as String?) == uid) {
        throw Exception('You cannot join your own versus');
      }

      final artist1Id = (data['artist1ID'] as String? ?? '').trim();
      final a2Id = artist2ID.trim();
      final selfMatchup = isSelfMatchup(artist1Id, a2Id);
      tx.update(ref, {
        'collaboratorID': uid,
        'artist2ID': a2Id,
        'artist2Name': artist2Name.trim(),
        'artist2TrackIDs': artist2TrackIDs.map((e) => e.trim()).toList(),
        'status': 'active',
        'is_self_matchup': selfMatchup,
        if ((data['entity_type'] as String? ?? '').isEmpty) 'entity_type': 'artist',
        // pair_key: only write for non-self-matchup and only if not already set.
        if (!selfMatchup && (data['pair_key'] as String? ?? '').isEmpty)
          'pair_key': makePairKey(artist1Id, a2Id),
      });
    });

    debugPrint(
        '[FirebaseService] joinArtistVersus → $documentId claimed by $uid');
  }

  // ── Collaboration: invitee confirms artist2 + tracks ─────────────────────
  /// Called from [CollaboratorAcceptScreen] when the invited user finishes
  /// picking their artist (if needed) and tracks. Requires `type: collaboration`,
  /// matching [collaboratorID], and status `incomplete` or `open`.
  static Future<void> acceptCollaborationInvite({
    required String versusID,
    required String editedArtistID,
    required String editedArtistName,
    required List<String> editedTrackIDs,
    String? editedComment,
    String? editorUsername,
    String? editorAvatarPath,
    /// Full track objects (name/artist/cover) — written alongside the IDs so the
    /// playground can render without Spotify API calls.
    List<Map<String, dynamic>>? editedTracklist,
    /// When [collaboratorID] is empty, the author may set both sides in one update.
    String? editedArtist2ID,
    String? editedArtist2Name,
    List<String>? editedArtist2TrackIDs,
    List<Map<String, dynamic>>? editedTracklist2,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    final ref = _firestore.collection('versus').doc(versusID);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Versus not found');

      final data = snap.data()!;
      final type = (data['type'] as String?)?.trim() ?? '';
      if (type != 'collaboration' && type != 'collaborator' && type != 'artist') {
        throw Exception('Not a supported versus type for this update');
      }

      final authorId = (data['authorID'] as String?)?.trim() ?? '';
      final collab = (data['collaboratorID'] as String?)?.trim() ?? '';
      final isAuthor = authorId.isNotEmpty && authorId == uid;
      final isCollaborator = collab.isNotEmpty && collab == uid;
      if (!isAuthor && !isCollaborator) {
        throw Exception('Only author or invited collaborator can confirm');
      }

      final st = (data['status'] as String?)?.trim() ?? '';
      if (st == 'completed') {
        throw Exception('This versus can no longer be updated');
      }

      final update = <String, dynamic>{};
      if (isAuthor) {
        update['artist1ID'] = editedArtistID.trim();
        update['artist1Name'] = editedArtistName.trim();
        update['artist1TrackIDs'] = editedTrackIDs.map((e) => e.trim()).toList();
        if (editedTracklist != null && editedTracklist.isNotEmpty) {
          update['artist1Tracklist'] = editedTracklist;
        }
        final ac = editedComment?.trim();
        if (ac != null && ac.isNotEmpty) {
          update['authorComment'] = ac;
        }
        final un = (editorUsername ?? '').trim();
        if (un.isNotEmpty) {
          update['author_username'] = un;
        }
        final av = (editorAvatarPath ?? '').trim();
        if (av.isNotEmpty) {
          update['author_avatar'] = av;
        }
        final noCollaborator = collab.isEmpty;
        final a2id = (editedArtist2ID ?? '').trim();
        if (noCollaborator &&
            a2id.isNotEmpty &&
            editedArtist2TrackIDs != null) {
          update['artist2ID'] = a2id;
          update['artist2Name'] = (editedArtist2Name ?? '').trim();
          update['artist2TrackIDs'] =
              editedArtist2TrackIDs.map((e) => e.trim()).toList();
          if (editedTracklist2 != null && editedTracklist2.isNotEmpty) {
            update['artist2Tracklist'] = editedTracklist2;
          }
        }
      } else {
        update['artist2ID'] = editedArtistID.trim();
        update['artist2Name'] = editedArtistName.trim();
        update['artist2TrackIDs'] = editedTrackIDs.map((e) => e.trim()).toList();
        if (editedTracklist != null && editedTracklist.isNotEmpty) {
          update['artist2Tracklist'] = editedTracklist;
        }
        final cc = editedComment?.trim();
        if (cc != null && cc.isNotEmpty) {
          update['collaboratorComment'] = cc;
        }
        update['collaborator_username'] = (editorUsername ?? '').trim();
        update['collaborator_avatar'] = (editorAvatarPath ?? '').trim();
      }

      // Write ranking metadata if not already present.
      if ((data['entity_type'] as String? ?? '').isEmpty) {
        update['entity_type'] = 'artist';
      }
      final a1Final = isAuthor
          ? editedArtistID.trim()
          : (data['artist1ID'] as String? ?? '').trim();
      final a2Final = isAuthor
          ? ((editedArtist2ID ?? '').trim().isNotEmpty
              ? (editedArtist2ID ?? '').trim()
              : (data['artist2ID'] as String? ?? '').trim())
          : editedArtistID.trim();
      final selfMatchup = isSelfMatchup(a1Final, a2Final);
      update['is_self_matchup'] = selfMatchup;
      if (!selfMatchup &&
          a1Final.isNotEmpty &&
          a2Final.isNotEmpty &&
          (data['pair_key'] as String? ?? '').isEmpty) {
        update['pair_key'] = makePairKey(a1Final, a2Final);
      }

      // Any non-completed collaboration edit should remain visible/active for battle.
      if (st == 'incomplete' || st.isEmpty) {
        update['status'] = 'open';
      }

      tx.update(ref, update);
    });

    debugPrint(
        '[FirebaseService] acceptCollaborationInvite → $versusID by $uid');

  }

  // ── Author finalizes tracks after invite (stays incomplete until collaborator) ─
  /// Called when the author clicks CREATE after having already sent an invite.
  /// Patches the existing collaboration doc with final artist1 tracks (and optional
  /// artist2 fields). **Does not** set `status` to `open` — the invited user does
  /// that via [acceptCollaborationInvite] when they finish in the backroom.
  static Future<void> openCollaborationVersus({
    required String versusID,
    required List<String> artist1TrackIDs,
    String? artist2ID,
    String? artist2Name,
    String? authorComment,
  }) async {
    final data = <String, dynamic>{
      'status': 'incomplete',
      'artist1TrackIDs': artist1TrackIDs.map((e) => e.trim()).toList(),
    };
    if (artist2ID != null && artist2ID.trim().isNotEmpty) {
      data['artist2ID'] = artist2ID.trim();
    }
    if (artist2Name != null && artist2Name.trim().isNotEmpty) {
      data['artist2Name'] = artist2Name.trim();
    }
    final comment = authorComment?.trim();
    if (comment != null && comment.isNotEmpty) {
      data['authorComment'] = comment;
    }
    await _firestore.collection('versus').doc(versusID).update(data);
    debugPrint(
        '[FirebaseService] openCollaborationVersus → $versusID (author tracks; status stays incomplete)');
    // Versus remains incomplete — no ranking stubs until collaborator confirms
    // and [acceptCollaborationInvite] sets status open|active.
  }

  // ── Update status ─────────────────────────────────────────────────────────
  static Future<void> updateArtistVersusStatus({
    required String documentId,
    required String status,
  }) async {
    assert(
      ['open', 'active', 'completed'].contains(status),
      'status must be open | active | completed',
    );
    await _firestore
        .collection('versus')
        .doc(documentId)
        .update({'status': status});
    debugPrint(
        '[FirebaseService] updateArtistVersusStatus → $documentId = $status');
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  static Future<void> deleteVersus(String documentId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');
    await _firestore.collection('versus').doc(documentId).delete();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // POLLS
  // ══════════════════════════════════════════════════════════════════════════

  /// Upserts a poll document for an artist versus session.
  ///
  /// Doc ID is deterministic: `{versusId}_{voterId}` — guarantees one doc
  /// per voter per versus, and makes the existence check a direct get()
  /// rather than a query (cheaper, faster).
  ///
  /// Called on every debounced vote tap. Uses set() with merge:false on
  /// creation, update() on subsequent taps — so only changed fields are
  /// sent on updates, keeping write costs minimal.
  // ── Unified poll write (replaces upsertArtistPoll / upsertAlbumPoll) ─────
  static const int _minRoundsToSave = 2;

  /// Writes or updates a unified poll document at `polls/{versusId}_{voterId}`.
  ///
  /// Gate: for new documents, skips if fewer than [_minRoundsToSave] non-bonus
  /// rounds have been decided (winner != null). Existing documents are always
  /// updated so in-progress state is preserved.
  static Future<void> upsertPoll({
    required String versusId,
    required String pairKey,
    required String entityType,
    required String voterId,
    required String voterName,
    required String voterAvatar,
    required String entity1Id,
    required String entity1Name,
    required String entity2Id,
    required String entity2Name,
    required List<Map<String, dynamic>> trackDetails,
    required double completionPercentage,
    required int unvotedCount,
  }) async {
    final vid = versusId.trim();
    final uid = voterId.trim();
    if (vid.isEmpty || uid.isEmpty) {
      debugPrint('[FirebaseService] upsertPoll → skipped: empty versusId or voterId');
      return;
    }

    final docId = '${vid}_$uid';
    final ref = _firestore.collection('polls').doc(docId);

    int entity1Votes = 0, entity2Votes = 0;
    for (final r in trackDetails) {
      if (r['isBonus'] == true) continue;
      if (r['winner'] == 'entity1') entity1Votes++;
      if (r['winner'] == 'entity2') entity2Votes++;
    }
    final decidedRounds = entity1Votes + entity2Votes;
    final total = decidedRounds;
    final e1Pct = total == 0 ? 0.0 : entity1Votes / total * 100;
    final e2Pct = total == 0 ? 0.0 : entity2Votes / total * 100;

    final selfMatchup = isSelfMatchup(entity1Id, entity2Id);
    try {
      final snap = await ref.get();
      if (!snap.exists) {
        if (decidedRounds < _minRoundsToSave) {
          debugPrint(
            '[FirebaseService] upsertPoll → skipped: only $decidedRounds '
            'non-bonus round(s) decided (min $_minRoundsToSave)',
          );
          return;
        }
        await ref.set({
          'versus_id':   vid,
          'voter_id':    uid,
          'voter_name':  voterName.trim(),
          'voter_avatar': voterAvatar.trim(),
          // Self-matchup polls are excluded from pair/ranking writes; pair_key is null.
          'pair_key':    selfMatchup ? null : pairKey.trim(),
          'entity_type': entityType.trim(),
          'entity1_id':   entity1Id.trim(),
          'entity1_name': entity1Name.trim(),
          'entity2_id':   entity2Id.trim(),
          'entity2_name': entity2Name.trim(),
          'track_details': trackDetails,
          'summary': {
            'entity1_votes':      entity1Votes,
            'entity2_votes':      entity2Votes,
            'entity1_percentage': e1Pct,
            'entity2_percentage': e2Pct,
          },
          'completion_percentage': completionPercentage,
          'unvoted_count': unvotedCount,
          'created_at': FieldValue.serverTimestamp(),
          'timestamp':  FieldValue.serverTimestamp(),
        });
        debugPrint('[FirebaseService] upsertPoll → created $docId');
      } else {
        await ref.update({
          'pair_key':    selfMatchup ? null : pairKey.trim(),
          'entity_type': entityType.trim(),
          'entity1_id':   entity1Id.trim(),
          'entity1_name': entity1Name.trim(),
          'entity2_id':   entity2Id.trim(),
          'entity2_name': entity2Name.trim(),
          'track_details': trackDetails,
          'summary': {
            'entity1_votes':      entity1Votes,
            'entity2_votes':      entity2Votes,
            'entity1_percentage': e1Pct,
            'entity2_percentage': e2Pct,
          },
          'completion_percentage': completionPercentage,
          'unvoted_count': unvotedCount,
          'timestamp': FieldValue.serverTimestamp(),
        });
        debugPrint('[FirebaseService] upsertPoll → updated $docId');
      }
    } catch (e) {
      debugPrint('[FirebaseService] upsertPoll($docId) failed: $e');
    }
  }

  /// Returns the raw poll document data for session restore, or null if absent.
  static Future<Map<String, dynamic>?> getExistingPoll({
    required String versusId,
    required String voterId,
  }) async {
    final vId = versusId.trim();
    final uId = voterId.trim();
    if (vId.isEmpty || uId.isEmpty) return null;
    try {
      final doc = await _firestore.collection('polls').doc('${vId}_$uId').get();
      if (!doc.exists || doc.data() == null) return null;
      debugPrint('[FirebaseService] getExistingPoll → found ${vId}_$uId');
      return doc.data();
    } catch (e) {
      debugPrint('[FirebaseService] getExistingPoll failed: $e');
      return null;
    }
  }

  /// Queries `pairs` where `entity_ids` array-contains [entityId].
  static Future<List<PairModel>> getPairsForEntity(String entityId) async {
    final id = entityId.trim();
    if (id.isEmpty) return [];
    try {
      final snap = await _firestore
          .collection('pairs')
          .where('entity_ids', arrayContains: id)
          .get();
      return snap.docs
          .map((doc) => PairModel.fromFirestore(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('[FirebaseService] getPairsForEntity($id) failed: $e');
      return [];
    }
  }

  // ── Fetch all polls by a voter (history / profile screen) ─────────────
  static Future<List<Map<String, dynamic>>> getPollsByVoter({
    required String voterId,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    if (voterId.trim().isEmpty) return [];
    try {
      var query = _firestore
          .collection('polls')
          .where('voter_id', isEqualTo: voterId.trim())
          .orderBy('timestamp', descending: true)
          .limit(limit);
      if (startAfter != null) query = query.startAfterDocument(startAfter);
      final snap = await query.get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('[FirebaseService] getPollsByVoter($voterId) failed: $e');
      return [];
    }
  }

  // ── Fetch rankings by Spotify IDs ─────────────────────────────────────────────
  /// Fetches ranking docs for the given [ids] (Spotify entity IDs).
  /// Deduplicates, chunks into batches of ≤30 (Firestore whereIn limit),
  /// and returns a map of id → [RankingModel]. Missing IDs are absent from
  /// the map (not defaulted to any value).
  static Future<Map<String, RankingModel>> getRankingsByIds(
    List<String> ids,
  ) async {
    final deduped =
        ids.where((id) => id.isNotEmpty).toSet().toList();
    if (deduped.isEmpty) return {};
    final result = <String, RankingModel>{};
    const chunkSize = 30;
    for (var i = 0; i < deduped.length; i += chunkSize) {
      final chunk = deduped.sublist(
        i,
        (i + chunkSize).clamp(0, deduped.length),
      );
      try {
        final snap = await _firestore
            .collection('rankings')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          result[doc.id] = RankingModel.fromFirestore(doc.data(), doc.id);
        }
      } catch (e) {
        debugPrint('[FirebaseService] getRankingsByIds chunk failed: $e');
      }
    }
    return result;
  }

  // ── Search users by username (substring match, case-insensitive) ─────────
  /// `username_search` holds every 2+ char substring of the lowercase username
  /// (written by the `onUserWritten` Cloud Function), so a substring search is
  /// a single `array-contains` query — cost scales with results, not users.
  /// 1-char queries use a prefix range instead. Prefix matches rank first
  /// ("nolan" → "nolan_x" before "mrnolan").
  static Future<List<UserModel>> searchUsersByUsername(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final currentUid = _auth.currentUser?.uid;
    const limit = 20;

    try {
      final users = _firestore.collection('users');
      final snapshot = q.length >= 2
          ? await users
              .where('username_search', arrayContains: q)
              .limit(limit + 1)
              .get()
          : await users
              .where('username', isGreaterThanOrEqualTo: q)
              .where('username', isLessThan: '$q\uf8ff')
              .limit(limit + 1)
              .get();

      final matches = snapshot.docs
          .where((doc) => doc.id != currentUid)
          .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
          .toList()
        ..sort((a, b) {
          final ap = a.username.startsWith(q) ? 0 : 1;
          final bp = b.username.startsWith(q) ? 0 : 1;
          if (ap != bp) return ap - bp;
          return a.username.length - b.username.length;
        });
      return matches.take(limit).toList();
    } catch (e) {
      debugPrint('[FirebaseService] searchUsersByUsername("$q") failed: $e');
      return [];
    }
  }

  // ── Check if current user is admin ───────────────────────────────────────
  static Future<bool> isCurrentUserAdmin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return false;
      return (doc.data()?['admin'] as bool?) == true;
    } catch (e) {
      debugPrint('[FirebaseService] isCurrentUserAdmin failed: $e');
      return false;
    }
  }

  // ── Backfill: add admin:false to all users missing the field ──────────────
  /// One-time migration. Scans every doc in [users] and writes `admin: false`
  /// to any doc that does not yet have the [admin] field.
  /// Returns `{'scanned': N, 'updated': M}`.
  /// Safe to re-run — skips docs that already have the field.
  static Future<Map<String, int>> backfillAdminField() async {
    final snapshot = await _firestore.collection('users').get();
    final docs = snapshot.docs;

    final toUpdate = docs
        .where((doc) => !doc.data().containsKey('admin'))
        .toList();

    const chunkSize = 500;
    for (var i = 0; i < toUpdate.length; i += chunkSize) {
      final chunk = toUpdate.sublist(
        i,
        (i + chunkSize) > toUpdate.length ? toUpdate.length : i + chunkSize,
      );
      final batch = _firestore.batch();
      for (final doc in chunk) {
        batch.update(doc.reference, {'admin': false});
      }
      await batch.commit();
    }

    debugPrint(
      '[FirebaseService] backfillAdminField → '
      'scanned ${docs.length}, updated ${toUpdate.length}',
    );
    return {'scanned': docs.length, 'updated': toUpdate.length};
  }

  // ── Username rules & uniqueness ───────────────────────────────────────────
  /// Returns an error message, or null if [raw] is an acceptable username.
  /// Keep in sync with `isValidUsername` in firestore.rules.
  static String? validateUsername(String raw) {
    final name = raw.trim().toLowerCase();
    if (name.length < 3 || name.length > 20) {
      return 'Username must be 3–20 characters.';
    }
    if (!RegExp(r'^[a-z0-9_.]+$').hasMatch(name) ||
        RegExp(r'^__.*__$').hasMatch(name)) {
      return 'Use only letters, numbers, _ and .';
    }
    return null;
  }

  /// One read of `usernames/{name}`. Readable while signed out, so signup can
  /// check before Google sign-in. Advisory only — the claim transaction in
  /// [_writeProfileClaimingUsername] is what actually guarantees uniqueness.
  static Future<bool> isUsernameAvailable(String raw) async {
    final name = raw.trim().toLowerCase();
    final claim = await _firestore.collection('usernames').doc(name).get();
    if (!claim.exists) return true;
    final owner = claim.data()?['uid'];
    return owner != null && owner == _auth.currentUser?.uid;
  }

  /// Writes [data] to `users/{uid}` while atomically claiming
  /// `usernames/{username}` and releasing the user's previous claim.
  /// Throws [UsernameTakenException] if another user owns [username].
  static Future<void> _writeProfileClaimingUsername({
    required String uid,
    required String username,
    required Map<String, dynamic> data,
  }) async {
    final userRef = _firestore.collection('users').doc(uid);
    final names = _firestore.collection('usernames');
    final newClaimRef = names.doc(username);

    await _firestore.runTransaction((tx) async {
      // All reads before any writes (Firestore transaction requirement).
      final userSnap = await tx.get(userRef);
      final newClaim = await tx.get(newClaimRef);
      final oldName = userSnap.data()?['username'] as String?;
      final oldClaimRef = (oldName != null && oldName.isNotEmpty && oldName != username)
          ? names.doc(oldName)
          : null;
      final oldClaim = oldClaimRef == null ? null : await tx.get(oldClaimRef);

      final claimedByOther =
          newClaim.exists && newClaim.data()?['uid'] != uid;
      if (oldName == username) {
        // Keeping the current name. Pre-uniqueness accounts may hold a name
        // that is invalid or duplicated; rules allow keeping it, so only claim
        // it when that's possible.
        if (!newClaim.exists && validateUsername(username) == null) {
          tx.set(newClaimRef, {'uid': uid});
        }
      } else {
        if (claimedByOther) throw UsernameTakenException(username);
        if (!newClaim.exists) tx.set(newClaimRef, {'uid': uid});
      }
      tx.set(userRef, {...data, 'username': username}, SetOptions(merge: true));
      if (oldClaim != null && oldClaim.exists && oldClaim.data()?['uid'] == uid) {
        tx.delete(oldClaimRef!);
      }
    });
  }

  // ── Create / update user profile ─────────────────────────────────────────
  /// Throws [UsernameTakenException] if [username] belongs to someone else.
  static Future<void> createUserProfile({
    required String uid,
    required String username,
    required String avatarPath,
    String bio = '',
    List<FavoriteAlbumEntry>? favoriteAlbums,
  }) async {
    await _writeProfileClaimingUsername(
      uid: uid,
      username: username.trim().toLowerCase(),
      data: {
        'bio': bio.trim(),
        'avatar_path': avatarPath,
        'favorite_albums': _serializeFavoriteAlbums(favoriteAlbums),
      },
    );
    if (_auth.currentUser?.uid == uid) {
      await _fetchCurrentUserFromFirestore(uid);
    }
  }

  // ── Update current user's editable profile fields ─────────────────────────
  /// Throws [UsernameTakenException] if [username] belongs to someone else.
  static Future<void> updateCurrentUserProfile({
    required String username,
    required String bio,
    required String avatarPath,
    List<FavoriteAlbumEntry>? favoriteAlbums,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    await _writeProfileClaimingUsername(
      uid: uid,
      username: username.trim().toLowerCase(),
      data: {
        'bio': bio.trim(),
        'avatar_path': avatarPath.trim(),
        if (favoriteAlbums != null)
          'favorite_albums': _serializeFavoriteAlbums(favoriteAlbums),
      },
    );
    await _fetchCurrentUserFromFirestore(uid);
  }

  static List<Map<String, dynamic>> _serializeFavoriteAlbums(
    List<FavoriteAlbumEntry>? favoriteAlbums,
  ) {
    return (favoriteAlbums ?? const <FavoriteAlbumEntry>[])
        .where((album) => album.albumId.trim().isNotEmpty)
        .take(5)
        .map((album) => album.toMap())
        .toList();
  }

  // ── Update only the favorite_albums field for the current user ────────────
  static Future<void> updateFavoriteAlbums(
    List<FavoriteAlbumEntry> albums,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    await _firestore.collection('users').doc(uid).set(
      {'favorite_albums': _serializeFavoriteAlbums(albums)},
      SetOptions(merge: true),
    );
    await _fetchCurrentUserFromFirestore(uid);
  }

  // ── Posts ─────────────────────────────────────────────────────────────────

  /// Creates a new document in the `posts` collection.
  /// [authorID], [authorName], [authorAvatar] are resolved from the current
  /// Firebase user + cached Firestore profile automatically.
  /// [artistID], [artistName], [artistImageUrl], [description], [tracklist]
  /// come from the create-post screen.
  /// Returns the new document ID.
  static Future<String> createPost({
    required String artistID,
    required String artistName,
    required String artistImageUrl,
    required String description,
    required List<Map<String, dynamic>> tracklist,
    RemixEnabled remixEnabled = RemixEnabled.same,
    List<String> mentionedUids = const [],
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not logged in');

    final profile = await getCurrentUser();
    final authorName = (profile?.username.trim().isNotEmpty ?? false)
        ? profile!.username.trim()
        : (_auth.currentUser?.displayName?.trim().isNotEmpty ?? false
            ? _auth.currentUser!.displayName!.trim()
            : 'User');
    final authorAvatar = profile?.avatarPath.trim() ?? '';

    final recipients = mentionedUids
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty && u != uid)
        .toSet()
        .toList();

    final now = FieldValue.serverTimestamp();
    final ref = await _firestore.collection('posts').add({
      'authorID':         uid,
      'authorName':       authorName,
      'Author_avatar':    authorAvatar,
      'artistID':         artistID,
      'Artistname':       artistName,
      'Artist_image_url': artistImageUrl,
      'Description':      description.trim(),
      'Sharecount':       0,
      'Remixcount':       0,
      'remixenabled':     remixEnabled.firestoreValue,
      'Tracklist':        tracklist,
      'mentionedUids':    recipients,
      'Created_at':       now,
      'modified_at':      now,
    });
    final postId = ref.id;

    if (recipients.isNotEmpty) {
      try {
        await _sendMentionNotifications(
          authorUid: uid,
          authorName: authorName,
          authorAvatar: authorAvatar,
          postId: postId,
          recipientUids: recipients,
        );
      } catch (e) {
        debugPrint('[FirebaseService] createPost → mention notifications failed: $e');
      }
    }

    return postId;
  }

  // ── Write a durable inbox doc + push to each friend tagged in a post ───────
  /// Uses auto-generated doc IDs — a user can be mentioned in many posts,
  /// unlike follow (one doc per follower) or invite (one invite at a time).
  static Future<void> _sendMentionNotifications({
    required String authorUid,
    required String authorName,
    required String authorAvatar,
    required String postId,
    required List<String> recipientUids,
  }) async {
    final batch = _firestore.batch();
    for (final recipientUid in recipientUids) {
      final ref = _firestore
          .collection('users')
          .doc(recipientUid)
          .collection('notifications')
          .doc();
      batch.set(ref, {
        'type':          'mention',
        'read':          false,
        'timestamp':     FieldValue.serverTimestamp(),
        'authorID':      authorUid,
        'authorName':    authorName,
        'author_avatar': authorAvatar,
        'postID':        postId,
      });
    }
    await batch.commit();

    await NotificationService.notifyUsersMentionedInPost(
      recipientUids: recipientUids,
      postId: postId,
    );
  }

  /// Live stream of all posts, ordered by newest first.
  static Stream<List<PostModel>> getPostsStream() {
    return _firestore
        .collection('posts')
        .orderBy('Created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PostModel.fromFirestore(d.data(), d.id))
            .toList());
  }

  /// One-time page of posts, newest first. Pass the previous page's
  /// [PostsPage.lastDoc] as [startAfter] to fetch the next page.
  static Future<PostsPage> getPostsPage({
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    var query = _firestore
        .collection('posts')
        .orderBy('Created_at', descending: true)
        .limit(limit);
    if (startAfter != null) query = query.startAfterDocument(startAfter);

    final snap = await query.get();
    return PostsPage(
      posts: snap.docs
          .map((d) => PostModel.fromFirestore(d.data(), d.id))
          .toList(),
      lastDoc: snap.docs.isEmpty ? null : snap.docs.last,
      hasMore: snap.docs.length == limit,
    );
  }

  /// One-time fetch of posts newer than [since], newest first. Used to pull
  /// in newly-arrived posts without re-fetching the whole feed.
  static Future<List<PostModel>> getPostsNewerThan(Timestamp since) async {
    final snap = await _firestore
        .collection('posts')
        .where('Created_at', isGreaterThan: since)
        .orderBy('Created_at', descending: true)
        .get();
    return snap.docs
        .map((d) => PostModel.fromFirestore(d.data(), d.id))
        .toList();
  }

  /// Cheap (1-doc) live listener on just the newest post, used to drive a
  /// "N new posts" indicator without streaming/re-fetching the full feed.
  ///
  /// Skips snapshots with a pending local write: a new post's `Created_at`
  /// (a `FieldValue.serverTimestamp()`) reads back as null until the server
  /// ack arrives, so without this filter a single `add()` emits twice —
  /// once locally with a null timestamp, once confirmed — double-counting
  /// the "new posts" indicator for one actual post.
  static Stream<PostModel?> watchNewestPost() {
    return _firestore
        .collection('posts')
        .orderBy('Created_at', descending: true)
        .limit(1)
        .snapshots()
        .where((snap) => !snap.metadata.hasPendingWrites)
        .map((snap) => snap.docs.isEmpty
            ? null
            : PostModel.fromFirestore(snap.docs.first.data(), snap.docs.first.id));
  }

  /// Live stream of posts by one author, ordered by newest first.
  static Stream<List<PostModel>> getPostsByAuthorStream(String authorId) {
    final uid = authorId.trim();
    if (uid.isEmpty) return Stream.value(const <PostModel>[]);

    return _firestore
        .collection('posts')
        .where('authorID', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final posts = snap.docs
          .map((d) => PostModel.fromFirestore(d.data(), d.id))
          .where((p) => p.authorID.trim() == uid)
          .toList();
      posts.sort((a, b) {
        final aDate = a.createdAt?.toDate();
        final bDate = b.createdAt?.toDate();
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      return posts;
    });
  }

  /// Live stream of posts for a Spotify artist/entity id.
  ///
  /// Firestore filters by `artistID`; ordering is client-side by whichever
  /// timestamp is newer between `modified_at` and `Created_at`.
  static Stream<List<PostModel>> getPostsByArtistStream(String artistId) {
    final id = artistId.trim();
    if (id.isEmpty) return Stream.value(const <PostModel>[]);

    DateTime? latest(PostModel post) {
      final created = post.createdAt?.toDate();
      final modified = post.modifiedAt?.toDate();
      if (created == null) return modified;
      if (modified == null) return created;
      return modified.isAfter(created) ? modified : created;
    }

    return _firestore
        .collection('posts')
        .where('artistID', isEqualTo: id)
        .snapshots()
        .map((snap) {
      final posts = snap.docs
          .map((d) => PostModel.fromFirestore(d.data(), d.id))
          .where((p) => p.artistID.trim() == id)
          .toList();
      posts.sort((a, b) {
        final aDate = latest(a);
        final bDate = latest(b);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      return posts;
    });
  }

  /// One-time fetch of posts for a Spotify artist/entity id.
  ///
  /// Uses the same ordering rule as [getPostsByArtistStream].
  static Future<List<PostModel>> getPostsByArtistList(String artistId) async {
    final id = artistId.trim();
    if (id.isEmpty) return const <PostModel>[];

    DateTime? latest(PostModel post) {
      final created = post.createdAt?.toDate();
      final modified = post.modifiedAt?.toDate();
      if (created == null) return modified;
      if (modified == null) return created;
      return modified.isAfter(created) ? modified : created;
    }

    final snap = await _firestore
        .collection('posts')
        .where('artistID', isEqualTo: id)
        .get();
    final posts = snap.docs
        .map((d) => PostModel.fromFirestore(d.data(), d.id))
        .where((p) => p.artistID.trim() == id)
        .toList();
    posts.sort((a, b) {
      final aDate = latest(a);
      final bDate = latest(b);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return posts;
  }

  /// Real-time stream for a single post document.
  /// Emits a new [PostModel] whenever any field on the doc changes —
  /// [Remixcount], [Sharecount], etc. update in real-time with no polling.
  static Stream<PostModel?> getPostStream(String postId) {
    final id = postId.trim();
    if (id.isEmpty) return Stream.value(null);
    return _firestore
        .collection('posts')
        .doc(id)
        .snapshots()
        .map((snap) => snap.exists && snap.data() != null
            ? PostModel.fromFirestore(snap.data()!, snap.id)
            : null);
  }

  /// Real-time stream of all remix versus docs that reference [postId] as
  /// their source post. Returns the raw Firestore data plus a synthetic 'id'
  /// key so callers never need to query the doc ID separately.
  static Stream<List<Map<String, dynamic>>> getPostRemixesStream(String postId) {
    final id = postId.trim();
    if (id.isEmpty) return Stream.value(const []);
    return _firestore
        .collection('versus')
        .where('sourcePostID', isEqualTo: id)
        .snapshots()
        .map((snap) {
          final docs = snap.docs
              .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
              .toList();
          // Sort newest-first client-side — avoids the composite index that
          // Firestore requires for where(...).orderBy('timestamp').
          docs.sort((a, b) {
            final ta = (a['timestamp'] as dynamic)?.millisecondsSinceEpoch ?? 0;
            final tb = (b['timestamp'] as dynamic)?.millisecondsSinceEpoch ?? 0;
            return (tb as int).compareTo(ta as int);
          });
          return docs;
        });
  }
}