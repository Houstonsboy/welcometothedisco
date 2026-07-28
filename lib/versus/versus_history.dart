import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/polls_model.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/theme/app_theme.dart';
import 'package:welcometothedisco/widgets/versus_share_card.dart';

// Deterministic accent colour from entity ID — avoids any API call.
const _kPalette = [
  Color(0xFFE63946), Color(0xFF4CC9F0), Color(0xFF2A9D8F),
  Color(0xFFE9C46A), Color(0xFFF4A261), Color(0xFF9B5DE5),
  Color(0xFF06D6A0), Color(0xFFFF6B6B), Color(0xFFF07012),
  Color(0xFF48CAE4),
];

Color _accentFor(String seed) {
  if (seed.isEmpty) return _kPalette[0];
  final hash = seed.codeUnits.fold(0, (a, b) => a + b);
  return _kPalette[hash % _kPalette.length];
}

// Shared across all feed items for the session — same entity ID is never
// fetched more than once even as pagination reveals new cards.
final _imgCache = <String, String?>{};

// ── Screen ─────────────────────────────────────────────────────────────────────
class VersusHistoryScreen extends StatefulWidget {
  /// Pass a [uid] to view another user's poll history;
  /// omit to default to the currently signed-in user.
  final String? uid;
  const VersusHistoryScreen({super.key, this.uid});

  @override
  State<VersusHistoryScreen> createState() => _VersusHistoryScreenState();
}

class _VersusHistoryScreenState extends State<VersusHistoryScreen> {
  static const int _firstPage      = 5;
  static const int _nextPage       = 4;
  static const int _prefetchBuffer = 3;

  List<PollModel> _allPolls  = [];
  int  _visibleCount = _firstPage;
  bool _loading      = true;

  String get _uid =>
      widget.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  List<PollModel> get _visible =>
      _allPolls.take(_visibleCount).toList();
  bool get _hasMore => _visibleCount < _allPolls.length;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // Single Firestore read — no orderBy, so no composite index needed.
  // Sort newest-first client-side after the fetch.
  Future<void> _loadAll() async {
    if (_uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('polls')
          .where('voter_id', isEqualTo: _uid)
          .get();
      final polls = snap.docs
          .map((d) => PollModel.fromFirestore(d.data(), d.id))
          .toList()
        ..sort((a, b) =>
            (b.timestamp?.millisecondsSinceEpoch ?? 0)
                .compareTo(a.timestamp?.millisecondsSinceEpoch ?? 0));
      if (mounted) {
        setState(() {
          _allPolls = polls;
          _loading  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMore() {
    setState(() {
      _visibleCount =
          (_visibleCount + _nextPage).clamp(0, _allPolls.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Background matches VersusShareCard's own background colour.
    return Container(
      color: const Color(0xFF0A0A0A),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _HistoryHeader(uid: _uid),
              Expanded(child: _buildFeed()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeed() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white38,
          strokeWidth: 2,
        ),
      );
    }
    final visible = _visible;
    if (visible.isEmpty) return const _EmptyState();

    final itemCount = visible.length + (_hasMore ? 1 : 0);

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: itemCount,
      // Thin seam between cards — background is already near-black.
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        // When 3rd-from-last card is built, reveal the next page.
        if (_hasMore && index == visible.length - _prefetchBuffer) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _showMore());
        }

        // Footer spinner while list expands.
        if (index == visible.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: CircularProgressIndicator(
                color: Colors.white24,
                strokeWidth: 1.5,
              ),
            ),
          );
        }

        return _FeedItem(poll: visible[index]);
      },
    );
  }
}

// ── Screen header ──────────────────────────────────────────────────────────────
class _HistoryHeader extends StatelessWidget {
  final String uid;
  const _HistoryHeader({required this.uid});

  @override
  Widget build(BuildContext context) {
    final isOwn =
        uid == (FirebaseAuth.instance.currentUser?.uid ?? '__none__');
    return Container(
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.10),
                border: Border.all(
                    color: Colors.white.withOpacity(0.18), width: 0.9),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOwn ? 'MY POLLS' : 'POLLS',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: AppTheme.fontHeader,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                ),
              ),
              Text(
                isOwn ? 'Your voting history' : 'Voting history',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.40),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Feed item ──────────────────────────────────────────────────────────────────
// Card is rendered at exactly 3/4 of the screen height so the top of the next
// card is always visible, giving an Instagram-style scroll hint.
class _FeedItem extends StatefulWidget {
  final PollModel poll;
  const _FeedItem({required this.poll});

  @override
  State<_FeedItem> createState() => _FeedItemState();
}

class _FeedItemState extends State<_FeedItem> {
  static final SpotifyApi _api = SpotifyApi();

  String? _img1;
  String? _img2;

  @override
  void initState() {
    super.initState();
    _fetchImages();
  }

  Future<void> _fetchImages() async {
    final poll = widget.poll;
    final id1  = poll.entity1Id;
    final id2  = poll.entity2Id;

    // Pull from in-memory cache first; only fire Spotify requests for misses.
    String? img1 = _imgCache.containsKey(id1) ? _imgCache[id1] : null;
    String? img2 = _imgCache.containsKey(id2) ? _imgCache[id2] : null;

    final futures = <Future<void>>[];

    if (!_imgCache.containsKey(id1) && id1.isNotEmpty) {
      futures.add(_fetchOne(id1, poll.isAlbumPoll).then((url) {
        _imgCache[id1] = url;
        img1 = url;
      }));
    }
    if (!_imgCache.containsKey(id2) && id2.isNotEmpty) {
      futures.add(_fetchOne(id2, poll.isAlbumPoll).then((url) {
        _imgCache[id2] = url;
        img2 = url;
      }));
    }

    if (futures.isNotEmpty) await Future.wait(futures);

    if (mounted) setState(() { _img1 = img1; _img2 = img2; });
  }

  // Album polls → getAlbumDetails; artist / collab polls → getArtistDetails.
  Future<String?> _fetchOne(String id, bool isAlbum) async {
    if (isAlbum) return (await _api.getAlbumDetails(id))?.imageUrl;
    return (await _api.getArtistDetails(id))?.imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    final poll      = widget.poll;
    final sorted    = poll.roundsSorted;
    final cardHeight = MediaQuery.sizeOf(context).height * 0.75;

    final rawDetails = <int, Map<String, dynamic>>{
      for (final e in poll.trackDetails.entries) e.key: e.value.toMap(),
    };

    final names1 = sorted.map((r) => r.entity1TrackName).toList();
    final names2 = sorted.map((r) => r.entity2TrackName).toList();
    final ids1   = sorted.map((r) => r.entity1TrackId).toList();
    final ids2   = sorted.map((r) => r.entity2TrackId).toList();

    final seed2  = poll.entity2Id.isNotEmpty ? poll.entity2Id : poll.entity2Name;
    final color1 = _accentFor(poll.entity1Id);
    final color2 = _accentFor(seed2);

    // Constrain to 3/4 of screen height and clip the card's bottom overflow.
    // FittedBox.fitWidth scales the fixed-360px card to fill the screen width.
    // Alignment.topCenter keeps artist images + vote totals always visible.
    return SizedBox(
      height: cardHeight,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          child: VersusShareCard(
            artist1Name:      poll.entity1Name.isNotEmpty ? poll.entity1Name : '—',
            artist2Name:      poll.entity2Name.isNotEmpty ? poll.entity2Name : '—',
            artist1Votes:     poll.entity1Vote,
            artist2Votes:     poll.entity2Vote,
            color1:           color1,
            color2:           color2,
            voterName:        poll.voterName.isNotEmpty ? poll.voterName : 'anon',
            trackDetails:     rawDetails,
            pairedRoundCount: sorted.length,
            roundTrackNames1: names1,
            roundTrackNames2: names2,
            roundTrackIds1:   ids1,
            roundTrackIds2:   ids2,
            // Images render inside _ArtistSide: circle for artists, square for albums.
            artist1ImageUrl:  _img1,
            artist2ImageUrl:  _img2,
            isAlbumPoll:      poll.isAlbumPoll,
          ),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.how_to_vote_outlined,
              size: 40, color: Colors.white.withOpacity(0.18)),
          const SizedBox(height: 12),
          Text(
            'No polls yet',
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Vote in a versus to see your history here.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.28),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
