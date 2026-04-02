// lib/models/artist_versus_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:welcometothedisco/models/users_model.dart';

/// Firestore document shape (collection: 'versus', type: 'artist'):
///
/// {
///   type:             "artist",
///   artist1ID:        "spotify_artist_id",
///   artist1Name:      "Frank Ocean",
///   artist1TrackIDs:  ["trackId1", "trackId2", ...],
///   artist2ID:        "spotify_artist_id",
///   artist2Name:      "The Weeknd",
///   artist2TrackIDs:  ["trackId1", "trackId2", ...],
///   authorID:         "firebase_uid",
///   collaboratorID:   null | "firebase_uid",
///   status:           "open" | "active" | "completed",
///   timestamp:        Timestamp,
///   authorComment:     optional note from author (e.g. collaborator invite),
///   author_username / author_avatar — denormalized on collaboration docs,
///   collaboratorComment, collaborator_username, collaborator_avatar — invitee fields.
/// }
class ArtistVersusModel {
  // ── Firestore identity ────────────────────────────────────────────────────
  final String id;

  /// Firestore `type` field (e.g. `artist`, `collaboration`).
  final String type;

  // ── Artist 1 ──────────────────────────────────────────────────────────────
  final String artist1ID;
  final String artist1Name;
  final List<String> artist1TrackIDs;

  // ── Artist 2 ──────────────────────────────────────────────────────────────
  final String artist2ID;
  final String artist2Name;
  final List<String> artist2TrackIDs;

  // ── Ownership & collaboration ─────────────────────────────────────────────
  final String authorID;
  final String? collaboratorID;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  /// "open"      — artist2 slot is unclaimed, joinable by another user
  /// "active"    — both users are in, versus is running
  /// "completed" — voting/session is finished
  final String status;
  final Timestamp? timestamp;

  /// Optional message from the author (e.g. collab lockeroom note).
  final String? authorComment;

  /// Denormalized author profile (collaboration docs).
  final String? authorUsername;
  final String? authorAvatar;

  /// Invitee note + denormalized profile (set on accept).
  final String? collaboratorComment;
  final String? collaboratorUsername;
  final String? collaboratorAvatar;

  // ── Runtime-hydrated: users collection ───────────────────────────────────
  UserModel? author;
  UserModel? collaborator;

  // ── Runtime-hydrated: Spotify API ────────────────────────────────────────
  // Artist metadata
  String? artist1ImageUrl;
  String? artist2ImageUrl;

  // Full track objects resolved from artist1TrackIDs / artist2TrackIDs
  // These are never stored in Firestore — fetched fresh from Spotify at runtime.
  List<dynamic> artist1Tracks; // List<SpotifyTrack> — dynamic to avoid circular import
  List<dynamic> artist2Tracks;

  ArtistVersusModel({
    required this.id,
    this.type = 'artist',
    required this.artist1ID,
    required this.artist1Name,
    required this.artist1TrackIDs,
    required this.artist2ID,
    required this.artist2Name,
    required this.artist2TrackIDs,
    required this.authorID,
    this.collaboratorID,
    this.status = 'open',
    this.timestamp,
    this.authorComment,
    this.authorUsername,
    this.authorAvatar,
    this.collaboratorComment,
    this.collaboratorUsername,
    this.collaboratorAvatar,
    this.author,
    this.collaborator,
    this.artist1ImageUrl,
    this.artist2ImageUrl,
    this.artist1Tracks = const [],
    this.artist2Tracks = const [],
  });

  // ── Firestore → model ─────────────────────────────────────────────────────
  factory ArtistVersusModel.fromFirestore(
      Map<String, dynamic> data, String id) {
    return ArtistVersusModel(
      id: id,
      type: (data['type'] as String?)?.trim().isNotEmpty == true
          ? (data['type'] as String).trim()
          : 'artist',
      artist1ID: (data['artist1ID'] as String?)?.trim() ?? '',
      artist1Name: (data['artist1Name'] as String?)?.trim() ?? '',
      artist1TrackIDs: _parseStringList(data['artist1TrackIDs']),
      artist2ID: (data['artist2ID'] as String?)?.trim() ?? '',
      artist2Name: (data['artist2Name'] as String?)?.trim() ?? '',
      artist2TrackIDs: _parseStringList(data['artist2TrackIDs']),
      authorID: (data['authorID'] as String?)?.trim() ?? '',
      collaboratorID: (data['collaboratorID'] as String?)?.trim(),
      status: (data['status'] as String?)?.trim() ?? 'incomplete',
      timestamp: data['timestamp'] as Timestamp?,
      authorComment: (data['authorComment'] as String?)?.trim(),
      authorUsername: (data['author_username'] as String?)?.trim(),
      authorAvatar: (data['author_avatar'] as String?)?.trim(),
      collaboratorComment: (data['collaboratorComment'] as String?)?.trim(),
      collaboratorUsername: (data['collaborator_username'] as String?)?.trim(),
      collaboratorAvatar: (data['collaborator_avatar'] as String?)?.trim(),
    );
  }

  // ── model → Firestore ─────────────────────────────────────────────────────
  /// Use this when writing to Firestore — only persists what belongs there.
  /// Runtime-hydrated fields (images, track objects, user models) are excluded.
  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'artist1ID': artist1ID,
      'artist1Name': artist1Name,
      'artist1TrackIDs': artist1TrackIDs,
      'artist2ID': artist2ID,
      'artist2Name': artist2Name,
      'artist2TrackIDs': artist2TrackIDs,
      'authorID': authorID,
      'collaboratorID': collaboratorID,
      'status': status,
      'timestamp': FieldValue.serverTimestamp(),
      if (authorComment != null && authorComment!.trim().isNotEmpty)
        'authorComment': authorComment!.trim(),
      if (authorUsername != null && authorUsername!.trim().isNotEmpty)
        'author_username': authorUsername!.trim(),
      if (authorAvatar != null && authorAvatar!.trim().isNotEmpty)
        'author_avatar': authorAvatar!.trim(),
      if (collaboratorComment != null && collaboratorComment!.trim().isNotEmpty)
        'collaboratorComment': collaboratorComment!.trim(),
      if (collaboratorUsername != null && collaboratorUsername!.trim().isNotEmpty)
        'collaborator_username': collaboratorUsername!.trim(),
      if (collaboratorAvatar != null && collaboratorAvatar!.trim().isNotEmpty)
        'collaborator_avatar': collaboratorAvatar!.trim(),
    };
  }

  // ── Convenience getters ───────────────────────────────────────────────────
  bool get isOpen => status == 'open';
  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';

  /// Inbox lists only [status] == `open` (excludes incomplete / active / completed).
bool get isEligibleForInboxDisplay =>
    status.trim() == 'open' && artist1ID.isNotEmpty && artist2ID.isNotEmpty;
bool get hasCollaborator => collaboratorID != null && collaboratorID!.isNotEmpty;

  int get totalSelectedTracks =>
      artist1TrackIDs.length + artist2TrackIDs.length;

  // ── Helpers ───────────────────────────────────────────────────────────────
  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }
}