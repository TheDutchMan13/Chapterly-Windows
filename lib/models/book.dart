import 'dart:convert';

import 'audio_progress.dart';
import 'book_format.dart';
import 'quote.dart';
import 'reading.dart';
import 'shelf.dart';
import 'wish_priority.dart';

int _idSequence = 0;

/// A new id that is unique even when several books are added in the same
/// microsecond (which can happen on Windows and in tests).
String newBookId() {
  _idSequence++;
  return '${DateTime.now().microsecondsSinceEpoch}-$_idSequence';
}

DateTime? _dateFromMillis(Object? value) =>
    value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

DateTime? _dateFromIso(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

BookFormat? _formatFromName(Object? value) =>
    value is String ? BookFormat.values.asNameMap()[value] : null;

WishPriority? _priorityFromName(Object? value) =>
    value is String ? WishPriority.values.asNameMap()[value] : null;

/// Every field this app writes in [Book.toJson].
const _knownJsonKeys = {
  'id', 'title', 'author', 'shelf', 'addedAt', 'tags', 'isbn', 'coverUrl',
  'firstPublishYear', 'pages', 'rating', 'startedAt', 'finishedAt', 'format',
  'favorite', 'notes', 'deletedAt', 'series', 'seriesNumber', 'readingLog',
  'previousReadings', 'collections', 'quotes', 'currentPage', 'aspectRatings',
  'priority', 'buyAt', 'queuePosition', 'audio', 'updatedAt',
};

/// Fields from a newer Chapterly that this app does not know yet.
Map<String, Object?> _extrasFrom(Map<String, dynamic> json) => {
      for (final entry in json.entries)
        if (!_knownJsonKeys.contains(entry.key)) entry.key: entry.value,
    };

Map<String, Object?> _objectMap(Object? value) => value is Map
    ? {for (final entry in value.entries) entry.key.toString(): entry.value}
    : const {};

List<String> _stringList(Object? value) =>
    value is List ? [for (final item in value) item.toString()] : const [];

Object? _decode(Object? text) => text is String ? jsonDecode(text) : null;

/// Reads {"plot": 4, ...}, keeping only whole numbers from 1 to 5.
Map<String, int> _ratingMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.value is int &&
          (entry.value as int) >= 1 &&
          (entry.value as int) <= 5)
        entry.key.toString(): entry.value as int,
  };
}

class Book {
  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.shelf,
    required this.addedAt,
    this.tags = const [],
    this.isbn,
    this.coverUrl,
    this.firstPublishYear,
    this.pages,
    this.rating,
    this.startedAt,
    this.finishedAt,
    this.format,
    this.favorite = false,
    this.notes,
    this.deletedAt,
    this.series,
    this.seriesNumber,
    this.readingLog = const [],
    this.previousReadings = const [],
    this.collections = const [],
    this.quotes = const [],
    this.currentPage,
    this.aspectRatings = const {},
    this.priority,
    this.buyAt,
    this.queuePosition,
    this.audio,
    this.extras = const {},
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? addedAt;

  final String id;

  /// When this book last changed. Used to merge changes made on two devices:
  /// the newer copy wins.
  final DateTime updatedAt;
  final String title;
  final String author;
  final Shelf shelf;
  final DateTime addedAt;
  final List<String> tags;
  final String? isbn;
  final String? coverUrl;
  final int? firstPublishYear;
  final int? pages;
  final BookFormat? format;
  final bool favorite;
  final String? notes;

  /// Set when the book is in the trash.
  final DateTime? deletedAt;

  /// The series this book belongs to, and its place in it (1, 2, 3...).
  final String? series;
  final int? seriesNumber;

  /// The current reading: 1 to 5 stars (or null), dates, and pages logged.
  final int? rating;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<LogEntry> readingLog;

  /// Earlier readings, oldest first. Each one counts as a finished read.
  final List<Reading> previousReadings;

  /// Your own shelves (for example "Book club") this book is on, as well as
  /// its reading shelf.
  final List<String> collections;

  /// Passages saved from this book.
  final List<Quote> quotes;

  /// The page you are on now, for books you are reading.
  final int? currentPage;

  /// Ratings for parts of the book (keys are [RatingAspect] names), 1 to 5.
  final Map<String, int> aspectRatings;

  /// How much you want to read this book, for the For later shelf.
  final WishPriority? priority;

  /// Where to buy or borrow it: a shop, a library or a web link.
  final String? buyAt;

  /// Place in your Next up order (0 is first). Null when not placed.
  final int? queuePosition;

  /// Where you are in the audiobook, or null if you have not listened.
  final AudioProgress? audio;

  /// Fields sent by a newer phone app that this Windows app does not know.
  /// They are saved and sent back unchanged, so a sync never wipes them.
  final Map<String, Object?> extras;

  /// [buyAt] as a web link, or null when it is plain text such as "Library".
  Uri? get buyLink {
    final text = buyAt?.trim() ?? '';
    if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
    final hasScheme = text.startsWith('http://') || text.startsWith('https://');
    if (!hasScheme && !text.contains('.')) return null;
    final uri = Uri.tryParse(hasScheme ? text : 'https://$text');
    return uri != null && uri.host.contains('.') ? uri : null;
  }

  /// How far you are: the current page, or else the pages in the reading log
  /// of this reading. Null when neither is known.
  int? get progressPage {
    final page = currentPage;
    if (page != null && page > 0) return page;
    final logged = readingLog.fold<int>(0, (sum, entry) => sum + entry.pages);
    return logged > 0 ? logged : null;
  }

  /// 0.0 to 1.0, or null when the page count or progress is unknown.
  double? get progress {
    final total = pages;
    final done = progressPage;
    if (total == null || total <= 0 || done == null) return null;
    final value = done / total;
    return value > 1 ? 1.0 : value;
  }

  Reading get currentReading => Reading(
        startedAt: startedAt,
        finishedAt: finishedAt,
        rating: rating,
        log: readingLog,
      );

  /// Every time this book has been finished, for statistics.
  List<Reading> get finishedReadings => [
        ...previousReadings,
        if (shelf == Shelf.finished) currentReading,
      ];

  /// Fields that can be cleared take a function so that `() => null` means
  /// "clear it" while leaving the argument out means "keep it".
  Book copyWith({
    String? title,
    String? author,
    Shelf? shelf,
    List<String>? tags,
    bool? favorite,
    List<LogEntry>? readingLog,
    List<Reading>? previousReadings,
    List<String>? collections,
    List<Quote>? quotes,
    String? Function()? isbn,
    String? Function()? coverUrl,
    int? Function()? firstPublishYear,
    BookFormat? Function()? format,
    String? Function()? notes,
    String? Function()? series,
    int? Function()? seriesNumber,
    DateTime? Function()? deletedAt,
    int? Function()? pages,
    int? Function()? rating,
    DateTime? Function()? startedAt,
    DateTime? Function()? finishedAt,
    int? Function()? currentPage,
    Map<String, int>? aspectRatings,
    WishPriority? Function()? priority,
    String? Function()? buyAt,
    int? Function()? queuePosition,
    AudioProgress? Function()? audio,
    DateTime? updatedAt,
  }) =>
      Book(
        id: id,
        title: title ?? this.title,
        author: author ?? this.author,
        shelf: shelf ?? this.shelf,
        addedAt: addedAt,
        tags: tags ?? this.tags,
        isbn: isbn != null ? isbn() : this.isbn,
        coverUrl: coverUrl != null ? coverUrl() : this.coverUrl,
        firstPublishYear: firstPublishYear != null
            ? firstPublishYear()
            : this.firstPublishYear,
        pages: pages != null ? pages() : this.pages,
        rating: rating != null ? rating() : this.rating,
        startedAt: startedAt != null ? startedAt() : this.startedAt,
        finishedAt: finishedAt != null ? finishedAt() : this.finishedAt,
        format: format != null ? format() : this.format,
        favorite: favorite ?? this.favorite,
        notes: notes != null ? notes() : this.notes,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
        series: series != null ? series() : this.series,
        seriesNumber:
            seriesNumber != null ? seriesNumber() : this.seriesNumber,
        readingLog: readingLog ?? this.readingLog,
        previousReadings: previousReadings ?? this.previousReadings,
        collections: collections ?? this.collections,
        quotes: quotes ?? this.quotes,
        currentPage: currentPage != null ? currentPage() : this.currentPage,
        aspectRatings: aspectRatings ?? this.aspectRatings,
        priority: priority != null ? priority() : this.priority,
        buyAt: buyAt != null ? buyAt() : this.buyAt,
        queuePosition:
            queuePosition != null ? queuePosition() : this.queuePosition,
        audio: audio != null ? audio() : this.audio,
        extras: extras,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Column values for the SQLite `books` table.
  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'author': author,
        'shelf': shelf.name,
        'added_at': addedAt.millisecondsSinceEpoch,
        'tags': jsonEncode(tags),
        'isbn': isbn,
        'cover_url': coverUrl,
        'first_publish_year': firstPublishYear,
        'pages': pages,
        'rating': rating,
        'started_at': startedAt?.millisecondsSinceEpoch,
        'finished_at': finishedAt?.millisecondsSinceEpoch,
        'format': format?.name,
        'favorite': favorite ? 1 : 0,
        'notes': notes,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
        'series': series,
        'series_number': seriesNumber,
        'reading_log': jsonEncode([for (final e in readingLog) e.toJson()]),
        'previous_readings':
            jsonEncode([for (final r in previousReadings) r.toJson()]),
        'collections': jsonEncode(collections),
        'quotes': jsonEncode([for (final q in quotes) q.toJson()]),
        'current_page': currentPage,
        'aspect_ratings': jsonEncode(aspectRatings),
        'priority': priority?.name,
        'buy_at': buyAt,
        'queue_position': queuePosition,
        'audio': switch (audio) {
          null => null,
          final AudioProgress progress => jsonEncode(progress.toJson()),
        },
        'extras': extras.isEmpty ? null : jsonEncode(extras),
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Book.fromMap(Map<String, Object?> map) => Book(
        id: map['id'] as String,
        title: map['title'] as String,
        author: map['author'] as String,
        shelf: Shelf.values.byName(map['shelf'] as String),
        addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
        tags: List<String>.from(jsonDecode(map['tags'] as String) as List),
        isbn: map['isbn'] as String?,
        coverUrl: map['cover_url'] as String?,
        firstPublishYear: map['first_publish_year'] as int?,
        pages: map['pages'] as int?,
        rating: map['rating'] as int?,
        startedAt: _dateFromMillis(map['started_at']),
        finishedAt: _dateFromMillis(map['finished_at']),
        format: _formatFromName(map['format']),
        favorite: map['favorite'] == 1,
        notes: map['notes'] as String?,
        deletedAt: _dateFromMillis(map['deleted_at']),
        series: map['series'] as String?,
        seriesNumber: map['series_number'] as int?,
        readingLog: logEntriesFromJson(_decode(map['reading_log'])),
        previousReadings: readingsFromJson(_decode(map['previous_readings'])),
        collections: _stringList(_decode(map['collections'])),
        quotes: quotesFromJson(_decode(map['quotes'])),
        currentPage: map['current_page'] as int?,
        aspectRatings: _ratingMap(_decode(map['aspect_ratings'])),
        priority: _priorityFromName(map['priority']),
        buyAt: map['buy_at'] as String?,
        queuePosition: map['queue_position'] as int?,
        audio: AudioProgress.fromJson(_decode(map['audio'])),
        extras: _objectMap(_decode(map['extras'])),
        updatedAt: _dateFromMillis(map['updated_at']),
      );

  /// Readable JSON used in backup files and sync.
  Map<String, Object?> toJson() => {
        ...extras,
        'id': id,
        'title': title,
        'author': author,
        'shelf': shelf.name,
        'addedAt': addedAt.toIso8601String(),
        'tags': tags,
        'isbn': isbn,
        'coverUrl': coverUrl,
        'firstPublishYear': firstPublishYear,
        'pages': pages,
        'rating': rating,
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'format': format?.name,
        'favorite': favorite,
        'notes': notes,
        'deletedAt': deletedAt?.toIso8601String(),
        'series': series,
        'seriesNumber': seriesNumber,
        'readingLog': [for (final e in readingLog) e.toJson()],
        'previousReadings': [for (final r in previousReadings) r.toJson()],
        'collections': collections,
        'quotes': [for (final q in quotes) q.toJson()],
        'currentPage': currentPage,
        'aspectRatings': aspectRatings,
        'priority': priority?.name,
        'buyAt': buyAt,
        'queuePosition': queuePosition,
        'audio': audio?.toJson(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String,
        title: json['title'] as String,
        author: (json['author'] as String?) ?? '',
        shelf: Shelf.values.asNameMap()[json['shelf']] ?? Shelf.forLater,
        addedAt: _dateFromIso(json['addedAt']) ?? DateTime.now(),
        tags: [
          for (final tag in (json['tags'] as List? ?? const [])) tag.toString(),
        ],
        isbn: json['isbn'] as String?,
        coverUrl: json['coverUrl'] as String?,
        firstPublishYear: json['firstPublishYear'] as int?,
        pages: json['pages'] as int?,
        rating: json['rating'] as int?,
        startedAt: _dateFromIso(json['startedAt']),
        finishedAt: _dateFromIso(json['finishedAt']),
        format: _formatFromName(json['format']),
        favorite: json['favorite'] == true,
        notes: json['notes'] as String?,
        deletedAt: _dateFromIso(json['deletedAt']),
        series: json['series'] as String?,
        seriesNumber: json['seriesNumber'] as int?,
        readingLog: logEntriesFromJson(json['readingLog']),
        previousReadings: readingsFromJson(json['previousReadings']),
        collections: _stringList(json['collections']),
        quotes: quotesFromJson(json['quotes']),
        currentPage: json['currentPage'] as int?,
        aspectRatings: _ratingMap(json['aspectRatings']),
        priority: _priorityFromName(json['priority']),
        buyAt: json['buyAt'] as String?,
        queuePosition: json['queuePosition'] as int?,
        audio: AudioProgress.fromJson(json['audio']),
        extras: _extrasFrom(json),
        updatedAt: _dateFromIso(json['updatedAt']),
      );
}
