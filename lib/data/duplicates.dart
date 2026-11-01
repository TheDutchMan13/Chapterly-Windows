import '../models/book.dart';
import '../models/quote.dart';
import 'fuzzy.dart';

String _normalize(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

List<String> _keys(Book book) {
  final keys = <String>[];
  final isbn = (book.isbn ?? '').replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
  if (isbn.length >= 10) keys.add('isbn:$isbn');
  final title = _normalize(book.title);
  if (title.isNotEmpty) keys.add('title:$title|${_normalize(book.author)}');
  return keys;
}

/// Groups of books that look like the same book: the same ISBN, or the same
/// title and author (ignoring capitals, spaces and punctuation).
List<List<Book>> findDuplicateGroups(List<Book> books) {
  final parent = List<int>.generate(books.length, (i) => i);

  int find(int start) {
    var i = start;
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  void union(int a, int b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) parent[rootB] = rootA;
  }

  final seen = <String, int>{};
  for (var i = 0; i < books.length; i++) {
    for (final key in _keys(books[i])) {
      final other = seen[key];
      if (other == null) {
        seen[key] = i;
      } else {
        union(other, i);
      }
    }
  }

  final groups = <int, List<Book>>{};
  for (var i = 0; i < books.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(books[i]);
  }
  return [
    for (final group in groups.values)
      if (group.length > 1) group,
  ];
}

int _score(Book book) {
  var score = 0;
  if (book.rating != null) score++;
  if (book.pages != null) score++;
  if (book.isbn != null) score++;
  if (book.coverUrl != null) score++;
  if (book.startedAt != null) score++;
  if (book.finishedAt != null) score++;
  if ((book.notes ?? '').isNotEmpty) score++;
  if (book.format != null) score++;
  if (book.series != null) score++;
  if (book.firstPublishYear != null) score++;
  if (book.favorite) score++;
  score += book.tags.length;
  score += book.readingLog.length;
  score += book.previousReadings.length;
  score += book.quotes.length;
  score += switch (book.shelf.name) {
    'finished' => 2,
    'inProgress' => 1,
    _ => 0,
  };
  return score;
}

/// The book in [group] with the most details. On a tie, the one added first.
Book bestOf(List<Book> group) {
  final sorted = [...group]..sort((a, b) {
      final byScore = _score(b).compareTo(_score(a));
      return byScore != 0 ? byScore : a.addedAt.compareTo(b.addedAt);
    });
  return sorted.first;
}

bool _hasText(String? text) => text != null && text.trim().isNotEmpty;

Book _absorb(Book base, Book other) {
  final tags = [
    ...base.tags,
    for (final tag in other.tags)
      if (!base.tags.any((t) => t.toLowerCase() == tag.toLowerCase())) tag,
  ];
  final collections = [
    ...base.collections,
    for (final name in other.collections)
      if (!base.collections.any((c) => c.toLowerCase() == name.toLowerCase()))
        name,
  ];
  final quotes = <Quote>[
    ...base.quotes,
    for (final quote in other.quotes)
      if (!base.quotes.any((q) => q.text == quote.text)) quote,
  ];
  final String? notes;
  if (!_hasText(base.notes)) {
    notes = other.notes;
  } else if (_hasText(other.notes) && other.notes!.trim() != base.notes!.trim()) {
    notes = '${base.notes}\n\n${other.notes}';
  } else {
    notes = base.notes;
  }
  return base.copyWith(
    tags: tags,
    collections: collections,
    quotes: quotes,
    previousReadings: [...base.previousReadings, ...other.previousReadings],
    favorite: base.favorite || other.favorite,
    currentPage: base.currentPage == null && other.currentPage != null
        ? () => other.currentPage
        : null,
    aspectRatings: {...other.aspectRatings, ...base.aspectRatings},
    priority: base.priority == null && other.priority != null
        ? () => other.priority
        : null,
    buyAt: !_hasText(base.buyAt) && _hasText(other.buyAt)
        ? () => other.buyAt
        : null,
    notes: () => notes,
    isbn: base.isbn == null && other.isbn != null ? () => other.isbn : null,
    coverUrl: base.coverUrl == null && other.coverUrl != null
        ? () => other.coverUrl
        : null,
    firstPublishYear:
        base.firstPublishYear == null && other.firstPublishYear != null
            ? () => other.firstPublishYear
            : null,
    pages: base.pages == null && other.pages != null ? () => other.pages : null,
    format:
        base.format == null && other.format != null ? () => other.format : null,
    series:
        base.series == null && other.series != null ? () => other.series : null,
    seriesNumber: base.seriesNumber == null && other.seriesNumber != null
        ? () => other.seriesNumber
        : null,
    rating:
        base.rating == null && other.rating != null ? () => other.rating : null,
    startedAt: base.startedAt == null && other.startedAt != null
        ? () => other.startedAt
        : null,
    finishedAt: base.finishedAt == null && other.finishedAt != null
        ? () => other.finishedAt
        : null,
  );
}

/// The best book of [group] with empty details filled in from the others,
/// and their tags, shelves, quotes and earlier readings added. Pass the
/// result to the library and trash the other books.
Book mergeDuplicateGroup(List<Book> group) {
  final keeper = bestOf(group);
  final others = [
    for (final book in group)
      if (book.id != keeper.id) book,
  ]..sort((a, b) => _score(b).compareTo(_score(a)));
  var merged = keeper;
  for (final other in others) {
    merged = _absorb(merged, other);
  }
  return merged;
}

// ---- Windows app: books that may be the same, found with fuzzy matching.

/// Two books that may be the same book, and why.
class PossibleDuplicate {
  const PossibleDuplicate(this.first, this.second, this.reason);

  final Book first;
  final Book second;
  final String reason;

  /// The same for (a, b) and (b, a), for remembering "Not the same".
  String get key => pairKey(first.id, second.id);

  static String pairKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
}

String _foldTitle(String text) {
  var value = foldText(text);
  value = value.replaceFirst(RegExp(r'^(the|a|an) '), '');
  return value;
}

String _mainPart(String title) =>
    title.split(RegExp(r'\s*[:(\[]\s*|\s+[-–—]\s+')).first;

/// Words that tell editions apart but not books, left out when comparing.
final _editionWords = RegExp(
  r'\b(deluxe|special|anniversary|illustrated|collectors?|annotated|'
  r'unabridged|abridged|edition|paperback|hardcover)\b',
);

Set<String> _digitsIn(String text) =>
    {for (final m in RegExp(r'\d+').allMatches(text)) m.group(0)!};

Set<String> _authorWords(String author) => {
      for (final word in foldedWords(author))
        if (word.length >= 2) word,
    };

bool _sameAuthor(Book a, Book b) {
  final wordsA = _authorWords(a.author);
  final wordsB = _authorWords(b.author);
  if (wordsA.isEmpty || wordsB.isEmpty) return true;
  if (wordsA.intersection(wordsB).isNotEmpty) return true;
  // A typo in the surname.
  return wordsA.any((x) => x.length >= 5 && wordsB.any((y) => isNearWord(x, y)));
}

/// Why [a] and [b] may be the same book, or null when they do not look
/// alike. Different series numbers, or different numbers in the titles
/// ("Book 1" and "Book 2"), are never the same.
String? _whyAlike(Book a, Book b) {
  if (a.seriesNumber != null &&
      b.seriesNumber != null &&
      a.seriesNumber != b.seriesNumber) {
    return null;
  }
  final titleA = _foldTitle(a.title);
  final titleB = _foldTitle(b.title);
  if (titleA.isEmpty || titleB.isEmpty) return null;
  if (_digitsIn(titleA).length + _digitsIn(titleB).length > 0 &&
      !_sameSet(_digitsIn(titleA), _digitsIn(titleB))) {
    return null;
  }
  if (!_sameAuthor(a, b)) return null;
  final mainA = _foldTitle(_mainPart(a.title));
  final mainB = _foldTitle(_mainPart(b.title));
  final hasSubA = mainA != titleA;
  final hasSubB = mainB != titleB;
  if (hasSubA != hasSubB && mainA == mainB && mainA.length >= 3) {
    return 'Same title, one with a subtitle';
  }
  final plainA = titleA.replaceAll(_editionWords, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final plainB = titleB.replaceAll(_editionWords, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (plainA.isNotEmpty && plainA == plainB) {
    return 'Same title apart from the edition';
  }
  final squashedA = plainA.replaceAll(' ', '');
  final squashedB = plainB.replaceAll(' ', '');
  if (squashedA.length >= 5 && similarity(squashedA, squashedB) >= 0.85) {
    return 'Almost the same title';
  }
  return null;
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// Pairs of books that may be the same book even though their titles are
/// not exactly the same: a typo, a subtitle on one, "Deluxe Edition".
/// Books already in an exact group ([findDuplicateGroups]) and pairs in
/// [dismissed] (see [PossibleDuplicate.key]) are left out. Only books by
/// the same author (or without one) are compared, so it stays quick.
List<PossibleDuplicate> findPossibleDuplicates(
  List<Book> books, {
  Set<String> dismissed = const {},
}) {
  final live = [
    for (final book in books)
      if (book.deletedAt == null) book,
  ];
  final exact = <String>{
    for (final group in findDuplicateGroups(live))
      for (var i = 0; i < group.length; i++)
        for (var j = i + 1; j < group.length; j++)
          PossibleDuplicate.pairKey(group[i].id, group[j].id),
  };
  // Blocks: by surname, or by the start of the title for books without one.
  final blocks = <String, List<Book>>{};
  for (final book in live) {
    final words = foldedWords(book.author);
    final block = words.isNotEmpty
        ? 'a:${words.last}'
        : 't:${_foldTitle(book.title).padRight(3).substring(0, 3)}';
    blocks.putIfAbsent(block, () => []).add(book);
  }
  final found = <PossibleDuplicate>[];
  final seen = <String>{};
  for (final block in blocks.values) {
    for (var i = 0; i < block.length; i++) {
      for (var j = i + 1; j < block.length; j++) {
        final a = block[i];
        final b = block[j];
        final key = PossibleDuplicate.pairKey(a.id, b.id);
        if (exact.contains(key) || dismissed.contains(key) || !seen.add(key)) {
          continue;
        }
        final reason = _whyAlike(a, b);
        if (reason != null) found.add(PossibleDuplicate(a, b, reason));
      }
    }
  }
  found.sort((x, y) => x.first.title.toLowerCase().compareTo(y.first.title.toLowerCase()));
  return found;
}
