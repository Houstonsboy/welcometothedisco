import 'package:cloud_firestore/cloud_firestore.dart';

// ── Friend entry stored inside a user's friends array ─────────────────────────
// Each element is a map: { uid, username, avatar_path }
// Back-compat: if an old doc still has a plain UID string in the array,
// it is parsed into a FriendEntry with only uid populated.
class FriendEntry {
  final String uid;
  final String username;
  final String avatarPath;

  const FriendEntry({
    required this.uid,
    required this.username,
    required this.avatarPath,
  });

  factory FriendEntry.fromMap(Map<String, dynamic> map) {
    return FriendEntry(
      uid: map['uid'] as String? ?? '',
      username: map['username'] as String? ?? '',
      avatarPath: map['avatar_path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'username': username,
        'avatar_path': avatarPath,
      };
}

// ── Favorite album entry stored inside a user's favorite_albums array ─────────
// Each element is a map: { album_id, album_title, artist_name, image_url }
class FavoriteAlbumEntry {
  final String albumId;
  final String albumTitle;
  final String artistName;
  final String? imageUrl;

  const FavoriteAlbumEntry({
    required this.albumId,
    required this.albumTitle,
    required this.artistName,
    this.imageUrl,
  });

  factory FavoriteAlbumEntry.fromMap(Map<String, dynamic> map) {
    return FavoriteAlbumEntry(
      albumId: map['album_id'] as String? ?? '',
      albumTitle: map['album_title'] as String? ?? '',
      artistName: map['artist_name'] as String? ?? '',
      imageUrl: map['image_url'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'album_id': albumId,
        'album_title': albumTitle,
        'artist_name': artistName,
        if (imageUrl != null && imageUrl!.trim().isNotEmpty)
          'image_url': imageUrl!.trim(),
      };
}

// ── User model ─────────────────────────────────────────────────────────────────
class UserModel {
  final String id;
  final String username;
  final String email;
  final String bio;
  final String avatarPath;
  final List<FriendEntry> friends;
  final List<FavoriteAlbumEntry> favoriteAlbums;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.bio,
    required this.avatarPath,
    required this.friends,
    required this.favoriteAlbums,
  });

  factory UserModel.fromFirestore(Map<String, dynamic> data, String id) {
    final rawFriends = data['friends'] as List<dynamic>? ?? const [];
    final friends = rawFriends
        .map((e) {
          if (e is Map<String, dynamic>) return FriendEntry.fromMap(e);
          // Legacy: plain UID string
          if (e is String && e.isNotEmpty) {
            return FriendEntry(uid: e, username: '', avatarPath: '');
          }
          return null;
        })
        .whereType<FriendEntry>()
        .toList();

    final rawFavoriteAlbums =
        data['favorite_albums'] as List<dynamic>? ?? const [];
    final favoriteAlbums = rawFavoriteAlbums
        .map((e) {
          if (e is Map<String, dynamic>) {
            return FavoriteAlbumEntry.fromMap(e);
          }
          return null;
        })
        .whereType<FavoriteAlbumEntry>()
        .toList();

    return UserModel(
      id: id,
      username: data['username'] as String? ?? '',
      email: data['email'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      avatarPath: data['avatar_path'] as String? ?? '',
      friends: friends,
      favoriteAlbums: favoriteAlbums,
    );
  }
}
