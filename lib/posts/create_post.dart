// lib/screens/create_post_screen.dart

import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/theme/app_theme.dart';
import 'package:welcometothedisco/widgets/expanding_search_bar.dart';

const _kGreen      = AppTheme.createGreen;
const _kPink       = AppTheme.gradientEnd;
const _kTextPrimary = Colors.white;
const _kTextMuted  = Color(0x66FFFFFF);
const _kDivider    = Color(0x1AFFFFFF);

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _descController = TextEditingController();

  Map<String, String>? _selectedArtist;

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.gradientStart, AppTheme.gradientEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      const SizedBox(height: 20),

                      const _CurrentUserAuthorRow(),

                      const SizedBox(height: 16),

                      // ── Description field ───────────────────────────────
                      TextField(
                        controller: _descController,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontFamily: AppTheme.fontBody,
                          fontSize: 15,
                          height: 1.6,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Write something…',
                          hintStyle: TextStyle(
                            color: _kTextMuted,
                            fontFamily: AppTheme.fontBody,
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        maxLines: null,
                        minLines: 3,
                        textInputAction: TextInputAction.newline,
                      ),

                      const SizedBox(height: 28),
                      _Divider(),
                      const SizedBox(height: 24),

                      // ── Artist search ───────────────────────────────────
                      if (_selectedArtist != null) ...[
                        _SelectedArtistRow(
                          name: _selectedArtist!['name']!,
                          imageUrl: _selectedArtist!['imageUrl']!,
                          onClear: () => setState(() => _selectedArtist = null),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ExpandingSearchBar(
                          hint: 'Search for an artist…',
                          onChanged: (_) {
                            // TODO: filter artist results
                          },
                          onSubmitted: (_) {
                            // TODO: run artist search
                          },
                        ),
                      ),

                      const SizedBox(height: 24),
                      _Divider(),
                      const SizedBox(height: 24),

                      // ── Tracklist placeholder ───────────────────────────
                      _TracklistPlaceholder(),
                    ],
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

// ─── Logged-in author row ─────────────────────────────────────────────────────
class _CurrentUserAuthorRow extends StatelessWidget {
  const _CurrentUserAuthorRow();

  static String _displayLabel(UserModel? user) {
    if (user != null && user.username.trim().isNotEmpty) {
      return user.username.trim();
    }
    final auth = FirebaseAuth.instance.currentUser;
    final fromAuth = auth?.displayName?.trim();
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;
    final email = auth?.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }
    return 'You';
  }

  static Widget _avatar(String avatarPath, double size) {
    final p = avatarPath.trim();

    if (p.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.15),
        ),
        child: Icon(Icons.person_rounded,
            color: Colors.white.withOpacity(0.85), size: size * 0.55),
      );
    }

    Widget image;
    if (p.startsWith('http://') || p.startsWith('https://')) {
      image = Image.network(
        p,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(Icons.person_rounded,
            color: Colors.white.withOpacity(0.85), size: size * 0.55),
      );
    } else {
      final asset = p.startsWith('assets/')
          ? p
          : p.startsWith('/')
              ? p.substring(1)
              : 'assets/images/$p';
      image = Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(Icons.person_rounded,
            color: Colors.white.withOpacity(0.85), size: size * 0.55),
      );
    }

    return ClipOval(
      child: SizedBox(width: size, height: size, child: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: FirebaseService.getCurrentUser(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final label = _displayLabel(user);
        final avatarPath = user?.avatarPath ?? '';

        return Row(
          children: [
            snapshot.connectionState == ConnectionState.waiting
                ? SizedBox(
                    width: 38,
                    height: 38,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  )
                : _avatar(avatarPath, 38),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Top bar ──────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Close
          _IconBtn(
            icon: Icons.close_rounded,
            onTap: () => Navigator.maybePop(context),
          ),

          const Spacer(),

          Text(
            'New Post',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontFamily: AppTheme.fontBody,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),

          const Spacer(),

          // Publish
          GestureDetector(
            onTap: () {
              // TODO: submit post
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: _kGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _kGreen.withOpacity(0.65),
                  width: 1,
                ),
              ),
              child: Text(
                'Publish',
                style: TextStyle(
                  color: _kGreen,
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Selected artist chip ─────────────────────────────────────────────────────
class _SelectedArtistRow extends StatelessWidget {
  const _SelectedArtistRow({
    required this.name,
    required this.imageUrl,
    required this.onClear,
  });

  final String name;
  final String imageUrl;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            imageUrl,
            width: 42,
            height: 42,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 42,
              height: 42,
              color: Colors.white.withOpacity(0.08),
              child: Icon(Icons.music_note_rounded,
                  color: Colors.white.withOpacity(0.45), size: 22),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontFamily: AppTheme.fontBody,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Artist',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontFamily: AppTheme.fontBody,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: onClear,
          child: Icon(Icons.close_rounded,
              color: Colors.white.withOpacity(0.45), size: 20),
        ),
      ],
    );
  }
}

// ─── Tracklist placeholder ────────────────────────────────────────────────────
class _TracklistPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // TODO: open track search / picker
      },
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            ),
            child: Icon(
              Icons.queue_music_rounded,
              color: Colors.white.withOpacity(0.45),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Add tracks',
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontFamily: AppTheme.fontBody,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 0.5,
        color: _kDivider,
      );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: Colors.white.withOpacity(0.7), size: 22),
    );
  }
}