import '../models/book.dart';
import 'fuzzy.dart';

// The same file is in the Android app; keep the two copies alike.

/// Words in file names that say nothing about which book it is.
const _noise = {
  'epub', 'pdf', 'mobi', 'azw', 'azw3', 'kfx', 'cbz', 'cbr', 'fb2', 'txt',
  'm4b', 'm4a', 'mp3', 'aac', 'flac', 'ogg', 'opus', 'wma',
  'unabridged', 'abridged', 'audiobook', 'audio', 'ebook', 'book', 'retail',
  'narrated', 'read', 'by', 'and', 'the', 'a', 'an', 'of', 'to', 'in', 'on',
  'vol', 'volume', 'part', 'edition', 'ed', 'series', 'novel', 'zlib',
  'z', 'lib', 'org', 'libgen', 'www', 'com', 'de', 'le', 'la', 'el',
};

/// The words of a file name that can say which book it is: no file
/// extension, no numbers, no words like "epub" or "unabridged".
List<String> nameWords(String name) {
  var text = name.trim();
  final dot = text.lastIndexOf('.');
  if (dot > 0 && text.length - dot <= 5) text = text.substring(0, dot);
  // Put spaces between joined words: "TheWager" gives "The Wager".
  text = text.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return [
    for (final word in foldedWords(text))
      if (word.length > 1 &&
          !_noise.contains(word) &&
          !RegExp(r'^\d+$').hasMatch(word))
        word,
  ];
}

bool _hasWord(Set<String> words, String word) {
  if (words.contains(word)) return true;
  if (word.length < 5) return false;
  // Allow one typo in a longer word.
  for (final other in words) {
    if ((other.length - word.length).abs() <= 1 &&
        editDistance(other, word, max: 1) <= 1) {
      return true;
    }
  }
  return false;
}

/// How alike a book's original name and its details are, from 0 (nothing
/// alike) to 1. Null when the book has no original name to compare with.
///
/// It is the lower of two shares: of the name's words found in the title
/// and author, and of the main title's words (before any ":") found in the
/// name. A wrong author or a different book brings it down; a subtitle the
/// file name leaves out does not.
double? matchSimilarity(Book book) {
  final name = book.origin?.name;
  if (name == null) return null;
  final fromName = nameWords(name);
  if (fromName.isEmpty) return null;
  final details = {
    ...foldedWords(book.title),
    ...foldedWords(book.author),
    ...foldedWords(book.series ?? ''),
  };
  final nameSet = fromName.toSet();
  final inDetails =
      nameSet.where((w) => _hasWord(details, w)).length / nameSet.length;
  final mainTitle = book.title.split(':').first;
  final titleWords = {
    for (final w in foldedWords(mainTitle))
      if (w.length > 1 && !_noise.contains(w)) w,
  };
  final inName = titleWords.isEmpty
      ? 1.0
      : titleWords.where((w) => _hasWord(nameSet, w)).length /
          titleWords.length;
  return inDetails < inName ? inDetails : inName;
}

/// Below this, a match is listed in Review matches.
const doubtfulBelow = 0.7;

/// A book whose match may be wrong, and how alike it is to its file name.
class DoubtfulMatch {
  const DoubtfulMatch(this.book, this.similarity);
  final Book book;
  final double similarity;

  /// "62%".
  String get percent => '${(similarity * 100).round()}%';
}

/// The books whose details look very different from their original name,
/// least alike first. Leaves out books you corrected yourself, and those
/// you said are right.
List<DoubtfulMatch> doubtfulMatches(Iterable<Book> books) {
  final found = <DoubtfulMatch>[];
  for (final book in books) {
    final origin = book.origin;
    if (origin == null || origin.edited || origin.matchConfirmed) continue;
    final similarity = matchSimilarity(book);
    if (similarity != null && similarity < doubtfulBelow) {
      found.add(DoubtfulMatch(book, similarity));
    }
  }
  found.sort((a, b) => a.similarity.compareTo(b.similarity));
  return found;
}

/// How many books have an original name to compare with and look fine.
int fineMatchCount(Iterable<Book> books) => books.where((book) {
      final origin = book.origin;
      if (origin == null) return false;
      if (origin.edited || origin.matchConfirmed) return true;
      final similarity = matchSimilarity(book);
      return similarity != null && similarity >= doubtfulBelow;
    }).length;
