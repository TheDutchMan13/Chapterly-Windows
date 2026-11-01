import 'dart:math' as math;

// Windows app only.

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'ç': 'c', 'č': 'c', 'ć': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ś': 's', 'š': 's', 'ș': 's', 'ž': 'z', 'ź': 'z', 'ż': 'z',
  'ł': 'l', 'ř': 'r', 'ť': 't', 'ț': 't', 'ď': 'd', 'ß': 'ss', 'æ': 'ae',
  'œ': 'oe',
};

final _notLetters = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Lower case, without accents ("Brontë" gives "bronte"), and with anything
/// that is not a letter or digit turned into a single space.
String foldText(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_accents[char] ?? char);
  }
  return out.toString().replaceAll(_notLetters, ' ').trim();
}

/// The words of [text], folded (see [foldText]).
List<String> foldedWords(String text) {
  final folded = foldText(text);
  return folded.isEmpty ? const [] : folded.split(' ');
}

/// How many single-letter changes (add, remove, replace, or swap two
/// letters next to each other) turn [a] into [b]. Stops counting once it is
/// sure the answer is more than [max], and then returns `max + 1`.
int editDistance(String a, String b, {int? max}) {
  if (a == b) return 0;
  final limit = max ?? (a.length > b.length ? a.length : b.length);
  if ((a.length - b.length).abs() > limit) return limit + 1;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var beforeLast = List<int>.filled(b.length + 1, 0);
  var last = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    var rowBest = current[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var value = math.min(
        math.min(last[j] + 1, current[j - 1] + 1),
        last[j - 1] + cost,
      );
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        value = math.min(value, beforeLast[j - 2] + 1);
      }
      current[j] = value;
      if (value < rowBest) rowBest = value;
    }
    if (rowBest > limit) return limit + 1;
    final spare = beforeLast;
    beforeLast = last;
    last = current;
    current = spare;
  }
  return math.min(last[b.length], limit + 1);
}

/// From 0 (nothing alike) to 1 (the same): the edit distance measured
/// against the longer text.
double similarity(String a, String b) {
  if (a == b) return 1;
  final longest = math.max(a.length, b.length);
  if (longest == 0) return 1;
  return 1 - editDistance(a, b) / longest;
}

/// How many typos a word of this length may have and still count: none for
/// short words, one up to six letters, two after that.
int allowedTypos(int length) => length < 4 ? 0 : (length < 7 ? 1 : 2);

/// Whether a (folded) search word [query] is [word] with a typo or two, or
/// the start of it with a typo ("sandr" for "sanderson").
bool isNearWord(String query, String word) {
  final allowed = allowedTypos(query.length);
  if (allowed == 0) return false;
  if (editDistance(query, word, max: allowed) <= allowed) return true;
  if (word.length > query.length) {
    final start = word.substring(0, query.length);
    if (editDistance(query, start, max: allowed) <= allowed) return true;
  }
  return false;
}

/// A search worked out once against every word in the library, so a word
/// with a typo looks for the library words it is near, while correctly
/// spelled words only find what they say.
class SearchPlan {
  SearchPlan._(this.text, this.words, {this.corrected = false});

  /// The whole search, lower case, for the plain "contains" test.
  final String text;

  /// For each search word, the words that count for it: the word itself, or
  /// for a word found nowhere in the library, the library words near it.
  final List<Set<String>> words;

  /// Whether any word was found nowhere and looks for near words instead.
  final bool corrected;

  static final empty = SearchPlan._('', const []);

  /// [vocabulary] is every folded word in the library.
  factory SearchPlan.build(String query, Set<String> vocabulary) {
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return empty;
    final words = <Set<String>>[];
    var corrected = false;
    for (final word in foldedWords(text)) {
      final known = vocabulary.any((v) => v.contains(word));
      if (known || allowedTypos(word.length) == 0) {
        words.add({word});
        continue;
      }
      final near = {
        for (final v in vocabulary)
          if (isNearWord(word, v)) v,
      };
      if (near.isNotEmpty) corrected = true;
      words.add(near.isEmpty ? {word} : near);
    }
    return SearchPlan._(text, words, corrected: corrected);
  }

  bool get isEmpty => text.isEmpty;

  /// Whether a book's folded words (title, author, series and tags) have
  /// every search word, or a near word for it.
  bool matchesFolded(String folded) {
    if (words.isEmpty) return false;
    for (final alternatives in words) {
      if (!alternatives.any(folded.contains)) return false;
    }
    return true;
  }
}
