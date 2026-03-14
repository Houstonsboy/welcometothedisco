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

  /// Inbox list: optional [typeFilter] 'album' | 'artist' | null (both).
  /// When null, returns both types merged and ordered by [timestamp] descending.
  static Future<List<InboxVersusEntry>> getInboxVersusList({
    String? typeFilter,
  }) async {
    if (typeFilter == 'album') {
      final list = await getVersusList();
      return list
          .map((v) => InboxVersusEntry(
                type: 'album',
                timestamp: v.timestamp,
                albumVersus: v,
              ))
          .toList();
    }
    if (typeFilter == 'artist') {
      final list = await getArtistVersusList();
      return list
          .map((v) => InboxVersusEntry(
                type: 'artist',
                timestamp: v.timestamp,
                artistVersus: v,
              ))
          .toList();
    }
    // Both: fetch in parallel, merge by timestamp desc
    final results = await Future.wait([
      getVersusList(),
      getArtistVersusList(),
    ]);
    final albums = results[0] as List<VersusModel>;
    final artists = results[1] as List<ArtistVersusModel>;
    final List<InboxVersusEntry> merged = [
      ...albums.map((v) => InboxVersusEntry(
            type: 'album',
            timestamp: v.timestamp,
            albumVersus: v,
          )),
      ...artists.map((v) => InboxVersusEntry(
            type: 'artist',
            timestamp: v.timestamp,
            artistVersus: v,
          )),
    ];
    merged.sort((a, b) {
      final ta = a.timestamp?.millisecondsSinceEpoch ?? 0;
      final tb = b.timestamp?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });
    return merged;
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
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

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
    );

    final ref =
        await _firestore.collection('versus').add(model.toFirestore());

    debugPrint('[FirebaseService] createArtistVersus → doc: ${ref.id}');
    return ref.id;
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
      'username': username,
      'bio': bio,
      'avatar_path': avatarPath,
    }, SetOptions(merge: true));
  }
}