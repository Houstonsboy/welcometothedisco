import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/Ranking/entity_history.dart';
import 'package:welcometothedisco/models/ranking_model.dart';
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

  @override
  void initState() {
    super.initState();
    _loadRanking();
  }

  Future<void> _loadRanking() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });

    final fetched = await FirebaseService.getRankingProfile(widget.entityId);
    if (!mounted) return;

    if (fetched == null) {
      setState(() {
        _loading = false;
        _notFound = true;
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

    if (_notFound || _ranking == null) {
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
        Text(
          'Opponents (${opponents.length})',
          style: TextStyle(
            color: Colors.white.withOpacity(0.95),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (opponents.isEmpty)
          _glassCard(
            child: Text(
              'No opponent data yet.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          ...opponents.map(
            (opp) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OpponentCard(
                opponent: opp,
                sameEntityTypeAsSource: ranking.entityType == 'artist',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EntityOpponentHistoryScreen(
                        ranking: ranking,
                        opponent: opp,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
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

class _OpponentCard extends StatelessWidget {
  final OpponentModel opponent;
  final bool sameEntityTypeAsSource;
  final VoidCallback onTap;

  const _OpponentCard({
    required this.opponent,
    required this.sameEntityTypeAsSource,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = sameEntityTypeAsSource
        ? BorderRadius.circular(999)
        : BorderRadius.circular(12);
    final image = opponent.opponentImage.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.9),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(color: Colors.white.withOpacity(0.34), width: 0.9),
                    ),
                    child: ClipRRect(
                      borderRadius: borderRadius,
                      child: image.isNotEmpty
                          ? Image.network(image, fit: BoxFit.cover)
                          : Container(
                              color: Colors.white.withOpacity(0.12),
                              child: Icon(
                                sameEntityTypeAsSource
                                    ? Icons.person_rounded
                                    : Icons.album_rounded,
                                color: Colors.white.withOpacity(0.72),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _resultBadge(),
                        const SizedBox(height: 4),
                        Text(
                          'Versus ${opponent.versusCount}  •  Votes ${opponent.totalentityVotes}-${opponent.totalopponentVotes}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.68),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Colors.white.withOpacity(0.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultBadge() {
    final bool won = opponent.winsAgainst > opponent.lossesTo;
    final bool lost = opponent.lossesTo > opponent.winsAgainst;

    final Color bgColor = won
        ? Colors.green.withOpacity(0.22)
        : lost
            ? Colors.red.withOpacity(0.22)
            : Colors.white.withOpacity(0.16);
    final Color borderColor = won
        ? Colors.greenAccent.withOpacity(0.75)
        : lost
            ? Colors.redAccent.withOpacity(0.78)
            : Colors.white.withOpacity(0.35);
    final String label = won
        ? 'Won'
        : lost
            ? 'Lost'
            : 'Draw';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: borderColor, width: 0.9),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
