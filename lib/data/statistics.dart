import '../models/book.dart';
import '../models/book_format.dart';
import '../models/reading.dart';
import '../models/shelf.dart';
import 'date_format.dart';

class BookStats {
  const BookStats({
    required this.finishedCount,
    required this.pagesRead,
    required this.averageRating,
    required this.averagePages,
    required this.longest,
    required this.byMonth,
    required this.byYear,
    required this.pagesByMonth,
    required this.pagesByYear,
    required this.shelfCounts,
    required this.finishedWithoutDate,
    required this.loggedPages,
    required this.loggedMinutes,
    required this.loggedByMonth,
    required this.formatCounts,
    required this.ratingCounts,
    required this.topAuthors,
    required this.topTags,
  });

  /// Finished readings in the chosen year (or ever, when no year is chosen).
  /// A book that was read twice counts twice.
  final int finishedCount;
  final int pagesRead;
  final double? averageRating;
  final int? averagePages;
  final Book? longest;

  /// Finished readings per month (index 0 is January) in the chosen year.
  final List<int> byMonth;

  /// Finished readings per year, oldest first. Always covers every year.
  final Map<int, int> byYear;

  /// Pages of the books finished per month (index 0 is January) in the
  /// chosen year. Books with no page count add nothing.
  final List<int> pagesByMonth;

  /// Pages of the books finished per year, for the same years as [byYear].
  final Map<int, int> pagesByYear;
  final Map<Shelf, int> shelfCounts;

  /// Finished readings that have no finish date, so no month or year.
  final int finishedWithoutDate;

  /// Pages written down in the reading log, in the chosen year or ever.
  final int loggedPages;

  /// Minutes spent reading, from the reading log.
  final int loggedMinutes;

  /// Logged pages per month (index 0 is January).
  final List<int> loggedByMonth;

  /// Finished readings per book format. Books without a format are left out.
  final Map<BookFormat, int> formatCounts;

  /// Finished readings per star rating (keys 1 to 5, always all present).
  final Map<int, int> ratingCounts;

  /// The authors with the most finished readings, most first (up to 5).
  final List<MapEntry<String, int>> topAuthors;

  /// The tags with the most finished readings, most first (up to 5).
  final List<MapEntry<String, int>> topTags;

  List<int> get yearsNewestFirst =>
      byYear.keys.toList()..sort((a, b) => b.compareTo(a));
}

BookStats computeStats(List<Book> books, {int? year}) {
  final all = <(Book, Reading)>[
    for (final book in books)
      for (final reading in book.finishedReadings) (book, reading),
  ];
  final finished = [
    for (final item in all)
      if (year == null || item.$2.finishedAt?.year == year) item,
  ];

  var pagesRead = 0;
  Book? longest;
  final ratings = <int>[];
  final pageCounts = <int>[];
  final formatCounts = <BookFormat, int>{};
  final ratingCounts = {for (var star = 1; star <= 5; star++) star: 0};
  final authorCounts = <String, int>{};
  final authorNames = <String, String>{};
  final tagCounts = <String, int>{};
  final tagNames = <String, String>{};
  final byMonth = List<int>.filled(12, 0);
  final pagesByMonth = List<int>.filled(12, 0);
  for (final (book, reading) in finished) {
    final pages = book.pages;
    if (pages != null) {
      pagesRead += pages;
      pageCounts.add(pages);
      if (pages > (longest?.pages ?? 0)) longest = book;
    }
    final rating = reading.rating;
    if (rating != null) {
      ratings.add(rating);
      if (ratingCounts.containsKey(rating)) {
        ratingCounts[rating] = ratingCounts[rating]! + 1;
      }
    }
    final author = book.author.trim();
    if (author.isNotEmpty) {
      final key = author.toLowerCase();
      authorNames.putIfAbsent(key, () => author);
      authorCounts[key] = (authorCounts[key] ?? 0) + 1;
    }
    for (final tag in book.tags) {
      final key = tag.toLowerCase();
      tagNames.putIfAbsent(key, () => tag);
      tagCounts[key] = (tagCounts[key] ?? 0) + 1;
    }
    final format = book.format;
    if (format != null) formatCounts[format] = (formatCounts[format] ?? 0) + 1;
    final date = reading.finishedAt;
    if (date != null) {
      byMonth[date.month - 1]++;
      if (pages != null) pagesByMonth[date.month - 1] += pages;
    }
  }

  final yearCounts = <int, int>{};
  final yearPages = <int, int>{};
  var withoutDate = 0;
  for (final (book, reading) in all) {
    final date = reading.finishedAt;
    if (date == null) {
      withoutDate++;
    } else {
      yearCounts[date.year] = (yearCounts[date.year] ?? 0) + 1;
      yearPages[date.year] = (yearPages[date.year] ?? 0) + (book.pages ?? 0);
    }
  }
  final sortedYears = yearCounts.keys.toList()..sort();

  var loggedPages = 0;
  var loggedMinutes = 0;
  final loggedByMonth = List<int>.filled(12, 0);
  for (final book in books) {
    final entries = [
      ...book.readingLog,
      for (final reading in book.previousReadings) ...reading.log,
    ];
    for (final entry in entries) {
      if (year != null && entry.date.year != year) continue;
      loggedPages += entry.pages;
      loggedMinutes += entry.minutes;
      loggedByMonth[entry.date.month - 1] += entry.pages;
    }
  }

  return BookStats(
    finishedCount: finished.length,
    pagesRead: pagesRead,
    averageRating: ratings.isEmpty
        ? null
        : ratings.reduce((a, b) => a + b) / ratings.length,
    averagePages: pageCounts.isEmpty
        ? null
        : (pageCounts.reduce((a, b) => a + b) / pageCounts.length).round(),
    longest: longest,
    byMonth: byMonth,
    byYear: {for (final y in sortedYears) y: yearCounts[y]!},
    pagesByMonth: pagesByMonth,
    pagesByYear: {for (final y in sortedYears) y: yearPages[y] ?? 0},
    shelfCounts: {
      for (final shelf in Shelf.values)
        shelf: books.where((b) => b.shelf == shelf).length,
    },
    finishedWithoutDate: withoutDate,
    loggedPages: loggedPages,
    loggedMinutes: loggedMinutes,
    loggedByMonth: loggedByMonth,
    formatCounts: formatCounts,
    ratingCounts: ratingCounts,
    topAuthors: _top(authorCounts, authorNames),
    topTags: _top(tagCounts, tagNames),
  );
}

List<MapEntry<String, int>> _top(
  Map<String, int> counts,
  Map<String, String> names,
) {
  final entries = [
    for (final entry in counts.entries) MapEntry(names[entry.key]!, entry.value),
  ];
  entries.sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    return byCount != 0
        ? byCount
        : a.key.toLowerCase().compareTo(b.key.toLowerCase());
  });
  return entries.take(5).toList();
}

Iterable<LogEntry> _allLogEntries(List<Book> books) sync* {
  for (final book in books) {
    yield* book.readingLog;
    for (final reading in book.previousReadings) {
      yield* reading.log;
    }
  }
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

/// Pages written in the reading log on [day].
int pagesLoggedOn(List<Book> books, DateTime day) {
  final target = _day(day);
  var total = 0;
  for (final entry in _allLogEntries(books)) {
    if (_day(entry.date) == target) total += entry.pages;
  }
  return total;
}

/// How many days in a row (ending today, or yesterday if nothing is logged
/// yet today) have something in the reading log.
int currentStreak(List<Book> books, {DateTime? now}) {
  final days = {
    for (final entry in _allLogEntries(books))
      if (entry.pages > 0 || entry.minutes > 0) _day(entry.date),
  };
  var day = _day(now ?? DateTime.now());
  if (!days.contains(day)) day = DateTime(day.year, day.month, day.day - 1);
  var streak = 0;
  while (days.contains(day)) {
    streak++;
    // Calendar arithmetic, so daylight saving changes cannot skip a day.
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

/// How fast a book in progress is being read, worked out from the reading log.
class ReadingPace {
  const ReadingPace({
    required this.pagesPerDay,
    required this.pagesRead,
    this.pagesLeft,
    this.daysLeft,
    this.finishEstimate,
  });

  final double pagesPerDay;
  final int pagesRead;
  final int? pagesLeft;
  final int? daysLeft;
  final DateTime? finishEstimate;

  /// For example "18.0 pages a day · about 12 days left (finish ~2026-11-09)".
  String describe() {
    final parts = ['${pagesPerDay.toStringAsFixed(1)} pages a day'];
    final left = daysLeft;
    final finish = finishEstimate;
    if (left != null && finish != null) {
      parts.add(
        left == 0
            ? 'should be finished'
            : 'about $left ${left == 1 ? 'day' : 'days'} left '
                '(finish ~${formatDate(finish)})',
      );
    }
    return parts.join(' · ');
  }
}

int _daysBetween(DateTime from, DateTime to) => DateTime.utc(to.year, to.month, to.day)
    .difference(DateTime.utc(from.year, from.month, from.day))
    .inDays;

/// The pace of a book on the In progress shelf, or null when there is
/// nothing to go on yet. Progress is the current page when it is set,
/// otherwise the pages in the reading log. Time counts from the start date or
/// the first log entry, whichever is earlier.
ReadingPace? readingPace(Book book, {DateTime? now}) {
  if (book.shelf != Shelf.inProgress) return null;
  final entries = [
    for (final entry in book.readingLog)
      if (entry.pages > 0) entry,
  ];
  final page = book.currentPage;
  final pagesRead = page != null && page > 0
      ? page
      : entries.fold<int>(0, (sum, entry) => sum + entry.pages);
  if (pagesRead <= 0) return null;
  final today = _day(now ?? DateTime.now());
  DateTime? first;
  for (final entry in entries) {
    final day = _day(entry.date);
    if (first == null || day.isBefore(first)) first = day;
  }
  final started = book.startedAt;
  if (started != null && (first == null || _day(started).isBefore(first))) {
    first = _day(started);
  }
  if (first == null) return null;
  final start = first;
  final days = _daysBetween(start, today) + 1;
  final pace = pagesRead / (days < 1 ? 1 : days);

  final total = book.pages;
  final remaining = total == null ? null : total - pagesRead;
  final pagesLeft = remaining == null ? null : (remaining < 0 ? 0 : remaining);
  final daysLeft = pagesLeft == null
      ? null
      : pagesLeft == 0
          ? 0
          : (pagesLeft / pace).ceil();
  return ReadingPace(
    pagesPerDay: pace,
    pagesRead: pagesRead,
    pagesLeft: pagesLeft,
    daysLeft: daysLeft,
    finishEstimate: daysLeft == null
        ? null
        : DateTime(today.year, today.month, today.day + daysLeft),
  );
}

/// Finished readings in [year] of books that have [tag] (ignoring capitals).
int finishedWithTag(List<Book> books, String tag, int year) {
  final key = tag.trim().toLowerCase();
  var count = 0;
  for (final book in books) {
    if (!book.tags.any((t) => t.toLowerCase() == key)) continue;
    for (final reading in book.finishedReadings) {
      if (reading.finishedAt?.year == year) count++;
    }
  }
  return count;
}

/// Progress towards a yearly reading goal.
class ChallengeStatus {
  const ChallengeStatus({
    required this.goal,
    required this.finished,
    required this.remaining,
    required this.progress,
    this.ahead,
  });

  final int goal;
  final int finished;

  /// Books still to read to reach the goal (0 once it is reached).
  final int remaining;

  /// 0.0 to 1.0, for a progress ring.
  final double progress;

  /// Books ahead of the pace needed (positive) or behind it (negative).
  /// Null for years that are not the current year.
  final int? ahead;

  /// A short sentence such as "14 to go · 2 ahead of pace". Pass a [unit]
  /// such as "pages" for goals that are not counted in books.
  String describe({String unit = ''}) {
    if (remaining == 0) return 'Goal reached!';
    final suffix = unit.isEmpty ? '' : ' $unit';
    final parts = ['$remaining$suffix to go'];
    final pace = ahead;
    if (pace != null) {
      if (pace > 0) {
        parts.add('$pace$suffix ahead of pace');
      } else if (pace < 0) {
        parts.add('${-pace}$suffix behind pace');
      } else {
        parts.add('on pace');
      }
    }
    return parts.join(' · ');
  }
}

ChallengeStatus challengeStatus({
  required int finished,
  required int goal,
  required int year,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  int? ahead;
  if (today.year == year) {
    final start = DateTime.utc(year, 1, 1);
    final dayOfYear =
        DateTime.utc(today.year, today.month, today.day).difference(start).inDays +
            1;
    final daysInYear = DateTime.utc(year + 1, 1, 1).difference(start).inDays;
    final expected = (goal * dayOfYear / daysInYear).floor();
    ahead = finished - expected;
  }
  return ChallengeStatus(
    goal: goal,
    finished: finished,
    remaining: finished >= goal ? 0 : goal - finished,
    progress: goal <= 0 ? 0 : (finished / goal).clamp(0.0, 1.0).toDouble(),
    ahead: ahead,
  );
}
