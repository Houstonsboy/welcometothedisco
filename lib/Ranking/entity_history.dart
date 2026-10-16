import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/artist_versus_model.dart';
import 'package:welcometothedisco/models/pair_model.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';
import 'package:welcometothedisco/versus/artistplayground.dart';
import 'package:welcometothedisco/versus/playground.dart';

const _kBlue = AppTheme.gradientStart;
const _kPink = AppTheme.gradientEnd;

class EntityOpponentHistoryScreen extends StatefulWidget {
  final String entityId;
  final String entityName;
  final String entityImage;
  final String entityType;
  final PairModel pair;

  const EntityOpponentHistoryScreen({
    super.key,
    required this.entityId,
    required this.entityName,
    required this.entityImage,
    required this.entityType,
    required this.pair,
  });

  @override
  State<EntityOpponentHistoryScreen> createState() =>
      _EntityOpponentHistoryScreenState();
}

class _EntityOpponentHistoryScreenState
    extends State<EntityOpponentHistoryScreen> {
  bool get _isArtist => widget.entityType == 'artist';

  // versusId → author metadata fetched from versus docs
  final Map<String, String> _authorNames = {};
  final Map<String, String> _authorAvatars = {};

  @override
  void initState() {
    super.initState();
    _fetchAuthors();
  }

  Future<void> _fetchAuthors() async {
    final ids = widget.pair.versusHistory
        .map((e) => e.versusId)
        .where((id) => id.trim().isNotEmpty)
        .toList();
    if (ids.isEmpty) return;

    final docs = await Future.wait(
      ids.map((id) =>
          FirebaseFirestore.instance.collection('versus').doc(id).get()),
    );

    final names = <String, String>{};
    final avatars = <String, String>{};
    for (final doc in docs) {
      if (!doc.exists) continue;
      final data = doc.data()!;
      names[doc.id] = (data['author_username'] as String?)?.trim() ?? '';
      avatars[doc.id] = (data['author_avatar'] as String?)?.trim() ?? '';
    }
    if (mounted) {
      setState(() {
        _authorNames.addAll(names);
        _authorAvatars.addAll(avatars);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final opp = widget.pair.opponentOf(widget.entityId);
    final items = widget.pair.versusHistory;

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
              _buildHeader(context, opp),
              Expanded(
                child: items.isEmpty
                    ? _EmptyState(opponentName: opp.entityName)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final entry = items[i];
                          final myRounds = widget.pair
                              .myRoundsInVersus(widget.entityId, entry.versusId);
                          final theirRounds = widget.pair
                              .theirRoundsInVersus(widget.entityId, entry.versusId);
                          final outcome = widget.pair
                              .outcomeFor(widget.entityId, entry.versusId);
                          return _VersusHistoryCard(
                            isArtist: _isArtist,
                            entityName: widget.entityName,
                            entityImage: widget.entityImage,
                            opponentName: opp.entityName,
                            opponentImage: opp.entityImage,
                            myRounds: myRounds,
                            theirRounds: theirRounds,
                            outcome: outcome,
                            pollCount: entry.pollCount,
                            authorName: _authorNames[entry.versusId] ?? '',
                            authorAvatar: _authorAvatars[entry.versusId] ?? '',
                            onTap: () => _openVersus(context, entry.versusId),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, PairEntityInfo opp) {
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
                color: Colors.white.withValues(alpha: 0.14),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.22), width: 0.9),
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
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                  ),
                ),
                Text(
                  '${widget.entityName} vs ${opp.entityName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
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
      final ArtistVersusModel? model =
          await FirebaseService.getArtistVersusById(versusId);
      if (!context.mounted) return;
      if (model == null) {
        _showMissingSnack(context);
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ArtistVersusPlayground(versus: model, versusId: versusId),
      ));
      return;
    }

    final VersusModel? albumVersus =
        await FirebaseService.getAlbumVersusById(versusId);
    if (!context.mounted) return;
    if (albumVersus == null) {
      _showMissingSnack(context);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VersusPlayground(versus: albumVersus, versusId: versusId),
    ));
  }

  void _showMissingSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open this versus right now.')),
    );
  }
}

// ── History card ──────────────────────────────────────────────────────────────
class _VersusHistoryCard extends StatelessWidget {
  final bool isArtist;
  final String entityName;
  final String entityImage;
  final String opponentName;
  final String opponentImage;
  final int myRounds;
  final int theirRounds;
  final String outcome; // 'won' | 'lost' | 'draw'
  final int pollCount;
  final String authorName;
  final String authorAvatar;
  final VoidCallback onTap;

  const _VersusHistoryCard({
    required this.isArtist,
    required this.entityName,
    required this.entityImage,
    required this.opponentName,
    required this.opponentImage,
    required this.myRounds,
    required this.theirRounds,
    required this.outcome,
    required this.pollCount,
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
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.9),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _entityTile(
                              name: entityName,
                              imageUrl: entityImage,
                              isArtist: isArtist)),
                      const SizedBox(width: 10),
                      _vsPill(),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _entityTile(
                              name: opponentName,
                              imageUrl: opponentImage,
                              isArtist: isArtist)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statusBadge(),
                      Expanded(
                        child: Text(
                          '$myRounds – $theirRounds',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
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

  Widget _statusBadge() {
    final won = outcome == 'won';
    final lost = outcome == 'lost';
    final label = won ? 'Won' : lost ? 'Lost' : 'Draw';
    final bg = won
        ? Colors.green.withValues(alpha: 0.22)
        : lost
            ? Colors.red.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.16);
    final border = won
        ? Colors.greenAccent.withValues(alpha: 0.75)
        : lost
            ? Colors.redAccent.withValues(alpha: 0.75)
            : Colors.white.withValues(alpha: 0.35);
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

  static String? _avatarAssetPath(String raw) {
    final p = raw.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('assets/')) return p;
    return 'assets/images/$p';
  }

  Widget _authorBubble() {
    final name = authorName.trim();
    final path = _avatarAssetPath(authorAvatar);
    if (name.isEmpty && path == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (path != null) ...[
            ClipOval(
              child: Image.asset(
                path,
                width: 18,
                height: 18,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.person_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            if (name.isNotEmpty) const SizedBox(width: 5),
          ],
          if (name.isNotEmpty)
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
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
    final borderRadius =
        isArtist ? BorderRadius.circular(999) : BorderRadius.circular(12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: borderRadius,
            child: imageUrl.trim().isNotEmpty
                ? Image.network(imageUrl, fit: BoxFit.cover)
                : Container(
                    color: Colors.white.withValues(alpha: 0.12),
                    child: Icon(
                      isArtist ? Icons.person_rounded : Icons.album_rounded,
                      color: Colors.white.withValues(alpha: 0.75),
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

  Widget _vsPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
