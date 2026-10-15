import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/Ranking/entity_history.dart';
import 'package:welcometothedisco/models/pair_model.dart';
import 'package:welcometothedisco/models/ranking_model.dart';
import 'package:welcometothedisco/posts/profile_posts_section.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kBlue = AppTheme.gradientStart;
const _kPink = AppTheme.gradientEnd;

class EntityProfileScreen extends StatefulWidget {
  final String entityId;
  final String initialTitle;
  final String? initialImageUrl;
  final bool isArtist;

  const EntityProfileScreen({
    super.key,
    required this.entityId,
    required this.initialTitle,
    required this.initialImageUrl,
    required this.isArtist,
  });

  @override
  State<EntityProfileScreen> createState() => _EntityProfileScreenState();
}

class _EntityProfileScreenState extends State<EntityProfileScreen> {
  RankingModel? _ranking;
  List<PairModel> _pairs = [];
  bool _loading = true;
  bool _postsOnlyProfile = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _postsOnlyProfile = false;
    });

    final results = await Future.wait([
      FirebaseService.getRankingProfile(widget.entityId),
      FirebaseService.getPairsForEntity(widget.entityId),
    ]);

    if (!mounted) return;

    final fetched = results[0] as RankingModel?;
    final pairs = results[1] as List<PairModel>;

    if (fetched == null && pairs.isEmpty) {
      if (widget.isArtist) {
        final posts = await FirebaseService.getPostsByArtistList(widget.entityId);
        if (!mounted) return;
        if (posts.isNotEmpty) {
          setState(() {
            _ranking = null;
            _pairs = [];
            _loading = false;
            _postsOnlyProfile = true;
          });
          return;
        }
      }
      setState(() {
        _ranking = null;
        _pairs = [];
        _loading = false;
      });
      return;
    }

    pairs.sort((a, b) {
      final ta = a.lastVotedAt?.millisecondsSinceEpoch ?? 0;
      final tb = b.lastVotedAt?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });

    setState(() {
      _ranking = fetched;
      _pairs = pairs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kBlue, _kPink],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.14),
                border: Border.all(color: Colors.white.withOpacity(0.22), width: 0.9),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'RANKING PROFILE',
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
      );
    }

    if (_ranking == null && _postsOnlyProfile) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 22),
        children: [
          _ProfileHeroCard(
            title: widget.initialTitle,
            imageUrl: widget.initialImageUrl,
            isArtist: widget.isArtist,
            points: null,
            provisional: true,
            rank: null,
          ),
          const SizedBox(height: 14),
          ProfilePostsSection.forArtist(artistId: widget.entityId),
        ],
      );
    }

    final ranking = _ranking;
    final isArtist = ranking?.isArtist ?? widget.isArtist;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 22),
      children: [
        _ProfileHeroCard(
          title: (ranking?.entityName ?? '').isNotEmpty
              ? ranking!.entityName
              : widget.initialTitle,
          imageUrl: (ranking?.entityImage ?? '').isNotEmpty
              ? ranking!.entityImage
              : widget.initialImageUrl,
          isArtist: isArtist,
          points: ranking?.points,
          provisional: ranking?.provisional ?? true,
          rank: ranking?.rank,
        ),
        const SizedBox(height: 14),
        _CollapsiblePairsWidget(
          pairs: _pairs,
          entityId: widget.entityId,
          isArtistType: isArtist,
          onPairTap: (pair) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EntityOpponentHistoryScreen(
                entityId: widget.entityId,
                entityName: ranking?.entityName ?? widget.initialTitle,
                entityImage: ranking?.entityImage ?? widget.initialImageUrl ?? '',
                entityType: isArtist ? 'artist' : 'album',
                pair: pair,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (isArtist)
          ProfilePostsSection.forArtist(
            artistId: ranking?.entityId ?? widget.entityId,
          ),
      ],
    );
  }
}

// ── Profile hero card ─────────────────────────────────────────────────────────
class _ProfileHeroCard extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final bool isArtist;
  final double? points;
  final bool provisional;
  final int? rank;

  const _ProfileHeroCard({
    required this.title,
    required this.imageUrl,
    required this.isArtist,
    required this.points,
    required this.provisional,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = isArtist ? BorderRadius.circular(999) : BorderRadius.circular(16);
    final pointsLabel = points != null ? points!.round().toString() : '—';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.9),
          ),
          child: Column(
            children: [
              // Image with rank badge overlaid in top-right corner.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
                    ),
                    child: ClipRRect(
                      borderRadius: borderRadius,
                      child: (imageUrl ?? '').trim().isNotEmpty
                          ? Image.network(imageUrl!, fit: BoxFit.cover)
                          : Container(
                              color: Colors.white.withOpacity(0.12),
                              child: Icon(
                                isArtist ? Icons.person_rounded : Icons.album_rounded,
                                color: Colors.white.withOpacity(0.75),
                                size: 44,
                              ),
                            ),
                    ),
                  ),
                  if (rank != null)
                    Positioned(
                      top: -14,
                      right: -14,
                      child: _RankBadge(rank: rank!),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pointsLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Rank badge (starburst seal) ───────────────────────────────────────────────
class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: CustomPaint(
        painter: _StarburstPainter(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '#$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
              const Text(
                'RANKED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 6.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StarburstPainter extends CustomPainter {
  static const _color = Color(0xFF1B4FE8);
  static const _numPoints = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _color;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = size.width / 2;
    final innerR = outerR * 0.82;

    final path = Path();
    for (int i = 0; i < _numPoints * 2; i++) {
      final angle = (i * pi / _numPoints) - pi / 2;
      final r = i.isEven ? outerR : innerR;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StarburstPainter old) => false;
}

// ── Collapsible pairs widget ──────────────────────────────────────────────────
class _CollapsiblePairsWidget extends StatefulWidget {
  final List<PairModel> pairs;
  final String entityId;
  final bool isArtistType;
  final void Function(PairModel) onPairTap;

  const _CollapsiblePairsWidget({
    required this.pairs,
    required this.entityId,
    required this.isArtistType,
    required this.onPairTap,
  });

  @override
  State<_CollapsiblePairsWidget> createState() => _CollapsiblePairsWidgetState();
}

class _CollapsiblePairsWidgetState extends State<_CollapsiblePairsWidget>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  static const double _avatarSize = 36.0;
  static const double _avatarOverlap = 10.0;
  static const int _previewCount = 7;

  Widget _avatar(PairModel pair) {
    final opp = pair.opponentOf(widget.entityId);
    final img = opp.entityImage.trim();
    final br = widget.isArtistType
        ? BorderRadius.circular(999)
        : BorderRadius.circular(7);
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(
        borderRadius: br,
        border: Border.all(color: Colors.white.withOpacity(0.30), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: img.isNotEmpty
            ? Image.network(img, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _avatarFallback())
            : _avatarFallback(),
      ),
    );
  }

  Widget _avatarFallback() => Container(
        color: _kBlue.withOpacity(0.35),
        child: Icon(
          widget.isArtistType ? Icons.person_rounded : Icons.album_rounded,
          color: Colors.white.withOpacity(0.65),
          size: _avatarSize * 0.5,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pairs = widget.pairs;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: pairs.isEmpty ? null : _toggle,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Row(
                    children: [
                      if (pairs.isEmpty)
                        Text(
                          'No matchups yet.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      else ...[
                        SizedBox(
                          height: _avatarSize,
                          width: _avatarSize +
                              (_avatarSize - _avatarOverlap) *
                                  (pairs.take(_previewCount).length - 1)
                                      .clamp(0, _previewCount - 1),
                          child: Stack(
                            children: pairs
                                .take(_previewCount)
                                .toList()
                                .asMap()
                                .entries
                                .map((e) => Positioned(
                                      left: e.key * (_avatarSize - _avatarOverlap),
                                      child: _avatar(e.value),
                                    ))
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${pairs.length} matchup${pairs.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (pairs.isNotEmpty)
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.expand_more_rounded,
                            color: Colors.white.withOpacity(0.55),
                            size: 22,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizeTransition(
                sizeFactor: _anim,
                axisAlignment: -1,
                child: Column(
                  children: [
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withOpacity(0.12),
                    ),
                    ...pairs.map((pair) => _PairListRow(
                          pair: pair,
                          entityId: widget.entityId,
                          isArtistType: widget.isArtistType,
                          isLast: pair == pairs.last,
                          onTap: () => widget.onPairTap(pair),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PairListRow extends StatelessWidget {
  final PairModel pair;
  final String entityId;
  final bool isArtistType;
  final bool isLast;
  final VoidCallback onTap;

  const _PairListRow({
    required this.pair,
    required this.entityId,
    required this.isArtistType,
    required this.isLast,
    required this.onTap,
  });

  Widget _resultBadge() {
    final my = pair.myVotes(entityId);
    final their = pair.theirVotes(entityId);
    final won = my > their;
    final lost = their > my;
    final bgColor = won
        ? Colors.green.withOpacity(0.22)
        : lost
            ? Colors.red.withOpacity(0.22)
            : Colors.white.withOpacity(0.14);
    final borderColor = won
        ? Colors.greenAccent.withOpacity(0.75)
        : lost
            ? Colors.redAccent.withOpacity(0.78)
            : Colors.white.withOpacity(0.30);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: borderColor, width: 0.9),
      ),
      child: Text(
        won ? 'Won' : lost ? 'Lost' : 'Draw',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opp = pair.opponentOf(entityId);
    final img = opp.entityImage.trim();
    final br = isArtistType ? BorderRadius.circular(999) : BorderRadius.circular(8);
    final myVotes = pair.myVotes(entityId);
    final theirVotes = pair.theirVotes(entityId);

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: br,
                    border: Border.all(color: Colors.white.withOpacity(0.28), width: 0.9),
                  ),
                  child: ClipRRect(
                    borderRadius: br,
                    child: img.isNotEmpty
                        ? Image.network(img, fit: BoxFit.cover)
                        : Container(
                            color: Colors.white.withOpacity(0.12),
                            child: Icon(
                              isArtistType ? Icons.person_rounded : Icons.album_rounded,
                              color: Colors.white.withOpacity(0.65),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opp.entityName.isEmpty ? 'Unknown' : opp.entityName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _resultBadge(),
                          const SizedBox(width: 8),
                          Text(
                            '${pair.versusCount}v  •  $myVotes–$theirVotes',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.white.withOpacity(0.35),
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            indent: 14,
            endIndent: 14,
            color: Colors.white.withOpacity(0.09),
          ),
      ],
    );
  }
}
