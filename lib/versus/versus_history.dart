import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:welcometothedisco/models/artist_versus_model.dart';
import 'package:welcometothedisco/models/polls_model.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/theme/app_theme.dart';
import 'package:welcometothedisco/versus/artistplayground.dart';
import 'package:welcometothedisco/versus/playground.dart';
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
  bool _openingPlayground = false;
  bool _shareCardOffstage = true;
  final GlobalKey _shareCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchImages();
  }

  Future<void> _fetchImages() async {
    final poll = widget.poll;
    final id1  = poll.entity1Id;
    final id2  = poll.entity2Id;

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

  Future<String?> _fetchOne(String id, bool isAlbum) async {
    if (isAlbum) return (await _api.getAlbumDetails(id))?.imageUrl;
    return (await _api.getArtistDetails(id))?.imageUrl;
  }

  // ── Open playground ──────────────────────────────────────────────────────
  Future<void> _openPlayground() async {
    final versusId = widget.poll.versusId;
    if (versusId.isEmpty) return;
    setState(() => _openingPlayground = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('versus')
          .doc(versusId)
          .get();
      if (!mounted) return;
      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Versus no longer available')),
        );
        return;
      }
      final data = doc.data()!;
      if (!mounted) return;
      if (widget.poll.isAlbumPoll) {
        final versus = VersusModel.fromFirestore(data, doc.id);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VersusPlayground(versus: versus, versusId: versusId),
        ));
      } else {
        final versus = ArtistVersusModel.fromFirestore(data, doc.id);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ArtistVersusPlayground(versus: versus, versusId: versusId),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open versus')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingPlayground = false);
    }
  }

  // ── Share / capture ──────────────────────────────────────────────────────
  Future<Uint8List?> _captureCard() async {
    setState(() => _shareCardOffstage = false);
    await WidgetsBinding.instance.endOfFrame;
    Uint8List? result;
    try {
      final boundary = _shareCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary != null) {
        final image  = await boundary.toImage(pixelRatio: 3.0);
        final bytes  = await image.toByteData(format: ui.ImageByteFormat.png);
        result = bytes?.buffer.asUint8List();
      }
    } finally {
      if (mounted) setState(() => _shareCardOffstage = true);
    }
    return result;
  }

  void _showShareSheet() {
    final poll = widget.poll;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Share poll result',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _SheetOption(
                icon: Icons.photo_library_outlined,
                label: 'Save to gallery',
                onTap: () async {
                  Navigator.pop(ctx);
                  final bytes = await _captureCard();
                  if (bytes == null || !mounted) return;
                  try {
                    await Gal.putImageBytes(bytes, name: 'wttd_poll_result');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Saved to gallery')),
                      );
                    }
                  } on GalException catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.type.message)),
                      );
                    }
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not save to gallery')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
              _SheetOption(
                icon: Icons.ios_share_rounded,
                label: 'Share image',
                onTap: () async {
                  Navigator.pop(ctx);
                  final bytes = await _captureCard();
                  if (bytes == null) return;
                  final tempDir = await getTemporaryDirectory();
                  final file = await File(
                    '${tempDir.path}/wttd_poll.png',
                  ).writeAsBytes(bytes);
                  await Share.shareXFiles(
                    [XFile(file.path)],
                    text: '${poll.entity1Name} vs ${poll.entity2Name}'
                        ' — my poll on welcometothedisco',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final poll       = widget.poll;
    final sorted     = poll.roundsSorted;
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

    VersusShareCard buildCard() => VersusShareCard(
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
      artist1ImageUrl:  _img1,
      artist2ImageUrl:  _img2,
      isAlbumPoll:      poll.isAlbumPoll,
    );

    return SizedBox(
      height: cardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Main card display ──────────────────────────────────────────
          Positioned.fill(
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                child: buildCard(),
              ),
            ),
          ),

          // ── Off-screen capture target (same as playground share trick) ─
          Positioned(
            left: -8000,
            top: 0,
            width: 360,
            child: Offstage(
              offstage: _shareCardOffstage,
              child: RepaintBoundary(
                key: _shareCardKey,
                child: SizedBox(width: 360, child: buildCard()),
              ),
            ),
          ),

          // ── Action pills — bottom-right corner ─────────────────────────
          Positioned(
            right: 12,
            bottom: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionPill(
                  onTap: _openingPlayground ? null : _openPlayground,
                  label: 'Open VS',
                  child: _openingPlayground
                      ? const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_circle_outline_rounded,
                          size: 14, color: Colors.white),
                ),
                const SizedBox(width: 8),
                _ActionPill(
                  onTap: _showShareSheet,
                  label: 'Share',
                  child: const Icon(Icons.ios_share_rounded,
                      size: 14, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action pill button ─────────────────────────────────────────────────────────
class _ActionPill extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final String label;

  const _ActionPill({
    required this.onTap,
    required this.child,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: Colors.black.withOpacity(onTap != null ? 0.52 : 0.28),
              border: Border.all(
                color: Colors.white.withOpacity(onTap != null ? 0.22 : 0.10),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                child,
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(onTap != null ? 0.90 : 0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Share sheet option row ─────────────────────────────────────────────────────
class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.70), size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.80),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
