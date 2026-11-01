import 'dart:math' as math;

import '../audio/audio_library.dart';
import '../ebook/ebook_library.dart';
import '../ebook/reader_stats.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import '../models/shelf.dart';
import 'date_format.dart';

// Windows app only.

/// Pages an hour when Chapterly knows nothing about your reading yet.
const averagePagesPerHour = 40.0;

/// How fast you read, in pages an hour.
class ReadingSpeed {
  const ReadingSpeed({required this.pagesPerHour, required this.yours});

  final double pagesPerHour;

  /// Worked out from your own reading (otherwise an average pace).
  final bool yours;
}

/// Your pages an hour, from reading log entries that have both pages and
/// minutes (not audiobooks) and from time in the reader, each counting by
/// its minutes. Needs at least half an hour of either; otherwise an average
/// pace.
ReadingSpeed readingSpeed(List<Book> books, {Map<String, EbookLink> ebooks = const {}}) {
  var minutes = 0.0;
  var pages = 0.0;
  for (final book in books) {
    if (book.deletedAt != null || book.format == BookFormat.audiobook) continue;
    for (final entry in book.readingLog) {
      if (entry.pages > 0 && entry.minutes > 0) {
        minutes += entry.minutes;
        pages += entry.pages;
      }
    }
  }
  if (ebooks.isNotEmpty) {
    final byId = {for (final b in books) b.id: b};
    final summary = readerSummary(ebooks, bookPages: (id) => byId[id]?.pages);
    final pace = summary.pagesPerHour;
    if (pace != null && summary.totalMinutes > 0) {
      minutes += summary.totalMinutes;
      pages += pace * summary.totalMinutes / 60;
    }
  }
  if (minutes < 30 || pages <= 0) {
    return const ReadingSpeed(pagesPerHour: averagePagesPerHour, yours: false);
  }
  final pace = (pages / minutes * 60).clamp(5.0, 200.0);
  return ReadingSpeed(pagesPerHour: pace, yours: true);
}

/// How long a book takes you.
class ReadingTime {
  const ReadingTime({
    required this.totalMinutes,
    required this.leftMinutes,
    required this.listening,
    required this.yourPace,
  });

  final int totalMinutes;

  /// What is left from where you are (the whole book if not started).
  final int leftMinutes;

  /// Worked out from the audiobook's length and your speed.
  final bool listening;

  /// At your own pace rather than an average one.
  final bool yourPace;

  /// For example "About 9 h 30 min to read · 3 h 10 min left (at your
  /// pace)".
  String describe({double? pagesPerHour}) {
    final verb = listening ? 'listen' : 'read';
    final parts = ['About ${_duration(totalMinutes)} to $verb'];
    if (leftMinutes < totalMinutes) {
      parts.add('${_duration(leftMinutes)} left');
    }
    final pace = listening
        ? null
        : pagesPerHour == null
            ? null
            : '${pagesPerHour.round()} pages an hour';
    final how = yourPace
        ? (pace == null ? 'at your speed' : 'at your $pace')
        : 'at an average $pace';
    return '${parts.join(' · ')} ($how)';
  }
}

String _duration(int minutes) =>
    minutes < 60 ? formatMinutes(math.max(1, minutes)) : formatMinutes((minutes / 5).round() * 5);

/// How long [book] takes: an audiobook by its length at your playback
/// [speed], otherwise its pages at your reading [pace]. Null without a
/// length or a page count.
ReadingTime? readingTime(
  Book book, {
  required ReadingSpeed pace,
  AudioLink? audio,
  double speed = 1,
}) {
  final length = audio?.lengthMs ?? book.audio?.lengthMs;
  final listening = length != null &&
      length > 0 &&
      (audio != null || book.format == BookFormat.audiobook);
  if (listening) {
    final total = length / 60000 / (speed <= 0 ? 1 : speed);
    final done = (book.audio?.positionMs ?? 0) / 60000 / (speed <= 0 ? 1 : speed);
    final finished = book.shelf == Shelf.finished;
    return ReadingTime(
      totalMinutes: total.round(),
      leftMinutes: finished ? 0 : math.max(0, total - done).round(),
      listening: true,
      yourPace: true,
    );
  }
  final pages = book.pages;
  if (pages == null || pages <= 0) return null;
  final total = pages / pace.pagesPerHour * 60;
  final done = book.shelf == Shelf.inProgress ? (book.progressPage ?? 0) : 0;
  final left = book.shelf == Shelf.finished
      ? 0.0
      : math.max(0, pages - done) / pace.pagesPerHour * 60;
  return ReadingTime(
    totalMinutes: total.round(),
    leftMinutes: left.round(),
    listening: false,
    yourPace: pace.yours,
  );
}

/// A book that fits the time you have, and how much of it it needs.
class TimeFit {
  const TimeFit(this.book, this.minutes);

  final Book book;
  final int minutes;
}

/// Books you could finish in [minutes]: books in progress by what is left,
/// For later books by their whole length. The closest fit (using most of
/// the time) comes first. [timeOf] gives each book's reading time.
List<TimeFit> fitsInTime(
  List<Book> books,
  int minutes,
  ReadingTime? Function(Book book) timeOf,
) {
  final fits = <TimeFit>[];
  for (final book in books) {
    if (book.deletedAt != null) continue;
    if (book.shelf != Shelf.inProgress && book.shelf != Shelf.forLater) continue;
    final time = timeOf(book);
    if (time == null) continue;
    final needed = book.shelf == Shelf.inProgress ? time.leftMinutes : time.totalMinutes;
    if (needed <= 0 || needed > minutes * 1.1) continue;
    fits.add(TimeFit(book, needed));
  }
  fits.sort((a, b) {
    // Books you are reading first, then the ones that use the time best.
    final byShelf = (a.book.shelf == Shelf.inProgress ? 0 : 1)
        .compareTo(b.book.shelf == Shelf.inProgress ? 0 : 1);
    if (byShelf != 0) return byShelf;
    return b.minutes.compareTo(a.minutes);
  });
  return fits;
}
