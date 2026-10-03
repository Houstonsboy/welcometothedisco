// lib/services/playback_gate.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:welcometothedisco/services/spotify_service.dart';

/// A/B variant shown to a non-Premium user in place of an in-app play
/// control. See docs/spotify-api.md — free-tier users can fully take part in
/// a versus (search, create, join, vote), they just can't trigger playback
/// inside the app, since that's gated by Spotify itself (PREMIUM_REQUIRED).
enum PlaybackGateVariant { openInSpotify, disabledMessage }

/// QA-only override: set to a non-null value (e.g. from a debug console
/// expression while the app is running) to force every account onto one
/// variant, bypassing the per-uid split below. Only has any effect in debug
/// builds — see the [kDebugMode] guard in [playbackVariantForUser] — so
/// there's no way for it to affect a release build or skew real test data.
PlaybackGateVariant? debugForcedVariant;

/// Deterministic 50/50 split keyed on the Firebase uid, so a given user sees
/// the same variant for the life of the test — not Dart's `String.hashCode`,
/// which is content-based but not a documented stability guarantee across
/// Dart versions; a flipped bucket mid-test would quietly corrupt the
/// comparison. No remote kill switch by design (see the premium-gating
/// plan) — ending the test or changing the split needs a release.
PlaybackGateVariant playbackVariantForUser(String uid) {
  if (kDebugMode && debugForcedVariant != null) return debugForcedVariant!;
  if (uid.isEmpty) return PlaybackGateVariant.disabledMessage;
  final digest = sha256.convert(utf8.encode(uid));
  return digest.bytes.first.isEven
      ? PlaybackGateVariant.openInSpotify
      : PlaybackGateVariant.disabledMessage;
}

/// Write-only event log for the playback-gate A/B test (see
/// `playback_gate_events` in firestore.rules). Fire-and-forget — a failed
/// write should never block or surface an error for the playback attempt
/// itself.
void _logGateEvent({
  required String versusId,
  required PlaybackGateVariant variant,
  required String action,
}) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  unawaited(
    FirebaseFirestore.instance.collection('playback_gate_events').add({
      'uid': uid,
      'versus_id': versusId,
      'variant': variant.name,
      'action': action,
      'timestamp': FieldValue.serverTimestamp(),
    }).then(
      (_) {},
      onError: (Object e) => debugPrint('[PlaybackGate] event log write failed: $e'),
    ),
  );
}

/// Opens a track/album/etc. in the Spotify app (or the web player if it's
/// not installed) given its `spotify:TYPE:ID` URI.
Future<void> _openInSpotify(String spotifyUri) async {
  final parts = spotifyUri.split(':');
  final webUrl = parts.length == 3
      ? Uri.parse('https://open.spotify.com/${parts[1]}/${parts[2]}')
      : Uri.tryParse(spotifyUri);
  if (webUrl == null) return;
  try {
    await launchUrl(webUrl, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('[PlaybackGate] _openInSpotify failed: $e');
  }
}

/// Gatekeeper for every in-app playback trigger (play/pause/resume/round).
///
/// Non-Premium accounts never reach the network call: [SpotifyService.isPremium]
/// is checked first (fails closed — unknown reads as not-premium), the A/B
/// variant for this user is shown via [onMessage], and the attempt is logged.
/// Premium accounts fall through to [action]; a late `premiumRequired` (or
/// other) result from Spotify is still surfaced as a message — a defensive
/// backstop for a stale premium flag, not the primary gate.
///
/// [spotifyUri] is only used for the `openInSpotify` variant's deep link —
/// pass null for actions with no single associated track (e.g. a bare
/// pause/resume), which just fall back to a text-only message.
/// [versusId] labels the event log; pass whatever id best identifies the
/// surrounding content (versus doc, post, or '' if neither applies).
///
/// Returns true only when in-app playback actually started/changed.
Future<bool> attemptPlayback({
  required String versusId,
  required String? spotifyUri,
  required void Function(String message) onMessage,
  required Future<PlaybackResult> Function() action,
}) async {
  if (!SpotifyService.isPremium) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final variant = playbackVariantForUser(uid);
    _logGateEvent(versusId: versusId, variant: variant, action: 'shown');

    final canOpenSpotify = variant == PlaybackGateVariant.openInSpotify &&
        spotifyUri != null &&
        spotifyUri.isNotEmpty;
    if (canOpenSpotify) {
      onMessage('Playback in-app needs Spotify Premium — opening in Spotify…');
      _logGateEvent(versusId: versusId, variant: variant, action: 'opened_spotify');
      unawaited(_openInSpotify(spotifyUri));
    } else {
      onMessage(
        'Playback in-app needs Spotify Premium. You can still take part and vote.',
      );
    }
    return false;
  }

  final result = await action();
  if (result == PlaybackResult.ok) return true;

  onMessage(switch (result) {
    PlaybackResult.premiumRequired => 'Playback needs Spotify Premium.',
    PlaybackResult.noActiveDevice =>
      'Open Spotify on a phone, speaker, or desktop, then try again.',
    _ => 'Playback failed. Check Spotify is active.',
  });
  return false;
}
