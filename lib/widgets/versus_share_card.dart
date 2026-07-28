import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VersusShareCard extends StatelessWidget {
  final String artist1Name;
  final String artist2Name;
  final String? artist1ImageUrl;
  final String? artist2ImageUrl;
  final int artist1Votes;
  final int artist2Votes;
  final Color color1;
  final Color color2;
  final String voterName;
  final Map<int, Map<String, dynamic>> trackDetails;
  final int pairedRoundCount;
  /// Per-round track title, artist 1 side — length should match [pairedRoundCount].
  final List<String> roundTrackNames1;
  /// Per-round track title, artist 2 side — length should match [pairedRoundCount].
  final List<String> roundTrackNames2;
  final List<String> roundTrackIds1;
  final List<String> roundTrackIds2;
  /// true = album poll → square cover art; false (default) = artist → circle.
  final bool isAlbumPoll;

  const VersusShareCard({
    super.key,
    required this.artist1Name,
    required this.artist2Name,
    required this.artist1Votes,
    required this.artist2Votes,
    required this.color1,
    required this.color2,
    required this.voterName,
    required this.trackDetails,
    required this.pairedRoundCount,
    required this.roundTrackNames1,
    required this.roundTrackNames2,
    required this.roundTrackIds1,
    required this.roundTrackIds2,
    this.artist1ImageUrl,
    this.artist2ImageUrl,
    this.isAlbumPoll = false,
  });

  Map<String, dynamic> _mergedRound(int index) {
    String nameAt(List<String> list, int i) =>
        (i < list.length && list[i].trim().isNotEmpty) ? list[i] : '—';
    String idAt(List<String> list, int i) =>
        i < list.length ? list[i] : '';

    final base = <String, dynamic>{
      'artist1trackName': nameAt(roundTrackNames1, index),
      'artist2trackName': nameAt(roundTrackNames2, index),
      'artist1trackID': idAt(roundTrackIds1, index),
      'artist2trackID': idAt(roundTrackIds2, index),
      'Winner': '',
      'voter_comment': '',
      'isBonus': false,
    };
    final voted = trackDetails[index];
    if (voted != null) {
      base.addAll(voted);
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final total = artist1Votes + artist2Votes;
    final bar1Flex = total == 0 ? 1 : artist1Votes;
    final bar2Flex = total == 0 ? 1 : artist2Votes;

    final visibleRoundIndices = <int>[];
    for (var i = 0; i < pairedRoundCount; i++) {
      final merged = _mergedRound(i);
      if (!(merged['isBonus'] as bool? ?? false)) {
        visibleRoundIndices.add(i);
      }
    }

    return SizedBox(
      width: 360,
      child: Container(
        width: 360,
        color: const Color(0xFF0A0A0A),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top accent bar ─────────────────────────────────────
            Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color1, color2],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // ── App mark row ───────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'welcometothedisco',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.2,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: const Color(0xFFF07012).withOpacity(0.5),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            'ARTIST VS',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.8,
                              color: Color(0xFFF07012),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // ── Artist header ──────────────────────────────
                    Row(
                      children: [
                        // Artist 1
                        Expanded(
                          child: _ArtistSide(
                            name: artist1Name,
                            imageUrl: artist1ImageUrl,
                            votes: artist1Votes,
                            color: color1,
                            align: CrossAxisAlignment.start,
                            isWinner: total > 0 &&
                                artist1Votes > artist2Votes,
                            isAlbum: isAlbumPoll,
                          ),
                        ),

                        // VS badge
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [color1, color2],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'VS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Artist 2
                        Expanded(
                          child: _ArtistSide(
                            name: artist2Name,
                            imageUrl: artist2ImageUrl,
                            votes: artist2Votes,
                            color: color2,
                            align: CrossAxisAlignment.end,
                            isWinner: total > 0 &&
                                artist2Votes > artist1Votes,
                            isAlbum: isAlbumPoll,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Vote bar ───────────────────────────────────
                    _VoteBar(
                      flex1: bar1Flex,
                      flex2: bar2Flex,
                      color1: color1,
                      color2: color2,
                      total: total,
                      votes1: artist1Votes,
                      votes2: artist2Votes,
                    ),

                    const SizedBox(height: 20),

                    // ── Full tracklist (all paired rounds); voted rows use highlight ──
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white.withOpacity(0.04),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.07),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: Row(
                              children: [
                                _ColHeader(
                                  name: artist1Name,
                                  color: color1,
                                  align: TextAlign.left,
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 0.5,
                                  height: 16,
                                  color: Colors.white.withOpacity(0.15),
                                ),
                                const SizedBox(width: 8),
                                _ColHeader(
                                  name: artist2Name,
                                  color: color2,
                                  align: TextAlign.right,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 0.5,
                            margin: const EdgeInsets.only(top: 8),
                            color: Colors.white.withOpacity(0.07),
                          ),
                          if (pairedRoundCount <= 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 24, horizontal: 12),
                              child: Center(
                                child: Text(
                                  'no rounds in this versus',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.25),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            )
                          else
                            for (var vi = 0; vi < visibleRoundIndices.length; vi++)
                              _TrackResultRow(
                                roundIndex: visibleRoundIndices[vi],
                                round: _mergedRound(visibleRoundIndices[vi]),
                                color1: color1,
                                color2: color2,
                                isLast: vi == visibleRoundIndices.length - 1,
                              ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Footer ─────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '@$voterName',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'WTTD',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: Colors.white.withOpacity(0.18),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Artist side ───────────────────────────────────────────────────────────────
class _ArtistSide extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final int votes;
  final Color color;
  final CrossAxisAlignment align;
  final bool isWinner;
  // true = album poll → rounded-square cover; false = artist → circle.
  final bool isAlbum;

  const _ArtistSide({
    required this.name,
    required this.votes,
    required this.color,
    required this.align,
    required this.isWinner,
    this.imageUrl,
    this.isAlbum = false,
  });

  static const double _size = 68;
  static const double _albumRadius = 12;

  @override
  Widget build(BuildContext context) {
    final br = isAlbum
        ? BorderRadius.circular(_albumRadius)
        : BorderRadius.circular(_size / 2);

    return Column(
      crossAxisAlignment: align,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                borderRadius: br,
                border: Border.all(
                  color: isWinner
                      ? color
                      : color.withOpacity(0.4),
                  width: isWinner ? 2.5 : 1.2,
                ),
              ),
              child: ClipRRect(
                borderRadius: br,
                child: imageUrl != null && imageUrl!.isNotEmpty
                    ? Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _fallback(color),
                      )
                    : _fallback(color),
              ),
            ),
            if (isWinner)
              Positioned(
                bottom: -4,
                right: align == CrossAxisAlignment.end ? null : -4,
                left: align == CrossAxisAlignment.end ? -4 : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'W',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          name,
          maxLines: 2,
          textAlign: align == CrossAxisAlignment.start
              ? TextAlign.left
              : TextAlign.right,
          style: TextStyle(
            color: Colors.white.withOpacity(isWinner ? 1.0 : 0.7),
            fontSize: 12,
            fontWeight:
                isWinner ? FontWeight.w800 : FontWeight.w600,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$votes',
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        Text(
          votes == 1 ? 'round' : 'rounds',
          style: TextStyle(
            fontSize: 9,
            color: Colors.white.withOpacity(0.35),
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _fallback(Color color) => Container(
        color: color.withOpacity(0.15),
        child: Icon(
          isAlbum ? Icons.album_rounded : Icons.person_rounded,
          color: Colors.white38,
          size: 28,
        ),
      );
}

// ── Vote bar ──────────────────────────────────────────────────────────────────
class _VoteBar extends StatelessWidget {
  final int flex1;
  final int flex2;
  final Color color1;
  final Color color2;
  final int total;
  final int votes1;
  final int votes2;

  const _VoteBar({
    required this.flex1,
    required this.flex2,
    required this.color1,
    required this.color2,
    required this.total,
    required this.votes1,
    required this.votes2,
  });

  @override
  Widget build(BuildContext context) {
    final pct1 = total == 0 ? 50 : ((votes1 / total) * 100).round();
    final pct2 = total == 0 ? 50 : ((votes2 / total) * 100).round();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: flex1,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: color1,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(99),
                    bottomLeft: Radius.circular(99),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              flex: flex2,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: color2,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(99),
                    bottomRight: Radius.circular(99),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$pct1%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color1.withOpacity(0.8),
              ),
            ),
            Text(
              total == 0
                  ? '0 rounds voted'
                  : '$total round${total == 1 ? '' : 's'} voted',
              style: TextStyle(
                fontSize: 9,
                color: Colors.white.withOpacity(0.3),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$pct2%',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color2.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Column header ─────────────────────────────────────────────────────────────
class _ColHeader extends StatelessWidget {
  final String name;
  final Color color;
  final TextAlign align;

  const _ColHeader({
    required this.name,
    required this.color,
    required this.align,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: align == TextAlign.left
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          if (align == TextAlign.right) ...[
            Text(
              name.split(' ').first.toUpperCase(),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
                color: Colors.white.withOpacity(0.35),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color),
            ),
          ] else ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 5),
            Text(
              name.split(' ').first.toUpperCase(),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
                color: Colors.white.withOpacity(0.35),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Track result row ──────────────────────────────────────────────────────────
class _TrackResultRow extends StatelessWidget {
  final int roundIndex;
  final Map<String, dynamic> round;
  final Color color1;
  final Color color2;
  final bool isLast;

  const _TrackResultRow({
    required this.roundIndex,
    required this.round,
    required this.color1,
    required this.color2,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final name1   = round['artist1trackName'] as String? ?? '—';
    final name2   = round['artist2trackName'] as String? ?? '—';
    final id1     = round['artist1trackID']   as String? ?? '';
    final id2     = round['artist2trackID']   as String? ?? '';
    final winner  = round['Winner']           as String? ?? '';
    final comment = (round['voter_comment']   as String? ?? '').trim();

    final artist1Won = id1.isNotEmpty && id1 == winner;
    final artist2Won = id2.isNotEmpty && id2 == winner;

    final commentLabelStyleLeft = GoogleFonts.ibmPlexMono(
      fontSize: 6.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: color1.withOpacity(0.65),
      height: 1.0,
    );
    final commentLabelStyleRight = GoogleFonts.ibmPlexMono(
      fontSize: 6.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: color2.withOpacity(0.65),
      height: 1.0,
    );
    final commentBodyStyle = GoogleFonts.dmSans(
      fontSize: 9.5,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w500,
      height: 1.25,
      color: Colors.white.withOpacity(0.78),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, 7, 12, comment.isNotEmpty ? 4 : 7),
          child: Row(
            children: [
              // Artist 1 track
              Expanded(
                child: Row(
                  children: [
                    if (artist1Won)
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color1,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        name1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: artist1Won
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: artist1Won
                              ? Colors.white
                              : Colors.white.withOpacity(0.35),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Round number
              Container(
                width: 28,
                alignment: Alignment.center,
                child: Text(
                  (roundIndex + 1).toString().padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.2),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),

              // Artist 2 track
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        name2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: artist2Won
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: artist2Won
                              ? Colors.white
                              : Colors.white.withOpacity(0.35),
                        ),
                      ),
                    ),
                    if (artist2Won)
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(left: 5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color2,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Voter comment: labeled block under each track column (same text, mirrored align).
        if (comment.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('COMMENT', style: commentLabelStyleLeft),
                      const SizedBox(height: 3),
                      Text(
                        comment,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                        style: commentBodyStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('COMMENT', style: commentLabelStyleRight),
                      const SizedBox(height: 3),
                      Text(
                        comment,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: commentBodyStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        if (!isLast)
          Divider(
            height: 0,
            indent: 12,
            endIndent: 12,
            color: Colors.white.withOpacity(0.05),
          ),
      ],
    );
  }
}
