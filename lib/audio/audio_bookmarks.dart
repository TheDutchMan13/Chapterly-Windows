import 'dart:convert';
import 'dart:io';

import '../data/book_repository.dart';
import '../models/audio_bookmark.dart';

export '../models/audio_bookmark.dart';

/// Where the app keeps audiobook bookmarks: with the books, so they sync.
/// Set up in main.dart. Null in tests, which hides the bookmark buttons.
class AudioBookmarking {
  AudioBookmarking._();

  static BookRepository? repository;
}

/// Reads the bookmark file Chapterly for Windows used before 1.11.0
/// (bookmarks by book id, kept only on this PC).
Future<Map<String, List<AudioBookmark>>> readOldBookmarkFile(File file) async {
  final result = <String, List<AudioBookmark>>{};
  try {
    if (!await file.exists()) return result;
    final json = jsonDecode(await file.readAsString());
    if (json is! Map) return result;
    for (final entry in json.entries) {
      final marks = audioBookmarksFromJson(entry.value);
      if (entry.key is String && marks.isNotEmpty) {
        result[entry.key as String] = marks;
      }
    }
  } catch (_) {
    // An unreadable file: nothing to move.
  }
  return result;
}

/// Moves the bookmarks from the old file into the books, once. Bookmarks a
/// book already has (same time added) are not added twice. The old file is
/// then renamed to "audio_bookmarks.moved.json" and kept as a copy.
/// Returns how many bookmarks were moved.
Future<int> moveOldBookmarks(File file, BookRepository repository) async {
  final old = await readOldBookmarkFile(file);
  var moved = 0;
  for (final entry in old.entries) {
    for (final mark in entry.value) {
      final book = repository.byId(entry.key);
      if (book == null) break;
      if (book.audioBookmarks.any(mark.sameAs)) continue;
      await repository.addBookmark(book.id, mark);
      moved++;
    }
  }
  try {
    if (await file.exists()) {
      await file.rename(
        file.path.replaceFirst(RegExp(r'\.json$'), '.moved.json'),
      );
    }
  } catch (_) {
    // Not renamed: the next start reads it again and adds nothing twice.
  }
  return moved;
}
