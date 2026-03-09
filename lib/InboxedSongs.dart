import 'package:flutter/material.dart';
import 'package:welcometothedisco/models/versus_model.dart';
import 'package:welcometothedisco/versus/playground.dart';

class InboxedSongs extends StatelessWidget {
  final VersusModel versus;

  const InboxedSongs({super.key, required this.versus});

  @override
  Widget build(BuildContext context) {
    final authorUsername = versus.author?.username;
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Author: ${authorUsername != null && authorUsername.isNotEmpty ? authorUsername : versus.authorId}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.white.withOpacity(0.13),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: const Text(
                      'VS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
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
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(
          color: Colors.white.withOpacity(0.14),
          width: 0.8,
        ),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imageUrl != null && imageUrl!.isNotEmpty
                ? Image.network(
                    imageUrl!,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 52,
                    height: 52,
                    color: Colors.white.withOpacity(0.12),
                    child: Icon(
                      Icons.album_rounded,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
