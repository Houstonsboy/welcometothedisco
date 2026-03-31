import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kPurple = AppTheme.gradientStart;
const _kPink   = AppTheme.gradientEnd;

class FriendRequest extends StatefulWidget {
  const FriendRequest({super.key});

  @override
  State<FriendRequest> createState() => _FriendRequestState();
}

class _FriendRequestState extends State<FriendRequest>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  List<UserModel> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String _lastQuery = '';

  // Set of UIDs the current user already follows — loaded once via stream,
  // O(1) lookup when rendering each search result row.
  Set<String> _followedUids = {};
  StreamSubscription<UserModel?>? _userSub;

  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    // Subscribe to the current user's doc so _followedUids stays up-to-date
    // without any extra per-row Firestore reads.
    _userSub = FirebaseService.getCurrentUserStream().listen((user) {
      if (!mounted) return;
      final ids = user?.friends.map((f) => f.uid).toSet() ?? {};
      if (ids.length != _followedUids.length ||
          !ids.every(_followedUids.contains)) {
        setState(() => _followedUids = ids);
      }
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q == _lastQuery) return;
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _hasSearched = false;
        _lastQuery = '';
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 380), () async {
      _lastQuery = q;
      final results = await FirebaseService.searchUsersByUsername(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
        _hasSearched = true;
      });
    });
  }

  static String? _assetPath(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('assets/')) return p;
    if (p.startsWith('/')) return p.substring(1);
    return 'assets/images/$p';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPageHeader(),
        const SizedBox(height: 12),
        _buildSearchBar(),
        const SizedBox(height: 4),
        Expanded(child: _buildBody()),
      ],
    );
  }

  // ── Page header ────────────────────────────────────────────────────────────
  Widget _buildPageHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FIND FRIENDS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'search by username',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Result count pill — visible while results are shown
          if (_hasSearched && !_isSearching)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _results.isNotEmpty ? 1 : 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: Colors.white.withOpacity(0.1),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.18),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '${_results.length} found',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.12),
              border: Border.all(
                color: Colors.white.withOpacity(0.18),
                width: 0.8,
              ),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              onChanged: _onSearchChanged,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: _kPink,
              decoration: InputDecoration(
                hintText: 'Search username...',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 15,
                ),
                prefixIcon: _isSearching
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.search_rounded,
                        color: Colors.white.withOpacity(0.5),
                        size: 20,
                      ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _onSearchChanged('');
                          _focusNode.unfocus();
                        },
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withOpacity(0.4),
                          size: 18,
                        ),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Body (states) ──────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_isSearching) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        itemCount: 6,
        separatorBuilder: (_, __) => Divider(
          height: 0,
          indent: 58,
          color: Colors.white.withOpacity(0.07),
        ),
        itemBuilder: (_, __) =>
            _ShimmerUserRow(shimmerController: _shimmerController),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
                border: Border.all(
                  color: Colors.white.withOpacity(0.14),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.person_search_rounded,
                color: Colors.white.withOpacity(0.3),
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Find your people',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start typing to search by username',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              color: Colors.white.withOpacity(0.2),
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              'No users found',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different username',
              style: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      physics: const BouncingScrollPhysics(),
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(
        height: 0,
        indent: 58,
        color: Colors.white.withOpacity(0.08),
      ),
      itemBuilder: (context, i) => _UserResultRow(
        user: _results[i],
        assetPath: _assetPath(_results[i].avatarPath),
        followedUids: _followedUids,
      ),
    );
  }
}

// ── User result row ───────────────────────────────────────────────────────────
class _UserResultRow extends StatefulWidget {
  final UserModel user;
  final String? assetPath;
  // Snapshot of already-followed UIDs from the parent — O(1) contains check.
  final Set<String> followedUids;

  const _UserResultRow({
    required this.user,
    required this.followedUids,
    this.assetPath,
  });

  @override
  State<_UserResultRow> createState() => _UserResultRowState();
}

class _UserResultRowState extends State<_UserResultRow> {
  // Local optimistic flag — true once the user taps Follow in this session.
  bool _added = false;
  bool _loading = false;
  bool _pressed = false;

  // True when already followed (from DB) OR just followed in this session.
  bool get _isFollowing =>
      widget.followedUids.contains(widget.user.id) || _added;

  Future<void> _handleFollow() async {
    if (_isFollowing || _loading) return;
    setState(() => _loading = true);
    try {
      await FirebaseService.addFriend(
        friendUid: widget.user.id,
        friendUsername: widget.user.username,
        friendAvatarPath: widget.user.avatarPath,
      );
      if (mounted) setState(() => _added = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not follow: ${e.toString()}',
            style: const TextStyle(fontSize: 13),
          ),
          backgroundColor: AppTheme.gradientEnd.withOpacity(0.85),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        // TODO: navigate to user profile
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: _pressed ? 0.72 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              // Avatar
              _UserAvatar(assetPath: widget.assetPath, size: 46),
              const SizedBox(width: 12),
              // Username + bio
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.user.username.isNotEmpty
                          ? widget.user.username
                          : 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (widget.user.bio.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.user.bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.42),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Follow / Following / Loading button
              GestureDetector(
                onTap: _handleFollow,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: _isFollowing
                        ? const LinearGradient(
                            colors: [_kPurple, _kPink],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: _isFollowing || _loading
                        ? null
                        : Colors.white.withOpacity(0.10),
                    border: Border.all(
                      color: _isFollowing
                          ? Colors.transparent
                          : Colors.white.withOpacity(0.22),
                      width: 0.8,
                    ),
                    boxShadow: _isFollowing
                        ? [
                            BoxShadow(
                              color: _kPink.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [],
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: Colors.white.withOpacity(0.65),
                          ),
                        )
                      : Text(
                          _isFollowing ? 'Following' : 'Follow',
                          style: TextStyle(
                            color: Colors.white
                                .withOpacity(_isFollowing ? 1.0 : 0.82),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Circular avatar with asset + fallback ─────────────────────────────────────
class _UserAvatar extends StatelessWidget {
  final String? assetPath;
  final double size;

  const _UserAvatar({this.assetPath, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1.5,
        ),
        gradient: LinearGradient(
          colors: [
            _kPurple.withOpacity(0.3),
            _kPink.withOpacity(0.2),
          ],
        ),
      ),
      child: ClipOval(
        child: assetPath != null
            ? Image.asset(
                assetPath!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: _kPurple.withOpacity(0.25),
        child: Icon(
          Icons.person_rounded,
          color: Colors.white.withOpacity(0.65),
          size: size * 0.5,
        ),
      );
}

// ── Shimmer row ───────────────────────────────────────────────────────────────
class _ShimmerUserRow extends StatelessWidget {
  final AnimationController shimmerController;
  const _ShimmerUserRow({required this.shimmerController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerController,
      builder: (_, __) {
        final s = shimmerController.value;
        LinearGradient grad(double opacity) => LinearGradient(
              begin: Alignment(-1 + s * 2, 0),
              end: Alignment(s * 2, 0),
              colors: [
                Colors.white.withOpacity(opacity * 0.5),
                Colors.white.withOpacity(opacity),
                Colors.white.withOpacity(opacity * 0.5),
              ],
            );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: grad(0.12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 13,
                      width: 110,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: grad(0.14),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 9,
                      width: 70,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: grad(0.08),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 58,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: grad(0.08),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
