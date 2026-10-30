import '../models/book.dart';
import 'open_library_client.dart';

/// The lines of a pasted list worth looking up: no blank lines, no list
/// markers ("- ", "* ", "1. "), and each line only once.
List<String> parseBulkLines(String text) {
  final seen = <String>{};
  final lines = <String>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw
        .trim()
        .replaceFirst(RegExp(r'^([-*•]|\d+[.)])\s+'), '')
        .trim();
    if (line.isEmpty) continue;
    if (seen.add(line.toLowerCase())) lines.add(line);
  }
  return lines;
}

bool _validIsbn10(String isbn) {
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    final char = isbn[i];
    final int value;
    if (char == 'X') {
      if (i != 9) return false;
      value = 10;
    } else {
      value = int.parse(char);
    }
    sum += value * (10 - i);
  }
  return sum % 11 == 0;
}

bool _validIsbn13(String isbn) {
  var sum = 0;
  for (var i = 0; i < 13; i++) {
    sum += int.parse(isbn[i]) * (i.isEven ? 1 : 3);
  }
  return sum % 10 == 0;
}

/// The ISBN on [line] (10 or 13 digits, dashes and spaces allowed, "ISBN"
/// in front allowed), or null when the line is not an ISBN.
String? isbnFromLine(String line) {
  final text = line
      .replaceFirst(RegExp(r'^isbn(-1[03])?:?', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s-]'), '')
      .toUpperCase();
  if (RegExp(r'^\d{13}$').hasMatch(text) && _validIsbn13(text)) return text;
  if (RegExp(r'^\d{9}[\dX]$').hasMatch(text) && _validIsbn10(text)) {
    return text;
  }
  return null;
}

/// Splits "Dune by Frank Herbert" or "Dune - Frank Herbert" into a title and
/// an author. The author is empty when the line has none.
({String title, String author}) splitTitleAuthor(String line) {
  for (final separator in [' by ', ' - ', ' – ', ' — ']) {
    final at = line.toLowerCase().lastIndexOf(separator);
    if (at > 0) {
      final title = line.substring(0, at).trim();
      final author = line.substring(at + separator.length).trim();
      if (title.isNotEmpty && author.isNotEmpty) {
        return (title: title, author: author);
      }
    }
  }
  return (title: line.trim(), author: '');
}

String _plain(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// The key used to spot a book already in the library.
String libraryKey(String title, String author) =>
    '${_plain(title)}|${_plain(author)}';

/// Whether a book with this title and author is already in [library]
/// (the trash does not count). An empty author matches any author.
bool alreadyInLibrary(List<Book> library, String title, String author) {
  final wantTitle = _plain(title);
  final wantAuthor = _plain(author);
  for (final book in library) {
    if (book.deletedAt != null) continue;
    if (_plain(book.title) != wantTitle) continue;
    if (wantAuthor.isEmpty || _plain(book.author) == wantAuthor) return true;
  }
  return false;
}

/// Where one line of the list stands.
enum BulkStatus { waiting, found, notFound, failed }

/// One line of a pasted list and what Open Library found for it.
class BulkItem {
  BulkItem(this.line) : isbn = isbnFromLine(line);

  final String line;

  /// Set when the line is an ISBN.
  final String? isbn;
  BulkStatus status = BulkStatus.waiting;
  OpenLibraryBook? match;

  /// Whether to add this book. Off for books already in the library.
  bool include = true;

  /// Whether a book with this title and author is already in the library.
  bool owned = false;

  /// The title to add: the match's, or the line as typed.
  String get title => match?.title ?? splitTitleAuthor(line).title;

  /// The author to add: the match's, or from the line as typed.
  String get author => match?.author ?? splitTitleAuthor(line).author;

  /// Whether this line can be added at all. An ISBN with no match has no
  /// title to add.
  bool get addable =>
      status != BulkStatus.waiting && (match != null || isbn == null);
}

/// The best Open Library match for [line]: the book for an ISBN, or the
/// first search result (preferring one by the author, if the line names one).
Future<OpenLibraryBook?> lookUpLine(
  OpenLibraryClient client,
  String line,
) async {
  final isbn = isbnFromLine(line);
  if (isbn != null) return client.lookupIsbn(isbn);
  final parts = splitTitleAuthor(line);
  final query =
      parts.author.isEmpty ? parts.title : '${parts.title} ${parts.author}';
  final results = await client.search(query);
  if (results.isEmpty) return null;
  if (parts.author.isNotEmpty) {
    final wanted = _plain(parts.author);
    for (final result in results) {
      final author = _plain(result.author);
      if (author.contains(wanted) || wanted.contains(author)) return result;
    }
  }
  return results.first;
}

/// Looks up every item, [workers] at a time, calling [onUpdate] after each
/// one so the screen can show progress. Marks books already in [library].
Future<void> lookUpAll(
  List<BulkItem> items, {
  required Future<OpenLibraryBook?> Function(String line) lookUp,
  required List<Book> library,
  required void Function() onUpdate,
  int workers = 4,
}) async {
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final item = items[next++];
      try {
        item.match = await lookUp(item.line);
        item.status =
            item.match == null ? BulkStatus.notFound : BulkStatus.found;
      } catch (_) {
        item.status = BulkStatus.failed;
      }
      item.owned = alreadyInLibrary(library, item.title, item.author);
      item.include = item.addable && !item.owned;
      onUpdate();
    }
  }

  await Future.wait([
    for (var i = 0; i < workers && i < items.length; i++) worker(),
  ]);
}
