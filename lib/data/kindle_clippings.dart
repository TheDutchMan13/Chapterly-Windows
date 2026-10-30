import '../models/book.dart';
import '../models/quote.dart';

/// One highlight from a Kindle's "My Clippings.txt" file.
class KindleClipping {
  const KindleClipping({
    required this.title,
    required this.author,
    required this.text,
    this.page,
    this.addedAt,
  });

  final String title;
  final String author;
  final String text;
  final int? page;
  final DateTime? addedAt;
}

const _months = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

/// "Dune (Dune Chronicles, Book 1) (Frank Herbert)" becomes the title
/// "Dune (Dune Chronicles, Book 1)" and the author "Frank Herbert".
(String, String) _splitTitleLine(String line) {
  final text = line.trim();
  if (text.endsWith(')')) {
    final open = text.lastIndexOf('(');
    if (open > 0) {
      return (
        text.substring(0, open).trim(),
        text.substring(open + 1, text.length - 1).trim(),
      );
    }
  }
  return (text, '');
}

/// Reads "Added on Monday, January 1, 2024 10:00:00 AM" (and the
/// day-month-year order used outside the US). Null if it cannot be read.
DateTime? _parseAdded(String meta) {
  final at = meta.toLowerCase().indexOf('added on');
  if (at < 0) return null;
  final rest = meta.substring(at + 8);
  final month = RegExp(
    r'(january|february|march|april|may|june|july|august|september|'
    r'october|november|december)',
    caseSensitive: false,
  ).firstMatch(rest);
  final year = RegExp(r'(?<!\d)(\d{4})(?!\d)').firstMatch(rest);
  final day = RegExp(r'(?<![\d:])(\d{1,2})(?![\d:])').firstMatch(rest);
  if (month == null || year == null || day == null) return null;
  var hour = 0;
  var minute = 0;
  final time = RegExp(
    r'(\d{1,2}):(\d{2})(?::\d{2})?\s*(am|pm)?',
    caseSensitive: false,
  ).firstMatch(rest);
  if (time != null) {
    hour = int.parse(time.group(1)!);
    minute = int.parse(time.group(2)!);
    final half = time.group(3)?.toLowerCase();
    if (half == 'pm' && hour < 12) hour += 12;
    if (half == 'am' && hour == 12) hour = 0;
  }
  final monthNumber = _months.indexOf(month.group(1)!.toLowerCase()) + 1;
  final dayNumber = int.parse(day.group(1)!);
  if (dayNumber < 1 || dayNumber > 31) return null;
  return DateTime(
    int.parse(year.group(1)!),
    monthNumber,
    dayNumber,
    hour,
    minute,
  );
}

/// Reads the highlights in a Kindle's "My Clippings.txt". Bookmarks and
/// notes are skipped.
List<KindleClipping> parseKindleClippings(String text) {
  final clean = text
      .replaceAll('﻿', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final clippings = <KindleClipping>[];
  for (final block in clean.split('==========')) {
    final lines = [for (final line in block.split('\n')) line.trim()];
    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }
    if (lines.length < 3) continue;
    final meta = lines[1];
    if (!meta.startsWith('-')) continue;
    final lower = meta.toLowerCase();
    if (lower.contains('bookmark') || lower.contains('note')) continue;
    final body = [
      for (final line in lines.skip(2))
        if (line.isNotEmpty) line,
    ].join('\n');
    if (body.isEmpty) continue;
    final (title, author) = _splitTitleLine(lines[0]);
    if (title.isEmpty) continue;
    final page = RegExp(r'\bpage\s+(\d+)', caseSensitive: false)
        .firstMatch(meta)
        ?.group(1);
    clippings.add(KindleClipping(
      title: title,
      author: author,
      text: body,
      page: page == null ? null : int.tryParse(page),
      addedAt: _parseAdded(meta),
    ));
  }
  return clippings;
}

/// Lower case letters and digits only, without anything in brackets and
/// without a subtitle after ":".
String _titleKey(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
    .split(':')
    .first
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

Set<String> _words(String text) => {
      for (final word in text
          .toLowerCase()
          .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
        if (word.length > 1) word,
    };

String _quoteKey(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Where the highlights go: new quotes for each book (by id), the titles
/// that matched no book, and how many highlights were already saved.
class ClippingsMatch {
  const ClippingsMatch({
    required this.quotesByBook,
    required this.unmatchedTitles,
    required this.alreadySaved,
  });

  final Map<String, List<Quote>> quotesByBook;
  final List<String> unmatchedTitles;
  final int alreadySaved;

  int get added =>
      quotesByBook.values.fold<int>(0, (sum, quotes) => sum + quotes.length);
}

/// Matches highlights to [books] by title (ignoring capitals, punctuation,
/// subtitles and series in brackets). When several books have the same
/// title, the one whose author shares a name with the clipping wins.
ClippingsMatch matchClippings(
  List<Book> books,
  List<KindleClipping> clippings, {
  DateTime? now,
}) {
  final byTitle = <String, List<Book>>{};
  for (final book in books) {
    if (book.deletedAt != null) continue;
    final key = _titleKey(book.title);
    if (key.isEmpty) continue;
    byTitle.putIfAbsent(key, () => []).add(book);
  }

  final quotesByBook = <String, List<Quote>>{};
  final seen = <String, Set<String>>{};
  final unmatched = <String>{};
  var alreadySaved = 0;
  for (final clipping in clippings) {
    final candidates = byTitle[_titleKey(clipping.title)];
    if (candidates == null || candidates.isEmpty) {
      unmatched.add(clipping.title);
      continue;
    }
    var book = candidates.first;
    if (candidates.length > 1) {
      final names = _words(clipping.author);
      for (final candidate in candidates) {
        if (_words(candidate.author).any(names.contains)) {
          book = candidate;
          break;
        }
      }
    }
    final known = seen.putIfAbsent(
      book.id,
      () => {for (final quote in book.quotes) _quoteKey(quote.text)},
    );
    if (!known.add(_quoteKey(clipping.text))) {
      alreadySaved++;
      continue;
    }
    quotesByBook.putIfAbsent(book.id, () => []).add(Quote(
          text: clipping.text,
          page: clipping.page,
          addedAt: clipping.addedAt ?? now ?? DateTime.now(),
        ));
  }
  final titles = unmatched.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return ClippingsMatch(
    quotesByBook: quotesByBook,
    unmatchedTitles: titles,
    alreadySaved: alreadySaved,
  );
}
