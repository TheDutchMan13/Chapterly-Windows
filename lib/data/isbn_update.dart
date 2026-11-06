import '../models/book.dart';
import 'details_refresh.dart';
import 'library_health.dart';
import 'open_library_client.dart';

// The same file is in the Android app; keep the two copies alike.

/// An ISBN found on Open Library for a book that has none.
class IsbnFix {
  const IsbnFix({required this.book, required this.isbn});

  final Book book;

  /// Always an ISBN-13.
  final String isbn;
}

/// What a scan for missing ISBNs found.
class IsbnScanResult {
  const IsbnScanResult({
    required this.checked,
    required this.fixes,
    required this.noMatch,
    required this.stopped,
    required this.unreachable,
  });

  final int checked;
  final List<IsbnFix> fixes;

  /// Books with no clear match, or whose match has no valid ISBN.
  final int noMatch;
  final bool stopped;
  final bool unreachable;
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
/// collects the ISBN of the result that is clearly that book. Nothing is
/// saved. After three failures in a row it gives up.
Future<IsbnScanResult> scanIsbns(
  List<Book> books,
  OpenLibraryClient client, {
  bool Function()? cancelled,
  void Function(int done, int total)? onProgress,
  void Function(IsbnFix fix)? onFix,
  Duration pause = const Duration(milliseconds: 250),
}) async {
  final fixes = <IsbnFix>[];
  var noMatch = 0, failures = 0, done = 0;
  var stopped = false, unreachable = false;
  for (final book in books) {
    if (cancelled?.call() ?? false) {
      stopped = true;
      break;
    }
    try {
      final match = await lookupOpenLibraryMatch(client, book);
      failures = 0;
      final isbn = isbn13Of(match?.isbn);
      if (isbn == null) {
        noMatch++;
      } else {
        final fix = IsbnFix(book: book, isbn: isbn);
        fixes.add(fix);
        onFix?.call(fix);
      }
    } catch (_) {
      failures++;
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
  );
}
