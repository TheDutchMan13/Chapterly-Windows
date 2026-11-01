import '../models/book.dart';
import 'fuzzy.dart';

// Windows app only.

/// A tag that may fit a book, and why.
class TagSuggestion {
  const TagSuggestion({
    required this.tag,
    required this.score,
    required this.reason,
    this.isNew = false,
  });

  final String tag;
  final double score;
  final String reason;

  /// Not one of your tags yet: an Open Library subject to add as a new tag.
  final bool isNew;
}

String _stem(String word) {
  if (word.length > 4 && word.endsWith('ies')) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.length > 3 && word.endsWith('s') && !word.endsWith('ss')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

String _stemmed(String text) => [for (final w in foldedWords(text)) _stem(w)].join(' ');

/// How well an Open Library subject fits one of your tags: 1 the same
/// (ignoring capitals and plurals), 0.8 when the tag is a whole word or
/// phrase in the subject ("fantasy" in "Epic fantasy"), 0.75 for a typo,
/// otherwise 0.
double subjectFit(String subject, String tag) {
  final s = _stemmed(subject);
  final t = _stemmed(tag);
  if (s.isEmpty || t.isEmpty) return 0;
  if (s == t) return 1;
  if (t.length >= 4 && ' $s '.contains(' $t ')) return 0.8;
  if (s.length >= 5 && ' $t '.contains(' $s ')) return 0.7;
  if (t.length >= 5 && similarity(s, t) >= 0.85) return 0.75;
  return 0;
}

/// Tags that may fit [book], best first, at most [limit]. Two signs count:
/// Open Library [subjects] that match one of your tags, and tags you used on
/// other books by the same author or in the same series. Subjects that fit
/// none of your tags are offered as new tags (at most [newTags]).
List<TagSuggestion> suggestTags(
  Book book,
  List<Book> library, {
  List<String> subjects = const [],
  int limit = 8,
  int newTags = 3,
}) {
  final has = {for (final tag in book.tags) tag.trim().toLowerCase()};
  final yours = <String, String>{};
  for (final other in library) {
    if (other.deletedAt != null) continue;
    for (final tag in other.tags) {
      yours.putIfAbsent(tag.trim().toLowerCase(), () => tag.trim());
    }
  }
  final scores = <String, double>{};
  final reasons = <String, String>{};
  void credit(String key, double value, String reason) {
    if (has.contains(key)) return;
    final before = scores[key] ?? 0;
    scores[key] = before + value;
    if (value > 0 && (reasons[key] == null || value > before)) {
      reasons[key] = reason;
    }
  }

  final used = <String>{};
  for (final subject in subjects) {
    var best = 0.0;
    String? bestTag;
    for (final entry in yours.entries) {
      final fit = subjectFit(subject, entry.value);
      if (fit > best) {
        best = fit;
        bestTag = entry.key;
      }
    }
    if (bestTag != null) {
      credit(bestTag, best, 'Open Library: $subject');
      used.add(subject);
    }
  }

  final author = foldText(book.author);
  final series = foldText(book.series ?? '');
  final related = [
    for (final other in library)
      if (other.deletedAt == null &&
          other.id != book.id &&
          ((author.isNotEmpty && foldText(other.author) == author) ||
              (series.isNotEmpty && foldText(other.series ?? '') == series)))
        other,
  ];
  if (related.isNotEmpty) {
    final counts = <String, int>{};
    for (final other in related) {
      for (final tag in other.tags) {
        final key = tag.trim().toLowerCase();
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    for (final entry in counts.entries) {
      final share = entry.value / related.length;
      if (share < 0.34) continue;
      final what = series.isNotEmpty ? 'this series or author' : 'this author';
      credit(
        entry.key,
        0.9 * share,
        'On ${entry.value} of ${related.length} books by $what',
      );
    }
  }

  final suggestions = [
    for (final entry in scores.entries)
      if (entry.value >= 0.4)
        TagSuggestion(
          tag: yours[entry.key] ?? entry.key,
          score: entry.value,
          reason: reasons[entry.key] ?? '',
        ),
  ]..sort((a, b) => b.score.compareTo(a.score));
  final result = suggestions.take(limit).toList();

  var added = 0;
  for (final subject in subjects) {
    if (added >= newTags || result.length >= limit + newTags) break;
    if (used.contains(subject)) continue;
    final key = subject.trim().toLowerCase();
    if (has.contains(key) || yours.containsKey(key)) continue;
    if (foldedWords(subject).length > 3) continue;
    result.add(TagSuggestion(
      tag: subject.trim(),
      score: 0,
      reason: 'New tag, from Open Library',
      isNew: true,
    ));
    added++;
  }
  return result;
}
