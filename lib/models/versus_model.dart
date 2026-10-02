// lib/models/versus_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:welcometothedisco/models/users_model.dart';

class VersusModel {
  final String id;
  /// Firestore document type: "album" or "artist".
  final String type;
  final String authorId;
  final String album1ID;
  final String album1Name;
  final String album2ID;
  final String album2Name;
  final Timestamp? timestamp;

  /// Inbox requires Firestore `status: "open"` (see [isEligibleForInboxDisplay]).
  final String? status;

  // populated after fetching from users collection
  UserModel? author;

  // populated after fetching from Spotify API
  String? album1Title;
  String? album1ArtistName;
  String? album1ImageUrl;
  String? album2Title;
  String? album2ArtistName;
  String? album2ImageUrl;

  /// Full track list stored at creation time.
  /// Each entry: { spotifyID, trackname, trackartist, trackcover }
  final List<Map<String, dynamic>>? album1Tracklist;
  final List<Map<String, dynamic>>? album2Tracklist;

  VersusModel({
    required this.id,
    this.type = 'album',
    required this.authorId,
    required this.album1ID,
    required this.album1Name,
    required this.album2ID,
    required this.album2Name,
    this.timestamp,
    this.status,
    this.author,
    this.album1Title,
    this.album1ArtistName,
    this.album1ImageUrl,
    this.album2Title,
    this.album2ArtistName,
    this.album2ImageUrl,
    this.album1Tracklist,
    this.album2Tracklist,
  });

  factory VersusModel.fromFirestore(Map<String, dynamic> data, String id) {
    final authorRaw = (data['Author'] as String?)?.trim() ?? '';
    final createdByRaw = (data['createdBy'] as String?)?.trim() ?? '';
    final resolvedAuthorId = authorRaw.isNotEmpty ? authorRaw : createdByRaw;

    return VersusModel(
      id: id,
      type: (data['type'] as String?)?.trim() ?? 'album',
      authorId: resolvedAuthorId,
      album1ID: data['album1ID'] ?? '',
      album1Name: data['album1Name'] ?? '',
      album2ID: data['album2ID'] ?? '',
      album2Name: data['album2Name'] ?? '',
      timestamp: (data['createdAt'] ?? data['timestamp']) as Timestamp?,
      status: (data['status'] as String?)?.trim(),
      // Denormalized at creation time — avoids Spotify API calls on read.
      album1ImageUrl: (data['album1ImageUrl'] as String?)?.trim(),
      album1ArtistName: (data['album1ArtistName'] as String?)?.trim(),
      album2ImageUrl: (data['album2ImageUrl'] as String?)?.trim(),
      album2ArtistName: (data['album2ArtistName'] as String?)?.trim(),
      album1Tracklist: _parseTracklist(data['album1Tracklist']),
      album2Tracklist: _parseTracklist(data['album2Tracklist']),
    );
  }

  static List<Map<String, dynamic>>? _parseTracklist(dynamic value) {
    if (value is! List || value.isEmpty) return null;
    final result = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is Map<String, dynamic>) {
        result.add(item);
      } else if (item is Map) {
        result.add(Map<String, dynamic>.from(item));
      }
    }
    return result.isEmpty ? null : result;
  }

  bool get isEligibleForInboxDisplay => status?.trim() == 'open';
}