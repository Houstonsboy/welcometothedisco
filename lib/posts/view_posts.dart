// lib/screens/view_posts_screen.dart

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/post_model.dart';
import 'package:welcometothedisco/posts/create_post.dart';
import 'package:welcometothedisco/posts/post_view.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/perf_trace.dart';
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
  final List<PostModel> _posts = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _error = false;

  int _newPostsCount = 0;
  Timestamp? _topTimestamp;
  StreamSubscription<PostModel?>? _newestSub;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _newestSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialPage() async {
    final trace = PerfTrace('posts_feed')..mark('query_start');
    try {
      final page = await FirebaseService.getPostsPage();
      trace.mark('first_snapshot');
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts);
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
        _loadingInitial = false;
        _error = false;
        _topTimestamp = page.posts.isNotEmpty ? page.posts.first.createdAt : null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        trace
          ..mark('first_frame')
          ..end();
      });
      _subscribeToNewest();
    } catch (e) {
      debugPrint('[ViewPostsScreen] initial load failed: $e');
      if (!mounted) return;
      setState(() {
        _loadingInitial = false;
        _error = true;
      });
    }
  }

  void _subscribeToNewest() {
    _newestSub?.cancel();
    _newestSub = FirebaseService.watchNewestPost().listen((newest) {
      if (!mounted || newest == null || _posts.isEmpty) return;
      if (newest.id == _posts.first.id) return;
      final newestCreated = newest.createdAt;
      final topCreated = _topTimestamp;
      if (newestCreated != null &&
          topCreated != null &&
          newestCreated.compareTo(topCreated) <= 0) {
        return;
      }
      setState(() => _newPostsCount += 1);
    });
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final trace = PerfTrace('posts_feed_more')..mark('query_start');
    setState(() => _loadingMore = true);
    try {
      final page = await FirebaseService.getPostsPage(startAfter: _lastDoc);
      trace
        ..mark('first_snapshot')
        ..end();
      if (!mounted) return;
      setState(() {
        _posts.addAll(page.posts);
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('[ViewPostsScreen] load more failed: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// Fetches posts newer than what's currently shown and splices them in at
  /// the top — the feed already on screen is never torn down or re-rendered
  /// wholesale. Used by the "new posts" banner, pull-to-refresh, and after
  /// creating a post.
  Future<void> _pullNewPosts() async {
    final since = _topTimestamp;
    if (since == null) {
      await _loadInitialPage();
      return;
    }
    final trace = PerfTrace('posts_feed_refresh')..mark('query_start');
    try {
      final newer = await FirebaseService.getPostsNewerThan(since);
      trace
        ..mark('first_snapshot')
        ..end();
      if (!mounted) return;
      setState(() {
        if (newer.isNotEmpty) {
          _posts.insertAll(0, newer);
          _topTimestamp = newer.first.createdAt ?? _topTimestamp;
        }
        _newPostsCount = 0;
      });
      if (newer.isNotEmpty && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      debugPrint('[ViewPostsScreen] pull new posts failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _pullNewPosts,
            color: Colors.white,
            backgroundColor: _kBlue,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                const SliverToBoxAdapter(child: _PostsHeader()),
                if (_loadingInitial)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Colors.white54,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (_error)
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
                else if (_posts.isEmpty)
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
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == _posts.length) {
                          return _hasMore
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white54,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink();
                        }
                        final post = _posts[index];
                        return Column(
                          key: ValueKey(post.id),
                          children: [
                            _PostCard(post: post),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Colors.white.withOpacity(0.24),
                              indent: 0,
                              endIndent: 0,
                            ),
                          ],
                        );
                      },
                      childCount: _posts.length + (_hasMore ? 1 : 0),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
          if (_newPostsCount > 0)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: _NewPostsBanner(
                  count: _newPostsCount,
                  onTap: _pullNewPosts,
                ),
              ),
            ),
          Positioned(
            bottom: 24,
            right: 20,
            child: _CreatePostFAB(onPostCreated: _pullNewPosts),
          ),
        ],
      ),
    );
  }
}

// ─── "N new posts" banner ───────────────────────────────────────────────────
class _NewPostsBanner extends StatelessWidget {
  const _NewPostsBanner({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: _kCreateCyan,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 15),
              const SizedBox(width: 6),
              Text(
                count == 1 ? '1 new post' : '$count new posts',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12.5,
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

// ─── Header ───────────────────────────────────────────────────────────────────
class _PostsHeader extends StatelessWidget {
  const _PostsHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8)
      
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
    const size = 24.0; // reduced from 36.0

    Widget fallback() => Container(
          width: size,
          height: size,
          color: _kBlue.withOpacity(0.35),
          child: Icon(Icons.person_rounded,
              color: Colors.white.withOpacity(0.75), size: 13),
        );

    if (p.isEmpty) {
      return ClipOval(child: fallback());
    }

    if (p.startsWith('http://') || p.startsWith('https://')) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: p,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => fallback(),
          errorWidget: (_, __, ___) => fallback(),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Section 1: author header ───────────────────────────────
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
                Icon(Icons.more_horiz_rounded,
                    color: Colors.white.withOpacity(0.40), size: 18),
              ],
            ),

            const SizedBox(height: 8),

            // ── Section 2: description anchors height; artist is
            //    positioned top-right and does NOT affect Stack height,
            //    so the tracklist margin tracks the description, not the
            //    artist circle.
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Forces the Stack to stretch to full card width so that
                // Positioned(right: 0) always anchors to the card edge,
                // not the description text's natural width.
                const SizedBox(width: double.infinity, height: 0),
                // Description drives the Stack's intrinsic height
                Padding(
                  padding: const EdgeInsets.only(right: 68),
                  child: _PostDescriptionBody(text: post.description),
                ),
                // Artist floats top-right, outside the layout flow
                Positioned(
                  right: 0,
                  top: 0,
                  width: 56,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: post.artistImageUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: _kBlue.withOpacity(0.35),
                              child: Icon(Icons.music_note_rounded,
                                  color: _kPink.withOpacity(0.9), size: 20),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: _kBlue.withOpacity(0.35),
                              child: Icon(Icons.music_note_rounded,
                                  color: _kPink.withOpacity(0.9), size: 20),
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

            // ── Section 3: tracklist covers ────────────────────────────
            _OverlappingTrackCovers(tracklist: post.tracklist),

            const SizedBox(height: 9),

            // ── Section 4: action stats (left-aligned) ─────────────────
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.loop_rounded,
                    color: _kGreen.withOpacity(0.75), size: 14),
                const SizedBox(width: 4),
                Text(
                  _fmt(post.remixCount),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.50),
                    fontFamily: AppTheme.fontBody,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 18),
                Icon(Icons.reply_rounded,
                    color: Colors.white.withOpacity(0.40), size: 14),
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
      fontSize: 12.5,  // reduced from 13.5
      height: 1.45,    // reduced from 1.55
      fontWeight: FontWeight.w400,
    );

    final linkStyle = TextStyle(
      color: _kCreateCyan,
      fontFamily: AppTheme.fontBody,
      fontSize: 12.5,  // reduced from 13.5
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
          const SizedBox(height: 3), // reduced from 4
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Show less' : 'Show more',
              style: linkStyle,
            ),
          ),
        ],
        if (truncatedAtMax) ...[
          const SizedBox(height: 3),
          Text('…', style: bodyStyle),
        ],
      ],
    );
  }
}

// ─── Overlapping track cover circles ─────────────────────────────────────────
class _OverlappingTrackCovers extends StatelessWidget {
  const _OverlappingTrackCovers({required this.tracklist});
  final List<TrackItem> tracklist;

  static const double _size    = 28.0;  // reduced from 35.2
  static const double _overlap = 8.5;   // reduced from 10.7

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
            child: _TrackCircle(
              url: items[i].trackCover,
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
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: _kBlue.withOpacity(0.35),
            child: Icon(Icons.album_rounded,
                color: _kPink.withOpacity(0.85), size: 16), // reduced from 22
          ),
          errorWidget: (_, __, ___) => Container(
            color: _kBlue.withOpacity(0.35),
            child: Icon(Icons.album_rounded,
                color: _kPink.withOpacity(0.85), size: 16), // reduced from 22
          ),
        ),
      ),
    );
  }
}

// ─── Create Post FAB ──────────────────────────────────────────────────────────
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