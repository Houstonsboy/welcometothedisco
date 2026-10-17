import 'package:cloud_firestore/cloud_firestore.dart';

// ── Single round entry inside track_details ────────────────────────────────
class TrackRoundEntry {
  final String winner;        // "entity1" | "entity2" | "" (unvoted)
  final String entity1TrackId;
  final String entity1TrackName;
  final String entity2TrackId;
  final String entity2TrackName;
  final bool isBonus;
  final String voterComment;

  const TrackRoundEntry({
    required this.winner,
    required this.entity1TrackId,
    required this.entity1TrackName,
    required this.entity2TrackId,
    required this.entity2TrackName,
    required this.isBonus,
    required this.voterComment,
  });

  bool get isVoted  => winner == 'entity1' || winner == 'entity2';
  bool get entity1Won => winner == 'entity1';
  bool get entity2Won => winner == 'entity2';

  factory TrackRoundEntry.fromMap(Map<String, dynamic> map) {
    return TrackRoundEntry(
      winner:           (map['winner']            as String?)?.trim() ?? '',
      entity1TrackId:   (map['entity1_track_id']  as String?)?.trim() ?? '',
      entity1TrackName: (map['entity1_track_name'] as String?)?.trim() ?? '',
      entity2TrackId:   (map['entity2_track_id']  as String?)?.trim() ?? '',
      entity2TrackName: (map['entity2_track_name'] as String?)?.trim() ?? '',
      isBonus:          (map['isBonus']            as bool?) ?? false,
      voterComment:     (map['voter_comment']      as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'winner':            winner,
    'entity1_track_id':  entity1TrackId,
    'entity1_track_name': entity1TrackName,
    'entity2_track_id':  entity2TrackId,
    'entity2_track_name': entity2TrackName,
    'isBonus':           isBonus,
    'voter_comment':     voterComment,
  };
}

// ── Poll model ─────────────────────────────────────────────────────────────
// Doc ID is deterministic: "{versusId}_{voterId}"
class PollModel {
  final String id;
  final String versusId;
  final String versusType;
  final String voterId;
  final String voterName;
  final String voterAvatar;
  final Timestamp? timestamp;

  final String entity1Id;
  final String entity1Name;
  final int entity1Vote;

  final String entity2Id;
  final String entity2Name;
  final int entity2Vote;

  final double completionPercentage;
  final int unvotedCount;
  final double? lastReconciledPct;

  final List<TrackRoundEntry> trackDetails;

  const PollModel({
    required this.id,
    required this.versusId,
    required this.versusType,
    required this.voterId,
    required this.voterName,
    required this.voterAvatar,
    this.timestamp,
    required this.entity1Id,
    required this.entity1Name,
    required this.entity1Vote,
    required this.entity2Id,
    required this.entity2Name,
    required this.entity2Vote,
    required this.completionPercentage,
    required this.unvotedCount,
    this.lastReconciledPct,
    required this.trackDetails,
  });

  bool get isAlbumPoll  => versusType == 'album';
  bool get isArtistPoll => versusType == 'artist';
  bool get isCollabPoll =>
      versusType == 'collaboration' || versusType == 'collaborator';

  int get totalVotes => entity1Vote + entity2Vote;

  double get entity1Percentage =>
      totalVotes == 0 ? 0 : entity1Vote / totalVotes * 100;
  double get entity2Percentage =>
      totalVotes == 0 ? 0 : entity2Vote / totalVotes * 100;

  // trackDetails is already ordered by round_number on write.
  List<TrackRoundEntry> get roundsSorted => trackDetails;

  // ── Firestore → model ─────────────────────────────────────────────────────
  factory PollModel.fromFirestore(Map<String, dynamic> data, String id) {
    final e1Id   = (data['entity1_id']   as String?)?.trim() ?? '';
    final e1Name = (data['entity1_name'] as String?)?.trim() ?? '';
    final e2Id   = (data['entity2_id']   as String?)?.trim() ?? '';
    final e2Name = (data['entity2_name'] as String?)?.trim() ?? '';

    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    final e1Vote  = (summary['entity1_votes'] as num?)?.toInt() ?? 0;
    final e2Vote  = (summary['entity2_votes'] as num?)?.toInt() ?? 0;

    // track_details is stored as a List in the new format.
    final rawDetails = data['track_details'];
    final trackDetails = <TrackRoundEntry>[];
    if (rawDetails is List) {
      for (final item in rawDetails) {
        if (item is Map<String, dynamic>) {
          trackDetails.add(TrackRoundEntry.fromMap(item));
        }
      }
    }

    return PollModel(
      id:                   id,
      versusId:             (data['versus_id']             as String?)?.trim() ?? '',
      versusType:           (data['entity_type']           as String?)?.trim() ?? 'album',
      voterId:              (data['voter_id']              as String?)?.trim() ?? '',
      voterName:            (data['voter_name']            as String?)?.trim() ?? '',
      voterAvatar:          (data['voter_avatar']          as String?)?.trim() ?? '',
      timestamp:            data['timestamp']              as Timestamp?,
      entity1Id:            e1Id,
      entity1Name:          e1Name,
      entity1Vote:          e1Vote,
      entity2Id:            e2Id,
      entity2Name:          e2Name,
      entity2Vote:          e2Vote,
      completionPercentage: (data['completion_percentage'] as num?)?.toDouble() ?? 0.0,
      unvotedCount:         (data['unvoted_count']         as num?)?.toInt()    ?? 0,
      lastReconciledPct:    (data['last_reconciled_pct']   as num?)?.toDouble(),
      trackDetails:         trackDetails,
    );
  }

  // ── model → Firestore ─────────────────────────────────────────────────────
  Map<String, dynamic> toFirestore() => {
    'versus_id':             versusId,
    'entity_type':           versusType,
    'voter_id':              voterId,
    'voter_name':            voterName,
    'voter_avatar':          voterAvatar,
    'timestamp':             timestamp ?? FieldValue.serverTimestamp(),
    'entity1_id':            entity1Id,
    'entity1_name':          entity1Name,
    'entity2_id':            entity2Id,
    'entity2_name':          entity2Name,
    'summary': {
      'entity1_votes': entity1Vote,
      'entity2_votes': entity2Vote,
    },
    'completion_percentage': completionPercentage,
    'unvoted_count':         unvotedCount,
    if (lastReconciledPct != null)
      'last_reconciled_pct': lastReconciledPct,
    'track_details': trackDetails.map((r) => r.toMap()).toList(),
  };
}
