import '../models/ranking_model.dart';

enum RankingPeriod { day, week }

/// Snapshot of a ranking entity's movement over a given period.
class RankingChange {
  /// Points gained (positive) or lost (negative) since the period start.
  /// Null when no baseline is available.
  final double? pointsDelta;

  /// Rank improvement (positive = moved up, i.e. rank number decreased).
  /// Null when either the current or start rank is null / unavailable.
  final int? rankDelta;

  /// True when the entity entered the ranked leaderboard during this period
  /// (start rank was null, current rank is non-null).
  final bool isNew;

  const RankingChange({
    this.pointsDelta,
    this.rankDelta,
    this.isNew = false,
  });

  /// True when we have enough data to display any change indicator.
  bool get hasData => pointsDelta != null || rankDelta != null || isNew;

  /// Points went up by a meaningful amount (> 0.005 avoids float noise).
  bool get isGain => !isNew && (pointsDelta ?? 0) > 0.005;

  /// Points went down.
  bool get isLoss => !isNew && (pointsDelta ?? 0) < -0.005;

  /// No meaningful change.
  bool get isFlat => !isNew && !isGain && !isLoss;
}

/// Computes the change for [model] over [period] from its stored baselines.
///
/// Returns a [RankingChange] with null deltas when the baseline hasn't been
/// set yet (e.g. the entity was created before the history feature launched).
RankingChange changeFor(RankingModel model, RankingPeriod period) {
  final startPoints = period == RankingPeriod.day
      ? model.dayStartPoints
      : model.weekStartPoints;
  final startRank = period == RankingPeriod.day
      ? model.dayStartRank
      : model.weekStartRank;

  // Entity just entered the leaderboard this period.
  final isNew = startRank == null && model.rank != null;

  final pointsDelta =
      startPoints != null ? model.points - startPoints : null;

  // rankDelta: positive = moved up (rank number went down).
  final rankDelta =
      (startRank != null && model.rank != null) ? startRank - model.rank! : null;

  return RankingChange(
    pointsDelta: pointsDelta,
    rankDelta: rankDelta,
    isNew: isNew,
  );
}
