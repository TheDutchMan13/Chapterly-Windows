import 'dart:convert';

import '../models/wish_priority.dart';
import 'fuzzy.dart';

/// A book you want but do not have yet. It is not in your library until you
/// move it there (see the Wish list screen).
class Wish {
  const Wish({
    required this.id,
    required this.title,
    required this.addedAt,
    this.author = '',
    this.isbn,
    this.priority,
    this.where,
    this.note = '',
  });

  final String id;
  final String title;
  final String author;
  final String? isbn;
  final WishPriority? priority;

  /// Where to get it: a shop, a library, or a web link.
  final String? where;
  final String note;
  final DateTime addedAt;

  Wish copyWith({
    String? title,
    String? author,
    String? Function()? isbn,
    WishPriority? Function()? priority,
    String? Function()? where,
    String? note,
  }) =>
      Wish(
        id: id,
        title: title ?? this.title,
        author: author ?? this.author,
        isbn: isbn != null ? isbn() : this.isbn,
        priority: priority != null ? priority() : this.priority,
        where: where != null ? where() : this.where,
        note: note ?? this.note,
        addedAt: addedAt,
      );

  /// The words a search looks at, without accents.
  String get searchText => foldText(
        [title, author, isbn ?? '', where ?? '', note].join(' '),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'isbn': isbn,
        'priority': priority?.name,
        'where': where,
        'note': note,
        'addedAt': addedAt.toIso8601String(),
      };

  static Wish? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final addedAt = DateTime.tryParse('${value['addedAt']}');
    if (id is! String || title is! String || addedAt == null) return null;
    final priority = value['priority'];
    final author = value['author'];
    final isbn = value['isbn'];
    final where = value['where'];
    final note = value['note'];
    return Wish(
      id: id,
      title: title,
      addedAt: addedAt,
      author: author is String ? author : '',
      isbn: isbn is String ? isbn : null,
      priority: priority is String
          ? WishPriority.values.asNameMap()[priority]
          : null,
      where: where is String && where.trim().isNotEmpty ? where : null,
      note: note is String ? note : '',
    );
  }
}

/// The wish list as saved in settings. Damaged entries are skipped.
List<Wish> decodeWishes(String? text) {
  if (text == null || text.isEmpty) return const [];
  try {
    final data = jsonDecode(text);
    if (data is! List) return const [];
    return [for (final item in data) ?Wish.fromJson(item)];
  } catch (_) {
    return const [];
  }
}

String encodeWishes(List<Wish> wishes) =>
    jsonEncode([for (final wish in wishes) wish.toJson()]);

/// Highest priority first, then by title.
List<Wish> sortWishes(List<Wish> wishes) {
  int rank(WishPriority? p) => switch (p) {
        WishPriority.high => 0,
        WishPriority.medium => 1,
        WishPriority.low => 2,
        null => 3,
      };
  return [...wishes]..sort((a, b) {
      final byPriority = rank(a.priority).compareTo(rank(b.priority));
      return byPriority != 0
          ? byPriority
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
}

/// The wishes matching [query]: every word somewhere (in any order), with
/// the same typo forgiveness as the library search. An empty query gives all.
List<Wish> searchWishes(List<Wish> wishes, String query) {
  if (query.trim().isEmpty) return sortWishes(wishes);
  final vocabulary = {
    for (final wish in wishes) ...foldedWords(wish.searchText),
  };
  final plan = SearchPlan.build(query, vocabulary);
  return sortWishes([
    for (final wish in wishes)
      if (plan.matchesFolded(wish.searchText)) wish,
  ]);
}
