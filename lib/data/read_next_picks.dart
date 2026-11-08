import '../models/book.dart';
import '../models/shelf.dart';
import 'author_page.dart';
import 'series.dart' show seriesMergeKey;

// The same code is in the Windows app; keep the two copies alike.

enum ReadNextReason { nextInSeries, authorYouLike, waitingLongest }

/// A For later book with the reason it is a good one to start now.
class ReadNextPick {
  const ReadNextPick(this.book, this.reason, this.why);

  final Book book;
  final ReadNextReason reason;

  /// "Next in Mistborn: you finished #2".
  final String why;
}

bool _read(Book book) =>
    book.shelf == Shelf.finished || book.previousReadings.isNotEmpty;

/// For later books that continue a series you have started: the lowest
/// numbered book you have not read, in a series where you have finished at
/// least one book.
List<ReadNextPick> nextInSeries(List<Book> all, List<Book> waiting) {
  final bySeries = <String, List<Book>>{};
  for (final book in all) {
    final series = book.series?.trim() ?? '';
    if (book.deletedAt != null || series.isEmpty) continue;
    bySeries.putIfAbsent(seriesMergeKey(series), () => []).add(book);
  }
  final waitingIds = {for (final book in waiting) book.id};
  final picks = <ReadNextPick>[];
  for (final books in bySeries.values) {
    final read = [
      for (final book in books)
        if (_read(book) && book.seriesNumber != null) book.seriesNumber!,
    ];
    if (read.isEmpty) continue;
    // Already reading one from this series: that is the next one.
    if (books.any((b) => b.shelf == Shelf.inProgress)) continue;
    final unread = [
      for (final book in books)
        if (!_read(book) && book.seriesNumber != null) book,
    ]..sort((a, b) => a.seriesNumber!.compareTo(b.seriesNumber!));
    if (unread.isEmpty || !waitingIds.contains(unread.first.id)) continue;
    final next = unread.first;
    read.sort();
    final lastRead = read.last;
    picks.add(
      ReadNextPick(
        next,
        ReadNextReason.nextInSeries,
        lastRead == next.seriesNumber! - 1
            ? 'Next in ${next.series!.trim()}: you finished #$lastRead'
            : 'Continues ${next.series!.trim()} (#${next.seriesNumber}); '
                  'you have read up to #$lastRead',
      ),
    );
  }
  picks.sort((a, b) => a.book.title.compareTo(b.book.title));
  return picks;
}

/// For later books by authors you have finished and rated well (an average
/// of 4 or more, or 2 finished books with no ratings), best liked first.
List<ReadNextPick> byAuthorsYouLike(
  List<Book> all,
  List<Book> waiting, {
  Set<String> skip = const {},
}) {
  final scored = <(Book, double, String)>[];
  // Every book filed once under each of its authors, so an author's books
  // are found without going through the whole library again (that took
  // seconds with a big library).
  final byAuthor = <String, List<Book>>{};
  for (final book in all) {
    if (book.deletedAt != null) continue;
    final keys = {
      authorKey(book.author),
      for (final name in authorNames(book.author)) authorKey(name),
    }..remove('');
    for (final key in keys) {
      (byAuthor[key] ??= []).add(book);
    }
  }
  final cache = <String, AuthorSummary>{};
  for (final book in waiting) {
    if (skip.contains(book.id) || book.author.trim().isEmpty) continue;
    final names = authorNames(book.author);
    if (names.isEmpty) continue;
    final name = names.first;
    final key = authorKey(name);
    if (key.isEmpty) continue;
    final summary = cache[key] ??= summarizeAuthor(byAuthor[key] ?? const []);
    if (summary.finished == 0) continue;
    final rating = summary.averageRating;
    final liked = rating == null ? summary.finished >= 2 : rating >= 4;
    if (!liked) continue;
    final finished = summary.finished;
    scored.add((
      book,
      (rating ?? 3.5) + finished / 100,
      'You finished $finished by $name'
          '${rating == null ? '' : ', average ${rating.toStringAsFixed(1)}★'}',
    ));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [
    for (final (book, _, why) in scored)
      ReadNextPick(book, ReadNextReason.authorYouLike, why),
  ];
}

/// The books that have waited on For later the longest.
List<ReadNextPick> waitingLongest(
  List<Book> waiting, {
  Set<String> skip = const {},
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final books = [
    for (final book in waiting)
      if (!skip.contains(book.id)) book,
  ]..sort((a, b) => a.addedAt.compareTo(b.addedAt));
  return [
    for (final book in books)
      ReadNextPick(
        book,
        ReadNextReason.waitingLongest,
        'Waiting since ${book.addedAt.year}'
        '${_age(today.difference(book.addedAt))}',
      ),
  ];
}

String _age(Duration waited) {
  final years = waited.inDays ~/ 365;
  if (years >= 1) return ' ($years ${years == 1 ? 'year' : 'years'})';
  final months = waited.inDays ~/ 30;
  if (months >= 1) return ' ($months ${months == 1 ? 'month' : 'months'})';
  return '';
}

/// Up to [each] picks of every kind, with no book twice. Series first, then
/// authors you like, then the longest waiting.
Map<ReadNextReason, List<ReadNextPick>> readNextPicks(
  List<Book> all,
  List<Book> waiting, {
  int each = 3,
  DateTime? now,
}) {
  final series = nextInSeries(all, waiting).take(each).toList();
  final used = {for (final pick in series) pick.book.id};
  final authors = byAuthorsYouLike(
    all,
    waiting,
    skip: used,
  ).take(each).toList();
  used.addAll([for (final pick in authors) pick.book.id]);
  final oldest = waitingLongest(
    waiting,
    skip: used,
    now: now,
  ).take(each).toList();
  return {
    ReadNextReason.nextInSeries: series,
    ReadNextReason.authorYouLike: authors,
    ReadNextReason.waitingLongest: oldest,
  };
}
