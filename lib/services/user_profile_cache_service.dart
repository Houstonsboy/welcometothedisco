import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:welcometothedisco/models/users_model.dart';

/// Caches the authenticated user's profile locally so screens can reuse it
/// without repeatedly hitting Firestore for initial paint.
class UserProfileCacheService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _cachedUserKey = 'cached_firebase_user_profile_v1';

  static Future<void> saveUser(UserModel user) async {
    final payload = <String, dynamic>{
      'id': user.id,
      'username': user.username,
      'email': user.email,
      'bio': user.bio,
      'avatar_path': user.avatarPath,
      'friends': user.friends.map((f) => f.toMap()).toList(),
      'cached_at': DateTime.now().toIso8601String(),
    };
    await _storage.write(key: _cachedUserKey, value: jsonEncode(payload));
    debugPrint('[UserProfileCacheService] cached uid=${user.id}');
  }

  static Future<UserModel?> readUser({String? expectedUid}) async {
    final raw = await _storage.read(key: _cachedUserKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final id = (decoded['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) return null;
      if (expectedUid != null && expectedUid.trim().isNotEmpty && id != expectedUid.trim()) {
        return null;
      }

      final rawFriends = decoded['friends'] as List<dynamic>? ?? const [];
      final friends = rawFriends
          .whereType<Map<String, dynamic>>()
          .map(FriendEntry.fromMap)
          .toList();

      return UserModel(
        id: id,
        username: (decoded['username'] as String?) ?? '',
        email: (decoded['email'] as String?) ?? '',
        bio: (decoded['bio'] as String?) ?? '',
        avatarPath: (decoded['avatar_path'] as String?) ?? '',
        friends: friends,
      );
    } catch (e) {
      debugPrint('[UserProfileCacheService] readUser parse error: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    await _storage.delete(key: _cachedUserKey);
    debugPrint('[UserProfileCacheService] cache cleared');
  }
}
