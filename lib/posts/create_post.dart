// lib/screens/create_post_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/services/firebase_service.dart';
import 'package:welcometothedisco/services/spotify_api.dart';
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

  // ── Artist search ──────────────────────────────────────────────────────────
  final SpotifyApi _spotifyApi = SpotifyApi();
  Timer? _artistDebounce;
  List<SpotifyArtistDetails> _artistResults = [];
  bool _isSearchingArtist = false;
  String _lastArtistQuery = '';
  SpotifyArtistDetails? _selectedArtist;

  // ── Track section ──────────────────────────────────────────────────────────
  List<SpotifyTrack> _topTracks = [];
  bool _isLoadingTracks = false;

  // Search within the selected artist's tracks
  final _trackSearchCtrl = TextEditingController();
  final _trackSearchFocus = FocusNode();
  Timer? _trackDebounce;
  List<SpotifyTrack>? _trackSearchResults; // null = show top tracks
  bool _isSearchingTracks = false;
  String _trackFilterQuery = '';

  List<SpotifyTrack> _selectedTracks = [];

  bool _trackSectionOpen = false;
  bool _isPublishing = false;

  List<SpotifyTrack> get _visibleTracks =>
      (_trackFilterQuery.isNotEmpty && _trackSearchResults != null)
          ? _trackSearchResults!
          : _topTracks;

  @override
  void dispose() {
    _artistDebounce?.cancel();
    _trackDebounce?.cancel();
    _descController.dispose();
    _trackSearchCtrl.dispose();
    _trackSearchFocus.dispose();
    super.dispose();
  }

  // ── Artist search callbacks ────────────────────────────────────────────────
  void _onArtistSearchChanged(String query) {
    _artistDebounce?.cancel();
    final q = query.trim();
    if (q == _lastArtistQuery) return;
    if (q.isEmpty) {
      setState(() {
        _artistResults = [];
        _isSearchingArtist = false;
        _lastArtistQuery = '';
      });
      return;
    }
    setState(() => _isSearchingArtist = true);
    _artistDebounce = Timer(const Duration(milliseconds: 380), () async {
      _lastArtistQuery = q;
      final results = await _spotifyApi.searchArtists(q, limit: 9);
      if (!mounted) return;
      setState(() {
        _artistResults = results;
        _isSearchingArtist = false;
      });
    });
  }

  void _onArtistSelected(SpotifyArtistDetails artist) {
    if (_selectedArtist?.id == artist.id) {
      _clearArtist();
      return;
    }
    setState(() {
      _selectedArtist = artist;
      _artistResults = [];
      _lastArtistQuery = '';
      // reset tracks
      _topTracks = [];
      _selectedTracks = [];
      _trackSearchResults = null;
      _trackFilterQuery = '';
      _trackSearchCtrl.clear();
      _isLoadingTracks = true;
      _trackSectionOpen = false;
    });
    _spotifyApi.getArtistTopTracks(artist.id).then((tracks) {
      if (!mounted) return;
      setState(() {
        _topTracks = tracks;
        _isLoadingTracks = false;
      });
    });
  }

  void _clearArtist() {
    setState(() {
      _selectedArtist = null;
      _artistResults = [];
      _lastArtistQuery = '';
      _topTracks = [];
      _selectedTracks = [];
      _trackSearchResults = null;
      _trackFilterQuery = '';
      _trackSearchCtrl.clear();
      _isLoadingTracks = false;
      _isSearchingTracks = false;
      _trackSectionOpen = false;
    });
  }

  // ── Track search callbacks ─────────────────────────────────────────────────
  void _onTrackFilterChanged() {
    _trackDebounce?.cancel();
    final q = _trackSearchCtrl.text.trim();
    if (q == _trackFilterQuery) return;
    setState(() => _trackFilterQuery = q);
    if (q.isEmpty) {
      setState(() {
        _trackSearchResults = null;
        _isSearchingTracks = false;
      });
      return;
    }
    setState(() => _isSearchingTracks = true);
    _trackDebounce = Timer(const Duration(milliseconds: 380), () async {
      final artist = _selectedArtist;
      if (artist == null || !mounted) return;
      final map = await _spotifyApi.searchTracksByArtists(
        q,
        artist1Id: artist.id,
        artist1Name: artist.name,
        artist2Id: artist.id,
        artist2Name: artist.name,
      );
      if (!mounted) return;
      setState(() {
        _trackSearchResults = map[artist.id] ?? [];
        _isSearchingTracks = false;
      });
    });
  }

  void _toggleTrack(SpotifyTrack track) {
    setState(() {
      final idx = _selectedTracks.indexWhere((t) => t.id == track.id);
      if (idx >= 0) {
        _selectedTracks.removeAt(idx);
      } else {
        _selectedTracks.add(track);
      }
    });
  }

  // ── Publish ────────────────────────────────────────────────────────────────
  Future<void> _publish() async {
    final desc = _descController.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write something before publishing.')),
      );
      return;
    }
    if (_selectedArtist == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an artist for this post.')),
      );
      return;
    }

    setState(() => _isPublishing = true);
    try {
      await FirebaseService.createPost(
        artistID:       _selectedArtist!.id,
        artistName:     _selectedArtist!.name,
        artistImageUrl: _selectedArtist!.imageUrl ?? '',
        description:    desc,
        tracklist: _selectedTracks
            .map((t) => {
                  'spotifyID':   t.id,
                  'trackname':   t.name,
                  'trackcover':  t.albumArtUrl ?? '',
                  'trackartist': t.artistName,
                })
            .toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to publish: $e')),
      );
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
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
              _TopBar(onPublish: _publish, isPublishing: _isPublishing),
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
                          artist: _selectedArtist!,
                          onClear: _clearArtist,
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ExpandingSearchBar(
                          hint: 'Search for an artist…',
                          onChanged: _onArtistSearchChanged,
                          onSubmitted: _onArtistSearchChanged,
                        ),
                      ),
                      if (_isSearchingArtist) ...[
                        const SizedBox(height: 20),
                        Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else if (_artistResults.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _ArtistResultsGrid(
                          results: _artistResults,
                          selected: _selectedArtist,
                          onTap: _onArtistSelected,
                        ),
                      ] else if (_lastArtistQuery.isNotEmpty &&
                          !_isSearchingArtist &&
                          _selectedArtist == null) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'No artists found',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.35),
                              fontFamily: AppTheme.fontBody,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      const SizedBox(height: 24),
                      _Divider(),
                      const SizedBox(height: 16),

                      // ── Track section ────────────────────────────────────
                      _TrackSection(
                        artist: _selectedArtist,
                        isLoadingTracks: _isLoadingTracks,
                        isSearchingTracks: _isSearchingTracks,
                        visibleTracks: _visibleTracks,
                        selectedTracks: _selectedTracks,
                        trackSearchCtrl: _trackSearchCtrl,
                        trackSearchFocus: _trackSearchFocus,
                        onFilterChanged: _onTrackFilterChanged,
                        onToggleTrack: _toggleTrack,
                        isOpen: _trackSectionOpen,
                        onToggleOpen: () =>
                            setState(() => _trackSectionOpen = !_trackSectionOpen),
                      ),
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
  const _TopBar({required this.onPublish, required this.isPublishing});
  final VoidCallback onPublish;
  final bool isPublishing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
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
          GestureDetector(
            onTap: isPublishing ? null : onPublish,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: _kGreen.withOpacity(isPublishing ? 0.07 : 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _kGreen.withOpacity(isPublishing ? 0.30 : 0.65),
                  width: 1,
                ),
              ),
              child: isPublishing
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kGreen.withOpacity(0.7),
                      ),
                    )
                  : Text(
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
    required this.artist,
    required this.onClear,
  });

  final SpotifyArtistDetails artist;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: ClipOval(
            child: artist.imageUrl != null && artist.imageUrl!.isNotEmpty
                ? Image.network(artist.imageUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white.withOpacity(0.08),
                      child: Icon(Icons.music_note_rounded,
                          color: Colors.white.withOpacity(0.45), size: 22),
                    ))
                : Container(
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
                artist.name,
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

// ─── Artist search results grid ───────────────────────────────────────────────
class _ArtistResultsGrid extends StatelessWidget {
  const _ArtistResultsGrid({
    required this.results,
    required this.selected,
    required this.onTap,
  });

  final List<SpotifyArtistDetails> results;
  final SpotifyArtistDetails? selected;
  final ValueChanged<SpotifyArtistDetails> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 10,
        childAspectRatio: 0.80,
      ),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final artist = results[i];
        final isSelected = selected?.id == artist.id;
        return _ArtistResultCard(
          artist: artist,
          isSelected: isSelected,
          onTap: () => onTap(artist),
        );
      },
    );
  }
}

class _ArtistResultCard extends StatelessWidget {
  const _ArtistResultCard({
    required this.artist,
    required this.isSelected,
    required this.onTap,
  });

  final SpotifyArtistDetails artist;
  final bool isSelected;
  final VoidCallback onTap;

  static const _kCyan = Color(0xFF17B5EE);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: LayoutBuilder(builder: (_, constraints) {
              final side =
                  math.min(constraints.maxWidth, constraints.maxHeight);
              return Stack(
                alignment: Alignment.topRight,
                children: [
                  SizedBox(
                    width: side,
                    height: side,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? _kCyan.withOpacity(0.85)
                              : Colors.white.withOpacity(0.12),
                          width: isSelected ? 2.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: _kCyan.withOpacity(0.40),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                )
                              ]
                            : [],
                      ),
                      child: ClipOval(
                        child: artist.imageUrl != null &&
                                artist.imageUrl!.isNotEmpty
                            ? Image.network(artist.imageUrl!, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _placeholder(side))
                            : _placeholder(side),
                      ),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kCyan,
                          boxShadow: [
                            BoxShadow(
                                color: _kCyan.withOpacity(0.55),
                                blurRadius: 8)
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.check_rounded,
                              color: Colors.white, size: 12),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            artist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.75),
              fontFamily: AppTheme.fontBody,
              fontSize: 11.5,
              fontWeight:
                  isSelected ? FontWeight.w700 : FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(double size) => Container(
        color: Colors.white.withOpacity(0.08),
        child: Icon(Icons.person_rounded,
            color: Colors.white.withOpacity(0.35),
            size: size * 0.40),
      );
}

// ─── Track section ────────────────────────────────────────────────────────────
class _TrackSection extends StatelessWidget {
  const _TrackSection({
    required this.artist,
    required this.isLoadingTracks,
    required this.isSearchingTracks,
    required this.visibleTracks,
    required this.selectedTracks,
    required this.trackSearchCtrl,
    required this.trackSearchFocus,
    required this.onFilterChanged,
    required this.onToggleTrack,
    required this.isOpen,
    required this.onToggleOpen,
  });

  final SpotifyArtistDetails? artist;
  final bool isLoadingTracks;
  final bool isSearchingTracks;
  final List<SpotifyTrack> visibleTracks;
  final List<SpotifyTrack> selectedTracks;
  final TextEditingController trackSearchCtrl;
  final FocusNode trackSearchFocus;
  final VoidCallback onFilterChanged;
  final ValueChanged<SpotifyTrack> onToggleTrack;
  final bool isOpen;
  final VoidCallback onToggleOpen;

  static const _kCyan = Color(0xFF17B5EE);

  bool _isSelected(SpotifyTrack t) => selectedTracks.any((s) => s.id == t.id);

  @override
  Widget build(BuildContext context) {
    final hasArtist = artist != null;

    // ── Header row (always visible) ──────────────────────────────────────────
    final header = GestureDetector(
      onTap: hasArtist ? onToggleOpen : null,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: hasArtist
                  ? _kCyan.withOpacity(0.12)
                  : Colors.white.withOpacity(0.06),
              border: Border.all(
                color: hasArtist
                    ? _kCyan.withOpacity(0.35)
                    : Colors.white.withOpacity(0.10),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.queue_music_rounded,
              color: hasArtist
                  ? _kCyan.withOpacity(0.85)
                  : Colors.white.withOpacity(0.30),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add tracks',
                  style: TextStyle(
                    color: hasArtist
                        ? Colors.white.withOpacity(0.85)
                        : Colors.white.withOpacity(0.30),
                    fontFamily: AppTheme.fontBody,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (!hasArtist)
                  Text(
                    'Select an artist first',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.22),
                      fontFamily: AppTheme.fontBody,
                      fontSize: 11,
                    ),
                  ),
                if (hasArtist && selectedTracks.isNotEmpty)
                  Text(
                    '${selectedTracks.length} track${selectedTracks.length == 1 ? '' : 's'} added',
                    style: TextStyle(
                      color: _kCyan.withOpacity(0.75),
                      fontFamily: AppTheme.fontBody,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (hasArtist)
            Icon(
              isOpen
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: Colors.white.withOpacity(0.45),
              size: 22,
            ),
        ],
      ),
    );

    if (!hasArtist || !isOpen) return header;

    // ── Selected tracks chips ────────────────────────────────────────────────
    Widget? selectedChips;
    if (selectedTracks.isNotEmpty) {
      selectedChips = Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: selectedTracks.map((t) {
            return GestureDetector(
              onTap: () => onToggleTrack(t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: _kCyan.withOpacity(0.15),
                  border: Border.all(color: _kCyan.withOpacity(0.55), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (t.albumArtUrl != null && t.albumArtUrl!.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(t.albumArtUrl!,
                            width: 18, height: 18, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _kCyan,
                        fontFamily: AppTheme.fontBody,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.close_rounded, size: 13, color: _kCyan.withOpacity(0.7)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    // ── Track search field ───────────────────────────────────────────────────
    final searchField = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withOpacity(0.07),
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search_rounded,
                color: Colors.white.withOpacity(0.4), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: trackSearchCtrl,
                focusNode: trackSearchFocus,
                onChanged: (_) => onFilterChanged(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13.5,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Filter ${artist!.name} tracks…',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.28),
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13.5,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: TextInputAction.search,
                cursorColor: _kCyan,
                cursorWidth: 1.5,
              ),
            ),
            if (trackSearchCtrl.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  trackSearchCtrl.clear();
                  onFilterChanged();
                  trackSearchFocus.unfocus();
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(Icons.close_rounded,
                      color: Colors.white.withOpacity(0.40), size: 16),
                ),
              ),
          ],
        ),
      ),
    );

    // ── Track list ───────────────────────────────────────────────────────────
    Widget trackList;
    if (isLoadingTracks) {
      trackList = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        ),
      );
    } else if (isSearchingTracks) {
      trackList = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _kCyan.withOpacity(0.6),
            ),
          ),
        ),
      );
    } else if (visibleTracks.isEmpty) {
      trackList = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'No tracks found',
            style: TextStyle(
              color: Colors.white.withOpacity(0.30),
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
            ),
          ),
        ),
      );
    } else {
      trackList = Column(
        children: visibleTracks.map((track) {
          final selected = _isSelected(track);
          return GestureDetector(
            onTap: () => onToggleTrack(track),
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: selected
                    ? _kCyan.withOpacity(0.12)
                    : Colors.white.withOpacity(0.04),
                border: Border.all(
                  color: selected
                      ? _kCyan.withOpacity(0.50)
                      : Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // Album art
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: track.albumArtUrl != null &&
                              track.albumArtUrl!.isNotEmpty
                          ? Image.network(track.albumArtUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _trackArtFallback())
                          : _trackArtFallback(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Name + artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : Colors.white.withOpacity(0.80),
                            fontFamily: AppTheme.fontBody,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        Text(
                          track.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.40),
                            fontFamily: AppTheme.fontBody,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Check icon
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: selected
                        ? Container(
                            key: const ValueKey('checked'),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _kCyan,
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.white, size: 13),
                          )
                        : Icon(
                            key: const ValueKey('unchecked'),
                            Icons.add_rounded,
                            color: Colors.white.withOpacity(0.25),
                            size: 20,
                          ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (selectedChips != null) selectedChips,
        searchField,
        const SizedBox(height: 4),
        trackList,
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _trackArtFallback() => Container(
        color: Colors.white.withOpacity(0.08),
        child: Icon(Icons.music_note_rounded,
            color: Colors.white.withOpacity(0.30), size: 18),
      );
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