// The same file is in both apps (lib/data/challenges.dart).

import 'dart:convert';

import '../models/book.dart';

/// What a challenge counts.
enum ChallengeKind {
  books('books', 'Books finished'),
  pages('pages', 'Pages in books finished'),
  tag('tag', 'Books finished with a tag'),
  authors('authors', 'Different authors read');

  const ChallengeKind(this.key, this.label);

  final String key;
  final String label;

  /// The word after a number: "12 books".
  String unit(int count) => switch (this) {
        ChallengeKind.pages => count == 1 ? 'page' : 'pages',
        ChallengeKind.authors => count == 1 ? 'author' : 'authors',
        _ => count == 1 ? 'book' : 'books',
      };

  static ChallengeKind? fromKey(Object? key) {
    for (final kind in values) {
      if (kind.key == key) return kind;
    }
    return null;
  }
}

/// A reading challenge of your own, between two dates: "12 books by March",
/// "3 books tagged Horror in October".
class ReadingChallenge {
  const ReadingChallenge({
    required this.id,
    required this.name,
    required this.kind,
    required this.target,
    required this.start,
    required this.end,
    this.tag,
  });

  final String id;
  final String name;
  final ChallengeKind kind;
  final int target;

  /// The first day and the last day (both counted).
  final DateTime start;
  final DateTime end;

  /// For [ChallengeKind.tag]: the tag to count.
  final String? tag;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.key,
        'target': target,
        'start': _day(start).toIso8601String(),
        'end': _day(end).toIso8601String(),
        if (tag != null) 'tag': tag,
      };

  static ReadingChallenge? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final kind = ChallengeKind.fromKey(json['kind']);
    final target = json['target'];
    final start = DateTime.tryParse('${json['start']}');
    final end = DateTime.tryParse('${json['end']}');
    final tag = json['tag'];
    if (id is! String || name is! String || kind == null) return null;
    if (target is! int || target <= 0 || start == null || end == null) {
      return null;
    }
    if (kind == ChallengeKind.tag && (tag is! String || tag.trim().isEmpty)) {
      return null;
    }
    return ReadingChallenge(
      id: id,
      name: name,
      kind: kind,
      target: target,
      start: _day(start),
      end: _day(end),
      tag: tag is String ? tag : null,
    );
  }
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

/// Saved challenges, as kept in settings.
String encodeChallenges(List<ReadingChallenge> challenges) =>
    jsonEncode([for (final c in challenges) c.toJson()]);

List<ReadingChallenge> decodeChallenges(String? text) {
  if (text == null) return [];
  try {
    final data = jsonDecode(text);
    if (data is! List) return [];
    return [
      for (final item in data)
        if (ReadingChallenge.fromJson(item) case final challenge?) challenge,
    ];
  } on FormatException {
    return [];
  }
}

/// How a challenge is going.
class ChallengeProgress {
  const ChallengeProgress({
    required this.challenge,
    required this.count,
    required this.daysLeft,
    required this.ahead,
  });

  final ReadingChallenge challenge;
  final int count;

  /// Days left including today; 0 once it has ended, null before it starts.
  final int? daysLeft;

  /// Ahead of (positive) or behind (negative) an even pace, while it runs.
  final int? ahead;

  bool get reached => count >= challenge.target;
  bool get ended => daysLeft == 0;
  bool get notStarted => daysLeft == null;

  double get fraction => (count / challenge.target).clamp(0.0, 1.0).toDouble();

  /// "8 of 12 books · 23 days left · 1 ahead of pace".
  String describe() {
    final kind = challenge.kind;
    final parts = [
      '$count of ${challenge.target} ${kind.unit(challenge.target)}',
    ];
    if (reached) {
      parts.add('done!');
    } else if (notStarted) {
      parts.add('starts ${_short(challenge.start)}');
    } else if (ended) {
      parts.add('ended ${_short(challenge.end)}');
    } else {
      parts.add(daysLeft == 1 ? 'last day' : '$daysLeft days left');
      final pace = ahead;
      if (pace != null && pace != 0) {
        parts.add(pace > 0 ? '$pace ahead of pace' : '${-pace} behind pace');
      }
    }
    return parts.join(' · ');
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _short(DateTime date) => '${_months[date.month - 1]} ${date.day}';

/// "Mar 1 – May 31, 2027".
String challengeDates(ReadingChallenge challenge) {
  final start = challenge.start;
  final end = challenge.end;
  return start.year == end.year
      ? '${_short(start)} – ${_short(end)}, ${end.year}'
      : '${_short(start)}, ${start.year} – ${_short(end)}, ${end.year}';
}

/// Counts [challenge] in [books] (books in the trash are left out): every
/// reading finished between its dates, re-reads included.
ChallengeProgress challengeProgress(
  ReadingChallenge challenge,
  List<Book> books, {
  DateTime? now,
}) {
  final start = challenge.start;
  final afterEnd = challenge.end.add(const Duration(days: 1));
  final tag = challenge.tag?.trim().toLowerCase();
  var count = 0;
  final authors = <String>{};
  for (final book in books) {
    if (book.deletedAt != null) continue;
    if (challenge.kind == ChallengeKind.tag &&
        !book.tags.any((t) => t.trim().toLowerCase() == tag)) {
      continue;
    }
    for (final reading in book.finishedReadings) {
      final at = reading.finishedAt;
      if (at == null || at.isBefore(start) || !at.isBefore(afterEnd)) {
        continue;
      }
      switch (challenge.kind) {
        case ChallengeKind.books:
        case ChallengeKind.tag:
          count++;
        case ChallengeKind.pages:
          count += book.pages ?? 0;
        case ChallengeKind.authors:
          final author = book.author.trim().toLowerCase();
          if (author.isNotEmpty) authors.add(author);
      }
    }
  }
  if (challenge.kind == ChallengeKind.authors) count = authors.length;
  final today = _day(now ?? DateTime.now());
  int? daysLeft;
  int? ahead;
  if (!today.isBefore(start)) {
    if (today.isAfter(challenge.end)) {
      daysLeft = 0;
    } else {
      daysLeft = _days(today, challenge.end) + 1;
      final total = _days(start, challenge.end) + 1;
      final passed = _days(start, today) + 1;
      ahead = count - (challenge.target * passed / total).floor();
    }
  }
  return ChallengeProgress(
    challenge: challenge,
    count: count,
    daysLeft: daysLeft,
    ahead: ahead,
  );
}

int _days(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
