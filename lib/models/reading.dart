DateTime? _parse(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Pages read and minutes spent reading on one day. Either can be 0.
class LogEntry {
  const LogEntry({required this.date, this.pages = 0, this.minutes = 0});

  final DateTime date;
  final int pages;
  final int minutes;

  Map<String, Object?> toJson() => {
        'date': date.toIso8601String(),
        'pages': pages,
        'minutes': minutes,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        date: DateTime.parse(json['date'] as String),
        pages: (json['pages'] as int?) ?? 0,
        minutes: (json['minutes'] as int?) ?? 0,
      );
}

/// One time through a book: when it was started and finished, the rating
/// given, and the pages logged along the way.
class Reading {
  const Reading({
    this.startedAt,
    this.finishedAt,
    this.rating,
    this.log = const [],
  });

  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? rating;
  final List<LogEntry> log;

  Map<String, Object?> toJson() => {
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'rating': rating,
        'log': [for (final entry in log) entry.toJson()],
      };

  factory Reading.fromJson(Map<String, dynamic> json) => Reading(
        startedAt: _parse(json['startedAt']),
        finishedAt: _parse(json['finishedAt']),
        rating: json['rating'] as int?,
        log: logEntriesFromJson(json['log']),
      );
}

List<LogEntry> logEntriesFromJson(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map<String, dynamic>) LogEntry.fromJson(item),
      ]
    : const [];

List<Reading> readingsFromJson(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map<String, dynamic>) Reading.fromJson(item),
      ]
    : const [];
