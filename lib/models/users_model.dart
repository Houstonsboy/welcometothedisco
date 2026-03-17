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

// ── User model ─────────────────────────────────────────────────────────────────
class UserModel {
  final String id;
  final String username;
  final String email;
  final String bio;
  final String avatarPath;
  final List<FriendEntry> friends;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.bio,
    required this.avatarPath,
    required this.friends,
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

    return UserModel(
      id: id,
      username: data['username'] as String? ?? '',
      email: data['email'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      avatarPath: data['avatar_path'] as String? ?? '',
      friends: friends,
    );
  }
}
