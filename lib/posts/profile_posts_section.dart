import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/post_model.dart';
import 'package:welcometothedisco/posts/post_view.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kBlue = AppTheme.gradientStart;
const _kPink = AppTheme.gradientEnd;
const _kGreen = AppTheme.createGreen;
const _kCreateCyan = Color(0xFF17B5EE);
const _kTextPrimary = Colors.white;
const _kTextMuted = Color(0x8CFFFFFF);

/// Read-only posts list for a profile, scoped to [authorUid].
class ProfilePostsSection extends StatelessWidget {
  final String authorUid;

  const ProfilePostsSection({
    super.key,
    required this.authorUid,
  });

  @override
  Widget build(BuildContext context) {
    final uid = authorUid.trim();
    if (uid.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _kBlue.withOpacity(0.30),
                _kPink.withOpacity(0.30),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.16),
              width: 0.8,
            ),
          ),
          child: StreamBuilder<List<PostModel>>(
            stream: FirebaseService.getPostsByAuthorStream(uid),
            builder: (context, snapshot) {
              final posts = (snapshot.data ?? const <PostModel>[])
                  .where((p) => p.authorID.trim() == uid)
                  .toList();
              final loading =
                  snapshot.connectionState == ConnectionState.waiting &&
                      posts.isEmpty;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    child: Row(
                      children: [
                        Text(
                          'POSTS',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.8,
                          ),
                        ),
                        if (posts.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${posts.length}',
                            style: TextStyle(
                              color: _kCreateCyan.withOpacity(0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white70,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    )
                  else if (snapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Text(
                        'Could not load posts.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else if (posts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Text(
                        'No posts yet.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.white.withOpacity(0.16),
                        ),
                        ...posts.asMap().entries.map((entry) {
                          final index = entry.key;
                          final post = entry.value;
                          return Column(
                            children: [
                              _ProfilePostTile(
                                post: post,
                                onTap: () => Navigator.of(context).push(
                                  slideUpRoute(
                                    PostDetailScreen(post: post),
                                  ),
                                ),
                              ),
                              if (index < posts.length - 1)
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Colors.white.withOpacity(0.16),
                                ),
                            ],
                          );
                        }),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfilePostTile extends StatelessWidget {
  final PostModel post;
  final VoidCallback onTap;

  const _ProfilePostTile({
    required this.post,
    required this.onTap,
  });

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  String _relativeTime() {
    final created = post.createdAt?.toDate();
    if (created == null) return 'now';

    final diff = DateTime.now().difference(created);
    if (diff.inDays >= 365) return '${diff.inDays ~/ 365}y';
    if (diff.inDays >= 30) return '${diff.inDays ~/ 30}mo';
    if (diff.inDays >= 1) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
    return 'now';
  }

  Widget _authorAvatar() {
    final p = post.authorAvatar.trim();
    const size = 24.0;

    Widget fallback() => Container(
          width: size,
          height: size,
          color: _kBlue.withOpacity(0.35),
          child: Icon(
            Icons.person_rounded,
            color: Colors.white.withOpacity(0.75),
            size: 13,
          ),
        );

    if (p.isEmpty) return ClipOval(child: fallback());

    if (p.startsWith('http://') || p.startsWith('https://')) {
      return ClipOval(
        child: Image.network(
          p,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        ),
      );
    }

    final asset = p.startsWith('assets/')
        ? p
        : p.startsWith('/')
            ? p.substring(1)
            : 'assets/images/$p';

    return ClipOval(
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _authorAvatar(),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          post.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kTextPrimary,
                            fontFamily: AppTheme.fontBody,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '· ${_relativeTime()}',
                        style: const TextStyle(
                          color: _kTextMuted,
                          fontFamily: AppTheme.fontBody,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.more_horiz_rounded,
                  color: Colors.white.withOpacity(0.40),
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _ProfilePostDescription(text: post.description)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.network(
                            post.artistImageUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: _kBlue.withOpacity(0.35),
                              child: Icon(
                                Icons.music_note_rounded,
                                color: _kPink.withOpacity(0.9),
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        post.artistName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kTextMuted,
                          fontFamily: AppTheme.fontBody,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ProfilePostTrackCovers(tracklist: post.tracklist),
            const SizedBox(height: 9),
            Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.loop_rounded,
                      color: _kGreen.withOpacity(0.75),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _fmt(post.remixCount),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.50),
                        fontFamily: AppTheme.fontBody,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 18),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.reply_rounded,
                      color: Colors.white.withOpacity(0.40),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _fmt(post.shareCount),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.50),
                        fontFamily: AppTheme.fontBody,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePostDescription extends StatefulWidget {
  final String text;

  const _ProfilePostDescription({required this.text});

  static const int _previewWords = 60;
  static const int _maxWords = 600;

  @override
  State<_ProfilePostDescription> createState() => _ProfilePostDescriptionState();
}

class _ProfilePostDescriptionState extends State<_ProfilePostDescription> {
  bool _expanded = false;

  static List<String> _words(String text) =>
      text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final words = _words(widget.text);
    final needsMore = words.length > _ProfilePostDescription._previewWords;
    final visibleWords = _expanded
        ? words.take(_ProfilePostDescription._maxWords).toList()
        : words.take(_ProfilePostDescription._previewWords).toList();
    final bodyStyle = TextStyle(
      color: Colors.white.withOpacity(0.82),
      fontFamily: AppTheme.fontBody,
      fontSize: 12.5,
      height: 1.45,
      fontWeight: FontWeight.w400,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: visibleWords.join(' '), style: bodyStyle),
              if (!_expanded && needsMore)
                TextSpan(text: '...', style: bodyStyle),
            ],
          ),
        ),
        if (needsMore) ...[
          const SizedBox(height: 3),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Show less' : 'Show more',
              style: const TextStyle(
                color: _kCreateCyan,
                fontFamily: AppTheme.fontBody,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProfilePostTrackCovers extends StatelessWidget {
  final List<TrackItem> tracklist;

  const _ProfilePostTrackCovers({required this.tracklist});

  static const double _size = 28.0;
  static const double _overlap = 8.5;

  @override
  Widget build(BuildContext context) {
    final items = tracklist.take(5).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final totalWidth = _size + (_size - _overlap) * (items.length - 1);

    return SizedBox(
      height: _size,
      width: totalWidth,
      child: Stack(
        children: List.generate(items.length, (i) {
          return Positioned(
            left: i * (_size - _overlap),
            child: _ProfilePostTrackCircle(url: items[i].trackCover),
          );
        }),
      ),
    );
  }
}

class _ProfilePostTrackCircle extends StatelessWidget {
  final String url;

  const _ProfilePostTrackCircle({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _ProfilePostTrackCovers._size,
      height: _ProfilePostTrackCovers._size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: _kBlue.withOpacity(0.35),
            child: Icon(
              Icons.album_rounded,
              color: _kPink.withOpacity(0.85),
              size: 16,
            ),
          ),
        ),
      ),
    );
  }
}
