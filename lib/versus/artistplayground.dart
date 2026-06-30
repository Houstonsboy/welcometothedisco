import 'dart:async';
  import 'dart:convert';
  import 'dart:io';
  import 'dart:typed_data';
  import 'dart:ui' as ui;
import 'dart:math' as math;

  import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
  import 'package:flutter/rendering.dart';
  import 'package:flutter/services.dart';
  import 'package:welcometothedisco/models/vote_doc_template_model.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:welcometothedisco/models/artist_versus_model.dart';
  import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
  import 'package:welcometothedisco/services/user_profile_cache_service.dart';
  import 'package:welcometothedisco/theme/app_theme.dart';
  import 'package:welcometothedisco/versus/collaboratorbackroom.dart';
  import 'package:welcometothedisco/versus/playable_album_cover.dart';
  import 'package:welcometothedisco/widgets/versus_share_card.dart';
  import 'package:gal/gal.dart';
  import 'package:path_provider/path_provider.dart';
  import 'package:share_plus/share_plus.dart';

  const _kDefaultColor1 = AppTheme.gradientStart;
  const _kDefaultColor2 = AppTheme.gradientEnd;
  const _kSpotifyGreen  = AppTheme.spotifyGreen;

  // Ranking: first-time `rankings/{spotifyArtistId}` documents are created when a versus
  // is saved from the artist lockeroom / collaborator flows — see
  // [FirebaseService.createArtistVersus] and [FirebaseService.ensureRankingDocIfAbsent]
  // (RANKINGS section in firebase_service.dart). This screen only consumes versus + polls.

  // ── Track Vote Detail ─────────────────────────────────────────────────────────
  /// Represents a fully captured vote for a single round (index).
  class TrackVoteDetail {
    final String artist1trackID;
    final String artist2trackID;
    final String winnerTrackID;   // the ID of the track the voter picked
    final String artist1trackName;
    final String artist2trackName;
    String voterComment;
    final bool isBonus;

    TrackVoteDetail({
      required this.artist1trackID,
      required this.artist2trackID,
      required this.winnerTrackID,
      required this.artist1trackName,
      required this.artist2trackName,
      this.voterComment = '',
      this.isBonus = false,
    });

    Map<String, dynamic> toMap() => {
      'artist1trackID':   artist1trackID,
      'artist2trackID':   artist2trackID,
      'Winner':           winnerTrackID,
      'voter_comment':    voterComment,
      'artist1trackName': artist1trackName,
      'artist2trackName': artist2trackName,
      'isBonus':          isBonus,
    };
  }

class ArtistVersusPlayground extends StatefulWidget {
  final ArtistVersusModel versus;
    final String? versusId;

    const ArtistVersusPlayground({
      super.key,
      required this.versus,
      this.versusId,
    });

  @override
  State<ArtistVersusPlayground> createState() => _ArtistVersusPlaygroundState();
}

class _ArtistVersusPlaygroundState extends State<ArtistVersusPlayground>
    with TickerProviderStateMixin, WidgetsBindingObserver {
    final GlobalKey _shareCardKey = GlobalKey();
  bool _shareCardOffstage = true;
  final SpotifyApi _api = SpotifyApi();
    late ArtistVersusModel _versus;
    String get _resolvedVersusId {
      final routeId = widget.versusId?.trim() ?? '';
      if (routeId.isNotEmpty) return routeId;
      return widget.versus.id.trim();
    }
    String _voterId = '';
    String _voterName = '';
    String _voterAvatar = '';
    Timer? _pollDebounce;

    // ── Ranking reconciliation state ──────────────────────────────────────────
    // Last ranking batch applied for this session: completion % plus entity vote
    // tallies. Seeded from poll doc in _restoreExistingPoll. When any of these
    // differ from the current template (e.g. unvote, same % but different winner),
    // we reconcile again — unlike pct-only checks, which skipped when pct dropped.
    double _lastReconciledPct = 0.0;
    int _lastReconciledEntity1Votes = 0;
    int _lastReconciledEntity2Votes = 0;

    // Guard: prevents concurrent reconcile calls from racing each other.
    // Set true at start of _reconcileRankingNow, false on completion.
    bool _isReconciling = false;

    // ── Hydrated track lists ──────────────────────────────────────────────────
  List<SpotifyTrack> _tracks1 = [];
  List<SpotifyTrack> _tracks2 = [];
  bool _isLoadingTracks = true;
  String? _loadError;

    // ── Artist profile images ─────────────────────────────────────────────────
  String? _artist1ImageUrl;
  String? _artist2ImageUrl;

  // ── Playback state ────────────────────────────────────────────────────────
  int _selectedArtist = 0;
  late final PageController _pageController;
  int _activeTrackIndex = 0;
  int? _playingTrackIndex;
  int _leadArtistIndex = 0;
  bool _hasVersusPlaybackStarted = false;
  int? _coverLoadingRoundIndex;

  bool _isBombLoading = false;
  StreamSubscription<NowPlaying?>? _nowPlayingSub;
  String? _advanceOnTrackId;
  String? _currentRoundTrack1Id;
  String? _currentRoundTrack2Id;
  bool _roundTrack2Started = false;
  // Which artist side started the current round (0 = artist1, 1 = artist2).
  // Used by bomb-queue so every subsequent round preserves the same lead order.
  int _playbackLeadArtistIndex = 0;

    // ── Vote state ────────────────────────────────────────────────────────────
    /// Map<roundIndex, artistIndex (0 or 1)> — which artist the voter picked per round
  final Map<int, int> _votesByIndex = {};

    /// Map<roundIndex, TrackVoteDetail> — full structured vote data per round
    final Map<int, TrackVoteDetail> _trackDetails = {};

    int get _pairedRoundCount => math.min(_tracks1.length, _tracks2.length);
    int? get _longerSideArtistIndex {
      if (_tracks1.length == _tracks2.length) return null;
      return _tracks1.length > _tracks2.length ? 0 : 1;
    }

    bool get _isVotingCompleteForPairs =>
        _votesByIndex.length >= _pairedRoundCount;

    int get _bonusVoteForLongerSide =>
        (_longerSideArtistIndex != null && _isVotingCompleteForPairs) ? 1 : 0;

    /// Tally counters include +1 on longer side once paired voting is complete.
    int get _artist1VoteCount {
      final base = _votesByIndex.values.where((v) => v == 0).length;
      final bonus = _longerSideArtistIndex == 0 ? _bonusVoteForLongerSide : 0;
      return base + bonus;
    }

    int get _artist2VoteCount {
      final base = _votesByIndex.values.where((v) => v == 1).length;
      final bonus = _longerSideArtistIndex == 1 ? _bonusVoteForLongerSide : 0;
      return base + bonus;
    }

    // ── Per-track comment controllers (keyed by track index) ─────────────────
    final Map<int, TextEditingController> _commentControllers = {};

    TextEditingController _commentCtrlAt(int index) {
      return _commentControllers.putIfAbsent(
          index, () => TextEditingController());
    }

  // ── Palette colors ────────────────────────────────────────────────────────
  Color _color1 = _kDefaultColor1;
  Color _color2 = _kDefaultColor2;

  // ── Animations ────────────────────────────────────────────────────────────
  late final AnimationController _pulseController;
  late final AnimationController _slideController;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _slideAnim;
    OverlayEntry? _profileBubble;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
      _versus = widget.versus;
      final versusId = _resolvedVersusId;
      debugPrint(
        '[ArtistVersusPlayground] opened | versus_id: '
        '${versusId.isEmpty ? '(missing)' : versusId}',
      );

    _pageController = PageController();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnim = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );

    _slideController.forward();
      unawaited(_hydrateVoterContext());
    _loadData();
  }

    Future<void> _hydrateVoterContext() async {
      final uid = FirebaseAuth.instance.currentUser?.uid?.trim() ?? '';
      if (uid.isEmpty) return;

      var cached = await UserProfileCacheService.readUser(expectedUid: uid);
      if (cached == null) {
        await FirebaseService.ensureCurrentUserProfileCached();
        cached = await UserProfileCacheService.readUser(expectedUid: uid);
      }
      if (!mounted) return;

      setState(() {
        _voterId = uid;
        _voterName = cached?.username.trim() ?? '';
        _voterAvatar = cached?.avatarPath.trim() ?? '';
      });

      // Attempt to restore any previous voting session for this versus.
      // _restoreExistingPoll checks internally if tracks are ready.
      await _restoreExistingPoll();
      _logVoteTemplateSnapshot('voter-context-ready');
    }

    /// Fetches the existing poll doc for this voter+versus and restores
    /// _votesByIndex and _trackDetails so the UI shows prior decisions.
    ///
    /// Safe to call before tracks load — it will wait. Safe to call if no
    /// poll exists — it exits silently.
    Future<void> _restoreExistingPoll() async {
      if (_voterId.isEmpty || _resolvedVersusId.isEmpty) return;

      if (_isLoadingTracks) {
        int waited = 0;
        while (_isLoadingTracks && waited < 8000) {
          await Future.delayed(const Duration(milliseconds: 100));
          waited += 100;
        }
        if (_isLoadingTracks) {
          debugPrint(
            '[ArtistVersusPlayground] _restoreExistingPoll → timed out waiting for tracks',
          );
          return;
        }
      }

      final data = await FirebaseService.getExistingArtistPoll(
        versusId: _resolvedVersusId,
        voterId: _voterId,
      );
      if (data == null || !mounted) return;

      // ── GAP-FILL SEED: runs on every restore regardless of track_details ──
      final storedLastPct =
          (data['last_reconciled_pct'] as num?)?.toDouble() ?? 0.0;
      final storedCompletionPct =
          (data['completion_percentage'] as num?)?.toDouble() ?? 0.0;

      _lastReconciledPct = storedLastPct;
      _lastReconciledEntity1Votes =
          (data['artist1Vote'] as num?)?.toInt() ?? 0;
      _lastReconciledEntity2Votes =
          (data['artist2Vote'] as num?)?.toInt() ?? 0;

      if (storedCompletionPct > storedLastPct) {
        debugPrint(
          '[_restoreExistingPoll] gap detected before track parse: '
          'completion=$storedCompletionPct > lastReconciled=$storedLastPct',
        );
        unawaited(_reconcileRankingNow(reason: 'restore-gap-fill-early'));
      }

      final rawDetails = data['track_details'] as Map<String, dynamic>?;
      if (rawDetails == null || rawDetails.isEmpty) return;

      final restoredVotes = <int, int>{};
      final restoredDetails = <int, TrackVoteDetail>{};

      for (final entry in rawDetails.entries) {
        final roundIndex = int.tryParse(entry.key);
        if (roundIndex == null) continue;
        final round = entry.value as Map<String, dynamic>?;
        if (round == null) continue;
        final isBonus = round['isBonus'] as bool? ?? false;
        if (isBonus) continue;

        final artist1trackID = round['artist1trackID'] as String? ?? '';
        final artist2trackID = round['artist2trackID'] as String? ?? '';
        final winnerId = round['Winner'] as String? ?? '';
        if (winnerId.isEmpty || artist1trackID.isEmpty || artist2trackID.isEmpty) {
          continue;
        }

        final int winnerArtistIndex;
        if (winnerId == artist1trackID) {
          winnerArtistIndex = 0;
        } else if (winnerId == artist2trackID) {
          winnerArtistIndex = 1;
        } else {
          continue;
        }

        restoredVotes[roundIndex] = winnerArtistIndex;
        restoredDetails[roundIndex] = TrackVoteDetail(
          artist1trackID: artist1trackID,
          artist2trackID: artist2trackID,
          winnerTrackID: winnerId,
          artist1trackName: round['artist1trackName'] as String? ?? '',
          artist2trackName: round['artist2trackName'] as String? ?? '',
          voterComment: round['voter_comment'] as String? ?? '',
          isBonus: false,
        );
      }

      if (restoredVotes.isEmpty || !mounted) return;

      setState(() {
        _votesByIndex.addAll(restoredVotes);
        _trackDetails.addAll(restoredDetails);
      });

      for (final entry in restoredDetails.entries) {
        final comment = entry.value.voterComment;
        if (comment.isNotEmpty) {
          _commentCtrlAt(entry.key).text = comment;
        }
      }

      if (storedCompletionPct > storedLastPct) {
        debugPrint(
          '[_restoreExistingPoll] gap-fill after vote restore: '
          'completion=$storedCompletionPct > lastReconciled=$storedLastPct',
        );
        unawaited(_reconcileRankingNow(reason: 'restore-gap-fill-post-restore'));
      }

      if (storedCompletionPct < storedLastPct) {
        debugPrint(
          '[_restoreExistingPoll] stale last_reconciled_pct after restore: '
          'completion=$storedCompletionPct < lastReconciled=$storedLastPct',
        );
        unawaited(_reconcileRankingNow(reason: 'restore-stale-last-pct'));
      }

      debugPrint(
        '[ArtistVersusPlayground] _restoreExistingPoll → restored '
        '${restoredVotes.length} round(s)',
      );
      _logVoteTemplateSnapshot('session-restored');
    }

    VoteDocTemplateModel _buildVoteTemplateDoc() {
      final totalRounds = _pairedRoundCount;
      final votedCount = _votesByIndex.length;
      final unvoted = totalRounds > votedCount ? totalRounds - votedCount : 0;
      final completion = totalRounds == 0
          ? 0.0
          : ((votedCount / totalRounds) * 100).clamp(0, 100).toDouble();

      final details = <int, VoteTrackDetailModel>{
        for (final entry in _trackDetails.entries)
          entry.key: VoteTrackDetailModel(
            artist1trackID: entry.value.artist1trackID,
            artist2trackID: entry.value.artist2trackID,
            winner: entry.value.winnerTrackID,
            voterComment: entry.value.voterComment,
            artist1trackName: entry.value.artist1trackName,
            artist2trackName: entry.value.artist2trackName,
            isBonus: entry.value.isBonus,
          ),
      };

      final longerIndex = _longerSideArtistIndex;
      if (longerIndex != null) {
        final longerTracks = longerIndex == 0 ? _tracks1 : _tracks2;
        for (int i = _pairedRoundCount; i < longerTracks.length; i++) {
          final t = longerTracks[i];
          details[i] = VoteTrackDetailModel(
            artist1trackID: longerIndex == 0 ? t.id : null,
            artist2trackID: longerIndex == 1 ? t.id : null,
            winner: t.id,
            voterComment: '',
            artist1trackName: longerIndex == 0 ? t.name : null,
            artist2trackName: longerIndex == 1 ? t.name : null,
            isBonus: true,
          );
        }
      }

      return VoteDocTemplateModel.artist(
        versusId: _resolvedVersusId,
        versusType: _versus.type,
        voterId: _voterId,
        voterName: _voterName,
        voterAvatar: _voterAvatar,
        timestamp: DateTime.now().toUtc(),
        artist1ID: _versus.artist1ID,
        artist1Name: _versus.artist1Name,
        artist1Vote: _artist1VoteCount,
        artist2ID: _versus.artist2ID,
        artist2Name: _versus.artist2Name,
        artist2Vote: _artist2VoteCount,
        completionPercentage: completion,
        unvotedCount: unvoted,
        trackDetails: details,
      );
    }

    void _logVoteTemplateSnapshot(String reason) {
      final payload = _buildVoteTemplateDoc();
      debugPrint(
        '[ArtistVersusPlayground][$reason] vote_doc_template=${jsonEncode(payload.toMap())}',
      );
    }

  // ── Data loading ──────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    setState(() { _isLoadingTracks = true; _loadError = null; });
    try {
      // Keep versus in sync with Firestore so new rounds (added in backroom /
      // elsewhere) load here — stale widget.versus would cap paired rounds and votes.
      var model = _versus;
      final vid = _resolvedVersusId;
      if (vid.isNotEmpty) {
        final fresh = await FirebaseService.getArtistVersusById(vid);
        if (fresh != null) {
          model = fresh;
        }
      }

      final results = await Future.wait([
          _api.getTracksByIds(model.artist1TrackIDs),
          _api.getTracksByIds(model.artist2TrackIDs),
          _api.getArtistDetails(model.artist1ID),
          _api.getArtistDetails(model.artist2ID),
        ]);

        final tracks1  = results[0] as List<SpotifyTrack>;
        final tracks2  = results[1] as List<SpotifyTrack>;
        final artist1  = results[2] as SpotifyArtistDetails?;
        final artist2  = results[3] as SpotifyArtistDetails?;

      if (!mounted) return;
      setState(() {
        _versus = model;
        _tracks1 = tracks1;
        _tracks2 = tracks2;
        _artist1ImageUrl = artist1?.imageUrl;
        _artist2ImageUrl = artist2?.imageUrl;
        _isLoadingTracks = false;
      });

      _extractPalette(_artist1ImageUrl, _artist2ImageUrl);
        _logVoteTemplateSnapshot('tracks-loaded');
    } catch (e) {
      debugPrint('[ArtistVersusPlayground] _loadData error: $e');
      if (mounted) {
        setState(() {
          _isLoadingTracks = false;
          _loadError = 'Failed to load tracks. Tap to retry.';
        });
      }
    }
  }

  Future<void> _extractPalette(String? url1, String? url2) async {
    if (url1 != null && url1.isNotEmpty) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          NetworkImage(url1), size: const Size(200, 200),
        );
        final color = palette.vibrantColor?.color ??
            palette.dominantColor?.color ?? _kDefaultColor1;
        if (mounted) setState(() => _color1 = color);
      } catch (_) {}
    }
    if (url2 != null && url2.isNotEmpty) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          NetworkImage(url2), size: const Size(200, 200),
        );
        final color = palette.vibrantColor?.color ??
            palette.dominantColor?.color ?? _kDefaultColor2;
        if (mounted) setState(() => _color2 = color);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      debugPrint('[lifecycle] state=$state — flushing poll + reconciling');

      _pollDebounce?.cancel();
      unawaited(
        _syncPollToFirestore().then(
          (_) => _reconcileRankingNow(reason: 'lifecycle-${state.name}'),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _pollDebounce?.cancel();

    unawaited(
      _syncPollToFirestore().then(
        (_) => _reconcileRankingNow(reason: 'dispose'),
      ),
    );

    _profileBubble?.remove();
    _nowPlayingSub?.cancel();
    _pulseController.dispose();
    _slideController.dispose();
    _pageController.dispose();
    for (final ctrl in _commentControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

    // ── Vote logic ────────────────────────────────────────────────────────────

    /// Called when the voter taps a vote button at [roundIndex] for [artistIndex] (0 or 1).
    ///
    /// Behaviour:
    ///  - If tapping the SAME artist again at this index → remove vote (toggle off).
    ///  - If tapping the other side (or first vote) → set/replace the vote.
    void _onVote(int roundIndex, int artistIndex) {
      if (roundIndex >= _pairedRoundCount) return;
      final current = _votesByIndex[roundIndex];
      if (current == artistIndex) {
        setState(() {
          _votesByIndex.remove(roundIndex);
          _trackDetails.remove(roundIndex);
        });
      } else {
        final t1 = _tracks1.elementAtOrNull(roundIndex);
        final t2 = _tracks2.elementAtOrNull(roundIndex);
        if (t1 == null || t2 == null) return;

        final winnerTrack = artistIndex == 0 ? t1 : t2;
        final comment = _commentCtrlAt(roundIndex).text.trim();

        final detail = TrackVoteDetail(
          artist1trackID:   t1.id,
          artist2trackID:   t2.id,
          winnerTrackID:    winnerTrack.id,
          artist1trackName: t1.name,
          artist2trackName: t2.name,
          voterComment:     comment,
          isBonus:          false,
        );

        setState(() {
          _votesByIndex[roundIndex] = artistIndex;
          _trackDetails[roundIndex]  = detail;
        });

        // Debug print — remove before production
        debugPrint('[Vote] Round $roundIndex → ${detail.toMap()}');
        debugPrint('[Tally] Artist1: $_artist1VoteCount | Artist2: $_artist2VoteCount');
        debugPrint('[TrackDetails] ${_trackDetails.map((k, v) => MapEntry(k, v.toMap()))}');
      }
      _logVoteTemplateSnapshot('vote-updated-round-$roundIndex');
      _schedulePollSync();
      _requestReconcileAfterVote();
    }

    /// Updates the voter_comment on an already-cast vote when the user edits the note field.
    void _onCommentChanged(int roundIndex, String text) {
      final detail = _trackDetails[roundIndex];
      if (detail != null) {
        setState(() => detail.voterComment = text);
        _logVoteTemplateSnapshot('comment-updated-round-$roundIndex');
        _schedulePollSync();
      }
    }

    void _schedulePollSync() {
      _pollDebounce?.cancel();
      _pollDebounce = Timer(
        const Duration(milliseconds: 800),
        _syncPollToFirestore,
      );
    }

    Future<void> _syncPollToFirestore() async {
      if (_voterId.isEmpty || _resolvedVersusId.isEmpty) return;

      // Ensure latest text field values are reflected before write.
      for (final entry in _commentControllers.entries) {
        final detail = _trackDetails[entry.key];
        if (detail != null) {
          detail.voterComment = entry.value.text.trim();
        }
      }

      final doc = _buildVoteTemplateDoc();
      await FirebaseService.upsertArtistPoll(
        versusId: _resolvedVersusId,
        versusType: _versus.type,
        voterId: _voterId,
        voterName: _voterName,
        voterAvatar: _voterAvatar,
        artist1ID: _versus.artist1ID,
        artist1Name: _versus.artist1Name,
        artist1Vote: _artist1VoteCount,
        artist2ID: _versus.artist2ID,
        artist2Name: _versus.artist2Name,
        artist2Vote: _artist2VoteCount,
        trackDetails: {
          for (final e in doc.trackDetails.entries) e.key: e.value.toMap(),
        },
        completionPercentage: doc.completionPercentage,
        unvotedCount: doc.unvotedCount,
      );
    }

    bool _samePct(double a, double b) => (a - b).abs() < 0.0001;

    bool _watermarkMatches(VoteDocTemplateModel doc) {
      return _samePct(doc.completionPercentage, _lastReconciledPct) &&
          doc.entity1Vote == _lastReconciledEntity1Votes &&
          doc.entity2Vote == _lastReconciledEntity2Votes;
    }

    /// After a vote change, refresh rankings whenever the poll template differs
    /// from the last reconciled watermark (including unvotes and same-% tally changes).
    void _requestReconcileAfterVote() {
      unawaited(_reconcileRankingNow(reason: 'vote'));
    }

    // ── Function 2: Core reconcile engine ─────────────────────────────────────
    Future<void> _reconcileRankingNow({required String reason}) async {
      if (_isReconciling) {
        debugPrint('[reconcile] skipped ($reason) — already in progress');
        return;
      }
      if (_voterId.isEmpty || _resolvedVersusId.isEmpty) return;
      if (_versus.artist1ID.trim().isEmpty ||
          _versus.artist2ID.trim().isEmpty) {
        debugPrint('[reconcile] skipped ($reason) — missing artist IDs');
        return;
      }

      final doc = _buildVoteTemplateDoc();
      final currentPct = doc.completionPercentage;

      // Early restore-gap-fill: poll may show completion ahead of ranking while
      // local _votesByIndex is still empty — do not skip on local completion.
      final skipGapCheck = reason == 'restore-gap-fill-early';
      if (!skipGapCheck && _watermarkMatches(doc)) {
        debugPrint(
          '[reconcile] skipped ($reason) — watermark unchanged '
          '(pct=$currentPct, votes=${doc.entity1Vote},${doc.entity2Vote})',
        );
        return;
      }

      _isReconciling = true;
      debugPrint(
        '[reconcile] START reason=$reason '
        'pct=$currentPct votes=(${doc.entity1Vote},${doc.entity2Vote})',
      );

      try {
        await FirebaseService.reconcileRankingBatch(
          entity1Id: _versus.artist1ID,
          entity2Id: _versus.artist2ID,
          versusId: _resolvedVersusId,
          voterId: _voterId,
          currentEntity1Votes: doc.entity1Vote,
          currentEntity2Votes: doc.entity2Vote,
          currentPct: currentPct,
        );

        _lastReconciledPct = currentPct;
        _lastReconciledEntity1Votes = doc.entity1Vote;
        _lastReconciledEntity2Votes = doc.entity2Vote;
        debugPrint(
          '[reconcile] DONE reason=$reason lastReconciledPct=$_lastReconciledPct '
          'votes=($_lastReconciledEntity1Votes,$_lastReconciledEntity2Votes)',
        );
      } on RankingStubsMissingException {
        debugPrint('[reconcile] ranking stubs missing — retry in 3s');
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        final docRetry = _buildVoteTemplateDoc();
        final pctRetry = docRetry.completionPercentage;
        final skipGapRetry = reason == 'restore-gap-fill-early';
        if (!skipGapRetry && _watermarkMatches(docRetry)) {
          debugPrint(
            '[reconcile] retry skipped — watermark unchanged '
            '(pct=$pctRetry)',
          );
          return;
        }
        try {
          await FirebaseService.reconcileRankingBatch(
            entity1Id: _versus.artist1ID,
            entity2Id: _versus.artist2ID,
            versusId: _resolvedVersusId,
            voterId: _voterId,
            currentEntity1Votes: docRetry.entity1Vote,
            currentEntity2Votes: docRetry.entity2Vote,
            currentPct: pctRetry,
          );
          _lastReconciledPct = pctRetry;
          _lastReconciledEntity1Votes = docRetry.entity1Vote;
          _lastReconciledEntity2Votes = docRetry.entity2Vote;
          debugPrint(
            '[reconcile] retry DONE lastReconciledPct=$_lastReconciledPct '
            'votes=($_lastReconciledEntity1Votes,$_lastReconciledEntity2Votes)',
          );
        } catch (e) {
          debugPrint('[reconcile] retry also failed: $e');
        }
      } catch (e, st) {
        debugPrint('[reconcile] FAILED reason=$reason: $e\n$st');
      } finally {
        _isReconciling = false;
      }
    }

    // ── Function 3: Back navigation hook ─────────────────────────────────────
    /// Flush poll + reconcile, then pop. Used from [PopScope] (system back) and
    /// from header via [Navigator.maybePop] which routes through the same [PopScope].
    Future<void> _handleBackNavigation() async {
      _pollDebounce?.cancel();
      await _syncPollToFirestore();
      await _reconcileRankingNow(reason: 'back-navigation');
      if (mounted) Navigator.of(context).pop();
    }

    Map<int, Map<String, dynamic>> _buildShareTrackDetails() {
      return {
        for (final e in _trackDetails.entries) e.key: e.value.toMap(),
      };
    }

    Future<Uint8List?> _captureShareCard() async {
      for (final entry in _commentControllers.entries) {
        final detail = _trackDetails[entry.key];
        if (detail != null) {
          detail.voterComment = entry.value.text.trim();
        }
      }
      if (!mounted) return null;

      // Make the share card visible so Flutter actually paints it this frame.
      // Offstage(offstage: true) skips the paint pass, causing toImage() to
      // throw '!debugNeedsPaint'.
      setState(() => _shareCardOffstage = false);
      await WidgetsBinding.instance.endOfFrame;

      Uint8List? result;
      try {
        final boundary = _shareCardKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 3.0);
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          result = byteData?.buffer.asUint8List();
        }
      } finally {
        if (mounted) setState(() => _shareCardOffstage = true);
      }
      return result;
    }

    void _showShareBottomSheet() {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF1A1A1A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _ShareSheet(
          onShare: _handleShare,
          onCopyLink: _handleCopyLink,
          onSaveToGallery: _handleSaveToGallery,
        ),
      );
    }

    Future<void> _handleSaveToGallery() async {
      Navigator.pop(context);
      if (_trackDetails.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Vote on at least one round to save a results image',
            ),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }
      final bytes = await _captureShareCard();
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not create image'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }

      try {
        // putImageBytes requests access automatically on iOS/macOS.
        // On Android 10+ no explicit permission is needed.
        // GalException(accessDenied) is thrown if the user refuses.
        await Gal.putImageBytes(bytes, name: 'wttd_versus_result');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved to gallery'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } on GalException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.type.message),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not save to gallery'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }

    Future<void> _handleShare(String platform) async {
      Navigator.pop(context);
      if (_trackDetails.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Vote on at least one round to share a results image',
            ),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }
      final bytes = await _captureShareCard();
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not create share image'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final file = await File(
        '${tempDir.path}/wttd_versus.png',
      ).writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${_versus.artist1Name} vs ${_versus.artist2Name} '
            '— voted on welcometothedisco',
      );
    }

    Future<void> _handleCopyLink() async {
      Navigator.pop(context);
      final link =
          'https://welcometothedisco.app/versus/${_resolvedVersusId}';
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied')),
        );
      }
    }

    // ── Profile bubble ────────────────────────────────────────────────────────
    void _showProfileBubble(BuildContext targetContext, String label) {
      if (label.trim().isEmpty) return;
      _profileBubble?.remove();

      final overlay = Overlay.of(context);
      final renderObject = targetContext.findRenderObject();
      if (overlay == null || renderObject is! RenderBox) return;

      final offset = renderObject.localToGlobal(Offset.zero);
      final size   = renderObject.size;

      _profileBubble = OverlayEntry(
        builder: (_) => Positioned(
          left: offset.dx + (size.width / 2) - 56,
          top:  offset.dy + size.height + 6,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );

      overlay.insert(_profileBubble!);
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        _profileBubble?.remove();
        _profileBubble = null;
      });
    }

    String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

    bool get _canOpenEditBackroom {
      final uid = _currentUid;
      if (uid == null || uid.isEmpty) return false;
      final isAuthor       = uid == _versus.authorID;
      final isCollaborator = uid == (_versus.collaboratorID?.trim() ?? '');
      return isAuthor || isCollaborator;
    }

    Future<void> _openEditBackroom() async {
      if (!_canOpenEditBackroom) return;
      final versusId = _resolvedVersusId;
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CollaboratorBackroom(versusID: versusId),
        ),
      );
      if (!mounted) return;

      // If the backroom updated the versus, refetch so track names/IDs are current.
      if (result is String && result.trim() == versusId.trim()) {
        await _refetchVersusAndReloadTracks();
      }
    }

    Future<void> _refetchVersusAndReloadTracks() async {
      if (_resolvedVersusId.isEmpty) return;
      final fresh = await FirebaseService.getArtistVersusById(_resolvedVersusId);
      if (!mounted || fresh == null) return;

      unawaited(
        FirebaseService.recalculatePollsAfterVersusTrackListChange(
          _resolvedVersusId,
        ),
      );

      setState(() {
        _versus = fresh;
        // Votes/comments tied to old track IDs may no longer match; reset UI state.
        _votesByIndex.clear();
        _trackDetails.clear();
        for (final ctrl in _commentControllers.values) {
          ctrl.clear();
        }
      });

      await _loadData();
      await _restoreExistingPoll();
    }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _selectArtist(int index) {
    if (_selectedArtist == index) return;
    setState(() => _selectedArtist = index);
    _slideController.forward(from: 0);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    if (_selectedArtist == index) return;
    setState(() => _selectedArtist = index);
    _slideController.forward(from: 0);
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  String _spotifyUriFor(SpotifyTrack track) {
    final uri = track.uri.trim();
    if (uri.isNotEmpty) return uri;
    final id = track.id.trim();
    if (id.isNotEmpty) return 'spotify:track:$id';
    return '';
  }

  void _stopPlaybackTracking() {
    _nowPlayingSub?.cancel();
    _nowPlayingSub = null;
    _advanceOnTrackId = null;
    _currentRoundTrack1Id = null;
    _currentRoundTrack2Id = null;
    _roundTrack2Started = false;
  }

  void _showPlaybackSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.black.withValues(alpha: 0.88),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Plays both tracks at [index]. [leadArtistIndex] (0 or 1) determines which
  /// artist's track plays immediately; the other is queued right after.
  Future<bool> _playRoundAtIndex(int index, {int leadArtistIndex = 0}) async {
    if (_tracks1.isEmpty || _tracks2.isEmpty) return false;
    final t1 = _tracks1.elementAtOrNull(index);
    final t2 = _tracks2.elementAtOrNull(index);
    if (t1 == null || t2 == null || t1.id.isEmpty || t2.id.isEmpty) {
      return false;
    }

    final uri1 = _spotifyUriFor(t1);
    final uri2 = _spotifyUriFor(t2);
    if (uri1.isEmpty || uri2.isEmpty) return false;

    // Swap order so the tapped side plays first.
    final firstUri   = leadArtistIndex == 1 ? uri2 : uri1;
    final secondUri  = leadArtistIndex == 1 ? uri1 : uri2;
    final firstId    = leadArtistIndex == 1 ? t2.id : t1.id;
    final secondId   = leadArtistIndex == 1 ? t1.id : t2.id;

    setState(() => _coverLoadingRoundIndex = index);
    try {
      final played = await _api.playRoundTracks(firstUri, secondUri);
      if (!played) {
        _showPlaybackSnack(
          'Open Spotify on a phone, speaker, or desktop, then try again.',
        );
        return false;
      }

      _hasVersusPlaybackStarted = true;
      _playbackLeadArtistIndex = leadArtistIndex;
      _currentRoundTrack1Id = firstId;
      _currentRoundTrack2Id = secondId;
      _roundTrack2Started = false;
      _advanceOnTrackId = secondId;
      _startNowPlayingIndexTracking();
      if (mounted) {
        setState(() => _playingTrackIndex = index);
      }
      return true;
    } catch (e) {
      debugPrint('[ArtistVersusPlayground] _playRoundAtIndex error: $e');
      _showPlaybackSnack('Playback failed. Check Spotify is active.');
      return false;
    } finally {
      if (mounted) setState(() => _coverLoadingRoundIndex = null);
    }
  }

  /// Tap title/artist — select round for voting & notes without starting playback.
  void _onTitleTap(int trackIndex, int artistIndex) {
    setState(() {
      _activeTrackIndex = trackIndex;
      _leadArtistIndex = artistIndex;
    });
  }

  /// Tap album cover — plays the tapped round with the tapped artist's track first.
  Future<void> _onCoverTap(int trackIndex, int artistIndex) async {
    if (_tracks1.isEmpty || _tracks2.isEmpty) return;

    if (_playingTrackIndex == trackIndex) {
      setState(() => _coverLoadingRoundIndex = trackIndex);
      try {
        final paused = await _api.pause();
        if (!mounted) return;
        if (paused) {
          _stopPlaybackTracking();
          setState(() => _playingTrackIndex = null);
        } else {
          _showPlaybackSnack(
            'Could not pause — open Spotify on a device and try again.',
          );
        }
      } finally {
        if (mounted) setState(() => _coverLoadingRoundIndex = null);
      }
      return;
    }

    await _playRoundAtIndex(trackIndex, leadArtistIndex: artistIndex);
  }

  void _startNowPlayingIndexTracking() {
    _nowPlayingSub?.cancel();
    _nowPlayingSub = _api
        .pollNowPlaying(interval: const Duration(seconds: 2))
        .listen((nowPlaying) {
      final trackId = nowPlaying?.trackId;
      if (!mounted || trackId == null || trackId.isEmpty) return;

      final roundTrack2 = _currentRoundTrack2Id;
      if (roundTrack2 == null || _advanceOnTrackId == null) return;

      if (trackId == roundTrack2) {
        _roundTrack2Started = true;
        return;
      }

      if (_roundTrack2Started && trackId != roundTrack2) {
        final total = math.min(_tracks1.length, _tracks2.length);
        if (_activeTrackIndex < total - 1) {
          setState(() {
            _activeTrackIndex++;
            _playingTrackIndex = null;
          });
        } else {
          setState(() => _playingTrackIndex = null);
        }
        _advanceOnTrackId     = null;
        _currentRoundTrack1Id = null;
        _currentRoundTrack2Id = null;
        _roundTrack2Started   = false;
      }
    });
  }

  Future<bool> _queueRoundAtIndex(int index, {int leadArtistIndex = 0}) async {
    final t1 = _tracks1.elementAtOrNull(index);
    final t2 = _tracks2.elementAtOrNull(index);
    if (t1 == null || t2 == null || t1.id.isEmpty || t2.id.isEmpty) {
      return false;
    }
    final uri1 = _spotifyUriFor(t1);
    final uri2 = _spotifyUriFor(t2);
    if (uri1.isEmpty || uri2.isEmpty) return false;
    final firstUri  = leadArtistIndex == 1 ? uri2 : uri1;
    final secondUri = leadArtistIndex == 1 ? uri1 : uri2;
    return _api.queueRoundTracks(firstUri, secondUri);
  }

  Future<void> _handleBomb() async {
    if (_isBombLoading || _tracks1.isEmpty || _tracks2.isEmpty) return;
    final total = math.min(_tracks1.length, _tracks2.length);
    if (total <= 0) return;

    setState(() => _isBombLoading = true);
    try {
      int queueFrom;
      if (!_hasVersusPlaybackStarted || _playingTrackIndex == null) {
        // Start from round 0 using whichever side the user is currently viewing.
        final started = await _playRoundAtIndex(0, leadArtistIndex: _leadArtistIndex);
        if (!started) return;
        queueFrom = 1;
      } else {
        if (_activeTrackIndex >= total - 1) return;
        queueFrom = _activeTrackIndex + 1;
      }

      // Queue remaining rounds in the same lead order as the round that started.
      for (int i = queueFrom; i < total; i++) {
        final queued = await _queueRoundAtIndex(i, leadArtistIndex: _playbackLeadArtistIndex);
        if (!queued) {
          debugPrint('[ArtistVersusPlayground] bomb stopped at index $i');
          break;
        }
      }
    } catch (e) {
      debugPrint('[ArtistVersusPlayground] _handleBomb error: $e');
    } finally {
      if (mounted) setState(() => _isBombLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
      final authorLabel            = _playgroundAuthorLabel(_versus);
      final avatarPath             = _playgroundAuthorAvatarPath(_versus);
      final collaboratorLabel      = _playgroundCollaboratorLabel(_versus);
      final collaboratorAvatarPath = _playgroundCollaboratorAvatarPath(_versus);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        unawaited(_handleBackNavigation());
      },
      child: Container(
        decoration: AppTheme.backgroundDecoration,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: DefaultTextStyle.merge(
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: _isLoadingTracks
            ? _buildLoadingState()
            : _loadError != null
                ? _buildErrorState()
                          : _buildContent(
                              context,
                              authorLabel,
                              avatarPath,
                              collaboratorLabel,
                              collaboratorAvatarPath,
                            ),
                ),
                // Must be [Positioned], not a loose [Offstage]: a non-positioned child
                // makes [Stack] size to that child (~360×640), so [Positioned.fill] only
                // fills that box and the playground looks blank.
                if (!_isLoadingTracks && _loadError == null)
                  Positioned(
                    left: -8000,
                    top: 0,
                    width: 360,
                    child: Offstage(
                      offstage: _shareCardOffstage,
                      child: RepaintBoundary(
                        key: _shareCardKey,
                        child: SizedBox(
                          width: 360,
                          child: VersusShareCard(
                            artist1Name: _versus.artist1Name,
                            artist2Name: _versus.artist2Name,
                            artist1ImageUrl: _artist1ImageUrl,
                            artist2ImageUrl: _artist2ImageUrl,
                            artist1Votes: _artist1VoteCount,
                            artist2Votes: _artist2VoteCount,
                            color1: _color1,
                            color2: _color2,
                            voterName: _voterName.trim().isEmpty
                                ? 'anonymous'
                                : _voterName.trim(),
                            trackDetails: _buildShareTrackDetails(),
                            pairedRoundCount: _pairedRoundCount,
                            roundTrackNames1: List.generate(
                              _pairedRoundCount,
                              (i) =>
                                  _tracks1.elementAtOrNull(i)?.name ?? '—',
                            ),
                            roundTrackNames2: List.generate(
                              _pairedRoundCount,
                              (i) =>
                                  _tracks2.elementAtOrNull(i)?.name ?? '—',
                            ),
                            roundTrackIds1: List.generate(
                              _pairedRoundCount,
                              (i) => _tracks1.elementAtOrNull(i)?.id ?? '',
                            ),
                            roundTrackIds2: List.generate(
                              _pairedRoundCount,
                              (i) => _tracks2.elementAtOrNull(i)?.id ?? '',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _color1),
          const SizedBox(height: 16),
            Text(
              'Loading tracks...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: GestureDetector(
        onTap: _loadData,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded,
                color: Colors.white.withOpacity(0.6), size: 40),
            const SizedBox(height: 12),
              Text(
                _loadError ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context,
      String authorLabel,
      String? avatarPath,
      String? collaboratorLabel,
      String? collaboratorAvatarPath,
    ) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Header ──────────────────────────────────────────────────────────
        SliverToBoxAdapter(
            child: _buildHeader(
              context,
              authorLabel,
              avatarPath,
              collaboratorLabel,
              collaboratorAvatarPath,
            ),
          ),

          // ── Artist selector ──────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildArtistSelector()),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // ── Swipe dots ───────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  _SwipeDot(isActive: _selectedArtist == 0, color: _color1),
                const SizedBox(width: 6),
                  _SwipeDot(isActive: _selectedArtist == 1, color: _color2),
              ],
            ),
          ),
        ),

        // ── Track PageView ───────────────────────────────────────────────────
        SliverFillRemaining(
          child: Column(
            children: [
              // ── Playback controls (tap covers to play; bomb queues ahead) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 9,
                          horizontal: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: _kSpotifyGreen.withOpacity(0.18),
                          border: Border.all(
                            color: _kSpotifyGreen.withOpacity(0.45),
                            width: 0.85,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _playingTrackIndex != null
                                    ? _kSpotifyGreen
                                    : Colors.white.withOpacity(0.35),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ROUND ${_activeTrackIndex + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            if (_playingTrackIndex != null) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.graphic_eq_rounded,
                                size: 14,
                                color: _kSpotifyGreen.withOpacity(0.95),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _isBombLoading ? null : _handleBomb,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: _kSpotifyGreen.withOpacity(
                            _isBombLoading ? 0.12 : 0.22,
                          ),
                          border: Border.all(
                            color: _kSpotifyGreen.withOpacity(
                              _isBombLoading ? 0.3 : 0.55,
                            ),
                            width: 0.85,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isBombLoading)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: _kSpotifyGreen,
                                ),
                              )
                            else ...[
                              const Text(
                                'QUEUE ALL',
                                style: TextStyle(
                                  color: _kSpotifyGreen,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.queue_music_rounded,
                                color: _kSpotifyGreen,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
             

                _buildVersusSideCommentStrip(),

              // ── Track pages ────────────────────────────────────────────────
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  children: [
                    _ArtistTrackPage(
                        tracks:            _tracks1,
                        artistIndex:       0,
                        votableRoundCount: _pairedRoundCount,
                        artistName:        _versus.artist1Name,
                        artistImageUrl:    _artist1ImageUrl,
                        slideAnim:         _slideAnim,
                        accentColor:       _color1,
                        activeTrackIndex:  _activeTrackIndex,
                        playingTrackIndex: _playingTrackIndex,
                        coverLoadingRoundIndex: _coverLoadingRoundIndex,
                        votesByIndex:      _votesByIndex,
                        onVote:            (roundIndex) => _onVote(roundIndex, 0),
                        onCoverTap:        _onCoverTap,
                        onTitleTap:        _onTitleTap,
                        getCommentCtrl:    _commentCtrlAt,
                        onCommentChanged:  _onCommentChanged,
                    ),
                    _ArtistTrackPage(
                        tracks:            _tracks2,
                        artistIndex:       1,
                        votableRoundCount: _pairedRoundCount,
                        artistName:        _versus.artist2Name,
                        artistImageUrl:    _artist2ImageUrl,
                        slideAnim:         _slideAnim,
                        accentColor:       _color2,
                        activeTrackIndex:  _activeTrackIndex,
                        playingTrackIndex: _playingTrackIndex,
                        coverLoadingRoundIndex: _coverLoadingRoundIndex,
                        votesByIndex:      _votesByIndex,
                        onVote:            (roundIndex) => _onVote(roundIndex, 1),
                        onCoverTap:        _onCoverTap,
                        onTitleTap:        _onTitleTap,
                        getCommentCtrl:    _commentCtrlAt,
                        onCommentChanged:  _onCommentChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(
      BuildContext context,
      String authorLabel,
      String? avatarPath,
      String? collaboratorLabel,
      String? collaboratorAvatarPath,
    ) {
      final hasCollaboratorSide =
          collaboratorLabel != null && collaboratorLabel.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16, right: 16, bottom: 8,
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            // ── Back button ──────────────────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.maybePop(context),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.15),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.2), width: 0.8),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 16),
              ),
            ),
            const SizedBox(width: 10),

            // ── Center: author avatar + title + collaborator avatar ───────
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (avatarPath != null && avatarPath.isNotEmpty) ...[
                    Builder(
                      builder: (avatarContext) => GestureDetector(
                        onTap: () =>
                            _showProfileBubble(avatarContext, authorLabel),
                        child: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.gradientEnd, width: 1.5),
                          ),
                          child: ClipOval(
                            child: _resolveAvatarWidget(avatarPath, 30),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Text('ARTIST VS', style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppTheme.fontHeader,
                    color: Color(0xFFF07012),
                    letterSpacing: 2.5,
                  )),
                  if (hasCollaboratorSide) ...[
                    const SizedBox(width: 8),
                    Builder(
                      builder: (avatarContext) => GestureDetector(
                        onTap: () =>
                            _showProfileBubble(avatarContext, collaboratorLabel),
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.gradientStart, width: 1.3),
                          ),
                          child: ClipOval(
                            child: collaboratorAvatarPath != null &&
                                    collaboratorAvatarPath.isNotEmpty
                                ? _resolveAvatarWidget(collaboratorAvatarPath, 28)
                                : Container(
                                    color: Colors.white.withOpacity(0.08),
                                    child: const Icon(Icons.person_rounded,
                                        color: Colors.white70, size: 14),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ── Right actions ────────────────────────────────────────────
            if (_canOpenEditBackroom) ...[
              GestureDetector(
                onTap: _openEditBackroom,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.12),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.25), width: 0.8),
                  ),
                  child: Icon(Icons.edit_rounded,
                      size: 14, color: Colors.white.withOpacity(0.9)),
                ),
              ),
              const SizedBox(width: 8),
            ],
            GestureDetector(
              onTap: _showShareBottomSheet,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.25), width: 0.8),
                ),
                child: const Icon(Icons.ios_share_rounded,
                    color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

    // ── Author / collaborator helpers ─────────────────────────────────────────
    static String _playgroundAuthorLabel(ArtistVersusModel v) {
      final u = v.author?.username.trim() ?? '';
      if (u.isNotEmpty) return '@$u';
      final d = v.authorUsername?.trim() ?? '';
      if (d.isNotEmpty) return '@$d';
      return v.authorID;
    }

    static String? _playgroundAuthorAvatarPath(ArtistVersusModel v) {
      final a = v.author?.avatarPath.trim() ?? '';
      if (a.isNotEmpty) return v.author!.avatarPath.trim();
      final d = v.authorAvatar?.trim() ?? '';
      return d.isNotEmpty ? d : null;
    }

    static String? _playgroundCollaboratorLabel(ArtistVersusModel v) {
      final hydrated = v.collaborator?.username.trim() ?? '';
      if (hydrated.isNotEmpty) return '@$hydrated';
      final denormalized = v.collaboratorUsername?.trim() ?? '';
      if (denormalized.isNotEmpty) return '@$denormalized';
      return null;
    }

    static String? _playgroundCollaboratorAvatarPath(ArtistVersusModel v) {
      final hydrated = v.collaborator?.avatarPath.trim() ?? '';
      if (hydrated.isNotEmpty) return v.collaborator!.avatarPath.trim();
      final denormalized = v.collaboratorAvatar?.trim() ?? '';
      return denormalized.isNotEmpty ? denormalized : null;
    }

    // ── Side comment strip ────────────────────────────────────────────────────
    Widget _buildVersusSideCommentStrip() {
      final isArtist1Side = _selectedArtist == 0;
      final accent = isArtist1Side ? _color1 : _color2;
      final hasCollaborator =
          (_versus.collaboratorID?.trim().isNotEmpty ?? false);
      final isSoloVersus = !hasCollaborator;

      final String userLabel;
      final String? rawAvatar;
      final String? comment;

      if (isSoloVersus) {
        userLabel = '';
        rawAvatar = _playgroundAuthorAvatarPath(_versus);
        comment = _versus.authorComment?.trim();
      } else if (isArtist1Side) {
        userLabel = _playgroundAuthorLabel(_versus);
        rawAvatar = _playgroundAuthorAvatarPath(_versus);
        comment   = _versus.authorComment?.trim();
      } else {
        final cu = _versus.collaborator?.username.trim() ?? '';
        if (cu.isNotEmpty) {
          userLabel = '@$cu';
        } else {
          final du = _versus.collaboratorUsername?.trim() ?? '';
          userLabel = du.isNotEmpty
              ? '@$du'
              : (_versus.collaboratorID ?? '—');
        }
        final ca = _versus.collaborator?.avatarPath.trim() ?? '';
        if (ca.isNotEmpty) {
          rawAvatar = _versus.collaborator!.avatarPath.trim();
        } else {
          final da = _versus.collaboratorAvatar?.trim() ?? '';
          rawAvatar = da.isNotEmpty ? da : null;
        }
        comment = _versus.collaboratorComment?.trim();
      }

      final hasComment = comment != null && comment.isNotEmpty;

      if (!hasComment) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: ValueKey<int>(_selectedArtist),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thin accent bar
                Container(
                  width: 1.5,
                  height: hasComment ? 32 : 22,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: accent.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 10),
                // Small avatar
                if (rawAvatar != null && rawAvatar.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 1),
                    child: ClipOval(
                      child: _resolveAvatarWidget(rawAvatar.trim(), 20),
                    ),
                  ),
                // Comment
                if (hasComment)
                  Expanded(
                    child: Text(
                      comment!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.52),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Artist selector ───────────────────────────────────────────────────────
  Widget _buildArtistSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectArtist(0),
                  child: _ArtistCard(
                      name:        _versus.artist1Name,
                      imageUrl:    _artist1ImageUrl,
                      isSelected:  _selectedArtist == 0,
                    accentColor: _color1,
                      trackCount:  _tracks1.length,
                      voteCount:   _artist1VoteCount,
                  ),
                ),
              ),
              const SizedBox(width: 52),
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectArtist(1),
                  child: _ArtistCard(
                      name:        _versus.artist2Name,
                      imageUrl:    _artist2ImageUrl,
                      isSelected:  _selectedArtist == 1,
                    accentColor: _color2,
                      trackCount:  _tracks2.length,
                      voteCount:   _artist2VoteCount,
                  ),
                ),
              ),
            ],
          ),

          // VS badge
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) =>
                Transform.scale(scale: _pulseAnim.value, child: child),
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_color1, _color2],
                ),
                boxShadow: [BoxShadow(
                  color: _color2.withOpacity(0.5),
                  blurRadius: 18, spreadRadius: 2,
                )],
              ),
              child: const Center(
                child: Text('VS', style: TextStyle(
                  color: Colors.white, fontSize: 14,
                  fontWeight: FontWeight.w900, letterSpacing: 1.5,
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }

    // ── Avatar helpers ────────────────────────────────────────────────────────
  Widget _resolveAvatarWidget(String avatarPath, double size) {
    final p = avatarPath.trim();
    if (p.isEmpty) return _avatarFallback(size);
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return Image.network(p, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(size));
    }
    final assetPath = p.startsWith('assets/') ? p : 'assets/images/$p';
    return Image.asset(assetPath, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _avatarFallback(size));
  }

  Widget _avatarFallback(double size) => Container(
    width: size, height: size,
    color: Colors.white.withOpacity(0.2),
    child: Icon(Icons.person_rounded,
        color: Colors.white.withOpacity(0.8), size: size * 0.55),
  );
}

  // ── Artist Card ───────────────────────────────────────────────────────────────
class _ArtistCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final bool isSelected;
  final Color accentColor;
  final int trackCount;
    final int voteCount;

  const _ArtistCard({
    required this.name,
    required this.isSelected,
    required this.accentColor,
    required this.trackCount,
      required this.voteCount,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? accentColor.withOpacity(0.7)
                        : Colors.white.withOpacity(0.12),
                    width: isSelected ? 2.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(
                          color: accentColor.withOpacity(0.4),
                          blurRadius: 18, spreadRadius: 2)]
                      : [],
                ),
                child: ClipOval(
                  child: imageUrl != null && imageUrl!.isNotEmpty
                      ? Image.network(imageUrl!, fit: BoxFit.cover)
                      : Container(
                          color: Colors.white.withOpacity(0.06),
                          child: Icon(Icons.person_rounded, size: 36,
                              color: Colors.white.withOpacity(0.3)),
                        ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.7),
                    fontSize: 13, fontWeight: FontWeight.w700, height: 1.3,
                  ),
                ),
          ),
          // Live vote badge
          if (voteCount > 0) ...[
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: accentColor.withOpacity(0.22),
                border: Border.all(
                    color: accentColor.withOpacity(0.55), width: 0.9),
              ),
              child: Text(
                '$voteCount',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
            ),
          ),
        ],
        ],
    );
  }
}

// ── Artist Track Page ─────────────────────────────────────────────────────────
class _ArtistTrackPage extends StatelessWidget {
  final List<SpotifyTrack> tracks;
  final int artistIndex;
    final int votableRoundCount;
  final String artistName;
  final String? artistImageUrl;
  final Animation<double> slideAnim;
  final Color accentColor;
  final int activeTrackIndex;
  final int? playingTrackIndex;
  final int? coverLoadingRoundIndex;

    /// Full vote map — keyed by round index, value = winning artist index (0 or 1)
    final Map<int, int> votesByIndex;

    /// Called with the round index when this artist's vote button is tapped
    final void Function(int roundIndex) onVote;
  final void Function(int trackIndex, int artistIndex) onCoverTap;
  final void Function(int trackIndex, int artistIndex) onTitleTap;
    final TextEditingController Function(int roundIndex) getCommentCtrl;
    final void Function(int roundIndex, String text) onCommentChanged;

  const _ArtistTrackPage({
    required this.tracks,
    required this.artistIndex,
      required this.votableRoundCount,
    required this.artistName,
    required this.artistImageUrl,
    required this.slideAnim,
    required this.accentColor,
    required this.activeTrackIndex,
    this.playingTrackIndex,
    this.coverLoadingRoundIndex,
      required this.votesByIndex,
    required this.onVote,
    required this.onCoverTap,
    required this.onTitleTap,
      required this.getCommentCtrl,
      required this.onCommentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
      physics: const BouncingScrollPhysics(),
      itemCount: tracks.isEmpty ? 2 : tracks.length + 1,
      itemBuilder: (context, index) {
          // Header row
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: accentColor.withOpacity(0.6), width: 1.2),
                    boxShadow: [BoxShadow(
                        color: accentColor.withOpacity(0.25), blurRadius: 6)],
                  ),
                  child: ClipOval(
                    child: artistImageUrl != null && artistImageUrl!.isNotEmpty
                        ? Image.network(artistImageUrl!, fit: BoxFit.cover)
                        : Container(
                            color: accentColor.withOpacity(0.3),
                            child: const Icon(Icons.person_rounded,
                                color: Colors.white, size: 14)),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 3, height: 16,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 10),
                Text('TRACKS', style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5,
                )),
                const SizedBox(width: 8),
                Text('${tracks.length}', style: TextStyle(
                  color: accentColor.withOpacity(0.9),
                  fontSize: 11, fontWeight: FontWeight.w700,
                )),
              ],
            ),
          );
        }

        if (tracks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text('No tracks found.',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 14)),
          );
        }

        final trackIndex = index - 1;
        if (trackIndex >= tracks.length) return const SizedBox.shrink();
        final track = tracks[trackIndex];

        final isActive = trackIndex == activeTrackIndex;
        final isPast   = trackIndex < activeTrackIndex;
        final isLocked = trackIndex > activeTrackIndex;
          final isBonusIndex = trackIndex >= votableRoundCount;

          // Vote state for this round
          final votedArtist   = votesByIndex[trackIndex];
          final hasVoted      = votedArtist != null;
          final isVotedForMe  = hasVoted && votedArtist == artistIndex;
          final isVoteDisabled =
              isBonusIndex || (hasVoted && votedArtist != artistIndex);

        return AnimatedBuilder(
          animation: slideAnim,
          builder: (context, child) => Transform.translate(
            offset: Offset(0,
                24 * (1 - slideAnim.value) *
                    math.max(0, 1 - trackIndex * 0.05)),
            child: Opacity(
                opacity: slideAnim.value.clamp(0.0, 1.0), child: child),
          ),
          child: _ArtistTrackRow(
              key: ValueKey('artist-$artistIndex-track-$trackIndex'),
              track:           track,
              index:           trackIndex,
              accentColor:     accentColor,
              isLast:          trackIndex == tracks.length - 1,
              isActive:        isActive,
              isPast:          isPast,
              isLocked:        isLocked,
              showVoteButton:  isActive || isVotedForMe,
              isVoted:         isVotedForMe,
              isVoteDisabled:  isVoteDisabled,
              commentController: getCommentCtrl(trackIndex),
              onVote:          isActive && !isBonusIndex ? () => onVote(trackIndex) : null,
              onCommentChanged: (text) => onCommentChanged(trackIndex, text),
              onCoverTap:      () => onCoverTap(trackIndex, artistIndex),
              onTitleTap:      () => onTitleTap(trackIndex, artistIndex),
              isRoundPlaying:  playingTrackIndex == trackIndex,
              isCoverLoading:  coverLoadingRoundIndex == trackIndex,
          ),
        );
      },
    );
  }
}

  // ── Artist Track Row ──────────────────────────────────────────────────────────
  class _ArtistTrackRow extends StatefulWidget {
  final SpotifyTrack track;
  final int index;
  final Color accentColor;
  final bool isLast, isActive, isPast, isLocked;
  final bool showVoteButton, isVoted, isVoteDisabled;
    final TextEditingController commentController;
  final VoidCallback? onVote;
    final void Function(String) onCommentChanged;
  final VoidCallback onCoverTap;
  final VoidCallback onTitleTap;
  final bool isRoundPlaying;
  final bool isCoverLoading;

  const _ArtistTrackRow({
      super.key,
    required this.track,
    required this.index,
    required this.accentColor,
      required this.commentController,
      required this.onCommentChanged,
    required this.onCoverTap,
    required this.onTitleTap,
      this.isLast          = false,
      this.isActive        = false,
      this.isPast          = false,
      this.isLocked        = false,
      this.showVoteButton  = false,
      this.isVoted         = false,
      this.isVoteDisabled  = false,
    this.isRoundPlaying    = false,
    this.isCoverLoading    = false,
    this.onVote,
  });

    @override
    State<_ArtistTrackRow> createState() => _ArtistTrackRowState();
  }

  class _ArtistTrackRowState extends State<_ArtistTrackRow> {
  @override
  Widget build(BuildContext context) {
      final track          = widget.track;
      final index          = widget.index;
      final accentColor    = widget.accentColor;
      final isActive       = widget.isActive;
      final isPast         = widget.isPast;
      final isLocked       = widget.isLocked;
      final isVoted        = widget.isVoted;
      final isVoteDisabled = widget.isVoteDisabled;
      final onVote         = widget.onVote;
      final isPlaying      = widget.isRoundPlaying;

      final titleOpacity = isPast
          ? 0.58
          : isLocked
              ? 0.46
              : 0.68;
      final artistOpacity = titleOpacity * 0.62;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isLocked ? 0.62 : 1.0,
      child: Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(0, 11, 0, 9),
                child: Column(children: [
                  Row(children: [
                // Track number / state icon (no active-round row tint)
                SizedBox(
                  width: 32,
                  child: isPast
                      ? Icon(Icons.check_rounded,
                          size: 15, color: accentColor.withOpacity(0.5))
                      : isLocked
                          ? Icon(Icons.lock_rounded,
                              size: 14,
                              color: Colors.white.withOpacity(0.45))
                          : Text(
                              '${index + 1}'.padLeft(2, '0'),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.40),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                ),
                const SizedBox(width: 8),

                if (track.albumArtUrl != null && track.albumArtUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: PlayableAlbumCover(
                      imageUrl: track.albumArtUrl!,
                      size: 40,
                      borderRadius: 6,
                      accentColor: accentColor,
                      isPlaying: isPlaying,
                      isLoading: widget.isCoverLoading,
                      emphasized: isPlaying,
                      onTap: widget.onCoverTap,
                    ),
                  ),

                // Title tap — select round (vote / note) without playback
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onTitleTap,
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.symmetric(
                        horizontal: isActive ? 10 : 4,
                        vertical: isActive ? 7 : 4,
                      ),
                      decoration: isActive
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  accentColor.withOpacity(0.24),
                                  Colors.white.withOpacity(0.08),
                                ],
                              ),
                              border: Border.all(
                                color: accentColor.withOpacity(0.50),
                                width: 0.9,
                              ),
                            )
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive
                                  ? Colors.white
                                  : Colors.white.withOpacity(titleOpacity),
                              fontSize: isActive ? 15 : 14,
                              fontWeight:
                                  isActive ? FontWeight.w800 : FontWeight.w500,
                              letterSpacing: isActive ? 0 : -0.1,
                              height: 1.15,
                              shadows: isActive
                                  ? [
                                      Shadow(
                                        color: accentColor.withOpacity(0.40),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          if (track.artistName.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              track.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive
                                    ? accentColor.withOpacity(0.95)
                                    : Colors.white.withOpacity(artistOpacity),
                                fontSize: isActive ? 12.5 : 12,
                                fontWeight:
                                    isActive ? FontWeight.w600 : FontWeight.w400,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                    // ── Vote button ──────────────────────────────────────────
                    if (widget.showVoteButton) ...[
                  GestureDetector(
                      onTap: isVoteDisabled ? null : onVote,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: isVoted
                            ? _kSpotifyGreen.withOpacity(0.5)
                            : isVoteDisabled
                                    ? Colors.white.withOpacity(0.06)
                                : _kSpotifyGreen.withOpacity(0.25),
                        border: Border.all(
                          color: isVoted
                              ? _kSpotifyGreen
                              : isVoteDisabled
                                      ? Colors.white.withOpacity(0.1)
                                  : _kSpotifyGreen.withOpacity(0.6),
                          width: 1,
                        ),
                      ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                        Icon(
                          isVoted
                              ? Icons.check_rounded
                              : Icons.how_to_vote_rounded,
                          size: 14,
                          color: isVoteDisabled
                                    ? Colors.white.withOpacity(0.2)
                                    : isVoted
                                        ? Colors.white
                                        : _kSpotifyGreen,
                        ),
                        const SizedBox(width: 4),
                              Text(
                                isVoted ? 'Voted' : 'Vote',
                          style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: isVoteDisabled
                                      ? Colors.white.withOpacity(0.2)
                                      : isVoted
                                          ? Colors.white
                                          : _kSpotifyGreen,
                                ),
                              ),
                            ],
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],

                    if (isVoted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withOpacity(0.85),
                          _kSpotifyGreen.withOpacity(0.55),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.35),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(0.35),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Text(
                      'NOTE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ),
              ]),

                  // ── Note / comment field (highlighted when voted) ───────────
                  if (isVoted) ...[
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accentColor.withOpacity(0.22),
                            _kSpotifyGreen.withOpacity(0.14),
                          ],
                        ),
                        border: Border.all(
                          color: accentColor.withOpacity(0.48),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withOpacity(0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: widget.commentController,
                        onChanged: widget.onCommentChanged,
                        minLines: 1,
                        maxLines: 3,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Disclaimer...',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.42),
                            fontSize: 12,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ]),
            ),
            if (!widget.isLast)
              Divider(
                height: 0, indent: 44,
                color: Colors.white.withOpacity(0.06)),
        ]),
    );
  }
}

  // ── Share bottom sheet ─────────────────────────────────────────────────────
  class _ShareSheet extends StatelessWidget {
    final Future<void> Function(String platform) onShare;
    final VoidCallback onCopyLink;
    final VoidCallback onSaveToGallery;

    const _ShareSheet({
      required this.onShare,
      required this.onCopyLink,
      required this.onSaveToGallery,
    });

    @override
    Widget build(BuildContext context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Share result',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _ShareButton(
                    label: 'Instagram',
                    icon: Icons.camera_alt_outlined,
                    color: const Color(0xFFE1306C),
                    onTap: () => onShare('instagram'),
                  ),
                  const SizedBox(width: 12),
                  _ShareButton(
                    label: 'WhatsApp',
                    icon: Icons.chat_rounded,
                    color: const Color(0xFF25D366),
                    onTap: () => onShare('whatsapp'),
                  ),
                  const SizedBox(width: 12),
                  _ShareButton(
                    label: 'Other',
                    icon: Icons.share_rounded,
                    color: Colors.white24,
                    onTap: () => onShare('other'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onSaveToGallery,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withOpacity(0.06),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.12),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white.withOpacity(0.7),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Save to gallery',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onCopyLink,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withOpacity(0.06),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.12),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.link_rounded,
                        color: Colors.white.withOpacity(0.7),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Copy link',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  class _ShareButton extends StatelessWidget {
    final String label;
    final IconData icon;
    final Color color;
    final VoidCallback onTap;

    const _ShareButton({
      required this.label,
      required this.icon,
      required this.color,
      required this.onTap,
    });

    @override
    Widget build(BuildContext context) {
      return GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
                border: Border.all(color: color.withOpacity(0.4), width: 0.8),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
  }

// ── Swipe dot ─────────────────────────────────────────────────────────────────
class _SwipeDot extends StatelessWidget {
  final bool isActive;
  final Color color;

  const _SwipeDot({required this.isActive, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: isActive ? 20 : 6,
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: isActive ? color : Colors.white.withOpacity(0.3),
      ),
    );
  }
}