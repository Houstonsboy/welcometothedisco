    // lib/models/ranking_model.dart
    import 'package:cloud_firestore/cloud_firestore.dart';

    // ── Individual versus result under an opponent ────────────────────────────────
    /// Represents one specific versus session between two entities.
    /// Stored as a nested map inside [OpponentModel.versus], keyed by versus doc ID.
    class VersusResultModel {
    final String versusId;    // the key in the map — stored here for convenience
    final int    entityVotes;
    final int    opponentVotes;
    final String result;      // "win" | "loss" | "draw"
    final DateTime? playedAt;

    const VersusResultModel({
        required this.versusId,
        required this.entityVotes,
        required this.opponentVotes,
        required this.result,
        this.playedAt,
    });

    factory VersusResultModel.fromMap(String versusId, Map<String, dynamic> data) {
        return VersusResultModel(
        versusId:   versusId,
        entityVotes:   (data['our_votes']   as num?)?.toInt() ?? 0,
        opponentVotes: (data['their_votes'] as num?)?.toInt() ?? 0,
        result:     (data['result']      as String?)?.trim() ?? 'draw',
        playedAt:   _toDateTime(data['played_at']),
        );
    }

    Map<String, dynamic> toMap() => {
        'our_votes':   entityVotes,
        'their_votes': opponentVotes,
        'result':      result,
        'played_at':   playedAt != null
            ? Timestamp.fromDate(playedAt!)
            : FieldValue.serverTimestamp(),
    };

    bool get isWin  => result == 'win';
    bool get isLoss => result == 'loss';
    bool get isDraw => result == 'draw';
    }

    // ── Head-to-head record against one opponent ──────────────────────────────────
    /// Stored as a nested map inside [RankingModel.opponents],
    /// keyed by the opponent's Spotify entity ID.
    class OpponentModel {
    final String opponentId;    // the key in the opponents map
    final String opponentName;
    final String opponentImage;

    // ── Cumulative head-to-head totals (sum across ALL versus with this opponent) ──
    final int versusCount;      // how many times these two have faced off
    final int winsAgainst;      // times our entity won against this opponent
    final int lossesTo;         // times our entity lost to this opponent
    final int draws;

    final int totalentityVotes;    // our entity's combined votes across all matchups
    final int totalopponentVotes;  // opponent's combined votes across all matchups

    final DateTime? lastPlayed;

    // ── Individual versus breakdown ───────────────────────────────────────────
    /// Map keyed by versus doc ID → one entry per versus between these two.
    final Map<String, VersusResultModel> versus;

    const OpponentModel({
        required this.opponentId,
        required this.opponentName,
        required this.opponentImage,
        required this.versusCount,
        required this.winsAgainst,
        required this.lossesTo,
        required this.draws,
        required this.totalentityVotes,
        required this.totalopponentVotes,
        this.lastPlayed,
        this.versus = const {},
    });

    factory OpponentModel.fromMap(String opponentId, Map<String, dynamic> data) {
        // Parse the nested versus map
        final rawVersus = data['versus'] as Map<String, dynamic>? ?? {};
        final versusMap = <String, VersusResultModel>{};
        for (final entry in rawVersus.entries) {
        final versusData = entry.value as Map<String, dynamic>?;
        if (versusData == null) continue;
        versusMap[entry.key] = VersusResultModel.fromMap(entry.key, versusData);
        }

        return OpponentModel(
        opponentId:        opponentId,
        opponentName:      (data['opponent_name']  as String?)?.trim() ?? '',
        opponentImage:     (data['opponent_image'] as String?)?.trim() ?? '',
        versusCount:       (data['versus_count']        as num?)?.toInt() ?? 0,
        winsAgainst:       (data['wins_against']        as num?)?.toInt() ?? 0,
        lossesTo:          (data['losses_to']           as num?)?.toInt() ?? 0,
        draws:             (data['draws']               as num?)?.toInt() ?? 0,
        totalentityVotes:     (data['total_our_votes']     as num?)?.toInt() ?? 0,
        totalopponentVotes:   (data['total_their_votes']   as num?)?.toInt() ?? 0,
        lastPlayed:        _toDateTime(data['last_played']),
        versus:            versusMap,
        );
    }

    /// Serializes cumulative fields only.
    /// The nested versus entries are written separately via dot-notation
    /// in [FirebaseService.updateRankingsFromPoll] using FieldValue.increment.
    Map<String, dynamic> toMap() => {
        'opponent_name':      opponentName,
        'opponent_image':     opponentImage,
        'versus_count':       versusCount,
        'wins_against':       winsAgainst,
        'losses_to':          lossesTo,
        'draws':              draws,
        'total_our_votes':    totalentityVotes,
        'total_their_votes':  totalopponentVotes,
        'last_played':        lastPlayed != null
            ? Timestamp.fromDate(lastPlayed!)
            : FieldValue.serverTimestamp(),
        'versus': {
        for (final e in versus.entries) e.key: e.value.toMap(),
        },
    };

    // ── Convenience ───────────────────────────────────────────────────────────
    /// Human-readable record string e.g. "2W - 1L - 0D"
    String get recordString => '${winsAgainst}W - ${lossesTo}L - ${draws}D';

    double get winRateAgainst =>
        versusCount == 0 ? 0.0 : winsAgainst / versusCount;

    int get scoreDiff => totalentityVotes - totalopponentVotes;

    /// Sorted list of individual versus results, newest first.
    List<VersusResultModel> get versusHistory {
        final list = versus.values.toList()
        ..sort((a, b) {
            final ta = a.playedAt?.millisecondsSinceEpoch ?? 0;
            final tb = b.playedAt?.millisecondsSinceEpoch ?? 0;
            return tb.compareTo(ta);
        });
        return list;
    }
    }

    // ── Root ranking document ─────────────────────────────────────────────────────
    /// One document per artist or album in the `rankings` collection.
    /// Doc ID = the Spotify entity ID (artist ID or album ID).
    ///
    /// Firestore location: rankings/{entityId}
    ///
    /// Structure mirrors the schema:
    ///
    ///   rankings/0iEtIxbK0KxaSlF7G42ZOp
    ///     entity_type:   "artist"
    ///     entity_name:   "Metro Boomin"
    ///     total_votes:   89
    ///     wins:          6
    ///     losses:        2
    ///     draws:         0
    ///     win_rate:      0.75
    ///     versus_count:  8
    ///     opponents:
    ///       5Y5TRrQiqgUO4S36tzjIRZ:   ← OpponentModel
    ///         wins_against: 2
    ///         versus:
    ///           QN9k4...: ...          ← VersusResultModel
    ///           Xm2pL...: ...
    class RankingModel {
    // ── Identity ───────────────────────────────────────────────────────────────
    final String entityId;      // same as Firestore doc ID
    final String entityType;    // "artist" | "album"
    final String entityName;
    final String entityImage;   // cached Spotify image URL

    // ── Global tallies ─────────────────────────────────────────────────────────
    final int    totalVotes;    // every vote cast FOR this entity across all versus
    final int    versusCount;   // total versus appearances
    final int    wins;          // versus where this entity got more votes
    final int    losses;        // versus where this entity got fewer votes
    final int    draws;         // versus where both entities got equal votes
    final double winRate;       // wins / versusCount — stored for cheap sorting

    // ── Timestamps ─────────────────────────────────────────────────────────────
    final DateTime? createdAt;
    final DateTime? lastUpdated;

    // ── Head-to-head records ───────────────────────────────────────────────────
    /// Map keyed by opponent entity ID → full head-to-head record.
    final Map<String, OpponentModel> opponents;

    const RankingModel({
        required this.entityId,
        required this.entityType,
        required this.entityName,
        required this.entityImage,
        required this.totalVotes,
        required this.versusCount,
        required this.wins,
        required this.losses,
        required this.draws,
        required this.winRate,
        this.createdAt,
        this.lastUpdated,
        this.opponents = const {},
    });

    /// Stub document for `rankings/{entityId}` the first time this Spotify entity
    /// appears in any versus. Only used for initial `set()`; later updates should
    /// use atomic `FieldValue.increment` / dot-path `update()` (see model header).
    factory RankingModel.newEntityStub({
        required String entityId,
        required String entityType,
        required String entityName,
        String entityImage = '',
    }) {
        final id = entityId.trim();
        final type = entityType.trim().toLowerCase();
        return RankingModel(
        entityId:     id,
        entityType:   type == 'album' ? 'album' : 'artist',
        entityName:   entityName.trim(),
        entityImage:  entityImage.trim(),
        totalVotes:   0,
        versusCount:  0,
        wins:         0,
        losses:       0,
        draws:        0,
        winRate:      0.0,
        opponents:    const {},
        );
    }

    // ── Firestore → model ──────────────────────────────────────────────────────
    factory RankingModel.fromFirestore(Map<String, dynamic> data, String id) {
        // Parse opponents map
        final rawOpponents = data['opponents'] as Map<String, dynamic>? ?? {};
        final opponentsMap = <String, OpponentModel>{};
        for (final entry in rawOpponents.entries) {
        final oppData = entry.value as Map<String, dynamic>?;
        if (oppData == null) continue;
        opponentsMap[entry.key] = OpponentModel.fromMap(entry.key, oppData);
        }

        final versusCount = (data['versus_count'] as num?)?.toInt() ?? 0;
        final wins        = (data['wins']         as num?)?.toInt() ?? 0;
        final winRate     = versusCount == 0
            ? 0.0
            : (data['win_rate'] as num?)?.toDouble() ?? (wins / versusCount);

        return RankingModel(
        entityId:     id,
        entityType:   (data['entity_type']  as String?)?.trim() ?? 'artist',
        entityName:   (data['entity_name']  as String?)?.trim() ?? '',
        entityImage:  (data['entity_image'] as String?)?.trim() ?? '',
        totalVotes:   (data['total_votes']  as num?)?.toInt() ?? 0,
        versusCount:  versusCount,
        wins:         wins,
        losses:       (data['losses']       as num?)?.toInt() ?? 0,
        draws:        (data['draws']        as num?)?.toInt() ?? 0,
        winRate:      winRate,
        createdAt:    _toDateTime(data['created_at']),
        lastUpdated:  _toDateTime(data['last_updated']),
        opponents:    opponentsMap,
        );
    }

    // ── model → Firestore ──────────────────────────────────────────────────────
    /// Full document write — used only when creating a new ranking doc from scratch.
    /// Incremental updates (vote tallies, opponent stats) are handled via
    /// dot-notation update() calls in FirebaseService to avoid race conditions.
    Map<String, dynamic> toFirestore() => {
        'entity_type':   entityType,
        'entity_id':     entityId,
        'entity_name':   entityName,
        'entity_image':  entityImage,
        'total_votes':   totalVotes,
        'versus_count':  versusCount,
        'wins':          wins,
        'losses':        losses,
        'draws':         draws,
        'win_rate':      versusCount == 0 ? 0.0 : wins / versusCount,
        'last_updated':  FieldValue.serverTimestamp(),
        'created_at':    FieldValue.serverTimestamp(),
        'opponents': {
        for (final e in opponents.entries) e.key: e.value.toMap(),
        },
    };

    // ── Convenience getters ────────────────────────────────────────────────────
    bool get isArtist => entityType == 'artist';
    bool get isAlbum  => entityType == 'album';

    /// Human-readable overall record e.g. "6W - 2L - 0D"
    String get recordString => '${wins}W - ${losses}L - ${draws}D';

    /// Opponents sorted by most recently played — for profile head-to-head list.
    List<OpponentModel> get opponentsByRecent {
        final list = opponents.values.toList()
        ..sort((a, b) {
            final ta = a.lastPlayed?.millisecondsSinceEpoch ?? 0;
            final tb = b.lastPlayed?.millisecondsSinceEpoch ?? 0;
            return tb.compareTo(ta);
        });
        return list;
    }

    /// Opponents sorted by most versus played — for "biggest rivalries" view.
    List<OpponentModel> get opponentsByVersusCount {
        final list = opponents.values.toList()
        ..sort((a, b) => b.versusCount.compareTo(a.versusCount));
        return list;
    }

    /// Opponents this entity has beaten — for "victories" view.
    List<OpponentModel> get victories =>
        opponents.values.where((o) => o.winsAgainst > o.lossesTo).toList();

    /// Opponents this entity has lost to — for "defeats" view.
    List<OpponentModel> get defeats =>
        opponents.values.where((o) => o.lossesTo > o.winsAgainst).toList();

    /// Score diff across all versus — positive means more votes received than given up.
    int get globalScoreDiff {
        int ourTotal   = 0;
        int theirTotal = 0;
        for (final o in opponents.values) {
        ourTotal   += o.totalentityVotes;
        theirTotal += o.totalopponentVotes;
        }
        return ourTotal - theirTotal;
    }
    }

    // ── Shared timestamp helper ───────────────────────────────────────────────────
    DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
    }