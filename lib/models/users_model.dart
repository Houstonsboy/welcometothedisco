import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String username;
  final String email;
  final String bio;
  final String avatarPath;
  final List<String> friends;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.bio,
    required this.avatarPath,
    required this.friends,
  });

  factory UserModel.fromFirestore(Map<String, dynamic> data, String id) {
    return UserModel(
      id: id,
      username: data['username'] as String? ?? '',
      email: data['email'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      avatarPath: data['avatar_path'] as String? ?? '',
      friends: List<String>.from(data['friends'] ?? const []),
    );
  }
}