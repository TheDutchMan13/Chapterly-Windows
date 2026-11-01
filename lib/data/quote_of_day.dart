import 'dart:convert';

import '../ebook/ebook_library.dart';
import '../models/book.dart';

// Windows app only.

/// A quote or highlight to read again.
class DailyQuote {
  const DailyQuote({required this.key, required this.book, required this.text});

  /// The same for the same quote, for remembering when it was shown.
  final String key;
  final Book book;
  final String text;
}

String quoteKey(String bookId, String text) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode('$bookId|${text.trim()}')) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16);
}

/// Every quote and highlight in the library, once each.
List<DailyQuote> allQuotes(List<Book> books, {Map<String, EbookLink> ebooks = const {}}) {
  final quotes = <String, DailyQuote>{};
  for (final book in books) {
    if (book.deletedAt != null) continue;
    final texts = [
      for (final quote in book.quotes) quote.text,
      for (final highlight in ebooks[book.id]?.highlights ?? const <EbookHighlight>[])
        highlight.text,
    ];
    for (final text in texts) {
      final clean = text.trim();
      if (clean.length < 12) continue;
      final key = quoteKey(book.id, clean);
      quotes.putIfAbsent(key, () => DailyQuote(key: key, book: book, text: clean));
    }
  }
  return quotes.values.toList();
}

/// Today's quote: the one you have not seen for longest (never shown counts
/// as longest), with quotes from books you rated highly or marked favorite
/// a little ahead. [seen] is the last day each quote was shown. The choice
/// stays the same all day; [skip] moves on to the next one.
DailyQuote? quoteOfTheDay(
  List<DailyQuote> quotes, {
  required Map<String, DateTime> seen,
  DateTime? now,
  int skip = 0,
}) {
  if (quotes.isEmpty) return null;
  final today = now ?? DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  final dayNumber = DateTime.utc(day.year, day.month, day.day)
          .millisecondsSinceEpoch ~/
      86400000;
  double score(DailyQuote q) {
    // A small, steady tie-breaker so equal quotes take turns by day.
    final jitter = (int.parse(q.key, radix: 16) ^ dayNumber) % 997 / 1e4;
    final last = seen[q.key];
    final shownToday = last != null &&
        DateTime(last.year, last.month, last.day) == day;
    // Already shown today: stays on top for the rest of the day.
    if (shownToday) return 1e9 + jitter;
    final days = last == null ? 3650 : day.difference(last).inDays.toDouble();
    final rating = q.book.rating ?? 3;
    final bonus = 1 + (rating - 3) * 0.1 + (q.book.favorite ? 0.2 : 0);
    return days * bonus + jitter;
  }

  final ranked = [...quotes]..sort((a, b) => score(b).compareTo(score(a)));
  return ranked[skip % ranked.length];
}

String encodeSeen(Map<String, DateTime> seen) =>
    jsonEncode({for (final e in seen.entries) e.key: e.value.toIso8601String()});

Map<String, DateTime> decodeSeen(String? text) {
  if (text == null || text.isEmpty) return {};
  try {
    final data = jsonDecode(text);
    if (data is! Map) return {};
    return {
      for (final e in data.entries)
        '${e.key}': ?DateTime.tryParse('${e.value}'),
    };
  } on FormatException {
    return {};
  }
}
