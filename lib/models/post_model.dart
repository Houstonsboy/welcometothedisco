// lib/models/post_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class TrackItem {
  final String spotifyID;
  final String trackName;
  final String trackCover;
  final String trackArtist;

  TrackItem({
    required this.spotifyID,
    required this.trackName,
    required this.trackCover,
    required this.trackArtist,
  });

  factory TrackItem.fromMap(Map<String, dynamic> data) {
    return TrackItem(
      spotifyID:   data['spotifyID']   ?? '',
      trackName:   data['trackname']   ?? '',
      trackCover:  data['trackcover']  ?? '',
      trackArtist: data['trackartist'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'spotifyID':   spotifyID,
    'trackname':   trackName,
    'trackcover':  trackCover,
    'trackartist': trackArtist,
  };
}

class PostModel {
  final String  id;           // Firestore document UID
  final String  authorID;
  final String  authorName;
  final String  authorAvatar;
  final String  artistID;
  final String  artistName;
  final String  artistImageUrl;
  final String  description;
  final int     shareCount;
  final int     remixCount;
  final List<TrackItem> tracklist;
  final Timestamp? createdAt;
  final Timestamp? modifiedAt;

  PostModel({
    required this.id,
    required this.authorID,
    required this.authorName,
    required this.authorAvatar,
    required this.artistID,
    required this.artistName,
    required this.artistImageUrl,
    required this.description,
    this.shareCount  = 0,
    this.remixCount  = 0,
    this.tracklist   = const [],
    this.createdAt,
    this.modifiedAt,
  });

  // Build from Firestore document
  factory PostModel.fromFirestore(Map<String, dynamic> data, String id) {
    final rawTracklist = data['Tracklist'] as List<dynamic>? ?? [];

    return PostModel(
      id:            id,
      authorID:      data['authorID']       ?? '',
      authorName:    data['authorName']      ?? '',
      authorAvatar:  data['Author_avatar']   ?? '',
      artistID:      data['artistID']        ?? '',
      artistName:    data['Artistname']      ?? '',
      artistImageUrl: data['Artist_image_url'] ?? '',
      description:   data['Description']     ?? '',
      shareCount:    (data['Sharecount']  as num?)?.toInt() ?? 0,
      remixCount:    (data['Remixcount']  as num?)?.toInt() ?? 0,
      tracklist:     rawTracklist
                       .map((t) => TrackItem.fromMap(t as Map<String, dynamic>))
                       .toList(),
      createdAt:     data['Created_at']   as Timestamp?,
      modifiedAt:    data['modified_at']  as Timestamp?,
    );
  }

  // Serialize back to Firestore
  Map<String, dynamic> toFirestore() => {
    'authorID':        authorID,
    'authorName':      authorName,
    'Author_avatar':   authorAvatar,
    'artistID':        artistID,
    'Artistname':      artistName,
    'Artist_image_url': artistImageUrl,
    'Description':     description,
    'Sharecount':      shareCount,
    'Remixcount':      remixCount,
    'Tracklist':       tracklist.map((t) => t.toMap()).toList(),
    'Created_at':      createdAt  ?? FieldValue.serverTimestamp(),
    'modified_at':     modifiedAt ?? FieldValue.serverTimestamp(),
  };
}