import '../models/book.dart';
import '../models/shelf.dart';
import 'fuzzy.dart';

// The same code is in the Android app; keep the two copies alike.

/// One series in your library: which numbers you have, which are missing,
/// and which one to read next.
class SeriesInfo {
  const SeriesInfo({
    required this.name,
    required this.author,
    required this.books,
    required this.missing,
    required this.unnumbered,
  });

  final String name;

  /// The author most of its books have.
  final String author;

  /// The numbered books, by number.
  final List<Book> books;

  /// Numbers from 1 to the highest you have that no book has.
  final List<int> missing;

  /// Books in the series without a number.
  final List<Book> unnumbered;

  int get finished =>
      [...books, ...unnumbered].where((b) => b.shelf == Shelf.finished).length;

  int get total => books.length + unnumbered.length;

  /// The first numbered book you have not finished, or null.
  Book? get next {
    for (final book in books) {
      if (book.shelf != Shelf.finished) return book;
    }
    return null;
  }

  bool get complete => missing.isEmpty && finished == total;
}

/// Every series among [books] (books in the trash are left out), by name.
/// Names that differ only in capitals or spaces are one series.
List<SeriesInfo> seriesOverview(List<Book> books) {
  final groups = <String, List<Book>>{};
  final names = <String, String>{};
  for (final book in books) {
    final name = book.series?.trim() ?? '';
    if (book.deletedAt != null || name.isEmpty) continue;
    final key = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    groups.putIfAbsent(key, () => []).add(book);
    names.putIfAbsent(key, () => name);
  }
  final result = <SeriesInfo>[];
  for (final entry in groups.entries) {
    final numbered = [
      for (final book in entry.value)
        if (book.seriesNumber != null && book.seriesNumber! > 0) book,
    ]..sort((a, b) => a.seriesNumber!.compareTo(b.seriesNumber!));
    final unnumbered = [
      for (final book in entry.value)
        if (book.seriesNumber == null || book.seriesNumber! <= 0) book,
    ];
    final have = {for (final book in numbered) book.seriesNumber!};
    final highest = have.isEmpty ? 0 : have.reduce((a, b) => a > b ? a : b);
    final authors = <String, int>{};
    for (final book in entry.value) {
      final author = book.author.trim();
      if (author.isNotEmpty) authors[author] = (authors[author] ?? 0) + 1;
    }
    final author = authors.isEmpty
        ? ''
        : (authors.entries.toList()..sort((a, b) => b.value - a.value))
            .first
            .key;
    result.add(SeriesInfo(
      name: names[entry.key]!,
      author: author,
      books: numbered,
      missing: [
        for (var n = 1; n < highest; n++)
          if (!have.contains(n)) n,
      ],
      unnumbered: unnumbered,
    ));
  }
  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}

/// Words that end a series name without telling series apart: "Dexter" and
/// "Dexter Series" are one series.
const _seriesFiller = {
  'series', 'saga', 'trilogy', 'quartet', 'quintet', 'books', 'novels',
  'cycle',
};

/// The name of a series with capitals, accents, punctuation, a leading "The"
/// and a trailing "Series", "Saga" or "Trilogy" taken away, so spellings of
/// the same series have the same key. Empty when nothing is left.
String seriesMergeKey(String name) {
  var words = foldedWords(name);
  if (words.length > 1 && words.first == 'the') words = words.sublist(1);
  while (words.length > 1 && _seriesFiller.contains(words.last)) {
    words = words.sublist(0, words.length - 1);
  }
  return words.join(' ');
}

/// Several spellings of one series, and the one to use for all of them.
class SeriesMerge {
  const SeriesMerge({required this.target, required this.names, required this.bookIds});

  /// The name to keep: the one most of the books already use.
  final String target;

  /// The other spellings that become [target].
  final List<String> names;

  /// The books to change: those in the other spellings.
  final List<String> bookIds;

  int get count => bookIds.length;
}

/// Series in [books] that are spelled in more than one way but are one
/// series: "Dexter" and "Dexter Series", "The Expanse" and "Expanse". Only
/// when the books share an author (or one group has none), so two different
/// series with a short name are not joined.
List<SeriesMerge> findSeriesMerges(List<Book> books) {
  // key -> exact name (lower case) -> books
  final byKey = <String, Map<String, List<Book>>>{};
  final spelled = <String, String>{};
  for (final book in books) {
    final name = (book.series ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (book.deletedAt != null || name.isEmpty) continue;
    final key = seriesMergeKey(name);
    if (key.isEmpty) continue;
    final exact = name.toLowerCase();
    byKey.putIfAbsent(key, () => {}).putIfAbsent(exact, () => []).add(book);
    spelled.putIfAbsent(exact, () => name);
  }
  Set<String> authorWords(Iterable<Book> group) => {
        for (final book in group) ...foldedWords(book.author).where((w) => w.length > 2),
      };
  final merges = <SeriesMerge>[];
  for (final spellings in byKey.values) {
    if (spellings.length < 2) continue;
    final order = spellings.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.length.compareTo(a.value.length);
        if (byCount != 0) return byCount;
        final byLength = a.key.length.compareTo(b.key.length);
        return byLength != 0 ? byLength : a.key.compareTo(b.key);
      });
    final keep = order.first;
    final keepAuthors = authorWords(keep.value);
    final names = <String>[];
    final ids = <String>[];
    for (final other in order.skip(1)) {
      final otherAuthors = authorWords(other.value);
      final related = keepAuthors.isEmpty ||
          otherAuthors.isEmpty ||
          keepAuthors.intersection(otherAuthors).isNotEmpty;
      if (!related) continue;
      names.add(spelled[other.key]!);
      ids.addAll([for (final book in other.value) book.id]);
    }
    if (names.isEmpty) continue;
    merges.add(SeriesMerge(target: spelled[keep.key]!, names: names, bookIds: ids));
  }
  merges.sort((a, b) => a.target.toLowerCase().compareTo(b.target.toLowerCase()));
  return merges;
}
