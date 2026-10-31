import 'ebook_library.dart';

// The same file is in the Android and the Windows app.

/// Time in the reader with one book, and how fast you read it there.
class ReaderBookStats {
  const ReaderBookStats({
    required this.minutes,
    required this.daysRead,
    this.pagesPerHour,
  });

  final int minutes;
  final int daysRead;

  /// Null until there is enough reading (10 minutes) and the book's pages
  /// are known.
  final double? pagesPerHour;
}

/// The pages to count a book file by: a PDF's own pages, or the book's.
int? _pagesOf(EbookLink link, int? bookPages) {
  final pages =
      link.format == EbookFormat.pdf ? (link.pageCount ?? bookPages) : bookPages;
  return pages != null && pages > 0 ? pages : null;
}

double? _pace(double progress, int minutes, int? pages) {
  if (pages == null || minutes < 10 || progress <= 0) return null;
  return progress * pages / (minutes / 60);
}

ReaderBookStats readerStatsFor(EbookLink link, {int? bookPages}) {
  var minutes = 0;
  var progress = 0.0;
  for (final day in link.days) {
    minutes += day.minutes;
    progress += day.progress;
  }
  return ReaderBookStats(
    minutes: minutes,
    daysRead: link.days.where((d) => d.minutes > 0).length,
    pagesPerHour: _pace(progress, minutes, _pagesOf(link, bookPages)),
  );
}

/// Time in the reader over all books on this device.
class ReaderSummary {
  const ReaderSummary({
    required this.totalMinutes,
    required this.lastWeekMinutes,
    required this.daysRead,
    required this.longestStreak,
    required this.topBooks,
    this.pagesPerHour,
  });

  final int totalMinutes;

  /// The last 7 days, today included.
  final int lastWeekMinutes;
  final int daysRead;

  /// The most days in a row with time in the reader.
  final int longestStreak;

  /// Books by time in the reader, most first, up to 5.
  final List<(String bookId, int minutes)> topBooks;
  final double? pagesPerHour;

  bool get isEmpty => totalMinutes == 0;
}

ReaderSummary readerSummary(
  Map<String, EbookLink> links, {
  required int? Function(String bookId) bookPages,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final weekStart = DateTime(today.year, today.month, today.day - 6);
  final days = <DateTime>{};
  final perBook = <(String, int)>[];
  var total = 0;
  var week = 0;
  var paceMinutes = 0;
  var pacePages = 0.0;
  for (final entry in links.entries) {
    final link = entry.value;
    final pages = _pagesOf(link, bookPages(entry.key));
    var bookMinutes = 0;
    for (final day in link.days) {
      if (day.minutes <= 0) continue;
      bookMinutes += day.minutes;
      days.add(day.day);
      if (!day.day.isBefore(weekStart)) week += day.minutes;
      if (pages != null) {
        paceMinutes += day.minutes;
        pacePages += day.progress * pages;
      }
    }
    total += bookMinutes;
    if (bookMinutes > 0) perBook.add((entry.key, bookMinutes));
  }
  perBook.sort((a, b) => b.$2.compareTo(a.$2));
  return ReaderSummary(
    totalMinutes: total,
    lastWeekMinutes: week,
    daysRead: days.length,
    longestStreak: longestRun(days),
    topBooks: perBook.take(5).toList(),
    pagesPerHour: paceMinutes < 10 || pacePages <= 0
        ? null
        : pacePages / (paceMinutes / 60),
  );
}

/// The most days in a row in [days] (each a midnight).
int longestRun(Iterable<DateTime> days) {
  final set = {for (final d in days) DateTime(d.year, d.month, d.day)};
  var best = 0;
  for (final day in set) {
    final before = DateTime(day.year, day.month, day.day - 1);
    if (set.contains(before)) continue;
    var run = 1;
    var next = DateTime(day.year, day.month, day.day + 1);
    while (set.contains(next)) {
      run++;
      next = DateTime(next.year, next.month, next.day + 1);
    }
    if (run > best) best = run;
  }
  return best;
}

/// How much new reading a move to [progress] counts as, given [mark], the
/// furthest place reached so far. Going back counts as nothing, and so
/// does a big jump forward (the slider, the contents), which is not
/// reading.
({double read, double mark}) newReading(double mark, double progress) {
  if (progress.isNaN || progress <= mark) return (read: 0, mark: mark);
  final step = progress - mark;
  return (read: step > 0.15 ? 0 : step, mark: progress);
}

/// "About 42 pages an hour".
String pagesPerHourText(double pace) => 'About ${pace.round()} pages an hour';
