import 'package:flutter/foundation.dart';

/// A place in an audiobook you want to find again, with your own note.
/// Kept with the book, so bookmarks sync between the phone and the PC.
@immutable
class AudioBookmark {
  const AudioBookmark({
    required this.track,
    required this.trackMs,
    required this.positionMs,
    required this.addedAt,
    this.note = '',
  });

  /// The file, and where in it.
  final int track;
  final int trackMs;

  /// Where in the whole book, for sorting and showing.
  final int positionMs;

  /// When it was added. Also what tells two bookmarks apart when syncing.
  final DateTime addedAt;
  final String note;

  AudioBookmark withNote(String note) => AudioBookmark(
        track: track,
        trackMs: trackMs,
        positionMs: positionMs,
        addedAt: addedAt,
        note: note,
      );

  /// The same bookmark (added at the same moment), whatever its note.
  bool sameAs(AudioBookmark other) =>
      addedAt.isAtSameMomentAs(other.addedAt);

  Map<String, Object?> toJson() => {
        'track': track,
        'trackMs': trackMs,
        'positionMs': positionMs,
        'addedAt': addedAt.toIso8601String(),
        'note': note,
      };

  static AudioBookmark? fromJson(Object? value) {
    if (value is! Map) return null;
    final track = value['track'];
    final trackMs = value['trackMs'];
    final positionMs = value['positionMs'];
    final addedAt = DateTime.tryParse('${value['addedAt']}');
    if (track is! int || trackMs is! int || addedAt == null) return null;
    final note = value['note'];
    return AudioBookmark(
      track: track,
      trackMs: trackMs,
      positionMs: positionMs is int ? positionMs : trackMs,
      addedAt: addedAt,
      note: note is String ? note : '',
    );
  }
}

/// Reads a list of bookmarks, skipping any that are damaged.
List<AudioBookmark> audioBookmarksFromJson(Object? value) => value is List
    ? [for (final item in value) ?AudioBookmark.fromJson(item)]
    : const [];

/// [marks] from the start of the book.
List<AudioBookmark> sortedBookmarks(List<AudioBookmark> marks) =>
    [...marks]..sort((a, b) => a.positionMs.compareTo(b.positionMs));
