import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/authentication/login.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/auth_service.dart';
import 'package:welcometothedisco/services/firebase_service.dart';

const _kBlue = Color(0xFF1E3DE1);
const _kPink = Color(0xFFf85187);
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

    // Prevent cursor jumps while typing by only hydrating when source user changes.
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
        SnackBar(
          content: const Text('Profile updated.'),
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

  // ── Logout ──────────────────────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      // Signs out Firebase and Google session. Spotify tokens are kept so
      // the user doesn't have to re-authenticate with Spotify on next login.
      await AuthService().signOut();
      if (!mounted) return;
      // Replace the entire route stack with LoginScreen so the user cannot
      // press Back to re-enter the app without authenticating.
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

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ── Auth guard ─────────────────────────────────────────────────────────────
    // If somehow the session was cleared while this page is open, redirect
    // immediately to login so the user cannot view a stale profile screen.
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
              Icons.arrow_back_ios_new,
              color: Colors.white.withOpacity(0.9),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Welcome to the Disco',
            style: TextStyle(
              fontSize: 22.0,
              fontFamily: 'Honk-Regular-VariableFont_MORF,SHLN',
              color: Color.fromARGB(255, 159, 181, 63),
            ),
          ),
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
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                child: Column(
                  children: [
                    _buildProfileCard(user, loading),
                    const SizedBox(height: 16),
                    if (user != null) ...[
                      _buildStatsRow(user),
                      const SizedBox(height: 32),
                    ],
                    _buildEditActions(user),
                    const SizedBox(height: 12),
                    _buildLogoutButton(),
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
    final sourceAvatar =
        _editing ? (_selectedAvatar ?? '') : (user?.avatarPath ?? '');
    final assetPath = _assetPath(sourceAvatar);

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
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
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
              : Column(
                  children: [
                    // ── Avatar ───────────────────────────────────────────────
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _kPink.withOpacity(0.35),
                            blurRadius: 22,
                            spreadRadius: 2,
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

                    const SizedBox(height: 20),

                    // ── Username ─────────────────────────────────────────────
                    _editing
                        ? _glassInput(
                            controller: _usernameController,
                            label: 'Username',
                          )
                        : Text(
                            user?.username.isNotEmpty == true
                                ? user!.username
                                : (FirebaseAuth.instance.currentUser
                                        ?.displayName ??
                                    'User'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),

                    const SizedBox(height: 5),

                    // ── Email (subtle) ───────────────────────────────────────
                    Text(
                      FirebaseAuth.instance.currentUser?.email ?? '',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.42),
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 18),
                    Divider(
                      color: Colors.white.withOpacity(0.12),
                      height: 1,
                    ),
                    const SizedBox(height: 16),
                    if (_editing) ...[
                      _buildAvatarPicker(),
                      const SizedBox(height: 14),
                      _glassInput(
                        controller: _bioController,
                        label: 'Bio',
                        maxLines: 2,
                      ),
                    ] else if (user?.bio.isNotEmpty == true) ...[
                      Text(
                        user!.bio,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _avatarFallback() => Container(
        color: _kBlue.withOpacity(0.35),
        child: Icon(
          Icons.person_rounded,
          color: Colors.white.withOpacity(0.65),
          size: 48,
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

  // ── Stats row ────────────────────────────────────────────────────────────────
  Widget _buildStatsRow(UserModel user) {
    return Row(
      children: [
        Expanded(
          child: _buildStatTile(
            icon: Icons.people_rounded,
            label: 'Friends',
            value: '${user.friends.length}',
          ),
        ),
      ],
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(0.08),
            border: Border.all(
              color: Colors.white.withOpacity(0.14),
              width: 0.8,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.5), size: 20),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Logout button ────────────────────────────────────────────────────────────
  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: _loggingOut ? null : _handleLogout,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(_loggingOut ? 0.05 : 0.10),
            border: Border.all(
              color: Colors.white.withOpacity(0.20),
              width: 0.8,
            ),
          ),
          child: Center(
            child: _loggingOut
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withOpacity(0.55),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.logout_rounded,
                        color: Colors.white.withOpacity(0.7),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Log out',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditActions(UserModel? user) {
    if (user == null) return const SizedBox.shrink();
    if (!_editing) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _startEditing(user),
          icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
          label: const Text('Edit profile'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.25)),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      );
    }

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
