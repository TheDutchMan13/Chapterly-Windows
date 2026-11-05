import 'book.dart';

// The same file is in the Android app; keep the two copies alike.

/// Where a book came from, and its details as they were when it was added
/// (or matched), before you changed them. Kept with the book and synced.
class BookOrigin {
  const BookOrigin({
    this.name,
    this.source,
    required this.title,
    required this.author,
    this.series,
    this.seriesNumber,
    this.isbn,
    this.pages,
    this.year,
    this.editedAt,
    this.matchConfirmed = false,
  });

  /// The book's original name: the name of its file (or folder, for an
  /// audiobook) on your book server or your PC. Null when the book did not
  /// come from a file.
  final String? name;

  /// Where it came from, in words: "Your book server", "A folder on this
  /// PC", "A file". Null when that was not recorded.
  final String? source;

  /// The details it was added with.
  final String title;
  final String author;
  final String? series;
  final int? seriesNumber;
  final String? isbn;
  final int? pages;
  final int? year;

  /// When you last corrected the book's details yourself, or null if you
  /// never did (or reset them).
  final DateTime? editedAt;

  /// Whether you said the match is right in Review matches, so it is not
  /// listed there again.
  final bool matchConfirmed;

  /// The details [book] has now, with [name] and [source] when known.
  factory BookOrigin.of(Book book, {String? name, String? source}) =>
      BookOrigin(
        name: _clean(name),
        source: _clean(source),
        title: book.title,
        author: book.author,
        series: book.series,
        seriesNumber: book.seriesNumber,
        isbn: book.isbn,
        pages: book.pages,
        year: book.firstPublishYear,
      );

  bool get edited => editedAt != null;

  BookOrigin withEditedAt(DateTime? time) => _copy(editedAt: () => time);

  BookOrigin withMatchConfirmed(bool confirmed) =>
      _copy(matchConfirmed: confirmed);

  BookOrigin _copy({DateTime? Function()? editedAt, bool? matchConfirmed}) =>
      BookOrigin(
        name: name,
        source: source,
        title: title,
        author: author,
        series: series,
        seriesNumber: seriesNumber,
        isbn: isbn,
        pages: pages,
        year: year,
        editedAt: editedAt == null ? this.editedAt : editedAt(),
        matchConfirmed: matchConfirmed ?? this.matchConfirmed,
      );

  /// Whether [book]'s details are still the ones it was added with.
  bool sameDetailsAs(Book book) =>
      book.title == title &&
      book.author == author &&
      book.series == series &&
      book.seriesNumber == seriesNumber &&
      book.isbn == isbn &&
      book.pages == pages &&
      book.firstPublishYear == year;

  Map<String, Object?> toJson() => {
        'name': ?name,
        'source': ?source,
        'title': title,
        'author': author,
        'series': ?series,
        'seriesNumber': ?seriesNumber,
        'isbn': ?isbn,
        'pages': ?pages,
        'year': ?year,
        if (editedAt case final time?) 'editedAt': time.toIso8601String(),
        if (matchConfirmed) 'matchConfirmed': true,
      };

  /// Reads [toJson]. Null for anything that is not an origin.
  static BookOrigin? fromJson(Object? value) {
    if (value is! Map) return null;
    final title = value['title'];
    if (title is! String) return null;
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    int? number(Object? v) => v is int ? v : null;
    final edited = value['editedAt'];
    return BookOrigin(
      name: text(value['name']),
      source: text(value['source']),
      title: title,
      author: value['author'] is String ? value['author'] as String : '',
      series: text(value['series']),
      seriesNumber: number(value['seriesNumber']),
      isbn: text(value['isbn']),
      pages: number(value['pages']),
      year: number(value['year']),
      editedAt: edited is String ? DateTime.tryParse(edited) : null,
      matchConfirmed: value['matchConfirmed'] == true,
    );
  }

  static String? _clean(String? text) {
    final value = text?.trim() ?? '';
    return value.isEmpty ? null : value;
  }
}
