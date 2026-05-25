import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

const _kBlue = AppTheme.gradientStart;
const _kPink = AppTheme.gradientEnd;

/// Read-only view of another user's profile.
class FriendProfilePage extends StatefulWidget {
  final String uid;
  final String? initialUsername;
  final String? initialAvatarPath;

  const FriendProfilePage({
    super.key,
    required this.uid,
    this.initialUsername,
    this.initialAvatarPath,
  });

  @override
  State<FriendProfilePage> createState() => _FriendProfilePageState();
}

class _FriendProfilePageState extends State<FriendProfilePage> {
  UserModel? _user;
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });
    final user = await FirebaseService.getUserById(widget.uid);
    if (!mounted) return;
    setState(() {
      _user = user;
      _loading = false;
      _notFound = user == null;
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
          title: Text(
            _user?.username.isNotEmpty == true
                ? _user!.username
                : (widget.initialUsername ?? 'Profile'),
            style: const TextStyle(
              fontSize: 14.0,
              fontFamily: 'Honk-Regular-VariableFont_MORF,SHLN',
              color: AppTheme.titleAccent,
            ),
          ),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : _notFound
                  ? Center(
                      child: Text(
                        'Profile not found.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProfileCard(),
                          const SizedBox(height: 16),
                          _FriendFavoriteAlbumsWidget(
                            key: ValueKey(_user!.id),
                            albums: _user!.favoriteAlbums,
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final user = _user!;
    final assetPath = _assetPath(user.avatarPath);
    final friendCount = user.friends.length;

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
          child: Column(
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
                        Text(
                          user.username.isNotEmpty ? user.username : 'User',
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
              if (user.bio.isNotEmpty)
                Text(
                  user.bio,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.55,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statPill({required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.8),
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
}

class _FriendFavoriteAlbumsWidget extends StatelessWidget {
  final List<FavoriteAlbumEntry> albums;

  const _FriendFavoriteAlbumsWidget({
    super.key,
    required this.albums,
  });

  @override
  Widget build(BuildContext context) {
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
              Text(
                'FAVORITE ALBUMS',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 14),
              albums.isEmpty
                  ? Text(
                      'No favourite albums added yet.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: albums.asMap().entries.map((e) {
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: e.key < albums.length - 1 ? 8 : 0,
                            ),
                            child: _albumTile(e.value),
                          ),
                        );
                      }).toList(),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _albumTile(FavoriteAlbumEntry entry) {
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
}
