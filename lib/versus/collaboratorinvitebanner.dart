import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';

const _kPurple = Color(0xFF1E3DE1);
const _kPink   = Color(0xFFf85187);
/// Success state for “invite sent” — reads clearly positive (not pink/red).
const _kInviteSentGreen = Color(0xFF22C55E);
const _kInviteSentGreenDeep = Color(0xFF15803D);

class CollaboratorInviteBanner {
  static Future<void> show(
    BuildContext context, {
    required String artistName,
    String? artistImageUrl,
    /// Called after a successful send with the resolved recipient [FriendEntry].
    /// Typed usernames are resolved to a user via search (exact username match).
    void Function(FriendEntry? selectedFriend)? onInviteSent,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      enableDrag: true,
      useRootNavigator: true,
      builder: (_) => _InviteBannerSheet(
        artistName:     artistName,
        artistImageUrl: artistImageUrl,
        onInviteSent:   onInviteSent,
      ),
    );
  }
}

class _InviteBannerSheet extends StatefulWidget {
  final String  artistName;
  final String? artistImageUrl;
  final void Function(FriendEntry? selectedFriend)? onInviteSent;

  const _InviteBannerSheet({
    required this.artistName,
    this.artistImageUrl,
    this.onInviteSent,
  });

  @override
  State<_InviteBannerSheet> createState() => _InviteBannerSheetState();
}

class _InviteBannerSheetState extends State<_InviteBannerSheet>
    with TickerProviderStateMixin {
  late final AnimationController _sheetCtrl;
  late final Animation<double>    _fadeAnim;
  late final Animation<double>    _scaleAnim;

  late final AnimationController _searchCtrl;
  late final Animation<double>    _searchWidthAnim;
  late final Animation<double>    _searchFadeAnim;
  bool _searchVisible = false;

  final TextEditingController _usernameCtrl  = TextEditingController();
  final FocusNode             _usernameFocus = FocusNode();
  bool _isSending = false;
  bool _sent      = false;

  FriendEntry? _selectedFriend;

  Timer? _searchDebounce;
  List<FriendEntry> _usernameSearchResults = [];
  bool _isSearchingUsername       = false;
  bool _ignoreNextUsernameChange  = false;

  /// Cached friends list from the stream so we can reorder it on selection.
  List<FriendEntry> _cachedFriends = [];

  @override
  void initState() {
    super.initState();

    _sheetCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _fadeAnim  = CurvedAnimation(parent: _sheetCtrl, curve: Curves.easeOutCubic);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _sheetCtrl, curve: Curves.easeOutBack),
    );
    _sheetCtrl.forward();

    _searchCtrl      = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _searchWidthAnim = CurvedAnimation(parent: _searchCtrl, curve: Curves.easeOutCubic);
    _searchFadeAnim  = CurvedAnimation(
      parent: _searchCtrl,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );
  }

  // ── Reorder helper — puts [selected] at index 0 ───────────────────────────
  List<FriendEntry> _withSelectedFirst(List<FriendEntry> source, FriendEntry? selected) {
    if (selected == null) return source;
    final rest = source.where((f) => f.uid != selected.uid).toList();
    return [selected, ...rest];
  }

  void _toggleSearch() {
    HapticFeedback.selectionClick();
    if (_searchVisible) {
      _searchCtrl.reverse().then((_) {
        if (mounted) {
          setState(() {
            _searchVisible         = false;
            _usernameSearchResults = [];
            _isSearchingUsername   = false;
            // Keep _selectedFriend so the friends strip still shows it first
            _usernameCtrl.clear();
          });
        }
      });
      _usernameFocus.unfocus();
    } else {
      setState(() => _searchVisible = true);
      _searchCtrl.forward().then((_) {
        if (mounted) _usernameFocus.requestFocus();
      });
    }
  }

  void _scheduleUsernameSearch(String raw) {
    _searchDebounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() { _usernameSearchResults = []; _isSearchingUsername = false; });
      return;
    }
    setState(() => _isSearchingUsername = true);
    _searchDebounce = Timer(const Duration(milliseconds: 380), () async {
      final queryAtFire = _usernameCtrl.text.trim();
      if (queryAtFire.isEmpty) {
        if (mounted) setState(() { _isSearchingUsername = false; _usernameSearchResults = []; });
        return;
      }
      final results = await FirebaseService.searchUsersByUsername(queryAtFire);
      if (!mounted) return;
      if (_usernameCtrl.text.trim() != queryAtFire) return;
      final entries = results
          .map((u) => FriendEntry(uid: u.id, username: u.username, avatarPath: u.avatarPath))
          .toList();
      setState(() {
        // Keep selected first in search results too
        _usernameSearchResults = _withSelectedFirst(entries, _selectedFriend);
        _isSearchingUsername   = false;
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _sheetCtrl.dispose();
    _searchCtrl.dispose();
    _usernameCtrl.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final rawManual = _usernameCtrl.text.trim();
    final manual =
        rawManual.replaceFirst(RegExp(r'^@+'), '').trim();
    if (_selectedFriend == null && manual.isEmpty) return;

    FriendEntry? recipient = _selectedFriend;

    // Search path: SEND is allowed with only typed text, but Firestore needs a UID.
    // Previously we passed null here, so [createCollaborationInvite] skipped
    // `users/{id}/notifications` entirely.
    if (recipient == null && manual.isNotEmpty) {
      setState(() => _isSending = true);
      try {
        final users = await FirebaseService.searchUsersByUsername(manual);
        final lower = manual.toLowerCase();
        final exact =
            users.where((u) => u.username.toLowerCase() == lower).toList();
        if (!mounted) return;
        setState(() => _isSending = false);
        if (exact.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'No account with that exact username. Pick someone from search results.',
                style: TextStyle(fontSize: 13),
              ),
              backgroundColor: Colors.black.withOpacity(0.78),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            ),
          );
          return;
        }
        final u = exact.first;
        recipient = FriendEntry(
          uid: u.id,
          username: u.username,
          avatarPath: u.avatarPath,
        );
      } catch (e) {
        if (mounted) setState(() => _isSending = false);
        debugPrint('[CollaboratorInviteBanner] username resolve failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not look up user: $e',
                  style: const TextStyle(fontSize: 13)),
              backgroundColor: Colors.black.withOpacity(0.78),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            ),
          );
        }
        return;
      }
    }

    if (recipient == null) return;

    HapticFeedback.mediumImpact();
    setState(() => _isSending = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() { _isSending = false; _sent = true; });
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      widget.onInviteSent?.call(recipient);
      Navigator.of(context).pop();
    }
  }

  void _close() {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: _buildSheet(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0E0E1A).withOpacity(0.97),
                const Color(0xFF14102A).withOpacity(0.97),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.09), width: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHandle(),
              _buildHeader(),
              _buildDivider(),
              _buildContactStrip(),
              _buildAnimatedSearchField(),
              _buildDivider(),
              _buildSendButton(),
              SizedBox(height: safeBottom + 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: 36, height: 4,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: Colors.white.withOpacity(0.18),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleSearch,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _searchVisible ? [_kPink, _kPurple] : [_kPurple, _kPink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                    color: (_searchVisible ? _kPurple : _kPink).withOpacity(0.40),
                    blurRadius: _searchVisible ? 18 : 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: Icon(
                  _searchVisible ? Icons.search_off_rounded : Icons.search_rounded,
                  key: ValueKey(_searchVisible),
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'INVITE TO COLLAB VS',
                  style: TextStyle(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w800, letterSpacing: 2.0),
                ),
                const SizedBox(height: 2),
                Text(
                  _searchVisible ? 'Search by username' : 'Pick tracks for ${widget.artistName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withOpacity(0.45),
                      fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _close,
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
                border: Border.all(color: Colors.white.withOpacity(0.10), width: 0.8),
              ),
              child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.45), size: 15),
            ),
          ),
        ],
      ),
    );
  }

  // ── Contact strip ──────────────────────────────────────────────────────────
  Widget _buildContactStrip() {
    final query = _usernameCtrl.text.trim();

    // ── Search results mode ──
    if (query.isNotEmpty) {
      if (_isSearchingUsername) {
        return _loadingStrip();
      }
      if (_usernameSearchResults.isEmpty) {
        return _emptyStrip('No users match that username');
      }
      // Selected always first in search results
      return _buildFriendPillRow(
        _withSelectedFirst(_usernameSearchResults, _selectedFriend),
      );
    }

    // ── Friends stream mode ──
    return StreamBuilder<UserModel?>(
      stream: FirebaseService.getCurrentUserStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loadingStrip();
        }
        final friends = snapshot.data?.friends ?? const <FriendEntry>[];
        if (friends.isEmpty) {
          return _emptyStrip('Add friends from Find Friends to invite them here');
        }
        // Cache for reorder and bubble selected to front
        _cachedFriends = friends;
        return _buildFriendPillRow(
          _withSelectedFirst(friends, _selectedFriend),
        );
      },
    );
  }

  Widget _loadingStrip() => const SizedBox(
    height: 90,
    child: Center(child: SizedBox(width: 22, height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))),
  );

  Widget _emptyStrip(String msg) => SizedBox(
    height: 90,
    child: Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(msg,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withOpacity(0.38),
            fontSize: 11, fontWeight: FontWeight.w500)),
    )),
  );

  Widget _buildFriendPillRow(List<FriendEntry> friends) {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: friends.length,
        itemBuilder: (_, i) {
          final f          = friends[i];
          final ringColor  = _accentForUid(f.uid);
          final isSelected = _selectedFriend?.uid == f.uid;
          var label = f.username.trim().isNotEmpty
              ? f.username.trim()
              : (f.uid.isNotEmpty ? f.uid : '—');
          if (label.startsWith('@')) label = label.substring(1);

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _searchDebounce?.cancel();
              final tappedSelf = _selectedFriend?.uid == f.uid;
              setState(() {
                _selectedFriend = tappedSelf ? null : f;
                if (_selectedFriend != null) {
                  _ignoreNextUsernameChange = true;
                  _usernameCtrl.clear();
                  _usernameSearchResults = [];
                  _isSearchingUsername   = false;
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(right: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Checkmark badge overlaid on avatar when selected ──────
                  Stack(
                    clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                            color: isSelected ? ringColor : Colors.white.withOpacity(0.10),
                            width: isSelected ? 2.5 : 1.0,
                      ),
                      boxShadow: isSelected
                              ? [BoxShadow(color: ringColor.withOpacity(0.50), blurRadius: 14)]
                              : [],
                        ),
                        child: ClipOval(child: _friendAvatar(f, 46)),
                      ),
                      // Badge
                      if (isSelected)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            width: 16, height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ringColor,
                              border: Border.all(color: const Color(0xFF0E0E1A), width: 1.5),
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.white, size: 9),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    width: 72,
                    child: Text(
                      label.startsWith('@') ? label : '@$label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white.withOpacity(0.4),
                      fontSize: 9,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Animated search field ──────────────────────────────────────────────────
  Widget _buildAnimatedSearchField() {
    if (!_searchVisible) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _searchCtrl,
      builder: (context, child) {
    return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: _searchWidthAnim.value,
              child: FadeTransition(opacity: _searchFadeAnim, child: child),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withOpacity(0.07),
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
            ),
            child: TextField(
              controller: _usernameCtrl,
              focusNode: _usernameFocus,
              onChanged: (value) {
                if (_ignoreNextUsernameChange) {
                  _ignoreNextUsernameChange = false;
                  return;
                }
                setState(() => _selectedFriend = null);
                _scheduleUsernameSearch(value);
              },
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              cursorColor: _kPink,
              decoration: InputDecoration(
                hintText: 'Search by username…',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 14),
                prefixIcon: Icon(Icons.alternate_email_rounded,
                    color: Colors.white.withOpacity(0.35), size: 18),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _usernameCtrl,
                  builder: (_, val, __) => val.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _usernameCtrl.clear();
                            setState(() {
                              _usernameSearchResults = [];
                              _isSearchingUsername   = false;
                              _selectedFriend        = null;
                            });
                          },
                          child: Icon(Icons.cancel_rounded,
                              color: Colors.white.withOpacity(0.30), size: 16),
                        )
                      : const SizedBox.shrink(),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Send button ────────────────────────────────────────────────────────────
  Widget _buildSendButton() {
    final hasTarget = _selectedFriend != null || _usernameCtrl.text.trim().isNotEmpty;
    final label = _sent ? 'INVITE SENT  ✓' : _isSending ? '' : 'SEND INVITE';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: GestureDetector(
        onTap: (!hasTarget || _isSending || _sent) ? null : _handleSend,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: hasTarget && !_sent
                ? const LinearGradient(
                    colors: [_kPurple, _kPink],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : _sent
                    ? const LinearGradient(
                        colors: [_kInviteSentGreenDeep, _kInviteSentGreen],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
            color: (!hasTarget && !_sent) ? Colors.white.withOpacity(0.07) : null,
            border: Border.all(
              color: _sent
                  ? Colors.white.withOpacity(0.4)
                  : hasTarget
                  ? Colors.transparent
                  : Colors.white.withOpacity(0.10),
              width: 0.8,
            ),
            boxShadow: hasTarget && !_sent
                ? [BoxShadow(color: _kPink.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 5))]
                : _sent
                ? [
                    BoxShadow(
                          color: _kInviteSentGreen.withOpacity(0.5),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: _isSending
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(label,
                      key: ValueKey(label),
                      style: TextStyle(
                        color: _sent || hasTarget
                            ? Colors.white
                            : Colors.white.withOpacity(0.25),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() => Divider(
    height: 0, thickness: 0.6,
        color: Colors.white.withOpacity(0.06),
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String? _friendAvatarAssetPath(String avatarPath) {
  final p = avatarPath.trim();
  if (p.isEmpty) return null;
  if (p.startsWith('assets/')) return p;
  if (p.startsWith('/')) return p.substring(1);
  return 'assets/images/$p';
}

Color _accentForUid(String uid) {
  if (uid.isEmpty) return _kPurple;
  const palette = <Color>[
    Color(0xFF6C63FF), Color(0xFFf85187), Color(0xFF00C9A7),
    Color(0xFFFFAA00), _kPurple,
  ];
  var h = 0;
  for (final c in uid.codeUnits) h = (h * 31 + c) & 0x7fffffff;
  return palette[h % palette.length];
}

String _initialsForFriend(FriendEntry f) {
  final u = f.username.trim();
  if (u.length >= 2) return u.substring(0, 2).toUpperCase();
  if (u.isNotEmpty) return u.substring(0, 1).toUpperCase();
  if (f.uid.length >= 2) return f.uid.substring(0, 2).toUpperCase();
  if (f.uid.isNotEmpty) return f.uid.substring(0, 1).toUpperCase();
  return '?';
}

Widget _friendAvatar(FriendEntry f, double size) {
  final p = f.avatarPath.trim();
  if (p.startsWith('http://') || p.startsWith('https://')) {
    return Image.network(p, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initialsPlate(f, size));
  }
  final asset = _friendAvatarAssetPath(p);
  if (asset != null) {
    return Image.asset(asset, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initialsPlate(f, size));
  }
  return _initialsPlate(f, size);
}

Widget _initialsPlate(FriendEntry f, double size) {
  final c = _accentForUid(f.uid);
  return Container(
    width: size, height: size,
    color: c.withOpacity(0.35),
    alignment: Alignment.center,
    child: Text(_initialsForFriend(f),
      style: TextStyle(color: Colors.white.withOpacity(0.92),
          fontSize: size * 0.28, fontWeight: FontWeight.w800)),
  );
}