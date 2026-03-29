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
    );
  }

  bool get isEligibleForInboxDisplay => status?.trim() == 'open';
}