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

/// The result that is clearly [book]: the same title (or the same main
/// title) and, when both have one, an author sharing a name. Null when none
/// is.
OpenLibraryBook? bestOpenLibraryMatch(Book book, List<OpenLibraryBook> found) {
  Set<String> words(String text) => {
        for (final word in text.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+',
            unicode: true)))
          if (word.length > 2) word,
      };
  final authorWords = words(book.author);
  for (final result in found) {
    if (titleScore(book.title, result.title) < 85) continue;
    if (authorWords.isNotEmpty && result.author.trim().isNotEmpty) {
      if (words(result.author).intersection(authorWords).isEmpty) continue;
    }
    return result;
  }
  return null;
}

/// Looks the book up on Open Library (by ISBN first, then title and author)
/// and fills in what it does not have yet: ISBN, first published year,
/// cover and pages. Nothing the book already has is changed.
Future<RefreshOutcome> refreshBookDetails(
  BookRepository repository,
  OpenLibraryClient client,
  Book book,
) async {
  OpenLibraryBook? match;
  try {
    final isbn = (book.isbn ?? '').replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (isbn.length >= 10) {
      final byIsbn = await client.lookupIsbn(isbn);
      if (byIsbn != null) match = bestOpenLibraryMatch(book, [byIsbn]) ?? byIsbn;
    }
    match ??= bestOpenLibraryMatch(
      book,
      await client.search('${book.title} ${book.author}'.trim()),
    );
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
