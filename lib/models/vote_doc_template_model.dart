class VoteTrackDetailModel {
  final String? artist1trackID;
  final String? artist2trackID;
  final String? winner;
  final String voterComment;
  final String? artist1trackName;
  final String? artist2trackName;
  final bool isBonus;

  const VoteTrackDetailModel({
    required this.artist1trackID,
    required this.artist2trackID,
    required this.winner,
    required this.voterComment,
    required this.artist1trackName,
    required this.artist2trackName,
    this.isBonus = false,
  });

  Map<String, dynamic> toMap() => {
        'artist1trackID': artist1trackID,
        'artist2trackID': artist2trackID,
        'Winner': winner,
        'voter_comment': voterComment,
        'artist1trackName': artist1trackName,
        'artist2trackName': artist2trackName,
        'isBonus': isBonus,
      };
}

class VoteDocTemplateModel {
  final String versusId;
  final String voterId;
  final String voterName;
  final String voterAvatar;
  final DateTime timestamp;

  final bool isArtistTemplate;
  final String side1Id;
  final String side1Name;
  final int side1Vote;
  final String side2Id;
  final String side2Name;
  final int side2Vote;

  final double completionPercentage;
  final int unvotedCount;
  final Map<int, VoteTrackDetailModel> trackDetails;

  const VoteDocTemplateModel({
    required this.versusId,
    required this.voterId,
    required this.voterName,
    required this.voterAvatar,
    required this.timestamp,
    required this.isArtistTemplate,
    required this.side1Id,
    required this.side1Name,
    required this.side1Vote,
    required this.side2Id,
    required this.side2Name,
    required this.side2Vote,
    required this.completionPercentage,
    required this.unvotedCount,
    required this.trackDetails,
  });

  factory VoteDocTemplateModel.artist({
    required String versusId,
    required String voterId,
    required String voterName,
    required String voterAvatar,
    required DateTime timestamp,
    required String artist1ID,
    required String artist1Name,
    required int artist1Vote,
    required String artist2ID,
    required String artist2Name,
    required int artist2Vote,
    required double completionPercentage,
    required int unvotedCount,
    required Map<int, VoteTrackDetailModel> trackDetails,
  }) {
    return VoteDocTemplateModel(
      versusId: versusId,
      voterId: voterId,
      voterName: voterName,
      voterAvatar: voterAvatar,
      timestamp: timestamp,
      isArtistTemplate: true,
      side1Id: artist1ID,
      side1Name: artist1Name,
      side1Vote: artist1Vote,
      side2Id: artist2ID,
      side2Name: artist2Name,
      side2Vote: artist2Vote,
      completionPercentage: completionPercentage,
      unvotedCount: unvotedCount,
      trackDetails: trackDetails,
    );
  }

  factory VoteDocTemplateModel.album({
    required String versusId,
    required String voterId,
    required String voterName,
    required String voterAvatar,
    required DateTime timestamp,
    required String album1ID,
    required String album1Name,
    required int album1Vote,
    required String album2ID,
    required String album2Name,
    required int album2Vote,
    required double completionPercentage,
    required int unvotedCount,
    required Map<int, VoteTrackDetailModel> trackDetails,
  }) {
    return VoteDocTemplateModel(
      versusId: versusId,
      voterId: voterId,
      voterName: voterName,
      voterAvatar: voterAvatar,
      timestamp: timestamp,
      isArtistTemplate: false,
      side1Id: album1ID,
      side1Name: album1Name,
      side1Vote: album1Vote,
      side2Id: album2ID,
      side2Name: album2Name,
      side2Vote: album2Vote,
      completionPercentage: completionPercentage,
      unvotedCount: unvotedCount,
      trackDetails: trackDetails,
    );
  }

  Map<String, dynamic> toMap() => {
        'Versus_id': versusId,
        'Voter_id': voterId,
        'Voter_name': voterName,
        'Voter_avatar': voterAvatar,
        'timestamp': timestamp.toIso8601String(),
        if (isArtistTemplate) ...{
          'artist1ID': side1Id,
          'artist1Name': side1Name,
          'artist1_vote': side1Vote,
          'artist2ID': side2Id,
          'artist2Name': side2Name,
          'artist2_vote': side2Vote,
        } else ...{
          'album1ID': side1Id,
          'album1Name': side1Name,
          'album1_vote': side1Vote,
          'album2ID': side2Id,
          'album2Name': side2Name,
          'album2_vote': side2Vote,
        },
        'Completion_percentage': completionPercentage,
        'Unvoted_count': unvotedCount,
        'Track_details': {
          for (final entry in trackDetails.entries)
            entry.key.toString(): entry.value.toMap(),
        },
      };
}
