// lib/services/firebase_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:welcometothedisco/models/artist_versus_model.dart';
import 'package:welcometothedisco/models/inbox_versus_entry.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/models/users_model.dart';

class FirebaseService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

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
    return getUserById(uid);
  }

  // ── Live stream of current user's document ────────────────────────────────
  /// Emits a new [UserModel] whenever the user's Firestore doc changes —
  /// friends list, username, avatar, etc. update in real-time with no
  /// extra fetch needed.
  static Stream<UserModel?> getCurrentUserStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) {
          if (!snap.exists || snap.data() == null) return null;
          return UserModel.fromFirestore(snap.data()!, snap.id);
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
      } else if (type == 'artist' || type == 'collaboration') {
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

  /// One-time migration — adds type: "album" to all versus docs missing the field.
  /// Call this once from a dev screen or admin button, then delete it.
  /// Note: Firestore batch limit is 500; if you have more docs, run multiple times or chunk.
  static Future<void> backfillVersusType() async {
    final snapshot = await _firestore.collection('versus').get();

    final batch = _firestore.batch();
    int count = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (!data.containsKey('type')) {
        batch.update(doc.reference, {'type': 'album'});
        count++;
      }
    }

    if (count > 0) {
      await batch.commit();
      debugPrint('[FirebaseService] backfillVersusType → updated $count docs');
    } else {
      debugPrint('[FirebaseService] backfillVersusType → nothing to update');
    }
  }

  // ── Create album versus ───────────────────────────────────────────────────
  static Future<void> createVersus({
    required String type,
    required String album1ID,
    required String album1Name,
    required String album2ID,
    required String album2Name,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    await _firestore.collection('versus').add({
      'type': type,
      'status': 'open',
      'Author': uid,
      'album1ID': album1ID,
      'album1Name': album1Name,
      'album2ID': album2ID,
      'album2Name': album2Name,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> createVersusFromLockeroom({
    required String album1ID,
    required String album1Name,
    required String album2ID,
    required String album2Name,
  }) async {
    await createVersus(
      type: 'album',
      album1ID: album1ID.trim(),
      album1Name: album1Name.trim(),
      album2ID: album2ID.trim(),
      album2Name: album2Name.trim(),
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
    );

    final ref =
        await _firestore.collection('versus').add(model.toFirestore());

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
  }) {
    return createArtistVersus(
      artist1ID: artist1ID,
      artist1Name: artist1Name,
      artist1TrackIDs: artist1TrackIDs,
      artist2ID: artist2ID,
      artist2Name: artist2Name,
      artist2TrackIDs: artist2TrackIDs,
      authorComment: authorComment,
    );
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
    // Author note from the comment strip
    String? authorComment,
    // Selected recipient from invite banner (nullable)
    String? collaboratorUID,
    String? collaboratorUsername,
    String? collaboratorAvatarPath,
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
      } catch (e) {
        debugPrint(
            '[FirebaseService] createCollaborationInvite → notification failed: $e');
      }
    }

    return versusID;
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

      tx.update(ref, {
        'collaboratorID': uid,
        'artist2ID': artist2ID.trim(),
        'artist2Name': artist2Name.trim(),
        'artist2TrackIDs':
            artist2TrackIDs.map((e) => e.trim()).toList(),
        'status': 'active',
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
    required String artist2ID,
    required String artist2Name,
    required List<String> artist2TrackIDs,
    String? collaboratorComment,
    String? collaboratorUsername,
    String? collaboratorAvatarPath,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    final ref = _firestore.collection('versus').doc(versusID);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Versus not found');

      final data = snap.data()!;
      final type = (data['type'] as String?)?.trim() ?? '';
      if (type != 'collaboration') {
        throw Exception('Not a collaboration versus');
      }

      final collab = (data['collaboratorID'] as String?)?.trim() ?? '';
      if (collab.isEmpty) {
        throw Exception('This draft has no invited collaborator');
      }
      if (collab != uid) {
        throw Exception('Only the invited collaborator can confirm');
      }

      final st = (data['status'] as String?)?.trim() ?? '';
      if (st != 'incomplete' && st != 'open') {
        throw Exception('This versus can no longer be updated');
      }

      final update = <String, dynamic>{
        'artist2ID': artist2ID.trim(),
        'artist2Name': artist2Name.trim(),
        'artist2TrackIDs': artist2TrackIDs.map((e) => e.trim()).toList(),
        // Recipient completes the draft → visible in inbox (`getInboxVersusList`).
        'status': 'open',
        'collaborator_username': (collaboratorUsername ?? '').trim(),
        'collaborator_avatar': (collaboratorAvatarPath ?? '').trim(),
      };
      final cc = collaboratorComment?.trim();
      if (cc != null && cc.isNotEmpty) {
        update['collaboratorComment'] = cc;
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

  // ── Search users by username (prefix match, case-insensitive) ────────────
  /// All usernames are stored lowercase, so lowercasing the query gives
  /// case-insensitive prefix search with no extra Firestore index needed.
  static Future<List<UserModel>> searchUsersByUsername(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final currentUid = _auth.currentUser?.uid;

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: '$q\uf8ff')
          .limit(20)
          .get();

      return snapshot.docs
          .where((doc) => doc.id != currentUid)
          .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
          .toList();
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

  // ── Create / update user profile ─────────────────────────────────────────
  static Future<void> createUserProfile({
    required String uid,
    required String email,
    required String username,
    required String bio,
    required String avatarPath,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'email': email,
      'username': username.trim().toLowerCase(),
      'bio': bio,
      'avatar_path': avatarPath,
    }, SetOptions(merge: true));
  }

  // ── Update current user's editable profile fields ─────────────────────────
  static Future<void> updateCurrentUserProfile({
    required String username,
    required String bio,
    required String avatarPath,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    await _firestore.collection('users').doc(uid).set({
      'username': username.trim().toLowerCase(),
      'bio': bio.trim(),
      'avatar_path': avatarPath.trim(),
    }, SetOptions(merge: true));
  }
}