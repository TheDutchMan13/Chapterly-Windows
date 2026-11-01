import 'dart:math' as math;

import '../ebook/ebook_library.dart';
import '../models/book.dart';
import '../models/shelf.dart';

// Windows app only.

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

/// A book on In progress that has not moved for a while.
class StalledBook {
  const StalledBook({
    required this.book,
    required this.lastActive,
    required this.idleDays,
    required this.usualGap,
  });

  final Book book;
  final DateTime lastActive;
  final int idleDays;

  /// Your usual number of days between reading sessions.
  final int usualGap;

  String describe() => 'Not touched for $idleDays days '
      '(you usually pick a book up again within $usualGap)';
}

/// Every day you read anything: reading log days and reader days.
List<DateTime> _activeDays(Book book, EbookLink? ebook) => {
      for (final entry in book.readingLog)
        if (entry.pages > 0 || entry.minutes > 0) _day(entry.date),
      for (final day in ebook?.days ?? const <EbookDay>[])
        if (day.minutes > 0) _day(day.day),
    }.toList()
      ..sort();

int _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Books on In progress you seem to have stopped reading. "A while" is
/// your own rhythm: three times your usual gap between reading days (the
/// median over your whole library), and never less than [minimumDays].
/// Without any log, the start date counts as the last activity. Books in
/// [snoozed] (book id to the day you said "keep") wait another full
/// stretch from that day.
List<StalledBook> stalledBooks(
  List<Book> books, {
  Map<String, EbookLink> ebooks = const {},
  Map<String, DateTime> snoozed = const {},
  int minimumDays = 14,
  DateTime? now,
}) {
  final today = _day(now ?? DateTime.now());
  final gaps = <int>[];
  for (final book in books) {
    if (book.deletedAt != null) continue;
    final days = _activeDays(book, ebooks[book.id]);
    for (var i = 1; i < days.length; i++) {
      final gap = days[i].difference(days[i - 1]).inDays;
      if (gap > 0) gaps.add(gap);
    }
  }
  final usual = gaps.isEmpty ? 3 : _median(gaps);
  final limit = math.max(minimumDays, usual * 3);
  final stalled = <StalledBook>[];
  for (final book in books) {
    if (book.deletedAt != null || book.shelf != Shelf.inProgress) continue;
    final days = _activeDays(book, ebooks[book.id]);
    var last = days.isNotEmpty
        ? days.last
        : _day(book.startedAt ?? book.updatedAt);
    final snooze = snoozed[book.id];
    if (snooze != null && snooze.isAfter(last)) last = _day(snooze);
    final idle = today.difference(last).inDays;
    if (idle >= limit) {
      stalled.add(StalledBook(
        book: book,
        lastActive: last,
        idleDays: idle,
        usualGap: usual,
      ));
    }
  }
  stalled.sort((a, b) => b.idleDays.compareTo(a.idleDays));
  return stalled;
}
