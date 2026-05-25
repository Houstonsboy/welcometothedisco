import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/authentication/login.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/auth_service.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kBlue = AppTheme.gradientStart;
const _kPink = AppTheme.gradientEnd;
const _kAvatars = [
  'avatar1.jpeg',
  'avatar2.jpeg',
  'avatar3.jpg',
  'avatar4.jpeg',
  'avatar5.jpeg',
  'avatar6.jpeg',
];

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _loggingOut = false;
  bool _editing = false;
  bool _savingProfile = false;

  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  String? _selectedAvatar;
  String _lastHydratedUserId = '';

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _hydrateFromUser(UserModel? user) {
    if (user == null) return;
    if (_editing) return;
    final key = '${user.id}:${user.username}:${user.bio}:${user.avatarPath}';
    if (_lastHydratedUserId == key) return;
    _lastHydratedUserId = key;
    _usernameController.text = user.username;
    _bioController.text = user.bio;
    _selectedAvatar = user.avatarPath;
  }

  void _startEditing(UserModel? user) {
    if (user != null) {
      _usernameController.text = user.username;
      _bioController.text = user.bio;
      _selectedAvatar = user.avatarPath;
    }
    setState(() => _editing = true);
  }

  void _cancelEditing(UserModel? user) {
    if (user != null) {
      _usernameController.text = user.username;
      _bioController.text = user.bio;
      _selectedAvatar = user.avatarPath;
    }
    setState(() => _editing = false);
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) return;
    final username = _usernameController.text.trim().toLowerCase();
    final bio = _bioController.text.trim();
    final avatar = (_selectedAvatar ?? '').trim();

    if (avatar.isEmpty || username.isEmpty || bio.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Avatar, username and bio are required.'),
          backgroundColor: _kPink.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _savingProfile = true);
    try {
      await FirebaseService.updateCurrentUserProfile(
        username: username,
        bio: bio,
        avatarPath: avatar,
      );
      if (!mounted) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update profile: $e'),
          backgroundColor: _kPink.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _handleLogout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await AuthService().signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      debugPrint('[UserProfilePage] logout error: $e');
      if (mounted) setState(() => _loggingOut = false);
    }
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
    if (FirebaseAuth.instance.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      });
      return const SizedBox.shrink();
    }

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
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.9),
              size: 18,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Welcome to the Disco',
            style: TextStyle(
              fontSize: 14.0,
              fontFamily: 'Honk-Regular-VariableFont_MORF,SHLN',
              color: AppTheme.titleAccent,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _loggingOut ? null : _handleLogout,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.22),
                      width: 0.9,
                    ),
                  ),
                  child: Center(
                    child: _loggingOut
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          )
                        : Icon(
                            Icons.logout_rounded,
                            color: Colors.white.withOpacity(0.85),
                            size: 17,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: StreamBuilder<UserModel?>(
            stream: FirebaseService.getCurrentUserStream(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              _hydrateFromUser(user);

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProfileCard(user, loading),
                    if (_editing && user != null) ...[
                      const SizedBox(height: 14),
                      _buildEditActions(user),
                    ],
                    const SizedBox(height: 16),
                    // Favorite albums — keyed by user id so it resets on load
                    _FavoriteAlbumsWidget(
                      key: ValueKey(user?.id ?? ''),
                      initialAlbums: user?.favoriteAlbums ?? const [],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Profile card ─────────────────────────────────────────────────────────────
  Widget _buildProfileCard(UserModel? user, bool loading) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
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
                    _kBlue.withOpacity(0.45),
                    _kPink.withOpacity(0.45),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.18),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
              child: loading
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.white.withOpacity(0.6),
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : _buildCardContent(user),
            ),
          ),
        ),
        // ── Edit pen bubble — top-right corner of card ─────────────────────
        if (!loading)
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: _editing ? null : () => _startEditing(user),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _editing
                      ? Colors.white.withOpacity(0.08)
                      : Colors.white.withOpacity(0.18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.28),
                    width: 0.9,
                  ),
                ),
                child: Icon(
                  Icons.edit_rounded,
                  size: 15,
                  color: Colors.white.withOpacity(_editing ? 0.35 : 0.9),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCardContent(UserModel? user) {
    final sourceAvatar =
        _editing ? (_selectedAvatar ?? '') : (user?.avatarPath ?? '');
    final assetPath = _assetPath(sourceAvatar);
    final displayName = user?.username.isNotEmpty == true
        ? user!.username
        : (FirebaseAuth.instance.currentUser?.displayName ?? 'User');
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final friendCount = user?.friends.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.35),
                  width: 2.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kPink.withOpacity(0.32),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipOval(
                child: assetPath != null
                    ? Image.asset(
                        assetPath,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback(),
                      )
                    : _avatarFallback(),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _editing
                      ? _glassInput(
                          controller: _usernameController,
                          label: 'Username',
                        )
                      : Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                  const SizedBox(height: 10),
                  _statPill(
                    value: '$friendCount',
                    label: friendCount == 1 ? 'friend' : 'friends',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Divider(color: Colors.white.withOpacity(0.12), height: 1),
        const SizedBox(height: 14),
        if (_editing) ...[
          _buildAvatarPicker(),
          const SizedBox(height: 14),
          _glassInput(
            controller: _bioController,
            label: 'Bio',
            maxLines: 2,
          ),
        ] else ...[
          if (email.isNotEmpty)
            Text(
              email,
              style: TextStyle(
                color: Colors.white.withOpacity(0.38),
                fontSize: 11,
              ),
            ),
          if (user?.bio.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              user!.bio,
              style: TextStyle(
                color: Colors.white.withOpacity(0.78),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.55,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _statPill({required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: Colors.white.withOpacity(0.18),
          width: 0.8,
        ),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback() => Container(
        color: _kBlue.withOpacity(0.35),
        child: Icon(
          Icons.person_rounded,
          color: Colors.white.withOpacity(0.65),
          size: 40,
        ),
      );

  Widget _glassInput({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.65)),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildAvatarPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose avatar',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _kAvatars.map((filename) {
              final selected = _selectedAvatar == filename;
              return GestureDetector(
                onTap: () => setState(() => _selectedAvatar = filename),
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? Colors.white
                            : Colors.white.withOpacity(0.22),
                        width: selected ? 2.2 : 1,
                      ),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/$filename',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEditActions(UserModel user) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _savingProfile ? null : () => _cancelEditing(user),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
              foregroundColor: Colors.white.withOpacity(0.85),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: _savingProfile ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.18),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: _savingProfile
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withOpacity(0.75),
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Favorite Albums Widget
// ══════════════════════════════════════════════════════════════════════════════

class _FavoriteAlbumsWidget extends StatefulWidget {
  final List<FavoriteAlbumEntry> initialAlbums;

  const _FavoriteAlbumsWidget({
    super.key,
    required this.initialAlbums,
  });

  @override
  State<_FavoriteAlbumsWidget> createState() => _FavoriteAlbumsWidgetState();
}

class _FavoriteAlbumsWidgetState extends State<_FavoriteAlbumsWidget> {
  final SpotifyApi _api = SpotifyApi();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  bool _editing = false;
  bool _saving = false;
  bool _isSearching = false;
  List<FavoriteAlbumEntry> _selected = [];
  List<SpotifyAlbumDetails> _results = [];
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialAlbums);
  }

  @override
  void didUpdateWidget(_FavoriteAlbumsWidget old) {
    super.didUpdateWidget(old);
    if (!_editing) {
      _selected = List.from(widget.initialAlbums);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _selected = List.from(widget.initialAlbums);
      _editing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _cancelEditing() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _editing = false;
      _selected = List.from(widget.initialAlbums);
      _results = [];
      _isSearching = false;
      _lastQuery = '';
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    _lastQuery = q;
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 420), () async {
      final albums = await _api.searchAlbums(q, limit: 12);
      if (!mounted || _lastQuery != q) return;
      setState(() {
        _results = albums;
        _isSearching = false;
      });
    });
  }

  void _selectAlbum(SpotifyAlbumDetails album) {
    if (_selected.length >= 5) return;
    if (_selected.any((e) => e.albumId == album.id)) return;
    setState(() {
      _selected.add(FavoriteAlbumEntry(
        albumId: album.id,
        albumTitle: album.title,
        artistName: album.artistName,
        imageUrl: album.imageUrl,
      ));
      _results = [];
      _searchController.clear();
      _lastQuery = '';
      _isSearching = false;
    });
  }

  void _removeAlbum(int i) => setState(() => _selected.removeAt(i));

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await FirebaseService.updateFavoriteAlbums(_selected);
      if (!mounted) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Favourite albums saved.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: _kPink.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
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
                    _kBlue.withOpacity(0.35),
                    _kPink.withOpacity(0.35),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.16),
                  width: 0.8,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 14),
                  _buildAlbumRow(),
                  if (_editing) ...[
                    if (_results.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildResults(),
                    ],
                    const SizedBox(height: 14),
                    _buildSaveCancel(),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Search bubble — only shown in view mode (editing uses inline bar)
        if (!_editing)
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: _startEditing,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.26),
                    width: 0.9,
                  ),
                ),
                child: Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: Colors.white.withOpacity(0.88),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    if (!_editing) {
      return Row(
        children: [
          Text(
            'FAVORITE ALBUMS',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          // Reserve space so title doesn't overlap the positioned bubble
          const SizedBox(width: 44),
        ],
      );
    }

    // Editing mode: search bar slides in
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Row(
        key: const ValueKey('search-bar'),
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withOpacity(0.12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 0.8,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    cursorColor: _kPink,
                    decoration: InputDecoration(
                      hintText: _selected.length >= 5
                          ? 'Max 5 albums selected'
                          : 'Search albums…',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.38),
                        fontSize: 14,
                      ),
                      prefixIcon: _isSearching
                          ? Padding(
                              padding: const EdgeInsets.all(11),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: Colors.white.withOpacity(0.6),
                                ),
                              ),
                            )
                          : Icon(
                              Icons.search_rounded,
                              color: Colors.white.withOpacity(0.5),
                              size: 18,
                            ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white.withOpacity(0.4),
                                size: 16,
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumRow() {
    if (_selected.isEmpty && !_editing) {
      return Text(
        'No favourite albums yet — tap 🔍 to add some.',
        style: TextStyle(
          color: Colors.white.withOpacity(0.45),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    if (_editing) {
      if (_selected.isEmpty) {
        return Text(
          'Search and add up to 5 albums.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 12,
          ),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_selected.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _albumTileEditing(_selected[i], i),
            );
          }),
        ),
      );
    }

    // View mode: equal-width tiles filling the full row
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _selected.asMap().entries.map((e) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: e.key < _selected.length - 1 ? 8 : 0,
            ),
            child: _albumTileView(e.value),
          ),
        );
      }).toList(),
    );
  }

  Widget _albumTileView(FavoriteAlbumEntry entry) {
    final hasImage = (entry.imageUrl ?? '').trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: hasImage
                ? Image.network(entry.imageUrl!, fit: BoxFit.cover)
                : Container(
                    color: Colors.white.withOpacity(0.12),
                    child: Icon(
                      Icons.album_rounded,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          entry.albumTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _albumTileEditing(FavoriteAlbumEntry entry, int i) {
    const tileSize = 68.0;
    final hasImage = (entry.imageUrl ?? '').trim().isNotEmpty;
    return SizedBox(
      width: tileSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: hasImage
                    ? Image.network(
                        entry.imageUrl!,
                        width: tileSize,
                        height: tileSize,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: tileSize,
                        height: tileSize,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.album_rounded,
                          color: Colors.white.withOpacity(0.5),
                          size: 28,
                        ),
                      ),
              ),
              Positioned(
                top: -7,
                right: -7,
                child: GestureDetector(
                  onTap: () => _removeAlbum(i),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kPink.withOpacity(0.9),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.55),
                        width: 0.9,
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            entry.albumTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final atMax = _selected.length >= 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: Colors.white.withOpacity(0.12), height: 1),
        const SizedBox(height: 10),
        if (atMax)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Maximum 5 albums selected.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 11,
              ),
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.78,
          ),
          itemCount: _results.length,
          itemBuilder: (_, i) {
            final album = _results[i];
            final alreadySelected =
                _selected.any((e) => e.albumId == album.id);
            final disabled = atMax || alreadySelected;
            return GestureDetector(
              onTap: disabled ? null : () => _selectAlbum(album),
              child: Opacity(
                opacity: disabled ? 0.35 : 1.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: (album.imageUrl ?? '').trim().isNotEmpty
                            ? Image.network(
                                album.imageUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                              )
                            : Container(
                                color: Colors.white.withOpacity(0.1),
                                child: Icon(
                                  Icons.album_rounded,
                                  color: Colors.white.withOpacity(0.4),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      album.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSaveCancel() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : _cancelEditing,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
              foregroundColor: Colors.white.withOpacity(0.85),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.18),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }
}
