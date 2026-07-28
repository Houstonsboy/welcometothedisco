import 'package:cloud_firestore/cloud_firestore.dart';

// ── Single round entry inside track_details ────────────────────────────────
// Firestore key is the round index as a string ("0", "1", "2", ...).
class TrackRoundEntry {
  final String winner;         // winning track ID (empty if unvoted)
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

  bool get isVoted => winner.isNotEmpty;
  bool get entity1Won => isVoted && winner == entity1TrackId;
  bool get entity2Won => isVoted && winner == entity2TrackId;

  factory TrackRoundEntry.fromMap(Map<String, dynamic> map) {
    return TrackRoundEntry(
      winner:           (map['Winner']          as String?)?.trim() ?? '',
      entity1TrackId:   (map['artist1trackID']  as String?)?.trim() ?? '',
      entity1TrackName: (map['artist1trackName'] as String?)?.trim() ?? '',
      entity2TrackId:   (map['artist2trackID']  as String?)?.trim() ?? '',
      entity2TrackName: (map['artist2trackName'] as String?)?.trim() ?? '',
      isBonus:    (map['isBonus']      as bool?) ?? false,
      voterComment: (map['voter_comment'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'Winner':           winner,
    'artist1trackID':   entity1TrackId,
    'artist1trackName': entity1TrackName,
    'artist2trackID':   entity2TrackId,
    'artist2trackName': entity2TrackName,
    'isBonus':          isBonus,
    'voter_comment':    voterComment,
  };
}

// ── Poll model ─────────────────────────────────────────────────────────────
// Doc ID is deterministic: "{versusId}_{voterId}"
// Handles both album polls (album1ID / album2ID) and
// artist polls (artist1ID / artist2ID) — unified as entity1 / entity2.
class PollModel {
  final String id;             // Firestore doc ID
  final String versusId;
  final String versusType;     // "album" | "artist" | "collaboration" | "collaborator"
  final String voterId;
  final String voterName;
  final String voterAvatar;
  final Timestamp? timestamp;

  // Entity 1 (album1ID / artist1ID depending on versusType)
  final String entity1Id;
  final String entity1Name;
  final int entity1Vote;

  // Entity 2 (album2ID / artist2ID depending on versusType)
  final String entity2Id;
  final String entity2Name;
  final int entity2Vote;

  final double completionPercentage;
  final int unvotedCount;

  /// Last reconciled percentage — only present on artist/collaboration polls.
  final double? lastReconciledPct;

  /// Round index (0-based) → round entry.
  final Map<int, TrackRoundEntry> trackDetails;

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

  // ── Convenience ──────────────────────────────────────────────────────────
  bool get isAlbumPoll   => versusType == 'album';
  bool get isArtistPoll  => versusType == 'artist';
  bool get isCollabPoll  =>
      versusType == 'collaboration' || versusType == 'collaborator';

  int get totalVotes => entity1Vote + entity2Vote;

  double get entity1Percentage =>
      totalVotes == 0 ? 0 : entity1Vote / totalVotes * 100;
  double get entity2Percentage =>
      totalVotes == 0 ? 0 : entity2Vote / totalVotes * 100;

  List<TrackRoundEntry> get roundsSorted {
    final keys = trackDetails.keys.toList()..sort();
    return keys.map((k) => trackDetails[k]!).toList();
  }

  // ── Firestore → model ─────────────────────────────────────────────────────
  factory PollModel.fromFirestore(Map<String, dynamic> data, String id) {
    final type = (data['Versus_type'] as String?)?.trim().toLowerCase() ?? 'album';
    final isAlbum = type == 'album';

    // Entity field names differ between album and artist polls.
    final e1Id   = isAlbum
        ? (data['album1ID']   as String?)?.trim() ?? ''
        : (data['artist1ID']  as String?)?.trim() ?? '';
    final e1Name = isAlbum
        ? (data['album1Name']  as String?)?.trim() ?? ''
        : (data['artist1Name'] as String?)?.trim() ?? '';
    final e1Vote = isAlbum
        ? (data['album1Vote']  as num?)?.toInt() ?? 0
        : (data['artist1Vote'] as num?)?.toInt() ?? 0;

    final e2Id   = isAlbum
        ? (data['album2ID']   as String?)?.trim() ?? ''
        : (data['artist2ID']  as String?)?.trim() ?? '';
    final e2Name = isAlbum
        ? (data['album2Name']  as String?)?.trim() ?? ''
        : (data['artist2Name'] as String?)?.trim() ?? '';
    final e2Vote = isAlbum
        ? (data['album2Vote']  as num?)?.toInt() ?? 0
        : (data['artist2Vote'] as num?)?.toInt() ?? 0;

    // Parse track_details: Firestore stores keys as strings ("0", "1", ...)
    final rawDetails = data['track_details'] as Map<String, dynamic>? ?? {};
    final trackDetails = <int, TrackRoundEntry>{};
    for (final entry in rawDetails.entries) {
      final idx = int.tryParse(entry.key);
      if (idx == null) continue;
      final raw = entry.value;
      if (raw is Map<String, dynamic>) {
        trackDetails[idx] = TrackRoundEntry.fromMap(raw);
      }
    }

    return PollModel(
      id:                  id,
      versusId:            (data['versus_id']            as String?)?.trim() ?? '',
      versusType:          (data['Versus_type']           as String?)?.trim() ?? 'album',
      voterId:             (data['voter_id']              as String?)?.trim() ?? '',
      voterName:           (data['voter_name']            as String?)?.trim() ?? '',
      voterAvatar:         (data['voter_avatar']          as String?)?.trim() ?? '',
      timestamp:           data['timestamp']              as Timestamp?,
      entity1Id:   e1Id,
      entity1Name: e1Name,
      entity1Vote: e1Vote,
      entity2Id:   e2Id,
      entity2Name: e2Name,
      entity2Vote: e2Vote,
      completionPercentage: (data['completion_percentage'] as num?)?.toDouble() ?? 0.0,
      unvotedCount:         (data['unvoted_count']         as num?)?.toInt()    ?? 0,
      lastReconciledPct:    (data['last_reconciled_pct']   as num?)?.toDouble(),
      trackDetails:         trackDetails,
    );
  }

  // ── model → Firestore ─────────────────────────────────────────────────────
  // Writes back using the correct field names for the poll type.
  Map<String, dynamic> toFirestore() {
    final trackMap = {
      for (final e in trackDetails.entries) '${e.key}': e.value.toMap(),
    };

    final entityPrefix1 = isAlbumPoll ? 'album1' : 'artist1';
    final entityPrefix2 = isAlbumPoll ? 'album2' : 'artist2';

    return {
      'versus_id':             versusId,
      'Versus_type':           versusType,
      'voter_id':              voterId,
      'voter_name':            voterName,
      'voter_avatar':          voterAvatar,
      'timestamp':             timestamp ?? FieldValue.serverTimestamp(),
      '${entityPrefix1}ID':   entity1Id,
      '${entityPrefix1}Name': entity1Name,
      '${entityPrefix1}Vote': entity1Vote,
      '${entityPrefix2}ID':   entity2Id,
      '${entityPrefix2}Name': entity2Name,
      '${entityPrefix2}Vote': entity2Vote,
      'completion_percentage': completionPercentage,
      'unvoted_count':         unvotedCount,
      if (lastReconciledPct != null)
        'last_reconciled_pct': lastReconciledPct,
      'track_details': trackMap,
    };
  }
}
