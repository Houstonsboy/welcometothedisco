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
  final String versusType;
  final String voterId;
  final String voterName;
  final String voterAvatar;
  final DateTime timestamp;

  final bool isArtistTemplate;
  final String entity1Id;
  final String entity1Name;
  final int entity1Vote;
  final String entity2Id;
  final String entity2Name;
  final int entity2Vote;

  final double completionPercentage;
  final int unvotedCount;
  final Map<int, VoteTrackDetailModel> trackDetails;

  const VoteDocTemplateModel({
    required this.versusId,
    required this.versusType,
    required this.voterId,
    required this.voterName,
    required this.voterAvatar,
    required this.timestamp,
    required this.isArtistTemplate,
    required this.entity1Id,
    required this.entity1Name,
    required this.entity1Vote,
    required this.entity2Id,
    required this.entity2Name,
    required this.entity2Vote,
    required this.completionPercentage,
    required this.unvotedCount,
    required this.trackDetails,
  });

  factory VoteDocTemplateModel.artist({
    required String versusId,
    required String versusType,
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
      versusType: versusType,
      voterId: voterId,
      voterName: voterName,
      voterAvatar: voterAvatar,
      timestamp: timestamp,
      isArtistTemplate: true,
      entity1Id: artist1ID,
      entity1Name: artist1Name,
      entity1Vote: artist1Vote,
      entity2Id: artist2ID,
      entity2Name: artist2Name,
      entity2Vote: artist2Vote,
      completionPercentage: completionPercentage,
      unvotedCount: unvotedCount,
      trackDetails: trackDetails,
    );
  }

  factory VoteDocTemplateModel.album({
    required String versusId,
    required String versusType,
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
      versusType: versusType,
      voterId: voterId,
      voterName: voterName,
      voterAvatar: voterAvatar,
      timestamp: timestamp,
      isArtistTemplate: false,
      entity1Id: album1ID,
      entity1Name: album1Name,
      entity1Vote: album1Vote,
      entity2Id: album2ID,
      entity2Name: album2Name,
      entity2Vote: album2Vote,
      completionPercentage: completionPercentage,
      unvotedCount: unvotedCount,
      trackDetails: trackDetails,
    );
  }

  Map<String, dynamic> toMap() => {
        'Versus_id': versusId,
        'Versus_type': versusType,
        'Voter_id': voterId,
        'Voter_name': voterName,
        'Voter_avatar': voterAvatar,
        'timestamp': timestamp.toIso8601String(),
        if (isArtistTemplate) ...{
          'artist1ID': entity1Id,
          'artist1Name': entity1Name,
          'artist1Vote': entity1Vote,
          'artist2ID': entity2Id,
          'artist2Name': entity2Name,
          'artist2Vote': entity2Vote,
        } else ...{
          'album1ID': entity1Id,
          'album1Name': entity1Name,
          'album1Vote': entity1Vote,
          'album2ID': entity2Id,
          'album2Name': entity2Name,
          'album2Vote': entity2Vote,
        },
        'Completion_percentage': completionPercentage,
        'Unvoted_count': unvotedCount,
        'Track_details': {
          for (final entry in trackDetails.entries)
            entry.key.toString(): entry.value.toMap(),
        },
      };
}
