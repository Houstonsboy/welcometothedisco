import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/artist_versus_model.dart';
import 'package:welcometothedisco/models/inbox_versus_entry.dart';
import 'package:welcometothedisco/models/users_model.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/versus/artistplayground.dart';
import 'package:welcometothedisco/versus/playground.dart';

class InboxedSongs extends StatelessWidget {
  final InboxVersusEntry entry;

  const InboxedSongs({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    if (entry.isAlbum && entry.albumVersus != null) {
      return _AlbumInboxTile(versus: entry.albumVersus!);
    }
    if (entry.isArtist && entry.artistVersus != null) {
      return _ArtistInboxTile(artistVersus: entry.artistVersus!);
    }
    return const SizedBox.shrink();
  }
}

/// Album versus: album cover + title, author chip, VS.
class _AlbumInboxTile extends StatelessWidget {
  final VersusModel versus;

  const _AlbumInboxTile({required this.versus});

  @override
  Widget build(BuildContext context) {
    final leftTitle = versus.album1Title ?? versus.album1Name ?? 'Album 1';
    final rightTitle = versus.album2Title ?? versus.album2Name ?? 'Album 2';
    final leftArtist = versus.album1ArtistName ?? 'Unknown artist';
    final rightArtist = versus.album2ArtistName ?? 'Unknown artist';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VersusPlayground(versus: versus),
            ),
          );
        },
        splashColor: Colors.white.withOpacity(0.08),
        highlightColor: Colors.white.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
          child: Transform.scale(
            scale: 0.85,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: _AuthorProfile(
                    author: versus.author,
                    authorId: versus.authorId,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _AlbumTile(
                        title: leftTitle,
                        artist: leftArtist,
                        imageUrl: versus.album1ImageUrl,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _vsPill(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AlbumTile(
                        title: rightTitle,
                        artist: rightArtist,
                        imageUrl: versus.album2ImageUrl,
                      ),
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

/// Artist versus: circular artist profile + name (same size as album tile).
class _ArtistInboxTile extends StatelessWidget {
  final ArtistVersusModel artistVersus;

  const _ArtistInboxTile({required this.artistVersus});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArtistVersusPlayground(versus: artistVersus),
            ),
          );
        },
        splashColor: Colors.white.withOpacity(0.08),
        highlightColor: Colors.white.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
          child: Transform.scale(
            scale: 0.85,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: _AuthorProfile(
                    author: artistVersus.author,
                    authorId: artistVersus.authorID,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _ArtistTile(
                        name: artistVersus.artist1Name,
                        imageUrl: artistVersus.artist1ImageUrl,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _vsPill(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ArtistTile(
                        name: artistVersus.artist2Name,
                        imageUrl: artistVersus.artist2ImageUrl,
                      ),
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

Widget _vsPill() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: Colors.white.withOpacity(0.13),
      border: Border.all(color: Colors.white.withOpacity(0.2)),
    ),
    child: const Text(
      'VS',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    ),
  );
}

/// Same overall size as _AlbumTile: circular profile + name only (no glass background).
class _ArtistTile extends StatelessWidget {
  final String name;
  final String? imageUrl;

  const _ArtistTile({required this.name, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (_, constraints) {
              final side = constraints.maxWidth < constraints.maxHeight
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              return Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: ClipOval(
                    child: imageUrl != null && imageUrl!.isNotEmpty
                        ? Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            width: side,
                            height: side,
                          )
                        : Container(
                            color: Colors.white.withOpacity(0.12),
                            child: Icon(
                              Icons.person_rounded,
                              color: Colors.white.withOpacity(0.8),
                              size: 32,
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small profile chip: circular avatar + username (no "Author:" label).
/// Size proportional to username; matches top-bar style.
/// Uses #E7188A hue so it sticks out while blending with the glassy aesthetic.
class _AuthorProfile extends StatelessWidget {
  static const _accentColor = Color(0xFFE310EF);

  final UserModel? author;
  final String authorId;

  const _AuthorProfile({this.author, required this.authorId});

  static String? _assetPathFromAvatar(String avatarPath) {
    final p = avatarPath.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('assets/')) return p;
    if (p.startsWith('/')) return p.substring(1);
    return 'assets/images/$p';
  }

  @override
  Widget build(BuildContext context) {
    final username = author?.username.trim();
    final displayName = (username != null && username.isNotEmpty)
        ? username
        : authorId.isNotEmpty
            ? authorId
            : 'Unknown';
    final assetPath = _assetPathFromAvatar(author?.avatarPath ?? '');
    const avatarSize = 20.0;
    const fontSize = 11.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: _accentColor.withOpacity(0.18),
            border: Border.all(
              color: _accentColor.withOpacity(0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withOpacity(0.15),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: assetPath != null
                    ? Image.asset(
                        assetPath,
                        width: avatarSize,
                        height: avatarSize,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: avatarSize,
                        height: avatarSize,
                        color: _accentColor.withOpacity(0.35),
                        child: Icon(
                          Icons.person_rounded,
                          color: Colors.white.withOpacity(0.9),
                          size: 12,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(
                        color: _accentColor.withOpacity(0.4),
                        blurRadius: 6,
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

class _AlbumTile extends StatelessWidget {
  final String title;
  final String artist;
  final String? imageUrl;

  const _AlbumTile({
    required this.title,
    required this.artist,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageUrl != null && imageUrl!.isNotEmpty
                ? Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                  )
                : Container(
                    color: Colors.white.withOpacity(0.12),
                    child: Icon(
                      Icons.album_rounded,
                      color: Colors.white.withOpacity(0.8),
                      size: 32,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          child: Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
