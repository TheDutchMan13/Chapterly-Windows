import '../models/book.dart';
import '../models/shelf.dart';

// Windows app only.

/// One series in your library: which numbers you have, which are missing,
/// and which one to read next.
class SeriesInfo {
  const SeriesInfo({
    required this.name,
    required this.author,
    required this.books,
    required this.missing,
    required this.unnumbered,
  });

  final String name;

  /// The author most of its books have.
  final String author;

  /// The numbered books, by number.
  final List<Book> books;

  /// Numbers from 1 to the highest you have that no book has.
  final List<int> missing;

  /// Books in the series without a number.
  final List<Book> unnumbered;

  int get finished =>
      [...books, ...unnumbered].where((b) => b.shelf == Shelf.finished).length;

  int get total => books.length + unnumbered.length;

  /// The first numbered book you have not finished, or null.
  Book? get next {
    for (final book in books) {
      if (book.shelf != Shelf.finished) return book;
    }
    return null;
  }

  bool get complete => missing.isEmpty && finished == total;
}

/// Every series among [books] (books in the trash are left out), by name.
/// Names that differ only in capitals or spaces are one series.
List<SeriesInfo> seriesOverview(List<Book> books) {
  final groups = <String, List<Book>>{};
  final names = <String, String>{};
  for (final book in books) {
    final name = book.series?.trim() ?? '';
    if (book.deletedAt != null || name.isEmpty) continue;
    final key = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    groups.putIfAbsent(key, () => []).add(book);
    names.putIfAbsent(key, () => name);
  }
  final result = <SeriesInfo>[];
  for (final entry in groups.entries) {
    final numbered = [
      for (final book in entry.value)
        if (book.seriesNumber != null && book.seriesNumber! > 0) book,
    ]..sort((a, b) => a.seriesNumber!.compareTo(b.seriesNumber!));
    final unnumbered = [
      for (final book in entry.value)
        if (book.seriesNumber == null || book.seriesNumber! <= 0) book,
    ];
    final have = {for (final book in numbered) book.seriesNumber!};
    final highest = have.isEmpty ? 0 : have.reduce((a, b) => a > b ? a : b);
    final authors = <String, int>{};
    for (final book in entry.value) {
      final author = book.author.trim();
      if (author.isNotEmpty) authors[author] = (authors[author] ?? 0) + 1;
    }
    final author = authors.isEmpty
        ? ''
        : (authors.entries.toList()..sort((a, b) => b.value - a.value))
            .first
            .key;
    result.add(SeriesInfo(
      name: names[entry.key]!,
      author: author,
      books: numbered,
      missing: [
        for (var n = 1; n < highest; n++)
          if (!have.contains(n)) n,
      ],
      unnumbered: unnumbered,
    ));
  }
  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}
