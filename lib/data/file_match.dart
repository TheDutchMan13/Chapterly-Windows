import '../models/book.dart';
import 'fuzzy.dart';

/// A title and author found inside a file, or guessed from its name.
class FoundBookInfo {
  const FoundBookInfo({this.title = '', this.author = ''});

  final String title;
  final String author;

  bool get isEmpty => title.isEmpty;
}

const _knownExtensions = {
  'epub', 'pdf', 'm4b', 'm4a', 'mp4', 'mp3', 'aac', 'flac', 'ogg', 'opus',
  'wav', 'wma',
};

/// A file or folder name made readable: no folder, no extension, no
/// underscores, and nothing in brackets (years, formats, narrators).
String cleanFileName(String name) {
  var text = name.split(RegExp(r'[\\/]')).last;
  final dot = text.lastIndexOf('.');
  if (dot > 0 && _knownExtensions.contains(text.substring(dot + 1).toLowerCase())) {
    text = text.substring(0, dot);
  }
  text = text
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}'), ' ');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The parts of a name like "Dune - Frank Herbert", "Frank Herbert - Dune"
/// or "Brandon Sanderson - Mistborn 01 - The Final Empire". A name with no
/// " - " but " by " ("Dune by Frank Herbert") splits there.
List<String> fileNameParts(String name) {
  final clean = cleanFileName(name);
  var parts = clean.split(RegExp(r'\s+[-–—]\s+'));
  if (parts.length == 1) {
    parts = clean.split(RegExp(r'\s+by\s+', caseSensitive: false));
  }
  return [
    for (final part in parts)
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// A first guess at the title and author from a file name, for a new book.
/// Two parts are read as "Title - Author" (how Calibre names files); with
/// more, the first is the author and the last the title. You can swap them
/// in the dialog when the guess is the wrong way round.
FoundBookInfo guessFromFileName(String name) {
  final parts = fileNameParts(name);
  if (parts.isEmpty) return const FoundBookInfo();
  if (parts.length == 1) return FoundBookInfo(title: parts.first);
  if (parts.length == 2) {
    return FoundBookInfo(title: parts.first, author: parts.last);
  }
  return FoundBookInfo(title: parts.last, author: parts.first);
}

/// Letters and digits only, lower case, without a leading "the", "a" or
/// "an", and with "&" read as "and".
String titleKey(String text) {
  var value = text.toLowerCase().replaceAll('&', ' and ').trim();
  value = value.replaceFirst(RegExp(r'^(the|a|an)\s+'), '');
  return value.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');
}

/// The title without its subtitle: "Dune: Book One" gives "Dune".
String mainTitle(String text) =>
    text.split(RegExp(r'\s*[:(]\s*|\s+[-–—]\s+')).first;

Set<String> _words(String text) => {
      for (final word in text
          .toLowerCase()
          .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
        if (word.length >= 3) word,
    };

/// How much [candidate] looks like [bookTitle]: 100 the same, 85 the same
/// without subtitles, 65 when one holds the other (such as a file name
/// with the series in it), 0 otherwise.
int titleScore(String bookTitle, String candidate) {
  final book = titleKey(bookTitle);
  final found = titleKey(candidate);
  if (book.isEmpty || found.isEmpty) return 0;
  if (book == found) return 100;
  final bookMain = titleKey(mainTitle(bookTitle));
  final foundMain = titleKey(mainTitle(candidate));
  if (bookMain.length >= 3 && bookMain == foundMain) return 85;
  final shorter = book.length <= found.length ? book : found;
  final longer = shorter == book ? found : book;
  if (shorter.length >= 6 && longer.contains(shorter)) return 65;
  return _nearTitleScore(bookTitle, candidate);
}

/// Words in file names and tags that are not part of the title.
final _noise = RegExp(
  r'\b(unabridged|abridged|audiobook|audio book|retail|epub|ebook|e book|'
  r'kindle|mp3|m4b|a novel|full cast|dramatized|dramatised)\b',
);

String _plainTitle(String text) =>
    titleKey(foldText(text).replaceAll(_noise, ' '));

Set<String> _numbers(String text) =>
    {for (final m in RegExp(r'\d+').allMatches(text)) m.group(0)!};

/// Windows app: titles that are nearly the same. 80 when they only differ
/// by words such as "Unabridged", 75 for a typo or two, 70 for the same
/// words in another order or the same title without subtitles but with a
/// typo, 0 otherwise. Different numbers ("Book 1", "Book 2") never match.
int _nearTitleScore(String bookTitle, String candidate) {
  final a = foldText(bookTitle);
  final b = foldText(candidate);
  final numbersA = _numbers(a);
  final numbersB = _numbers(b);
  if (numbersA.isNotEmpty &&
      numbersB.isNotEmpty &&
      !(numbersA.length == numbersB.length && numbersA.containsAll(numbersB))) {
    return 0;
  }
  final plainA = _plainTitle(bookTitle);
  final plainB = _plainTitle(candidate);
  if (plainA.length >= 4 && plainA == plainB) return 80;
  if (plainA.length >= 6 && similarity(plainA, plainB) >= 0.88) return 75;
  final mainA = titleKey(mainTitle(bookTitle));
  final mainB = titleKey(mainTitle(candidate));
  if (mainA.length >= 6 && similarity(mainA, mainB) >= 0.9) return 70;
  final wordsA = _words(a.replaceAll(_noise, ' '));
  final wordsB = _words(b.replaceAll(_noise, ' '));
  if (wordsA.length >= 2 && wordsB.length >= 2) {
    final shared = wordsA.intersection(wordsB).length;
    final all = wordsA.union(wordsB).length;
    if (shared / all >= 0.75) return 70;
  }
  return 0;
}

/// Whether two sets of author words are the same person: a shared word,
/// or a surname with a typo.
bool _authorsMeet(Set<String> a, Set<String> b) {
  if (a.intersection(b).isNotEmpty) return true;
  return a.any((x) => x.length >= 5 && b.any((y) => isNearWord(x, y)));
}

/// A book that may be the one in a file, and how sure we are.
class BookMatch {
  const BookMatch(this.book, this.score);

  final Book book;
  final int score;
}

/// Books in [books] that look like the one in a file, best first, at most
/// [limit]. [title] and [author] come from inside the file (an author that
/// does not fit counts against a book); [nameParts] come from the file
/// name, where any part may be the title or the author (they only help).
List<BookMatch> findMatchingBooks(
  List<Book> books, {
  String title = '',
  String author = '',
  List<String> nameParts = const [],
  int limit = 5,
}) {
  final titles = [
    if (title.isNotEmpty) title,
    ...nameParts,
    if (nameParts.length > 1) nameParts.join(' '),
  ];
  if (titles.isEmpty) return const [];
  final fileAuthorWords = _words(author);
  final nameWords = {for (final part in nameParts) ..._words(part)};
  final matches = <BookMatch>[];
  for (final book in books) {
    if (book.deletedAt != null) continue;
    var score = 0;
    for (final candidate in titles) {
      final s = titleScore(book.title, candidate);
      if (s > score) score = s;
    }
    if (score == 0) continue;
    final bookAuthorWords = _words(book.author);
    if (bookAuthorWords.isNotEmpty) {
      if (fileAuthorWords.isNotEmpty) {
        score += _authorsMeet(bookAuthorWords, fileAuthorWords) ? 15 : -25;
      } else if (bookAuthorWords.intersection(nameWords).isNotEmpty) {
        score += 15;
      }
    }
    if (score >= 50) matches.add(BookMatch(book, score));
  }
  matches.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.book.title.compareTo(b.book.title);
  });
  return matches.take(limit).toList();
}

/// Whether the best match is clearly the book: a good score, well ahead of
/// the next one.
bool isSureMatch(List<BookMatch> matches) {
  if (matches.isEmpty || matches.first.score < 85) return false;
  return matches.length == 1 || matches[1].score <= matches.first.score - 15;
}
