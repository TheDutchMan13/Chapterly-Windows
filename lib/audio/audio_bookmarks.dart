import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// Windows app only.

/// A place in an audiobook you want to find again, with your own note.
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
  final DateTime addedAt;
  final String note;

  AudioBookmark withNote(String note) => AudioBookmark(
        track: track,
        trackMs: trackMs,
        positionMs: positionMs,
        addedAt: addedAt,
        note: note,
      );

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

/// Every audiobook bookmark on this PC, kept in a small file.
class AudioBookmarks extends ChangeNotifier {
  AudioBookmarks({this.file});

  final File? file;
  final _marks = <String, List<AudioBookmark>>{};

  static Future<AudioBookmarks> load(File file) async {
    final store = AudioBookmarks(file: file);
    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          for (final entry in json.entries) {
            final list = entry.value;
            if (entry.key is! String || list is! List) continue;
            store._marks[entry.key as String] = [
              for (final item in list)
                ?AudioBookmark.fromJson(item),
            ];
          }
        }
      }
    } catch (_) {
      // An unreadable file: start with no bookmarks.
    }
    return store;
  }

  /// A book's bookmarks, from the start of the book.
  List<AudioBookmark> forBook(String bookId) {
    final list = [...?_marks[bookId]]
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    return list;
  }

  Future<void> add(String bookId, AudioBookmark mark) {
    _marks[bookId] = [...?_marks[bookId], mark];
    return _changed();
  }

  Future<void> setNote(String bookId, AudioBookmark mark, String note) {
    _marks[bookId] = [
      for (final m in _marks[bookId] ?? const <AudioBookmark>[])
        m.addedAt == mark.addedAt ? m.withNote(note.trim()) : m,
    ];
    return _changed();
  }

  Future<void> remove(String bookId, AudioBookmark mark) {
    final left = [
      for (final m in _marks[bookId] ?? const <AudioBookmark>[])
        if (m.addedAt != mark.addedAt) m,
    ];
    if (left.isEmpty) {
      _marks.remove(bookId);
    } else {
      _marks[bookId] = left;
    }
    return _changed();
  }

  Future<void> _changed() async {
    notifyListeners();
    final target = file;
    if (target == null) return;
    try {
      await target.writeAsString(jsonEncode({
        for (final entry in _marks.entries)
          entry.key: [for (final m in entry.value) m.toJson()],
      }));
    } catch (_) {
      // Not saved; the bookmarks stay until Chapterly closes.
    }
  }
}

/// The bookmarks for the whole app, set up in main.dart. Null in tests.
class AudioBookmarking {
  AudioBookmarking._();

  static AudioBookmarks? store;
}
