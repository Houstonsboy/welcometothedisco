import 'package:flutter/material.dart';

import '../services/spotify_auth.dart';
import '../services/token_storage_service.dart';

/// Explains a failed Spotify playback attempt.
///
/// When Spotify isn't connected (never linked, or Spotify revoked access),
/// every playback call fails the same way "no active device" does, so the
/// device hint alone would send the user to open Spotify when what they need
/// is to reconnect. Check which it is, and offer the right fix.
Future<void> showSpotifyPlaybackFailure(
  BuildContext context,
  String deviceHint,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  if (await TokenStorageService.hasSpotifyTokens()) {
    messenger.showSnackBar(_snackBar(deviceHint));
    return;
  }
  messenger.showSnackBar(_snackBar(
    "Spotify isn't connected.",
    action: SnackBarAction(
      label: 'Reconnect',
      textColor: const Color(0xFF1DB954),
      onPressed: () => _reconnect(messenger),
    ),
  ));
}

Future<void> _reconnect(ScaffoldMessengerState messenger) async {
  final result = await SpotifyAuth().login();
  if (result.isCancelled) return;
  messenger.showSnackBar(_snackBar(
    result.isSuccess ? 'Spotify connected. Tap play again.' : "Couldn't connect Spotify. Try again.",
  ));
}

SnackBar _snackBar(String message, {SnackBarAction? action}) => SnackBar(
      content: Text(message),
      action: action,
      backgroundColor: Colors.black.withValues(alpha: 0.88),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
