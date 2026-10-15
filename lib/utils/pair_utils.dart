// lib/utils/pair_utils.dart

/// Sorts [id1] and [id2] lexicographically and joins them with '_'.
/// The lower-lexicographic ID is always the a-side.
String makePairKey(String id1, String id2) {
  final a = id1.trim();
  final b = id2.trim();
  final ids = [a, b]..sort();
  return '${ids[0]}_${ids[1]}';
}

/// Returns 'a' if [entityId] is the a-side (lexicographically smaller) of
/// [pairKey], or 'b' otherwise.
String entitySide(String entityId, String pairKey) {
  final parts = pairKey.split('_');
  if (parts.isEmpty) return 'a';
  return entityId.trim() == parts[0] ? 'a' : 'b';
}

/// Counts non-bonus rounds where winner is 'entity1' or 'entity2' (decided).
int countDecidedRounds(List<Map<String, dynamic>> trackDetails) {
  return trackDetails.where((r) {
    if (r['isBonus'] == true) return false;
    final w = r['winner'] as String?;
    return w == 'entity1' || w == 'entity2';
  }).length;
}

/// Counts non-bonus rounds won by each entity from the unified track_details
/// list. Returns (rounds_entity1, rounds_entity2).
(int, int) computeRoundCounts(List<Map<String, dynamic>> trackDetails) {
  int r1 = 0, r2 = 0;
  for (final round in trackDetails) {
    if (round['isBonus'] == true) continue;
    final w = round['winner'] as String?;
    if (w == 'entity1') r1++;
    if (w == 'entity2') r2++;
  }
  return (r1, r2);
}

/// Maps per-entity round counts to per-pair-side (a/b) counts.
///
/// [entity1Id] is the poll's entity1 ID. The pair's a-side is whichever entity
/// ID is lexicographically smaller (first segment of [pairKey]).
/// Returns (rounds_a, rounds_b).
(int, int) mapRoundsToAB(
  String entity1Id,
  String pairKey,
  int rounds1,
  int rounds2,
) {
  final parts = pairKey.split('_');
  if (parts.isEmpty) return (rounds1, rounds2);
  final aId = parts[0];
  return entity1Id.trim() == aId ? (rounds1, rounds2) : (rounds2, rounds1);
}

/// Returns true when both IDs (trimmed) are identical — a self-matchup.
/// Self-matchups are recorded but excluded from pair docs and rankings.
bool isSelfMatchup(String id1, String id2) => id1.trim() == id2.trim();

/// Returns percentage shares for a and b sides (each 0.0–100.0).
(double, double) computeShares(int votesA, int votesB) {
  final total = votesA + votesB;
  if (total == 0) return (0.0, 0.0);
  return (votesA / total * 100, votesB / total * 100);
}
