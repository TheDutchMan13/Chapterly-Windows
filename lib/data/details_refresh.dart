import '../models/book.dart';
import 'book_repository.dart';
import 'file_match.dart';
import 'open_library_client.dart';

// Windows app only.

/// What refreshing one book from Open Library did.
enum RefreshOutcome {
  /// Something blank was filled in.
  updated,

  /// Found, but the book already had everything Open Library has.
  unchanged,

  /// No result that is clearly this book.
  notFound,

  /// Open Library could not be reached.
  failed,
}

Set<String> _words(String text) => {
      for (final word in text.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+',
          unicode: true)))
        if (word.length > 2) word,
    };

/// Whether [result] is clearly the book with this [title] and [author]: the
/// same title (or the same main title) and, when both have one, an author
/// sharing a name.
bool isOpenLibraryMatch(String title, String author, OpenLibraryBook result) {
  if (titleScore(title, result.title) < 85) return false;
  final authorWords = _words(author);
  if (authorWords.isNotEmpty && result.author.trim().isNotEmpty) {
    if (_words(result.author).intersection(authorWords).isEmpty) return false;
  }
  return true;
}

/// The result that is clearly [book]: the same title (or the same main
/// title) and, when both have one, an author sharing a name. Null when none
/// is.
OpenLibraryBook? bestOpenLibraryMatch(Book book, List<OpenLibraryBook> found) {
  for (final result in found) {
    if (isOpenLibraryMatch(book.title, book.author, result)) return result;
  }
  return null;
}

/// Looks the book up on Open Library (by ISBN first, then title and author)
/// and returns the result that is clearly this book, or null. Throws when
/// Open Library cannot be reached.
Future<OpenLibraryBook?> lookupOpenLibraryMatch(
  OpenLibraryClient client,
  Book book,
) async {
  OpenLibraryBook? match;
  final isbn = (book.isbn ?? '').replaceAll(RegExp(r'[^0-9Xx]'), '');
  if (isbn.length >= 10) {
    final byIsbn = await client.lookupIsbn(isbn);
    if (byIsbn != null) match = bestOpenLibraryMatch(book, [byIsbn]) ?? byIsbn;
  }
  return match ??
      bestOpenLibraryMatch(
        book,
        await client.search('${book.title} ${book.author}'.trim()),
      );
}

/// Looks the book up on Open Library (by ISBN first, then title and author)
/// and fills in what it does not have yet: ISBN, first published year,
/// cover and pages. Nothing the book already has is changed.
Future<RefreshOutcome> refreshBookDetails(
  BookRepository repository,
  OpenLibraryClient client,
  Book book,
) async {
  final OpenLibraryBook? match;
  try {
    match = await lookupOpenLibraryMatch(client, book);
  } catch (_) {
    return RefreshOutcome.failed;
  }
  if (match == null) return RefreshOutcome.notFound;
  var changed = await repository.fillBlanks(
    book.id,
    isbn: match.isbn,
    year: match.firstPublishYear,
    coverUrl: match.coverUrl,
  );
  final pages = match.pages;
  if (book.pages == null && pages != null && pages > 0) {
    await repository.setPages(book.id, pages);
    changed = true;
  }
  return changed ? RefreshOutcome.updated : RefreshOutcome.unchanged;
}
