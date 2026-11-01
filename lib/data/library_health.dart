import '../models/book.dart';
import '../models/shelf.dart';

// Windows app only.

/// Digits (and a final X) of an ISBN, without dashes and spaces.
String isbnDigits(String text) =>
    text.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();

/// Whether [text] is a real ISBN-10 or ISBN-13: the right length and the
/// check digit adds up.
bool isValidIsbn(String text) {
  final digits = isbnDigits(text);
  if (digits.length == 10) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final c = digits[i];
      final value = c == 'X' ? (i == 9 ? 10 : -1) : int.parse(c);
      if (value < 0) return false;
      sum += value * (10 - i);
    }
    return sum % 11 == 0;
  }
  if (digits.length == 13 && !digits.contains('X')) {
    var sum = 0;
    for (var i = 0; i < 13; i++) {
      sum += int.parse(digits[i]) * (i.isEven ? 1 : 3);
    }
    return sum % 10 == 0;
  }
  return false;
}

/// The ISBN-13 for a valid ISBN-10 (978 in front, new check digit), or
/// null.
String? isbn10To13(String text) {
  final digits = isbnDigits(text);
  if (digits.length != 10 || !isValidIsbn(digits)) return null;
  final body = '978${digits.substring(0, 9)}';
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(body[i]) * (i.isEven ? 1 : 3);
  }
  return '$body${(10 - sum % 10) % 10}';
}

/// Kinds of problems, in the order they are shown.
enum HealthIssueKind {
  badIsbn('ISBN is not valid', 'The check digit does not add up; it may have a typo.'),
  oldIsbn('ISBN-10 can become ISBN-13', 'Most sites now use the 13-digit form.'),
  noFinishDate('Finished without a finish date', 'Left out of yearly and monthly statistics.'),
  finishBeforeStart('Finished before it was started', 'One of the dates is probably wrong.'),
  noStartDate('Reading without a start date', 'The finish forecast and pace need one.'),
  pageBeyondEnd('Current page past the last page', 'The page count or current page is wrong.'),
  noPages('No page count', 'Needed for progress, pace and reading time.'),
  noAuthor('No author', 'Matching files and finding duplicates use it.'),
  noCover('No cover', 'Try Refresh details from Open Library.'),
  ratedUnread('Rated but not read', 'A book on For later with stars.');

  const HealthIssueKind(this.title, this.hint);

  final String title;
  final String hint;
}

/// One problem with one book.
class HealthIssue {
  const HealthIssue(this.kind, this.book);

  final HealthIssueKind kind;
  final Book book;
}

/// Everything that looks wrong or missing in the library, by kind.
Map<HealthIssueKind, List<Book>> checkLibrary(List<Book> books) {
  final issues = {for (final kind in HealthIssueKind.values) kind: <Book>[]};
  for (final book in books) {
    if (book.deletedAt != null) continue;
    final isbn = book.isbn;
    if (isbn != null && isbn.trim().isNotEmpty) {
      if (!isValidIsbn(isbn)) {
        issues[HealthIssueKind.badIsbn]!.add(book);
      } else if (isbnDigits(isbn).length == 10) {
        issues[HealthIssueKind.oldIsbn]!.add(book);
      }
    }
    final read = book.shelf == Shelf.finished;
    final reading = book.shelf == Shelf.inProgress;
    if (read && book.finishedAt == null) {
      issues[HealthIssueKind.noFinishDate]!.add(book);
    }
    final started = book.startedAt;
    final finished = book.finishedAt;
    if (started != null && finished != null && finished.isBefore(started)) {
      issues[HealthIssueKind.finishBeforeStart]!.add(book);
    }
    if (reading && started == null) {
      issues[HealthIssueKind.noStartDate]!.add(book);
    }
    final page = book.currentPage;
    final pages = book.pages;
    if (reading && page != null && pages != null && page > pages) {
      issues[HealthIssueKind.pageBeyondEnd]!.add(book);
    }
    if ((read || reading) && (pages == null || pages <= 0) && book.audio == null) {
      issues[HealthIssueKind.noPages]!.add(book);
    }
    if (book.author.trim().isEmpty) issues[HealthIssueKind.noAuthor]!.add(book);
    if ((book.coverUrl ?? '').trim().isEmpty) {
      issues[HealthIssueKind.noCover]!.add(book);
    }
    if (book.shelf == Shelf.forLater && book.rating != null) {
      issues[HealthIssueKind.ratedUnread]!.add(book);
    }
  }
  issues.removeWhere((_, list) => list.isEmpty);
  return issues;
}
