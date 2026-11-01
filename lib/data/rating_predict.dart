import '../models/book.dart';
import '../models/shelf.dart';
import 'recommend.dart';

// Windows app only.

/// A guess at the stars you would give a book.
class PredictedRating {
  const PredictedRating({required this.stars, required this.basedOn});

  /// From 1 to 5.
  final double stars;

  /// How many similar rated books it comes from.
  final int basedOn;

  /// For example "You'd probably give this 4.2★ (from 6 similar books)".
  String describe() => "You'd probably give this ${stars.toStringAsFixed(1)}★ "
      '(from $basedOn similar ${basedOn == 1 ? 'book' : 'books'})';
}

/// Rated books, finished or given up on.
List<Book> _rated(List<Book> books) => [
      for (final book in books)
        if (book.deletedAt == null &&
            book.rating != null &&
            (book.shelf == Shelf.finished || book.shelf == Shelf.unfinished))
          book,
    ];

/// Predicts the stars for [book] from the [neighbours] rated books most like
/// it (k nearest neighbours): your average, moved by how those books
/// differ from your average, the closer ones counting more. Null with fewer
/// than [minimumRated] rated books, or when nothing rated is much like it.
PredictedRating? predictRating(
  List<Book> library,
  Book book, {
  BookFeatures? features,
  int neighbours = 10,
  int minimumRated = 5,
}) {
  final rated = [
    for (final other in _rated(library))
      if (other.id != book.id) other,
  ];
  if (rated.length < minimumRated) return null;
  final f = features ?? BookFeatures.of([...library, book]);
  final average =
      rated.fold<int>(0, (sum, b) => sum + b.rating!) / rated.length;
  final scored = [
    for (final other in rated) (other, f.similarity(book.id, other.id)),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  final near = [
    for (final pair in scored.take(neighbours))
      if (pair.$2 >= 0.1) pair,
  ];
  if (near.isEmpty) return null;
  var weights = 0.0;
  var shift = 0.0;
  for (final (other, s) in near) {
    final w = s;
    weights += w;
    shift += w * (other.rating! - average);
  }
  if (weights < 0.1) return null;
  // Little in common pulls the guess towards your average.
  final confidence = weights / (weights + 0.5);
  final stars = (average + confidence * shift / weights).clamp(1.0, 5.0);
  return PredictedRating(stars: stars, basedOn: near.length);
}
