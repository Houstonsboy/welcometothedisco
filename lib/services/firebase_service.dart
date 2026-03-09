// lib/services/firebase_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/models/users_model.dart';

class FirebaseService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // ── Fetch user by UID from users collection ───────────────────────────────
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

  // ── Enrich versus list with author data from users collection ─────────────
  static Future<List<VersusModel>> _enrichWithAuthors(
      List<VersusModel> versusList) async {
    // collect unique author IDs to avoid duplicate fetches
    final authorIds = versusList
        .map((v) => v.authorId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    // fetch all authors in parallel
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

    // attach author to each versus
    for (final versus in versusList) {
      versus.author = authorMap[versus.authorId];
    }

    return versusList;
  }

  // ── Realtime stream with author data ──────────────────────────────────────
  static Stream<List<VersusModel>> getVersusStream() {
    return _firestore
        .collection('versus')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final versusList = snapshot.docs
              .map((doc) => VersusModel.fromFirestore(doc.data(), doc.id))
              .toList();
          return _enrichWithAuthors(versusList);
        });
  }

  // ── One time fetch with author data ───────────────────────────────────────
  static Future<List<VersusModel>> getVersusList() async {
    final snapshot = await _firestore
        .collection('versus')
        .orderBy('timestamp', descending: true)
        .get();

    final versusList = snapshot.docs
        .map((doc) => VersusModel.fromFirestore(doc.data(), doc.id))
        .toList();

    return _enrichWithAuthors(versusList);
  }

  // ── Create ────────────────────────────────────────────────────────────────
  static Future<void> createVersus({
    required String album1ID,
    required String album1Name,
    required String album2ID,
    required String album2Name,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    await _firestore.collection('versus').add({
      'Author': uid,
      'album1ID': album1ID,
      'album1Name': album1Name,
      'album2ID': album2ID,
      'album2Name': album2Name,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Saves a versus document from lockeroom input.
  /// Document fields in "versus":
  /// Author, album1ID, album1Name, album2ID, album2Name, timestamp
  static Future<void> createVersusFromLockeroom({
    required String album1ID,
    required String album1Name,
    required String album2ID,
    required String album2Name,
  }) async {
    await createVersus(
      album1ID: album1ID.trim(),
      album1Name: album1Name.trim(),
      album2ID: album2ID.trim(),
      album2Name: album2Name.trim(),
    );
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  static Future<void> deleteVersus(String documentId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not logged in');

    await _firestore.collection('versus').doc(documentId).delete();
  }

  // ── Fetch by author ───────────────────────────────────────────────────────
  static Stream<List<VersusModel>> getVersusByAuthor(String authorId) {
    return _firestore
        .collection('versus')
        .where('Author', isEqualTo: authorId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final versusList = snapshot.docs
              .map((doc) => VersusModel.fromFirestore(doc.data(), doc.id))
              .toList();
          return _enrichWithAuthors(versusList);
        });
  }
}