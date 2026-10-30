import '../models/book.dart';

class MergedLibrary {
  const MergedLibrary({required this.books, required this.tombstones});

  final List<Book> books;
  final Map<String, DateTime> tombstones;
}

/// Combines the library on this phone with the one from the PC.
///
/// For each book the copy changed most recently wins. A book that was
/// permanently deleted on either device stays deleted, unless it was changed
/// after the deletion.
MergedLibrary mergeLibraries({
  required List<Book> local,
  required Map<String, DateTime> localTombstones,
  required List<Book> remote,
  required Map<String, DateTime> remoteTombstones,
}) {
  final tombstones = <String, DateTime>{};
  for (final source in [localTombstones, remoteTombstones]) {
    for (final entry in source.entries) {
      final existing = tombstones[entry.key];
      if (existing == null || entry.value.isAfter(existing)) {
        tombstones[entry.key] = entry.value;
      }
    }
  }

  final winners = <String, Book>{};
  // Local copies come first, so they win a tie.
  for (final book in [...local, ...remote]) {
    final current = winners[book.id];
    if (current == null || book.updatedAt.isAfter(current.updatedAt)) {
      winners[book.id] = book;
    }
  }

  final kept = <String, DateTime>{};
  for (final entry in tombstones.entries) {
    final book = winners[entry.key];
    if (book == null || !book.updatedAt.isAfter(entry.value)) {
      kept[entry.key] = entry.value;
    }
  }

  final books = [
    for (final book in winners.values)
      if (!kept.containsKey(book.id)) book,
  ];
  return MergedLibrary(books: books, tombstones: kept);
}
