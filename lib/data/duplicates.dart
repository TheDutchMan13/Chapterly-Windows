import '../models/book.dart';
import '../models/quote.dart';

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
