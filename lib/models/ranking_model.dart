// lib/models/ranking_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// One document per Spotify artist or album in the `rankings` collection.
/// Doc ID = the Spotify entity ID.
///
/// rankings/{entityId}
///   entity_id            string
///   entity_type          "artist" | "album"
///   entity_name          string
///   entity_image         string   (cached Spotify URL)
///   created_at           Timestamp
///   points               double   (100.0 on creation; updated by nightly job)
///   rank                 int?     (null until nightly job runs)
///   provisional          bool     (true until nightly job promotes)
///   distinct_opponents   int      (unique pair partners; updated by onPollWritten)
///   total_voters         int      (unique voters across all pairs; updated by onPollWritten)
///   points_updated_at    Timestamp? (null until nightly job first runs)
class RankingModel {
  final String entityId;
  final String entityType;
  final String entityName;
  final String entityImage;
  final String entityNameLower;
  final DateTime? createdAt;
  final double points;
  final int? rank;
  final bool provisional;
  final int distinctOpponents;
  final int totalVoters;
  final DateTime? pointsUpdatedAt;

  const RankingModel({
    required this.entityId,
    required this.entityType,
    required this.entityName,
    required this.entityImage,
    this.entityNameLower = '',
    this.createdAt,
    this.points = 100.0,
    this.rank,
    this.provisional = true,
    this.distinctOpponents = 0,
    this.totalVoters = 0,
    this.pointsUpdatedAt,
  });

  bool get isArtist => entityType == 'artist';
  bool get isAlbum  => entityType == 'album';

  factory RankingModel.fromFirestore(Map<String, dynamic> data, String id) {
    return RankingModel(
      entityId:          id,
      entityType:        (data['entity_type']       as String?)?.trim() ?? 'artist',
      entityName:        (data['entity_name']       as String?)?.trim() ?? '',
      entityImage:       (data['entity_image']      as String?)?.trim() ?? '',
      entityNameLower:   (data['entity_name_lower'] as String?)?.trim() ?? '',
      createdAt:         _toDateTime(data['created_at']),
      points:            (data['points'] as num?)?.toDouble() ?? 100.0,
      rank:              (data['rank'] as num?)?.toInt(),
      provisional:       (data['provisional'] as bool?) ?? true,
      distinctOpponents: (data['distinct_opponents'] as num?)?.toInt() ?? 0,
      totalVoters:       (data['total_voters'] as num?)?.toInt() ?? 0,
      pointsUpdatedAt:   _toDateTime(data['points_updated_at']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'entity_id':          entityId,
        'entity_type':        entityType,
        'entity_name':        entityName,
        'entity_image':       entityImage,
        'created_at':         FieldValue.serverTimestamp(),
        'points':             points,
        'rank':               rank,
        'provisional':        provisional,
        'distinct_opponents': distinctOpponents,
        'total_voters':       totalVoters,
        'points_updated_at':  pointsUpdatedAt != null
            ? Timestamp.fromDate(pointsUpdatedAt!)
            : null,
      };
}

DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
