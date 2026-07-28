import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/artist_versus_model.dart';
import 'package:welcometothedisco/models/ranking_model.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';
import 'package:welcometothedisco/versus/artistplayground.dart';
import 'package:welcometothedisco/versus/playground.dart';

const _kBlue = AppTheme.gradientStart;
const _kPink = AppTheme.gradientEnd;

class EntityOpponentHistoryScreen extends StatefulWidget {
  final RankingModel ranking;
  final OpponentModel opponent;

  const EntityOpponentHistoryScreen({
    super.key,
    required this.ranking,
    required this.opponent,
  });

  @override
  State<EntityOpponentHistoryScreen> createState() =>
      _EntityOpponentHistoryScreenState();
}

class _EntityOpponentHistoryScreenState
    extends State<EntityOpponentHistoryScreen> {
  bool get _isArtist => widget.ranking.entityType == 'artist';

  // versusId → {authorName, authorAvatarPath}
  final Map<String, String> _authorNames   = {};
  final Map<String, String> _authorAvatars = {};

  @override
  void initState() {
    super.initState();
    _fetchAuthors();
  }

  Future<void> _fetchAuthors() async {
    final ids = widget.opponent.versusHistory
        .map((v) => v.versusId)
        .where((id) => id.trim().isNotEmpty)
        .toList();
    if (ids.isEmpty) return;

    final futures = ids.map(
      (id) => FirebaseFirestore.instance.collection('versus').doc(id).get(),
    );
    final docs = await Future.wait(futures);

    final names   = <String, String>{};
    final avatars = <String, String>{};
    for (final doc in docs) {
      if (!doc.exists) continue;
      final data = doc.data()!;
      names[doc.id]   = (data['author_username'] as String?)?.trim() ?? '';
      avatars[doc.id] = (data['author_avatar']   as String?)?.trim() ?? '';
    }
    if (mounted) setState(() {
      _authorNames.addAll(names);
      _authorAvatars.addAll(avatars);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.opponent.versusHistory;
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
              Expanded(
                child: items.isEmpty
                    ? _EmptyState(opponentName: widget.opponent.opponentName)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
                        itemBuilder: (context, i) {
                          final versus = items[i];
                          return _VersusHistoryCard(
                            isArtist: _isArtist,
                            entityName: widget.ranking.entityName,
                            entityImage: widget.ranking.entityImage,
                            opponentName: widget.opponent.opponentName,
                            opponentImage: widget.opponent.opponentImage,
                            versusResult: versus,
                            authorName:   _authorNames[versus.versusId]   ?? '',
                            authorAvatar: _authorAvatars[versus.versusId] ?? '',
                            onTap: () => _openVersus(context, versus.versusId),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemCount: items.length,
                      ),
              ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VERSUS HISTORY',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                  ),
                ),
                Text(
                  '${widget.ranking.entityName} vs ${widget.opponent.opponentName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openVersus(BuildContext context, String versusId) async {
    if (_isArtist) {
      final ArtistVersusModel? model = await FirebaseService.getArtistVersusById(
        versusId,
      );
      if (!context.mounted) return;
      if (model == null) {
        _showMissingSnack(context);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ArtistVersusPlayground(
            versus: model,
            versusId: versusId,
          ),
        ),
      );
      return;
    }

    final VersusModel? albumVersus = await FirebaseService.getAlbumVersusById(
      versusId,
    );
    if (!context.mounted) return;
    if (albumVersus == null) {
      _showMissingSnack(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VersusPlayground(
          versus: albumVersus,
          versusId: versusId,
        ),
      ),
    );
  }

  void _showMissingSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open this versus right now.')),
    );
  }
}

class _VersusHistoryCard extends StatelessWidget {
  final bool isArtist;
  final String entityName;
  final String entityImage;
  final String opponentName;
  final String opponentImage;
  final VersusResultModel versusResult;
  final String authorName;
  final String authorAvatar;
  final VoidCallback onTap;

  const _VersusHistoryCard({
    required this.isArtist,
    required this.entityName,
    required this.entityImage,
    required this.opponentName,
    required this.opponentImage,
    required this.versusResult,
    required this.authorName,
    required this.authorAvatar,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 0.9,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _entityTile(
                          name: entityName,
                          imageUrl: entityImage,
                          isArtist: isArtist,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _vsPill(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _entityTile(
                          name: opponentName,
                          imageUrl: opponentImage,
                          isArtist: isArtist,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statusBadge(versusResult.status),
                      Expanded(
                        child: Text(
                          '${versusResult.entityVotes} - ${versusResult.opponentVotes}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _authorBubble(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _avatarAssetPath(String raw) {
    final p = raw.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('assets/')) return p;
    return 'assets/images/$p';
  }

  Widget _authorBubble() {
    final name   = authorName.trim();
    final path   = _avatarAssetPath(authorAvatar);
    final hasAvatar = path != null;
    final hasName   = name.isNotEmpty;
    if (!hasName && !hasAvatar) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.20), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAvatar) ...[
            ClipOval(
              child: Image.asset(
                path!,
                width: 18,
                height: 18,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.person_rounded,
                  size: 14,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),
            if (hasName) const SizedBox(width: 5),
          ],
          if (hasName)
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _entityTile({
    required String name,
    required String imageUrl,
    required bool isArtist,
  }) {
    final borderRadius = isArtist ? BorderRadius.circular(999) : BorderRadius.circular(12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(borderRadius: borderRadius),
            child: ClipRRect(
              borderRadius: borderRadius,
              child: imageUrl.trim().isNotEmpty
                  ? Image.network(imageUrl, fit: BoxFit.cover)
                  : Container(
                      color: Colors.white.withOpacity(0.12),
                      child: Icon(
                        isArtist ? Icons.person_rounded : Icons.album_rounded,
                        color: Colors.white.withOpacity(0.75),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          name.isEmpty ? 'Unknown' : name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    final bool won = s == 'won';
    final bool lost = s == 'lost';
    final String label = won ? 'Won' : lost ? 'Lost' : 'Draw';
    final Color bg = won
        ? Colors.green.withOpacity(0.22)
        : lost
            ? Colors.red.withOpacity(0.22)
            : Colors.white.withOpacity(0.16);
    final Color border = won
        ? Colors.greenAccent.withOpacity(0.75)
        : lost
            ? Colors.redAccent.withOpacity(0.75)
            : Colors.white.withOpacity(0.35);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 0.9),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _vsPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.13),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: const Text(
        'VS',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String opponentName;

  const _EmptyState({required this.opponentName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No versus history yet with $opponentName.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withOpacity(0.72),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
