// lib/screens/view_posts_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/post_model.dart';
import 'package:welcometothedisco/posts/create_post.dart';
import 'package:welcometothedisco/posts/post_view.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kBlue        = AppTheme.gradientStart;
const _kPink        = AppTheme.gradientEnd;
const _kGreen       = AppTheme.createGreen;
const _kCreateCyan  = Color(0xFF17B5EE);
const _kTextPrimary = Colors.white;
const _kTextMuted   = Color(0x8CFFFFFF);

// ─── Screen ───────────────────────────────────────────────────────────────────
class ViewPostsScreen extends StatefulWidget {
  const ViewPostsScreen({super.key});

  @override
  State<ViewPostsScreen> createState() => _ViewPostsScreenState();
}

class _ViewPostsScreenState extends State<ViewPostsScreen> {
  late Stream<List<PostModel>> _postsStream;

  @override
  void initState() {
    super.initState();
    _postsStream = FirebaseService.getPostsStream();
  }

  void _refreshPosts() {
    setState(() {
      _postsStream = FirebaseService.getPostsStream();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<List<PostModel>>(
        stream: _postsStream,
        builder: (context, snapshot) {
          final posts = snapshot.data ?? [];
          final loading = snapshot.connectionState == ConnectionState.waiting
              && posts.isEmpty;
          final error = snapshot.hasError;

          return Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: _PostsHeader()),
                  if (loading)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.white54,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else if (error)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'Could not load posts',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontFamily: AppTheme.fontBody,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  else if (posts.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'No posts yet — be the first!',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.40),
                            fontFamily: AppTheme.fontBody,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _PostCard(post: posts[index]),
                          ),
                          childCount: posts.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
              Positioned(
                bottom: 24,
                right: 20,
                child: _CreatePostFAB(onPostCreated: _refreshPosts),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Header (unchanged) ───────────────────────────────────────────────────────
class _PostsHeader extends StatelessWidget {
  const _PostsHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(
        'POSTS',
        style: TextStyle(
          color: Colors.white.withOpacity(0.95),
          fontFamily: AppTheme.fontBody,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.4,
        ),
      ),
    );
  }
}

// ─── Post Card ────────────────────────────────────────────────────────────────
class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});
  final PostModel post;

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  Widget _authorAvatar() {
    final p = post.authorAvatar.trim();
    const size = 36.0;

    Widget fallback() => Container(
          width: size,
          height: size,
          color: _kBlue.withOpacity(0.35),
          child: Icon(Icons.person_rounded,
              color: Colors.white.withOpacity(0.75), size: 18),
        );

    if (p.isEmpty) {
      return ClipOval(child: fallback());
    }

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

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      slideUpRoute(PostDetailScreen(post: post)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openDetail(context),
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: AppTheme.glassPanelGradient(opacity: 0.38),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.9),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Row 1: X-style creator header ───────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _authorAvatar(),
                  const SizedBox(width: 9),
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
                        const SizedBox(width: 6),
                        Text(
                          '· ${_relativeTime()}',
                          style: const TextStyle(
                            color: _kTextMuted,
                            fontFamily: AppTheme.fontBody,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.more_horiz_rounded,
                      color: Colors.white.withOpacity(0.55), size: 20),
                ],
              ),

              const SizedBox(height: 10),

              // ── Row 2: description paragraph (left) + artist (right) ────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description — fills remaining width
                  Expanded(
                    child: _PostDescriptionBody(text: post.description),
                  ),

                  const SizedBox(width: 12),

                  // Artist circle + name — fixed width column
                  SizedBox(
                    width: 66,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.28),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _kPink.withOpacity(0.22),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.network(
                              post.artistImageUrl,
                              width: 66,
                              height: 66,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: _kBlue.withOpacity(0.35),
                                child: Icon(Icons.music_note_rounded,
                                    color: _kPink.withOpacity(0.9), size: 28),
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
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Row 3: tracklist circles ─────────────────────────────────
              _OverlappingTrackCovers(tracklist: post.tracklist),

              const SizedBox(height: 10),

              // ── Row 4: remix + share stats (X-style icon + number) ──────
              Row(
                children: [
                  // Remix stat
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.loop_rounded,
                          color: _kGreen.withOpacity(0.75), size: 16),
                      const SizedBox(width: 4),
                      Text(
                        _fmt(post.remixCount),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontFamily: AppTheme.fontBody,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 18),
                  // Share stat
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.reply_rounded,
                          color: Colors.white.withOpacity(0.55), size: 16),
                      const SizedBox(width: 4),
                      Text(
                        _fmt(post.shareCount),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontFamily: AppTheme.fontBody,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

// ─── Description with preview + show more (max 600 words) ───────────────────
class _PostDescriptionBody extends StatefulWidget {
  const _PostDescriptionBody({required this.text});
  final String text;

  static const int _previewWords = 60;
  static const int _maxWords = 600;

  @override
  State<_PostDescriptionBody> createState() => _PostDescriptionBodyState();
}

class _PostDescriptionBodyState extends State<_PostDescriptionBody> {
  bool _expanded = false;

  static List<String> _words(String text) =>
      text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  static String _joinWords(List<String> words) => words.join(' ');

  @override
  Widget build(BuildContext context) {
    final words = _words(widget.text);
    final total = words.length;
    final needsMore = total > _PostDescriptionBody._previewWords;

    final visibleWords = _expanded
        ? words.take(_PostDescriptionBody._maxWords).toList()
        : words.take(_PostDescriptionBody._previewWords).toList();

    final bodyStyle = TextStyle(
      color: Colors.white.withOpacity(0.82),
      fontFamily: AppTheme.fontBody,
      fontSize: 13.5,
      height: 1.55,
      fontWeight: FontWeight.w400,
    );

    final linkStyle = TextStyle(
      color: _kCreateCyan,
      fontFamily: AppTheme.fontBody,
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    );

    final truncatedAtMax =
        _expanded && total > _PostDescriptionBody._maxWords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: _joinWords(visibleWords), style: bodyStyle),
              if (!_expanded && needsMore)
                TextSpan(text: '…', style: bodyStyle),
            ],
          ),
        ),
        if (needsMore) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Show less' : 'Show more',
              style: linkStyle,
            ),
          ),
        ],
        if (truncatedAtMax) ...[
          const SizedBox(height: 4),
          Text(
            '…',
            style: bodyStyle,
          ),
        ],
      ],
    );
  }
}

// ─── Overlapping track cover circles ─────────────────────────────────────────
class _OverlappingTrackCovers extends StatelessWidget {
  const _OverlappingTrackCovers({required this.tracklist});
  final List<TrackItem> tracklist;

  static const double _size    = 35.2;   // circle diameter (39.1 × 0.90)
  static const double _overlap = 10.7;   // overlap scaled with diameter

  @override
  Widget build(BuildContext context) {
    final items = tracklist.take(5).toList(); // cap at 5
    if (items.isEmpty) return const SizedBox.shrink();

    // Total width so the Row knows how much space this stack occupies
    final totalWidth = _size + (_size - _overlap) * (items.length - 1);

    return SizedBox(
      height: _size,
      width: totalWidth,
      child: Stack(
        children: List.generate(items.length, (i) {
          return Positioned(
            left: i * (_size - _overlap),
            child: _TrackCircle(
              url: items[i].trackCover,
              // later circles sit on top
              zIndex: i.toDouble(),
            ),
          );
        }),
      ),
    );
  }
}

class _TrackCircle extends StatelessWidget {
  const _TrackCircle({required this.url, required this.zIndex});
  final String url;
  final double zIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _OverlappingTrackCovers._size,
      height: _OverlappingTrackCovers._size,
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
            child: Icon(Icons.album_rounded,
                color: _kPink.withOpacity(0.85), size: 22),
          ),
        ),
      ),
    );
  }
}

class _CreatePostFAB extends StatefulWidget {
  const _CreatePostFAB({required this.onPostCreated});

  final VoidCallback onPostCreated;

  @override
  State<_CreatePostFAB> createState() => _CreatePostFABState();
}

class _CreatePostFABState extends State<_CreatePostFAB>
    with SingleTickerProviderStateMixin {
  static const double _size = 52;

  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const CreatePostScreen(),
      ),
    );
    if (created == true && mounted) {
      widget.onPostCreated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        _onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kCreateCyan,
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _kCreateCyan.withOpacity(0.45),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.add_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}