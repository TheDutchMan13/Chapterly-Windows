import '../models/book.dart';
import '../models/reading.dart';
import 'statistics.dart';

/// The numbers for one year's "year in review" card.
class YearReview {
  const YearReview({
    required this.year,
    required this.stats,
    required this.topRated,
    required this.busiestMonth,
    required this.longestStreak,
  });

  final int year;
  final BookStats stats;

  /// Up to three books finished this year, best rated first.
  final List<Book> topRated;

  /// 1 for January to 12 for December, or null if nothing was finished.
  final int? busiestMonth;

  /// The most days in a row with something in the reading log this year.
  final int longestStreak;
}

int _longestStreak(List<Book> books, int year) {
  final days = <DateTime>{};
  for (final book in books) {
    final entries = <LogEntry>[
      ...book.readingLog,
      for (final reading in book.previousReadings) ...reading.log,
    ];
    for (final entry in entries) {
      if (entry.date.year != year) continue;
      if (entry.pages <= 0 && entry.minutes <= 0) continue;
      days.add(DateTime(entry.date.year, entry.date.month, entry.date.day));
    }
  }
  var longest = 0;
  for (final day in days) {
    final before = DateTime(day.year, day.month, day.day - 1);
    if (days.contains(before)) continue; // not the start of a run
    var length = 1;
    var next = DateTime(day.year, day.month, day.day + 1);
    while (days.contains(next)) {
      length++;
      next = DateTime(next.year, next.month, next.day + 1);
    }
    if (length > longest) longest = length;
  }
  return longest;
}

YearReview computeYearReview(List<Book> books, int year) {
  final stats = computeStats(books, year: year);

  final rated = <(Book, int)>[];
  for (final book in books) {
    int? best;
    for (final reading in book.finishedReadings) {
      final rating = reading.rating;
      if (reading.finishedAt?.year == year && rating != null) {
        if (best == null || rating > best) best = rating;
      }
    }
    if (best != null) rated.add((book, best));
  }
  rated.sort((a, b) {
    final byRating = b.$2.compareTo(a.$2);
    return byRating != 0
        ? byRating
        : a.$1.title.toLowerCase().compareTo(b.$1.title.toLowerCase());
  });

  var busiest = 0;
  for (var i = 1; i < 12; i++) {
    if (stats.byMonth[i] > stats.byMonth[busiest]) busiest = i;
  }

  return YearReview(
    year: year,
    stats: stats,
    topRated: [for (final item in rated.take(3)) item.$1],
    busiestMonth: stats.byMonth[busiest] > 0 ? busiest + 1 : null,
    longestStreak: _longestStreak(books, year),
  );
}
