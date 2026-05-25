import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/Ranking/entity_history.dart';
import 'package:welcometothedisco/models/ranking_model.dart';
import 'package:welcometothedisco/posts/profile_posts_section.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
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
  final SpotifyApi _spotifyApi = SpotifyApi();
  RankingModel? _ranking;
  bool _loading = true;
  bool _notFound = false;
  bool _postsOnlyProfile = false;

  @override
  void initState() {
    super.initState();
    _loadRanking();
  }

  Future<void> _loadRanking() async {
    setState(() {
      _loading = true;
      _notFound = false;
      _postsOnlyProfile = false;
    });

    final fetched = await FirebaseService.getRankingProfile(widget.entityId);
    if (!mounted) return;

    if (fetched == null) {
      if (widget.isArtist) {
        final posts = await FirebaseService.getPostsByArtistList(widget.entityId);
        if (!mounted) return;
        if (posts.isNotEmpty) {
          setState(() {
            _ranking = null;
            _loading = false;
            _notFound = false;
            _postsOnlyProfile = true;
          });
          return;
        }
      }

      setState(() {
        _loading = false;
        _notFound = true;
        _postsOnlyProfile = false;
      });
      return;
    }

    final resolved = await FirebaseService.resolveRankingOpponentImages(
      fetched,
      _spotifyApi,
    );
    if (!mounted) return;

    setState(() {
      _ranking = resolved;
      _loading = false;
      _notFound = false;
      _postsOnlyProfile = false;
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
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2.2,
        ),
      );
    }

    if (_notFound) {
      return Center(
        child: Text(
          'No ranking profile found for this entity.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
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
            totalVotes: 0,
            versusCount: 0,
            record: '0W - 0L - 0D',
            winRate: 0,
          ),
          const SizedBox(height: 14),
          ProfilePostsSection.forArtist(artistId: widget.entityId),
        ],
      );
    }

    if (_ranking == null) {
      return const SizedBox.shrink();
    }

    final ranking = _ranking!;
    final opponents = ranking.opponentsByRecent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 22),
      children: [
        _ProfileHeroCard(
          title: ranking.entityName.isEmpty ? widget.initialTitle : ranking.entityName,
          imageUrl: ranking.entityImage.isEmpty
              ? widget.initialImageUrl
              : ranking.entityImage,
          isArtist: ranking.entityType == 'artist',
          totalVotes: ranking.totalVotes,
          versusCount: ranking.versusCount,
          record: ranking.recordString,
          winRate: ranking.winRate,
        ),
        const SizedBox(height: 14),
        _CollapsibleOpponentsWidget(
          opponents: opponents,
          isArtistType: ranking.entityType == 'artist',
          onOpponentTap: (opp) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EntityOpponentHistoryScreen(
                ranking: ranking,
                opponent: opp,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (ranking.isArtist)
          ProfilePostsSection.forArtist(artistId: ranking.entityId),
      ],
    );
  }

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.13),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.9),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final bool isArtist;
  final int totalVotes;
  final int versusCount;
  final String record;
  final double winRate;

  const _ProfileHeroCard({
    required this.title,
    required this.imageUrl,
    required this.isArtist,
    required this.totalVotes,
    required this.versusCount,
    required this.record,
    required this.winRate,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = isArtist ? BorderRadius.circular(999) : BorderRadius.circular(16);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.9),
          ),
          child: Column(
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
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _statChip('Votes', '$totalVotes'),
                  _statChip('Versus', '$versusCount'),
                  _statChip('Record', record),
                  _statChip('Win Rate', '${(winRate * 100).toStringAsFixed(1)}%'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.16), width: 0.8),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Collapsible opponents widget ──────────────────────────────────────────────
class _CollapsibleOpponentsWidget extends StatefulWidget {
  final List<OpponentModel> opponents;
  final bool isArtistType;
  final void Function(OpponentModel) onOpponentTap;

  const _CollapsibleOpponentsWidget({
    required this.opponents,
    required this.isArtistType,
    required this.onOpponentTap,
  });

  @override
  State<_CollapsibleOpponentsWidget> createState() =>
      _CollapsibleOpponentsWidgetState();
}

class _CollapsibleOpponentsWidgetState
    extends State<_CollapsibleOpponentsWidget>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  static const double _avatarSize = 36.0;
  static const double _avatarOverlap = 10.0;
  static const int _previewCount = 7;

  Widget _avatar(OpponentModel opp) {
    final img = opp.opponentImage.trim();
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
    final opponents = widget.opponents;

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
              // ── Header / collapsed strip ───────────────────────────────
              GestureDetector(
                onTap: opponents.isEmpty ? null : _toggle,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Row(
                    children: [
                      // Overlapping avatars
                      if (opponents.isEmpty)
                        Text(
                          'No opponents yet.',
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
                                  (opponents
                                          .take(_previewCount)
                                          .length -
                                      1).clamp(0, _previewCount - 1),
                          child: Stack(
                            children: opponents
                                .take(_previewCount)
                                .toList()
                                .asMap()
                                .entries
                                .map((e) => Positioned(
                                      left: e.key *
                                          (_avatarSize - _avatarOverlap),
                                      child: _avatar(e.value),
                                    ))
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${opponents.length} opponent${opponents.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (opponents.isNotEmpty)
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

              // ── Expanded list ──────────────────────────────────────────
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
                    ...opponents.map((opp) {
                      final isLast = opp == opponents.last;
                      return _OpponentListRow(
                        opponent: opp,
                        isArtistType: widget.isArtistType,
                        isLast: isLast,
                        onTap: () => widget.onOpponentTap(opp),
                      );
                    }),
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

class _OpponentListRow extends StatelessWidget {
  final OpponentModel opponent;
  final bool isArtistType;
  final bool isLast;
  final VoidCallback onTap;

  const _OpponentListRow({
    required this.opponent,
    required this.isArtistType,
    required this.isLast,
    required this.onTap,
  });

  Widget _resultBadge() {
    final won = opponent.winsAgainst > opponent.lossesTo;
    final lost = opponent.lossesTo > opponent.winsAgainst;
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
    final img = opponent.opponentImage.trim();
    final br = isArtistType
        ? BorderRadius.circular(999)
        : BorderRadius.circular(8);

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
                    border: Border.all(
                        color: Colors.white.withOpacity(0.28), width: 0.9),
                  ),
                  child: ClipRRect(
                    borderRadius: br,
                    child: img.isNotEmpty
                        ? Image.network(img, fit: BoxFit.cover)
                        : Container(
                            color: Colors.white.withOpacity(0.12),
                            child: Icon(
                              isArtistType
                                  ? Icons.person_rounded
                                  : Icons.album_rounded,
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
                        opponent.opponentName.isEmpty
                            ? 'Unknown opponent'
                            : opponent.opponentName,
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
                            '${opponent.versusCount}v  •  ${opponent.totalentityVotes}-${opponent.totalopponentVotes}',
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
