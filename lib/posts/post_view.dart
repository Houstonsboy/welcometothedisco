// lib/posts/post_view.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:welcometothedisco/models/post_model.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kGreen      = AppTheme.createGreen;
const _kPink       = AppTheme.gradientEnd;
const _kBlue       = AppTheme.gradientStart;
const _kCyan       = Color(0xFF17B5EE);
const _kTextPrimary = Colors.white;
const _kTextMuted  = Color(0x8CFFFFFF);
const _kDivider    = Color(0x18FFFFFF);

// ─── Slide-up route helper ────────────────────────────────────────────────────
Route<void> slideUpRoute(Widget page) => PageRouteBuilder(
      pageBuilder: (_, a, __) => page,
      transitionsBuilder: (_, a, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 380),
    );

// ─── Screen ───────────────────────────────────────────────────────────────────
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.post});
  final PostModel post;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen>
    with SingleTickerProviderStateMixin {
  final SpotifyApi _api = SpotifyApi();

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  // Track whose cover was last tapped — null means nothing playing.
  String? _playingTrackId;
  bool    _isBusy = false; // prevents double-taps while API in flight

  PostModel get post => widget.post;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  String _trackUri(TrackItem t) {
    final id = t.spotifyID.trim();
    return id.isEmpty ? '' : 'spotify:track:$id';
  }

  // ── Tap a track cover → play or pause ─────────────────────────────────────
  Future<void> _onTrackCoverTap(TrackItem track) async {
    if (_isBusy) return;
    final uri = _trackUri(track);
    if (uri.isEmpty) {
      _snack('No Spotify URI for this track.');
      return;
    }

    setState(() => _isBusy = true);
    try {
      if (_playingTrackId == track.spotifyID) {
        // Already playing → pause
        final ok = await _api.pause();
        if (!mounted) return;
        if (ok) {
          setState(() => _playingTrackId = null);
        } else {
          _snack('Could not pause — open Spotify on a device and try again.');
        }
      } else {
        // Play this track
        final ok = await _api.play(uri);
        if (!mounted) return;
        if (ok) {
          setState(() => _playingTrackId = track.spotifyID);
        } else {
          _snack('Open Spotify on a phone, speaker, or desktop, then try again.');
        }
      }
    } catch (e) {
      if (mounted) _snack('Playback error: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ── Queue all tracks ───────────────────────────────────────────────────────
  Future<void> _queueAll() async {
    if (_isBusy || post.tracklist.isEmpty) return;
    final tracks = post.tracklist;

    setState(() => _isBusy = true);
    try {
      // Play the first track immediately, then queue the rest.
      final firstUri = _trackUri(tracks.first);
      if (firstUri.isEmpty) {
        _snack('First track has no Spotify URI.');
        return;
      }

      if (_playingTrackId == null) {
        final ok = await _api.play(firstUri);
        if (!mounted) return;
        if (!ok) {
          _snack('Open Spotify on a device first, then try again.');
          return;
        }
        setState(() => _playingTrackId = tracks.first.spotifyID);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      for (int i = 1; i < tracks.length; i++) {
        final uri = _trackUri(tracks[i]);
        if (uri.isEmpty) continue;
        await _api.queueTrack(uri);
        if (!mounted) return;
      }
      _snack('All ${tracks.length} tracks queued in Spotify.');
    } catch (e) {
      if (mounted) _snack('Queue error: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: AppTheme.fontBody, fontSize: 13)),
        backgroundColor: const Color(0xFF1E1E2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: AppTheme.backgroundDecoration,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  _TopBar(
                    onBack: () => Navigator.maybePop(context),
                    onQueueAll: _isBusy ? null : _queueAll,
                  ),
                  Expanded(
                    child: CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        // Author row
                        SliverToBoxAdapter(
                          child: _AuthorRow(post: post),
                        ),

                        // Description
                        SliverToBoxAdapter(
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(20, 14, 20, 0),
                            child: Text(
                              post.description,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.78),
                                fontFamily: AppTheme.fontBody,
                                fontSize: 15,
                                height: 1.65,
                              ),
                            ),
                          ),
                        ),

                        SliverToBoxAdapter(
                            child: _HDivider(top: 22, bottom: 16)),

                        // Artist block
                        SliverToBoxAdapter(
                          child: _ArtistBlock(post: post),
                        ),

                        SliverToBoxAdapter(
                            child: _HDivider(top: 16, bottom: 4)),

                        // Tracklist header
                        SliverToBoxAdapter(
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(20, 4, 20, 8),
                            child: Row(
                              children: [
                                Icon(Icons.queue_music_rounded,
                                    color: _kCyan.withOpacity(0.75),
                                    size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'TRACKLIST',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.45),
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 1),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: _kCyan.withOpacity(0.12),
                                  ),
                                  child: Text(
                                    '${post.tracklist.length}',
                                    style: TextStyle(
                                      color: _kCyan.withOpacity(0.8),
                                      fontFamily: AppTheme.fontBody,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Track tiles
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 0),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                final track = post.tracklist[i];
                                return _TrackTile(
                                  track: track,
                                  index: i,
                                  isPlaying:
                                      _playingTrackId == track.spotifyID,
                                  isBusy: _isBusy,
                                  onCoverTap: () =>
                                      _onTrackCoverTap(track),
                                );
                              },
                              childCount: post.tracklist.length,
                            ),
                          ),
                        ),

                        SliverToBoxAdapter(
                            child: _HDivider(top: 12, bottom: 8)),

                        // Footer
                        SliverToBoxAdapter(
                          child: _FooterActions(
                            post: post,
                            fmt: _fmt,
                            onQueueAll: _isBusy ? null : _queueAll,
                          ),
                        ),

                        const SliverToBoxAdapter(
                            child: SizedBox(height: 48)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Top bar ──────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onQueueAll});
  final VoidCallback onBack;
  final VoidCallback? onQueueAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Back button — glass circle
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
                border: Border.all(
                    color: Colors.white.withOpacity(0.12), width: 0.8),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white.withOpacity(0.80),
                size: 15,
              ),
            ),
          ),

          const Spacer(),

          // Share
          GestureDetector(
            onTap: () {/* TODO: share */},
            child: Icon(Icons.ios_share_rounded,
                color: Colors.white.withOpacity(0.55), size: 20),
          ),

          const SizedBox(width: 18),

          // ⋯
          GestureDetector(
            onTap: () {/* TODO: options */},
            child: Icon(Icons.more_horiz_rounded,
                color: Colors.white.withOpacity(0.55), size: 22),
          ),
        ],
      ),
    );
  }
}

// ─── Author row ───────────────────────────────────────────────────────────────
class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.post});
  final PostModel post;

  String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  Widget _avatar() {
    final p = post.authorAvatar.trim();
    const size = 42.0;

    Widget fallback() => Container(
          width: size,
          height: size,
          color: _kBlue.withOpacity(0.35),
          child: Icon(Icons.person_rounded,
              color: Colors.white.withOpacity(0.7), size: 22),
        );

    if (p.isEmpty) return ClipOval(child: fallback());

    if (p.startsWith('http://') || p.startsWith('https://')) {
      return ClipOval(
        child: Image.network(p,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback()),
      );
    }
    final asset = p.startsWith('assets/')
        ? p
        : p.startsWith('/')
            ? p.substring(1)
            : 'assets/images/$p';
    return ClipOval(
      child: Image.asset(asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: _kGreen.withOpacity(0.5), width: 1.5),
            ),
            child: _avatar(),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.authorName,
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontFamily: AppTheme.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _relativeTime(post.createdAt?.toDate()),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontFamily: AppTheme.fontBody,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          _FollowPill(),
        ],
      ),
    );
  }
}

// ─── Follow pill ──────────────────────────────────────────────────────────────
class _FollowPill extends StatefulWidget {
  @override
  State<_FollowPill> createState() => _FollowPillState();
}

class _FollowPillState extends State<_FollowPill> {
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _following = !_following),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _following
              ? Colors.white.withOpacity(0.07)
              : _kGreen.withOpacity(0.13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _following
                ? Colors.white.withOpacity(0.14)
                : _kGreen.withOpacity(0.55),
            width: 1,
          ),
        ),
        child: Text(
          _following ? 'Following' : 'Follow',
          style: TextStyle(
            color: _following ? _kTextMuted : _kGreen,
            fontFamily: AppTheme.fontBody,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Artist block ─────────────────────────────────────────────────────────────
class _ArtistBlock extends StatelessWidget {
  const _ArtistBlock({required this.post});
  final PostModel post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: AppTheme.glassPanelGradient(opacity: 0.35),
              border: Border.all(
                  color: Colors.white.withOpacity(0.14), width: 0.8),
            ),
            child: Row(
              children: [
                // Artist circle
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.20), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: _kPink.withOpacity(0.20),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: post.artistImageUrl.startsWith('http')
                        ? Image.network(
                            post.artistImageUrl,
                            width: 54,
                            height: 54,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _artistFallback(54),
                          )
                        : _artistFallback(54),
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.artistName,
                        style: const TextStyle(
                          color: _kTextPrimary,
                          fontFamily: AppTheme.fontBody,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${post.tracklist.length} tracks',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.38),
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.22), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _artistFallback(double size) => Container(
        color: _kBlue.withOpacity(0.35),
        child: Icon(Icons.music_note_rounded,
            color: _kPink.withOpacity(0.8), size: size * 0.5),
      );
}

// ─── Track tile ───────────────────────────────────────────────────────────────
class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.index,
    required this.isPlaying,
    required this.isBusy,
    required this.onCoverTap,
  });

  final TrackItem    track;
  final int          index;
  final bool         isPlaying;
  final bool         isBusy;
  final VoidCallback onCoverTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isPlaying
                  ? _kCyan.withOpacity(0.10)
                  : Colors.white.withOpacity(0.04),
              border: Border.all(
                color: isPlaying
                    ? _kCyan.withOpacity(0.45)
                    : Colors.white.withOpacity(0.08),
                width: isPlaying ? 1.0 : 0.7,
              ),
            ),
            child: Row(
              children: [
                // Track number
                SizedBox(
                  width: 22,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isPlaying
                          ? _kCyan
                          : Colors.white.withOpacity(0.25),
                      fontFamily: AppTheme.fontBody,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Cover — tappable
                GestureDetector(
                  onTap: isBusy ? null : onCoverTap,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: track.trackCover.isNotEmpty
                            ? Image.network(
                                track.trackCover,
                                width: 46,
                                height: 46,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _coverFallback(),
                              )
                            : _coverFallback(),
                      ),
                      // Overlay play/pause icon
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.black
                              .withOpacity(isPlaying ? 0.45 : 0.18),
                        ),
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: isPlaying
                              ? _kCyan
                              : Colors.white.withOpacity(0.70),
                          size: isPlaying ? 22 : 20,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Name + artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.trackName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isPlaying
                              ? Colors.white
                              : Colors.white.withOpacity(0.88),
                          fontFamily: AppTheme.fontBody,
                          fontSize: 13.5,
                          fontWeight: isPlaying
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.trackArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.38),
                          fontFamily: AppTheme.fontBody,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Playing indicator bars
                if (isPlaying) ...[
                  const SizedBox(width: 8),
                  _PlayingBars(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverFallback() => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: _kBlue.withOpacity(0.30),
        ),
        child: Icon(Icons.album_rounded,
            color: _kPink.withOpacity(0.75), size: 22),
      );
}

// ─── Animated "playing" bars indicator ───────────────────────────────────────
class _PlayingBars extends StatefulWidget {
  @override
  State<_PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<_PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final v = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(height: 6 + 8 * v),
            const SizedBox(width: 2),
            _bar(height: 6 + 8 * (1 - v)),
            const SizedBox(width: 2),
            _bar(height: 6 + 8 * v * 0.7),
          ],
        );
      },
    );
  }

  Widget _bar({required double height}) => Container(
        width: 3,
        height: height,
        decoration: BoxDecoration(
          color: _kCyan,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

// ─── Footer actions ───────────────────────────────────────────────────────────
class _FooterActions extends StatelessWidget {
  const _FooterActions({
    required this.post,
    required this.fmt,
    required this.onQueueAll,
  });
  final PostModel post;
  final String Function(int) fmt;
  final VoidCallback? onQueueAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          // Remix
          _ActionBtn(
            icon: Icons.shuffle_rounded,
            label: 'remix ${fmt(post.remixCount)}',
            color: _kGreen,
            filled: true,
            onTap: () {},
          ),

          const SizedBox(width: 10),

          // Share
          _ActionBtn(
            icon: Icons.reply_rounded,
            label: fmt(post.shareCount),
            color: Colors.white.withOpacity(0.45),
            filled: false,
            onTap: () {},
          ),

          const Spacer(),

          // Queue all
          GestureDetector(
            onTap: onQueueAll,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: onQueueAll != null
                    ? _kCyan.withOpacity(0.14)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: onQueueAll != null
                      ? _kCyan.withOpacity(0.55)
                      : Colors.white.withOpacity(0.10),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    color: onQueueAll != null
                        ? _kCyan
                        : Colors.white.withOpacity(0.25),
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Queue all',
                    style: TextStyle(
                      color: onQueueAll != null
                          ? _kCyan
                          : Colors.white.withOpacity(0.25),
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  final IconData     icon;
  final String       label;
  final Color        color;
  final bool         filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? color.withOpacity(0.13) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: filled
                ? color.withOpacity(0.50)
                : Colors.white.withOpacity(0.13),
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontFamily: AppTheme.fontBody,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Thin horizontal divider ──────────────────────────────────────────────────
class _HDivider extends StatelessWidget {
  const _HDivider({this.top = 0, this.bottom = 0});
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, top, 20, bottom),
        child: Container(height: 0.5, color: _kDivider),
      );
}
