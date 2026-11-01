import 'dart:math' as math;

import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import 'fuzzy.dart';

// Windows app only.

/// What a book is like, as weighted features: its author, tags, series,
/// format, length and decade. Rare features (a tag on 3 books) count more
/// than common ones (a tag on half the library).
class BookFeatures {
  BookFeatures._(this._vectors, this._names);

  final Map<String, Map<String, double>> _vectors;

  /// A readable name for each feature, such as "fantasy" or "Brandon
  /// Sanderson".
  final Map<String, String> _names;

  static const _authorWeight = 1.6;
  static const _seriesWeight = 2.0;
  static const _tagWeight = 1.0;
  static const _formatWeight = 0.3;
  static const _lengthWeight = 0.3;
  static const _decadeWeight = 0.25;

  static String _lengthBucket(int pages) => pages < 250
      ? 'short'
      : pages < 400
          ? 'medium'
          : pages < 600
              ? 'long'
              : 'very long';

  static Map<String, double> _raw(Book book, Map<String, String> names) {
    final features = <String, double>{};
    void add(String key, double weight, String name) {
      features[key] = (features[key] ?? 0) + weight;
      names.putIfAbsent(key, () => name);
    }

    final author = foldText(book.author);
    if (author.isNotEmpty) add('a:$author', _authorWeight, book.author.trim());
    final series = foldText(book.series ?? '');
    if (series.isNotEmpty) add('s:$series', _seriesWeight, book.series!.trim());
    for (final tag in book.tags) {
      final key = foldText(tag);
      if (key.isNotEmpty) add('t:$key', _tagWeight, tag.trim());
    }
    final format = book.format;
    if (format != null) add('f:${format.name}', _formatWeight, format.label);
    final pages = book.pages;
    if (pages != null && pages > 0) {
      final bucket = _lengthBucket(pages);
      add('l:$bucket', _lengthWeight, '$bucket books');
    }
    final year = book.firstPublishYear;
    if (year != null && year > 0) {
      final decade = year ~/ 10 * 10;
      add('d:$decade', _decadeWeight, 'the ${decade}s');
    }
    return features;
  }

  /// Features for every book in [books] (not in the trash).
  factory BookFeatures.of(List<Book> books) {
    final names = <String, String>{};
    final raw = <String, Map<String, double>>{};
    final counts = <String, int>{};
    for (final book in books) {
      if (book.deletedAt != null) continue;
      final features = _raw(book, names);
      raw[book.id] = features;
      for (final key in features.keys) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    final n = raw.length;
    final vectors = <String, Map<String, double>>{};
    for (final entry in raw.entries) {
      final vector = <String, double>{};
      var norm = 0.0;
      for (final feature in entry.value.entries) {
        final idf = math.log((n + 1) / (counts[feature.key]! + 1)) + 1;
        final value = feature.value * idf;
        vector[feature.key] = value;
        norm += value * value;
      }
      norm = math.sqrt(norm);
      if (norm > 0) {
        vector.updateAll((_, value) => value / norm);
      }
      vectors[entry.key] = vector;
    }
    return BookFeatures._(vectors, names);
  }

  Map<String, double> vectorOf(String bookId) => _vectors[bookId] ?? const {};

  String nameOf(String feature) => _names[feature] ?? feature;

  /// From 0 (nothing in common) to 1 (alike in every way).
  double similarity(String a, String b) => _dot(vectorOf(a), vectorOf(b));
}

double _dot(Map<String, double> a, Map<String, double> b) {
  final small = a.length <= b.length ? a : b;
  final large = identical(small, a) ? b : a;
  var sum = 0.0;
  for (final entry in small.entries) {
    final other = large[entry.key];
    if (other != null) sum += entry.value * other;
  }
  return sum;
}

/// How much a book you have read says about your taste: stars above 3 count
/// for it, below 3 against, a finished book without stars a little for it,
/// a favorite more, and a book you gave up on against.
double tasteWeight(Book book) {
  if (book.deletedAt != null) return 0;
  var weight = 0.0;
  final rating = book.rating;
  if (rating != null && (book.shelf == Shelf.finished || book.shelf == Shelf.unfinished)) {
    weight = rating - 3.0;
  } else if (book.shelf == Shelf.finished || book.previousReadings.isNotEmpty) {
    weight = 0.5;
  } else if (book.shelf == Shelf.unfinished) {
    weight = -1;
  }
  if (book.favorite) weight += 1;
  return weight;
}

/// A suggested book, and why.
class Recommendation {
  const Recommendation({
    required this.book,
    required this.score,
    this.becauseOf,
    this.reasons = const [],
    this.nextInSeries = false,
  });

  final Book book;
  final double score;

  /// The book you liked that is most like this one.
  final Book? becauseOf;

  /// What it has in common with books you liked, such as "fantasy".
  final List<String> reasons;

  /// It is the next book of a series you are reading.
  final bool nextInSeries;

  /// For example "Next in a series you are reading" or "Because you liked
  /// Mistborn · fantasy, Brandon Sanderson".
  String describe() {
    final parts = <String>[
      if (nextInSeries) 'Next in a series you are reading',
      if (!nextInSeries && becauseOf != null)
        'Because you liked ${becauseOf!.title}',
      if (reasons.isNotEmpty) reasons.join(', '),
    ];
    return parts.isEmpty ? 'Something different' : parts.join(' · ');
  }
}

/// Whether [book] is the next unread number of a series where you finished
/// (or are reading) the one before it, and did not dislike it.
bool _isNextInSeries(Book book, List<Book> books) {
  final series = foldText(book.series ?? '');
  final number = book.seriesNumber;
  if (series.isEmpty || number == null) return false;
  return books.any((other) =>
      other.deletedAt == null &&
      other.id != book.id &&
      foldText(other.series ?? '') == series &&
      other.seriesNumber == number - 1 &&
      (other.shelf == Shelf.finished || other.shelf == Shelf.inProgress) &&
      tasteWeight(other) >= 0);
}

/// [candidates] ranked by how well they fit your taste, worked out from
/// every book in [books] you have read, rated or given up on. With nothing
/// to go on yet, the next books of series you are reading come first, then
/// the oldest wishes.
List<Recommendation> recommend(List<Book> books, List<Book> candidates) {
  final features = BookFeatures.of([...books, ...candidates]);
  final profile = <String, double>{};
  final liked = <Book>[];
  for (final book in books) {
    final weight = tasteWeight(book);
    if (weight == 0) continue;
    if (weight > 0) liked.add(book);
    features.vectorOf(book.id).forEach((key, value) {
      profile[key] = (profile[key] ?? 0) + weight * value;
    });
  }
  var norm = 0.0;
  for (final value in profile.values) {
    norm += value * value;
  }
  norm = math.sqrt(norm);

  final results = <Recommendation>[];
  for (final book in candidates) {
    final vector = features.vectorOf(book.id);
    final fit = norm == 0 ? 0.0 : _dot(profile, vector) / norm;
    final next = _isNextInSeries(book, books);
    // What it shares with your taste, strongest first.
    final shared = [
      for (final entry in vector.entries)
        if ((profile[entry.key] ?? 0) > 0 &&
            !entry.key.startsWith('l:') &&
            !entry.key.startsWith('d:'))
          MapEntry(entry.key, entry.value * profile[entry.key]!),
    ]..sort((a, b) => b.value.compareTo(a.value));
    Book? because;
    var closest = 0.15;
    for (final other in liked) {
      if (other.id == book.id) continue;
      final s = features.similarity(book.id, other.id);
      if (s > closest) {
        closest = s;
        because = other;
      }
    }
    results.add(Recommendation(
      book: book,
      score: fit + (next ? 1 : 0),
      becauseOf: because,
      reasons: [for (final e in shared.take(2)) features.nameOf(e.key)],
      nextInSeries: next,
    ));
  }
  results.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.book.addedAt.compareTo(b.book.addedAt);
  });
  return results;
}

/// The books in [books] most like [book], best first, at most [limit], and
/// only those with something real in common.
List<(Book, double)> similarBooks(List<Book> books, Book book, {int limit = 12}) {
  final features = BookFeatures.of(books);
  final scored = <(Book, double)>[
    for (final other in books)
      if (other.deletedAt == null && other.id != book.id)
        (other, features.similarity(book.id, other.id)),
  ]..removeWhere((pair) => pair.$2 < 0.12);
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.take(limit).toList();
}
