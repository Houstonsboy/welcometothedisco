// lib/models/post_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Stored in Firestore field [remixenabled] as `false`, `same`, or `different`.
enum RemixEnabled {
  /// Remixes are not allowed.
  disabled,
  /// Remixes must use the same artist as the post.
  same,
  /// Remixes must use a different artist than the post.
  different;

  /// Value written to / read from Firestore [remixenabled].
  Object get firestoreValue {
    switch (this) {
      case RemixEnabled.disabled:
        return false;
      case RemixEnabled.same:
        return 'same';
      case RemixEnabled.different:
        return 'different';
    }
  }

  static RemixEnabled fromFirestore(dynamic value) {
    if (value == null) return RemixEnabled.same;
    if (value is bool) return value ? RemixEnabled.same : RemixEnabled.disabled;
    final s = value.toString().trim().toLowerCase();
    switch (s) {
      case 'same':
        return RemixEnabled.same;
      case 'different':
        return RemixEnabled.different;
      case 'false':
      case 'off':
      case 'none':
        return RemixEnabled.disabled;
      case 'true':
        return RemixEnabled.same;
      default:
        return RemixEnabled.same;
    }
  }
}

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
  final RemixEnabled remixEnabled;
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
    this.remixEnabled = RemixEnabled.same,
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
      remixEnabled:  RemixEnabled.fromFirestore(data['remixenabled']),
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
    'remixenabled':    remixEnabled.firestoreValue,
    'Tracklist':       tracklist.map((t) => t.toMap()).toList(),
    'Created_at':      createdAt  ?? FieldValue.serverTimestamp(),
    'modified_at':     modifiedAt ?? FieldValue.serverTimestamp(),
  };
}