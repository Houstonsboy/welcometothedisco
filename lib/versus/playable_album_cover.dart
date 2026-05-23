import 'package:flutter/material.dart';

/// Album art with tap-to-play / tap-again-to-pause on Spotify.
class PlayableAlbumCover extends StatelessWidget {
  final String imageUrl;
  final double size;
  final double borderRadius;
  final Color accentColor;
  final bool isPlaying;
  final bool isLoading;
  final bool emphasized;
  final VoidCallback onTap;

  const PlayableAlbumCover({
    super.key,
    required this.imageUrl,
    required this.size,
    required this.borderRadius,
    required this.accentColor,
    required this.isPlaying,
    required this.isLoading,
    this.emphasized = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: emphasized
                ? accentColor.withOpacity(0.95)
                : isPlaying
                    ? accentColor.withOpacity(0.75)
                    : accentColor.withOpacity(0.22),
            width: emphasized ? 1.6 : (isPlaying ? 1.4 : 0.9),
          ),
          boxShadow: [
            if (emphasized) ...[
              BoxShadow(
                color: accentColor.withOpacity(0.55),
                blurRadius: 16,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.12),
                blurRadius: 8,
              ),
            ],
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 6,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius - 0.5),
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              Image.network(imageUrl, fit: BoxFit.cover),
              if (isLoading)
                Container(
                  color: Colors.black.withOpacity(0.45),
                  child: Center(
                    child: SizedBox(
                      width: size * 0.38,
                      height: size * 0.38,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              else if (isPlaying)
                Container(
                  color: Colors.black.withOpacity(emphasized ? 0.32 : 0.42),
                  child: Icon(
                    Icons.pause_rounded,
                    color: Colors.white,
                    size: size * 0.42,
                  ),
                )
              else
                Container(
                  color: Colors.black.withOpacity(0.28),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white.withOpacity(0.92),
                    size: size * 0.44,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
