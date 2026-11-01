import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';

// Windows app only.

/// Something you rate higher or lower than your usual, such as "fantasy".
class TasteFinding {
  const TasteFinding({
    required this.kind,
    required this.label,
    required this.difference,
    required this.books,
  });

  /// "tag", "author", "format", "length" or "decade".
  final String kind;
  final String label;

  /// Stars above (positive) or below (negative) your average, after
  /// allowing for how few books it is based on.
  final double difference;
  final int books;

  /// For example "You rate fantasy 0.6 stars higher (8 books)".
  String describe() {
    final amount = difference.abs().toStringAsFixed(1);
    final direction = difference > 0 ? 'higher' : 'lower';
    final what = switch (kind) {
      'author' => 'books by $label',
      'format' => '${label.toLowerCase()}s',
      'length' => label,
      'decade' => 'books from $label',
      _ => label,
    };
    return 'You rate $what $amount ${amount == '1.0' ? 'star' : 'stars'} '
        '$direction ($books ${books == 1 ? 'book' : 'books'})';
  }
}

/// What your ratings say about your taste.
class TasteProfile {
  const TasteProfile({
    required this.average,
    required this.ratedBooks,
    required this.likes,
    required this.dislikes,
  });

  final double average;
  final int ratedBooks;

  /// Rated higher than usual, most first.
  final List<TasteFinding> likes;

  /// Rated lower than usual, most first.
  final List<TasteFinding> dislikes;
}

String _lengthLabel(int pages) => pages < 250
    ? 'short books (under 250 pages)'
    : pages < 400
        ? 'books of 250 to 400 pages'
        : pages < 600
            ? 'books of 400 to 600 pages'
            : 'long books (600+ pages)';

/// Your taste from the books you finished (or gave up on) and rated. Each
/// tag, author, format, length and decade with enough rated books is
/// compared with your average, and pulled towards it when it is based on
/// few books, so one 5-star book does not make a pattern. Null with fewer
/// than [minimumRated] rated books.
TasteProfile? tasteProfile(
  List<Book> books, {
  int minimumRated = 5,
  int minimumGroup = 3,
  double threshold = 0.25,
}) {
  final rated = [
    for (final book in books)
      if (book.deletedAt == null &&
          book.rating != null &&
          (book.shelf == Shelf.finished || book.shelf == Shelf.unfinished))
        book,
  ];
  if (rated.length < minimumRated) return null;
  final average =
      rated.fold<int>(0, (sum, b) => sum + b.rating!) / rated.length;

  final groups = <String, List<int>>{};
  final labels = <String, String>{};
  void add(String kind, String key, String label, int rating) {
    final id = '$kind|$key';
    groups.putIfAbsent(id, () => []).add(rating);
    labels.putIfAbsent(id, () => label);
  }

  for (final book in rated) {
    final rating = book.rating!;
    for (final tag in book.tags) {
      add('tag', tag.trim().toLowerCase(), tag.trim(), rating);
    }
    if (book.author.trim().isNotEmpty) {
      add('author', book.author.trim().toLowerCase(), book.author.trim(), rating);
    }
    if (book.format != null) {
      add('format', book.format!.name, book.format!.label, rating);
    }
    final pages = book.pages;
    if (pages != null && pages > 0) {
      final label = _lengthLabel(pages);
      add('length', label, label, rating);
    }
    final year = book.firstPublishYear;
    if (year != null && year > 0) {
      final decade = '${year ~/ 10 * 10}s';
      add('decade', decade, 'the $decade', rating);
    }
  }

  final findings = <TasteFinding>[];
  for (final entry in groups.entries) {
    final ratings = entry.value;
    if (ratings.length < minimumGroup || ratings.length == rated.length) {
      continue;
    }
    final mean = ratings.fold<int>(0, (s, r) => s + r) / ratings.length;
    // Shrink towards your average: worth n / (n + 3) of the difference.
    final shrunk = (mean - average) * ratings.length / (ratings.length + 3);
    if (shrunk.abs() < threshold) continue;
    findings.add(TasteFinding(
      kind: entry.key.split('|').first,
      label: labels[entry.key]!,
      difference: shrunk,
      books: ratings.length,
    ));
  }
  findings.sort((a, b) => b.difference.abs().compareTo(a.difference.abs()));
  return TasteProfile(
    average: average,
    ratedBooks: rated.length,
    likes: [
      for (final f in findings)
        if (f.difference > 0) f,
    ].take(5).toList(),
    dislikes: [
      for (final f in findings)
        if (f.difference < 0) f,
    ].take(5).toList(),
  );
}
