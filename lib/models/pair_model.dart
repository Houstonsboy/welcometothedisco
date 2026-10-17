// lib/models/pair_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Entity info embedded in a pair doc ───────────────────────────────────────
class PairEntityInfo {
  final String entityId;
  final String entityName;
  final String entityImage;

  const PairEntityInfo({
    required this.entityId,
    required this.entityName,
    required this.entityImage,
  });

  factory PairEntityInfo.fromMap(Map<String, dynamic> data) => PairEntityInfo(
        entityId:    (data['entity_id']    as String?)?.trim() ?? '',
        entityName:  (data['entity_name']  as String?)?.trim() ?? '',
        entityImage: (data['entity_image'] as String?)?.trim() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'entity_id':    entityId,
        'entity_name':  entityName,
        'entity_image': entityImage,
      };
}

// ── Per-versus breakdown stored in pairs/{pairKey}.versus map ─────────────────
class PairVersusEntry {
  final String versusId;
  final int roundsA;
  final int roundsB;
  final int pollCount;
  final DateTime? lastVotedAt;

  const PairVersusEntry({
    required this.versusId,
    required this.roundsA,
    required this.roundsB,
    required this.pollCount,
    this.lastVotedAt,
  });

  factory PairVersusEntry.fromMap(String versusId, Map<String, dynamic> data) =>
      PairVersusEntry(
        versusId:    versusId,
        roundsA:     (data['rounds_a']    as num?)?.toInt() ?? 0,
        roundsB:     (data['rounds_b']    as num?)?.toInt() ?? 0,
        pollCount:   (data['poll_count']  as num?)?.toInt() ?? 0,
        lastVotedAt: _toDateTime(data['last_voted_at']),
      );

  String get outcome {
    if (roundsA > roundsB) return 'a_wins';
    if (roundsB > roundsA) return 'b_wins';
    return 'draw';
  }
}

// ── Voter subcollection doc (pairs/{pairKey}/voters/{voterId}) ─────────────────
class VoterModel {
  final String voterId;
  final String pairKey;
  final int roundsA;
  final int roundsB;
  final double shareA;
  final double shareB;
  final bool counted;
  final DateTime? updatedAt;

  const VoterModel({
    required this.voterId,
    required this.pairKey,
    required this.roundsA,
    required this.roundsB,
    required this.shareA,
    required this.shareB,
    required this.counted,
    this.updatedAt,
  });

  factory VoterModel.fromMap(String voterId, Map<String, dynamic> data) =>
      VoterModel(
        voterId:   voterId,
        pairKey:   (data['pair_key'] as String?)?.trim() ?? '',
        roundsA:   (data['rounds_a'] as num?)?.toInt()    ?? 0,
        roundsB:   (data['rounds_b'] as num?)?.toInt()    ?? 0,
        shareA:    (data['share_a']  as num?)?.toDouble() ?? 0.0,
        shareB:    (data['share_b']  as num?)?.toDouble() ?? 0.0,
        counted:   (data['counted']  as bool?)            ?? false,
        updatedAt: _toDateTime(data['updated_at']),
      );
}

// ── Root pair document (pairs/{pairKey}) ──────────────────────────────────────
class PairModel {
  final String pairKey;
  final String entityType;
  final List<String> entityIds;
  final PairEntityInfo entityA;
  final PairEntityInfo entityB;

  /// Bradley-Terry share sums — float in [0, voter_count].
  final double votesA;
  final double votesB;

  /// Raw round counts — display only (integer).
  final int roundsA;
  final int roundsB;

  final int voterCount;
  final int versusCount;
  final DateTime? createdAt;
  final DateTime? lastVotedAt;
  final Map<String, PairVersusEntry> versus;

  const PairModel({
    required this.pairKey,
    required this.entityType,
    required this.entityIds,
    required this.entityA,
    required this.entityB,
    required this.votesA,
    required this.votesB,
    required this.roundsA,
    required this.roundsB,
    required this.voterCount,
    required this.versusCount,
    this.createdAt,
    this.lastVotedAt,
    this.versus = const {},
  });

  factory PairModel.fromFirestore(String pairKey, Map<String, dynamic> data) {
    final rawA = data['entity_a'] as Map<String, dynamic>? ?? {};
    final rawB = data['entity_b'] as Map<String, dynamic>? ?? {};

    final rawVersus = data['versus'] as Map<String, dynamic>? ?? {};
    final versusMap = <String, PairVersusEntry>{};
    for (final e in rawVersus.entries) {
      final vData = e.value as Map<String, dynamic>?;
      if (vData != null) versusMap[e.key] = PairVersusEntry.fromMap(e.key, vData);
    }

    final rawIds = data['entity_ids'];
    final List<String> entityIds = rawIds is List
        ? rawIds.map((e) => e.toString()).toList()
        : [];

    return PairModel(
      pairKey:     pairKey,
      entityType:  (data['entity_type'] as String?)?.trim() ?? 'artist',
      entityIds:   entityIds,
      entityA:     PairEntityInfo.fromMap(rawA),
      entityB:     PairEntityInfo.fromMap(rawB),
      votesA:      (data['votes_a']     as num?)?.toDouble() ?? 0.0,
      votesB:      (data['votes_b']     as num?)?.toDouble() ?? 0.0,
      roundsA:     (data['rounds_a']    as num?)?.toInt()    ?? 0,
      roundsB:     (data['rounds_b']    as num?)?.toInt()    ?? 0,
      voterCount:  (data['voter_count'] as num?)?.toInt()    ?? 0,
      versusCount: (data['versus_count'] as num?)?.toInt()   ?? 0,
      createdAt:   _toDateTime(data['created_at']),
      lastVotedAt: _toDateTime(data['last_voted_at']),
      versus:      versusMap,
    );
  }

  // ── Convenience ─────────────────────────────────────────────────────────────

  PairEntityInfo opponentOf(String entityId) =>
      entityId.trim() == entityA.entityId ? entityB : entityA;

  /// Raw round count for display (not Bradley-Terry shares).
  int myVotes(String entityId) =>
      entityId.trim() == entityA.entityId ? roundsA : roundsB;

  int theirVotes(String entityId) =>
      entityId.trim() == entityA.entityId ? roundsB : roundsA;

  int myRoundsInVersus(String entityId, String versusId) {
    final entry = versus[versusId];
    if (entry == null) return 0;
    return entityId.trim() == entityA.entityId ? entry.roundsA : entry.roundsB;
  }

  int theirRoundsInVersus(String entityId, String versusId) {
    final entry = versus[versusId];
    if (entry == null) return 0;
    return entityId.trim() == entityA.entityId ? entry.roundsB : entry.roundsA;
  }

  String outcomeFor(String entityId, String versusId) {
    final my = myRoundsInVersus(entityId, versusId);
    final their = theirRoundsInVersus(entityId, versusId);
    if (my > their) return 'won';
    if (their > my) return 'lost';
    return 'draw';
  }

  /// Versus entries sorted newest-first.
  List<PairVersusEntry> get versusHistory {
    final list = versus.values.toList()
      ..sort((a, b) {
        final ta = a.lastVotedAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.lastVotedAt?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });
    return list;
  }
}

DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
