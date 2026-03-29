// lib/models/inbox_versus_entry.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:welcometothedisco/models/artist_versus_model.dart';
import 'package:welcometothedisco/models/versus_model.dart';

/// Single inbox row: either an album versus or an artist versus.
/// [timestamp] is used for sorting when no type filter is applied.
class InboxVersusEntry {
  final String type; // 'album' | 'artist'
  final Timestamp? timestamp;
  final VersusModel? albumVersus;
  final ArtistVersusModel? artistVersus;

  const InboxVersusEntry({
    required this.type,
    this.timestamp,
    this.albumVersus,
    this.artistVersus,
  });

  bool get isAlbum => type == 'album';
  bool get isArtist => type == 'artist';

  /// Versus docs with `status: incomplete` (and non-open states) stay out of the inbox UI.
  bool get isEligibleForInboxDisplay {
    if (isAlbum) {
      final v = albumVersus;
      return v != null && v.isEligibleForInboxDisplay;
    }
    if (isArtist) {
      final v = artistVersus;
      return v != null && v.isEligibleForInboxDisplay;
    }
    return false;
  }
}
