import '../models/book.dart';
import 'details_refresh.dart';
import 'google_books_client.dart';
import 'library_health.dart';
import 'open_library_client.dart';

// The same file is in the Android app; keep the two copies alike.

/// An ISBN found on Open Library or Google Books for a book that has none.
class IsbnFix {
  const IsbnFix({
    required this.book,
    required this.isbn,
    this.source = 'Open Library',
  });

  final Book book;

  /// Always an ISBN-13.
  final String isbn;

  /// Where it was found: 'Open Library' or 'Google Books'.
  final String source;
}

/// What a scan for missing ISBNs found.
class IsbnScanResult {
  const IsbnScanResult({
    required this.checked,
    required this.fixes,
    required this.noMatch,
    required this.stopped,
    required this.unreachable,
    this.googleQuotaReached = false,
  });

  final int checked;
  final List<IsbnFix> fixes;

  /// Books with no clear match, or whose match has no valid ISBN.
  final int noMatch;
  final bool stopped;
  final bool unreachable;

  /// Google said it has no more searches today, so later books were only
  /// looked up on Open Library.
  final bool googleQuotaReached;
}

/// Books (not in the trash) that have no ISBN.
List<Book> booksWithoutIsbn(List<Book> books) => [
      for (final book in books)
        if (book.deletedAt == null && (book.isbn ?? '').trim().isEmpty) book,
    ];

/// The valid ISBN in [text] as an ISBN-13, or null.
String? isbn13Of(String? text) {
  final digits = isbnDigits(text ?? '');
  if (digits.length == 13) return isValidIsbn(digits) ? digits : null;
  return isbn10To13(digits);
}

/// Looks up each of [books] on Open Library (by title and author) and
/// collects the ISBN of the result that is clearly that book. When Open
/// Library has none and [google] is given, Google Books is asked next.
/// Nothing is saved. After three failures in a row it gives up.
Future<IsbnScanResult> scanIsbns(
  List<Book> books,
  OpenLibraryClient client, {
  bool Function()? cancelled,
  void Function(int done, int total)? onProgress,
  void Function(IsbnFix fix)? onFix,
  Duration pause = const Duration(milliseconds: 250),
  GoogleBooksClient? google,
}) async {
  final fixes = <IsbnFix>[];
  var noMatch = 0, failures = 0, done = 0;
  var stopped = false, unreachable = false, googleQuota = false;
  for (final book in books) {
    if (cancelled?.call() ?? false) {
      stopped = true;
      break;
    }
    var reached = true;
    String? isbn;
    var source = 'Open Library';
    try {
      final match = await lookupOpenLibraryMatch(client, book);
      failures = 0;
      isbn = isbn13Of(match?.isbn);
    } catch (_) {
      failures++;
      reached = false;
    }
    if (isbn == null && reached && google != null && !googleQuota) {
      try {
        isbn = isbn13Of((await google.find(book))?.isbn);
        if (isbn != null) source = 'Google Books';
      } on GoogleQuotaReached {
        googleQuota = true;
      } catch (_) {
        // Google could not be asked; the book stays without an ISBN.
      }
    }
    if (isbn != null) {
      final fix = IsbnFix(book: book, isbn: isbn, source: source);
      fixes.add(fix);
      onFix?.call(fix);
    } else if (reached) {
      noMatch++;
    }
    await Future<void>.delayed(pause);
    done++;
    onProgress?.call(done, books.length);
    if (failures >= 3) {
      unreachable = true;
      break;
    }
  }
  return IsbnScanResult(
    checked: done,
    fixes: fixes,
    noMatch: noMatch,
    stopped: stopped,
    unreachable: unreachable,
    googleQuotaReached: googleQuota,
  );
}
