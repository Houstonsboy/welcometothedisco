import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/Ranking/entity_profile.dart';
import 'package:welcometothedisco/Ranking/entity_search.dart';
import 'package:welcometothedisco/models/ranking_model.dart';
import 'package:welcometothedisco/theme/app_theme.dart';
import 'package:welcometothedisco/utils/ranking_change.dart';

// ── Leaderboard screen ────────────────────────────────────────────────────────

enum _EntityTab { artists, albums }

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  _EntityTab _entityTab    = _EntityTab.artists;
  RankingPeriod? _period   = RankingPeriod.day; // null = All-time (no change shown)
  bool _band2Collapsed   = false; // rank 11–50
  bool _band3Collapsed   = true;  // rank 51+

  Stream<List<RankingModel>> _buildStream(_EntityTab tab) {
    final type = tab == _EntityTab.artists ? 'artist' : 'album';
    return FirebaseFirestore.instance
        .collection('rankings')
        .where('entity_type', isEqualTo: type)
        .where('provisional', isEqualTo: false)
        .orderBy('points', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => RankingModel.fromFirestore(d.data(), d.id))
            .toList());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.backgroundDecoration,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              _buildEntityToggle(),
              _buildPeriodTabs(),
              Expanded(
                child: StreamBuilder<List<RankingModel>>(
                  stream: _buildStream(_entityTab),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      );
                    }
                    final all = snap.data ?? [];
                    if (all.isEmpty) {
                      return Center(
                        child: Text(
                          'No ranked ${_entityTab == _EntityTab.artists ? 'artists' : 'albums'} yet.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 14,
                          ),
                        ),
                      );
                    }
                    return _buildList(all);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'LEADERBOARD',
            style: TextStyle(
              fontFamily: AppTheme.fontHeader,
              fontSize: 22,
              color: Colors.white,
              letterSpacing: 1.8,
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const EntityHistoryScreen(),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.search_rounded,
                color: Colors.white.withValues(alpha: 0.8),
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Entity type toggle ───────────────────────────────────────────────────────

  Widget _buildEntityToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14), width: 0.8),
            ),
            child: Row(
              children: [
                _toggleChip('Artists', _EntityTab.artists),
                _toggleChip('Albums', _EntityTab.albums),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggleChip(String label, _EntityTab tab) {
    final selected = _entityTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_entityTab != tab) setState(() => _entityTab = tab);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  // ── Period tabs ──────────────────────────────────────────────────────────────

  Widget _buildPeriodTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          _periodTab('Day',  RankingPeriod.day),
          const SizedBox(width: 8),
          _periodTab('Week', RankingPeriod.week),
          const SizedBox(width: 8),
          _periodTab('All',  null),
        ],
      ),
    );
  }

  Widget _periodTab(String label, RankingPeriod? period) {
    final selected = _period == period;
    return GestureDetector(
      onTap: () => setState(() => _period = period),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? AppTheme.navSelectedIcon.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.07),
          border: Border.all(
            color: selected
                ? AppTheme.navSelectedIcon.withValues(alpha: 0.60)
                : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? AppTheme.navSelectedIcon : Colors.white.withValues(alpha: 0.55),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Ranked list ──────────────────────────────────────────────────────────────

  Widget _buildList(List<RankingModel> all) {
    final band1 = all.where((m) => (m.rank ?? 999) <= 10).toList();
    final band2 = all.where((m) {
      final r = m.rank ?? 999;
      return r > 10 && r <= 50;
    }).toList();
    final band3 = all.where((m) => (m.rank ?? 999) > 50).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (band1.isNotEmpty) ...[
          _sectionHeader('Top 10', band1.length, null, false, null),
          ...band1.map((m) => _RankRow(model: m, period: _period)),
        ],
        if (band2.isNotEmpty) ...[
          const SizedBox(height: 6),
          _sectionHeader(
            'Rank 11–50',
            band2.length,
            _band2Collapsed,
            true,
            () => setState(() => _band2Collapsed = !_band2Collapsed),
          ),
          if (!_band2Collapsed)
            ...band2.map((m) => _RankRow(model: m, period: _period)),
        ],
        if (band3.isNotEmpty) ...[
          const SizedBox(height: 6),
          _sectionHeader(
            'Rank 51+',
            band3.length,
            _band3Collapsed,
            true,
            () => setState(() => _band3Collapsed = !_band3Collapsed),
          ),
          if (!_band3Collapsed)
            ...band3.map((m) => _RankRow(model: m, period: _period)),
        ],
      ],
    );
  }

  Widget _sectionHeader(
    String title,
    int count,
    bool? collapsed,
    bool collapsible,
    VoidCallback? onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.30),
                fontSize: 11,
              ),
            ),
            if (collapsible) ...[
              const Spacer(),
              Icon(
                collapsed == true
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                color: Colors.white.withValues(alpha: 0.35),
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Rank row ──────────────────────────────────────────────────────────────────

class _RankRow extends StatelessWidget {
  final RankingModel model;
  final RankingPeriod? period; // null = All-time, no change indicator

  const _RankRow({required this.model, required this.period});

  @override
  Widget build(BuildContext context) {
    final change = period != null
        ? changeFor(model, period!)
        : const RankingChange();

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EntityProfileScreen(
            entityId: model.entityId,
            initialTitle: model.entityName,
            initialImageUrl:
                model.entityImage.isNotEmpty ? model.entityImage : null,
            isArtist: model.isArtist,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10), width: 0.7),
              ),
              child: Row(
                children: [
                  // Rank badge
                  SizedBox(
                    width: 32,
                    child: Text(
                      '#${model.rank}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  // Avatar
                  _EntityAvatar(
                      imageUrl: model.entityImage,
                      name: model.entityName,
                      isArtist: model.isArtist),
                  const SizedBox(width: 10),
                  // Name + points
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.entityName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${model.points.round()} pts',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.50),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Change indicator
                  _ChangeChip(change: change),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Entity avatar ─────────────────────────────────────────────────────────────

class _EntityAvatar extends StatelessWidget {
  final String imageUrl;
  final String name;
  final bool isArtist;

  const _EntityAvatar({
    required this.imageUrl,
    required this.name,
    required this.isArtist,
  });

  @override
  Widget build(BuildContext context) {
    final radius = isArtist ? BorderRadius.circular(999) : BorderRadius.circular(6);
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.22), width: 0.8),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: imageUrl.isNotEmpty
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _InitialsFallback(initials: initials),
              )
            : _InitialsFallback(initials: initials),
      ),
    );
  }
}

class _InitialsFallback extends StatelessWidget {
  final String initials;
  const _InitialsFallback({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Change chip ───────────────────────────────────────────────────────────────

class _ChangeChip extends StatelessWidget {
  final RankingChange change;
  const _ChangeChip({required this.change});

  @override
  Widget build(BuildContext context) {
    if (!change.hasData) return const SizedBox(width: 52);

    if (change.isNew) {
      return _chip('NEW', AppTheme.navSelectedIcon, Icons.fiber_new_rounded);
    }

    if (change.isFlat) {
      return _chip('—', AppTheme.changeFlat, null);
    }

    final delta = change.pointsDelta ?? 0;
    final label = delta >= 0
        ? '+${delta.abs().toStringAsFixed(1)}'
        : '−${delta.abs().toStringAsFixed(1)}';
    final color = change.isGain ? AppTheme.successGreen : AppTheme.lossRed;
    final icon = change.isGain
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    return _chip(label, color, icon);
  }

  Widget _chip(String label, Color color, IconData? icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
