import '../models/book.dart';
import 'fuzzy.dart';

// Windows app only.

/// A series and number found in a book's title.
class SeriesGuess {
  const SeriesGuess({
    required this.book,
    required this.series,
    this.number,
  });

  final Book book;
  final String series;
  final int? number;

  String describe() => number == null ? series : '$series #$number';
}

const _numberWords = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
  'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5, 'sixth': 6,
  'seventh': 7, 'eighth': 8, 'ninth': 9, 'tenth': 10,
};

const _roman = {
  'i': 1, 'ii': 2, 'iii': 3, 'iv': 4, 'v': 5, 'vi': 6, 'vii': 7, 'viii': 8,
  'ix': 9, 'x': 10, 'xi': 11, 'xii': 12,
};

/// "3", "three", "third" or "III" as a number, or null.
int? parseSeriesNumber(String text) {
  final value = text.trim().toLowerCase();
  final digits = int.tryParse(value);
  if (digits != null) return digits > 0 && digits < 1000 ? digits : null;
  return _numberWords[value] ?? _roman[value];
}

const _num = r'(\d{1,3}|one|two|three|four|five|six|seven|eight|nine|ten|'
    r'eleven|twelve|first|second|third|fourth|fifth|sixth|seventh|eighth|'
    r'ninth|tenth|[ivx]{1,4})';
const _marker = r'(?:#|book|bk\.?|vol\.?|volume|no\.?|number|part|tome)';

/// "The Final Empire (Mistborn, #1)" or "(Mistborn Book 1)".
final _inBrackets = RegExp(
  r'[(\[]\s*([^()\[\]]+?)\s*[,;:]?\s*' + _marker + r'\s*' + _num + r'\s*[)\]]',
  caseSensitive: false,
);

/// "Mistborn, Book 2: The Well of Ascension", "The Expanse Book 3",
/// "Mistborn #2" or "Wheel of Time Vol. 4 - The Shadow Rising".
final _withMarker = RegExp(
  r'^(.+?)[\s,:–—-]+' + _marker + r'\s*' + _num + r'\b',
  caseSensitive: false,
);

/// "Book 2 of The Stormlight Archive", "Book Two of the Wingfeather Saga".
final _ofSeries = RegExp(
  _marker + r'\s*' + _num + r'\s+(?:of|in)\s+(?:the\s+)?(.+?)\s*[)\]]?$',
  caseSensitive: false,
);

/// "Mistborn 3: The Hero of Ages": a name, a number, then a subtitle. Only
/// trusted when another book has the same name before its number.
final _bareNumber = RegExp(r'^(.+?)\s+(\d{1,2})\s*[:–—-]\s+\S', caseSensitive: false);

String _tidy(String name) => name
    .replaceAll(RegExp(r'^[\s,:;–—-]+|[\s,:;–—-]+$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The series and number in one title, or null. Only clear patterns count:
/// "(Series, #3)", "Series Book 3", "Series #3", "Book 3 of Series".
({String series, int? number})? seriesInTitle(String title) {
  final bracket = _inBrackets.firstMatch(title);
  if (bracket != null) {
    final number = parseSeriesNumber(bracket.group(2)!);
    final name = _tidy(bracket.group(1)!);
    if (number != null && name.isNotEmpty) return (series: name, number: number);
  }
  final of = _ofSeries.firstMatch(title);
  if (of != null) {
    final number = parseSeriesNumber(of.group(1)!);
    final name = _tidy(of.group(2)!);
    if (number != null && name.length >= 3) return (series: name, number: number);
  }
  final marked = _withMarker.firstMatch(title);
  if (marked != null) {
    final number = parseSeriesNumber(marked.group(2)!);
    final name = _tidy(marked.group(1)!);
    // "Book" alone, or a whole sentence, is not a series name.
    if (number != null && name.length >= 3 && foldedWords(name).length <= 6) {
      return (series: name, number: number);
    }
  }
  return null;
}

/// Series for the books in [books] that have none yet, found in their
/// titles. A series spelled like one you already have uses your spelling.
/// "Name 3: Subtitle" only counts when at least two books share the name.
List<SeriesGuess> detectSeries(List<Book> books) {
  final live = [
    for (final book in books)
      if (book.deletedAt == null) book,
  ];
  final known = <String, String>{
    for (final book in live)
      if ((book.series ?? '').trim().isNotEmpty)
        foldText(book.series!): book.series!.trim(),
  };
  String spelling(String name) {
    final key = foldText(name);
    final exact = known[key];
    if (exact != null) return exact;
    for (final entry in known.entries) {
      if (entry.key.length >= 5 && similarity(entry.key, key) >= 0.9) {
        return entry.value;
      }
    }
    return name;
  }

  final guesses = <SeriesGuess>[];
  final bare = <String, List<(Book, int, String)>>{};
  for (final book in live) {
    if ((book.series ?? '').trim().isNotEmpty) continue;
    final found = seriesInTitle(book.title);
    if (found != null) {
      guesses.add(SeriesGuess(
        book: book,
        series: spelling(found.series),
        number: found.number,
      ));
      continue;
    }
    final match = _bareNumber.firstMatch(book.title);
    if (match != null) {
      final name = _tidy(match.group(1)!);
      final number = int.parse(match.group(2)!);
      if (name.length >= 3 && number > 0) {
        bare.putIfAbsent(foldText(name), () => []).add((book, number, name));
      }
    }
  }
  for (final entry in bare.entries) {
    final alreadyKnown = known.containsKey(entry.key);
    if (entry.value.length < 2 && !alreadyKnown) continue;
    for (final (book, number, name) in entry.value) {
      guesses.add(SeriesGuess(book: book, series: spelling(name), number: number));
    }
  }
  guesses.sort((a, b) {
    final bySeries = a.series.toLowerCase().compareTo(b.series.toLowerCase());
    if (bySeries != 0) return bySeries;
    return (a.number ?? 0).compareTo(b.number ?? 0);
  });
  return guesses;
}
