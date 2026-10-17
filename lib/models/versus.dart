// lib/models/versus_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class VersusModel {
  final String    id;
  final String    author;
  final String    album1ID;
  final String    album1Name;
  final String    album2ID;
  final String    album2Name;
  final Timestamp? timestamp;

  // Spotify data — populated later from Spotify API
  String? album1ImageUrl;
  String? album2ImageUrl;

  VersusModel({
    required this.id,
    required this.author,
    required this.album1ID,
    required this.album1Name,
    required this.album2ID,
    required this.album2Name,
    this.timestamp,
    this.album1ImageUrl,
    this.album2ImageUrl,
  });

  // build from Firestore document
  factory VersusModel.fromFirestore(Map<String, dynamic> data, String id) {
    return VersusModel(
      id:         id,
      author:     data['Author']     ?? '',
      album1ID:   data['album1ID']   ?? '',
      album1Name: data['album1Name'] ?? '',
      album2ID:   data['album2ID']   ?? '',
      album2Name: data['album2Name'] ?? '',
      timestamp:  data['timestamp']  as Timestamp?,
    );
  }
}