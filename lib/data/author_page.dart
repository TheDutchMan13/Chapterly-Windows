import '../models/book.dart';
import '../models/shelf.dart';

// The same code is in the Windows app; keep the two copies alike.

/// A name in lower case with punctuation and spaces removed, so
/// "J.R.R. Tolkien" and "J. R. R. Tolkien" match.
String authorKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// The people in an author field: "Terry Pratchett & Neil Gaiman" is two.
List<String> authorNames(String author) => [
      for (final part in author.split(RegExp(r'\s*(?:,|&|;|\band\b)\s*')))
        if (part.trim().isNotEmpty) part.trim(),
    ];

/// Your books with [author] among their authors, newest first by when you
/// finished or added them.
List<Book> booksByAuthor(List<Book> books, String author) {
  final key = authorKey(author);
  if (key.isEmpty) return const [];
  final found = [
    for (final book in books)
      if (book.deletedAt == null &&
          (authorKey(book.author) == key ||
              authorNames(book.author).any((name) => authorKey(name) == key)))
        book,
  ];
  DateTime when(Book book) => book.finishedAt ?? book.addedAt;
  found.sort((a, b) => when(b).compareTo(when(a)));
  return found;
}

/// What you have read by one author.
class AuthorSummary {
  const AuthorSummary({
    required this.owned,
    required this.finished,
    required this.reading,
    required this.waiting,
    required this.averageRating,
    required this.pagesRead,
  });

  /// Every book you have by them, wishlist included.
  final int owned;

  /// Books you have finished, counting re-reads once.
  final int finished;
  final int reading;

  /// On For later or the wishlist.
  final int waiting;

  /// Your average rating of their books, or null if none are rated.
  final double? averageRating;
  final int pagesRead;

  String describe() {
    final parts = [
      '$owned ${owned == 1 ? 'book' : 'books'}',
      '$finished finished',
      if (reading > 0) '$reading reading',
      if (waiting > 0) '$waiting waiting',
      if (averageRating case final rating?)
        'average ${rating.toStringAsFixed(1)}★',
      if (pagesRead > 0) '$pagesRead pages read',
    ];
    return parts.join(' · ');
  }
}

AuthorSummary summarizeAuthor(List<Book> books) {
  final ratings = [
    for (final book in books) ?book.rating,
  ];
  final finished = [
    for (final book in books)
      if (book.shelf == Shelf.finished || book.previousReadings.isNotEmpty)
        book,
  ];
  return AuthorSummary(
    owned: books.length,
    finished: finished.length,
    reading: books.where((b) => b.shelf == Shelf.inProgress).length,
    waiting: books
        .where((b) => b.shelf == Shelf.forLater || b.shelf == Shelf.wishlist)
        .length,
    averageRating: ratings.isEmpty
        ? null
        : ratings.reduce((a, b) => a + b) / ratings.length,
    pagesRead: finished.fold(0, (sum, book) => sum + (book.pages ?? 0)),
  );
}
