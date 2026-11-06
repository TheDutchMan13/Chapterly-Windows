import '../models/book.dart';
import 'details_refresh.dart';
import 'google_books_client.dart';
import 'open_library_client.dart';

// The same file is in the Android app; keep the two copies alike.

/// Whether [url] is a cover from Open Library.
bool isOpenLibraryCover(String? url) =>
    url != null && Uri.tryParse(url.trim())?.host == 'covers.openlibrary.org';

/// Why a book's cover is to be replaced.
enum CoverProblem { missing, broken }

/// A better cover found for [book].
class CoverFix {
  const CoverFix({
    required this.book,
    required this.problem,
    required this.newUrl,
    this.source = 'Open Library',
  });

  final Book book;
  final CoverProblem problem;
  final String newUrl;

  /// Where the new cover is from: "Open Library" or "Google Books".
  final String source;
}

/// What a scan for covers to update found.
class CoverScanResult {
  const CoverScanResult({
    required this.checked,
    required this.fixes,
    required this.noMatch,
    required this.stopped,
    required this.unreachable,
    this.googleQuotaReached = false,
  });

  /// Whether Google Books ran out of searches for today during the scan.
  final bool googleQuotaReached;

  /// How many books were looked at.
  final int checked;

  /// The covers found.
  final List<CoverFix> fixes;

  /// Books that need a cover but have no clear match on Open Library.
  final int noMatch;

  /// Whether the scan was stopped before it looked at every book.
  final bool stopped;

  /// Whether the scan gave up because Open Library could not be reached.
  final bool unreachable;
}

/// The books whose cover the update may replace: those with no cover and
/// those whose cover comes from Open Library. A picture you added yourself,
/// or a cover from anywhere else, is never a candidate. Books in the trash
/// are left out.
List<Book> coverCandidates(List<Book> books) => [
      for (final book in books)
        if (book.deletedAt == null &&
            ((book.coverUrl ?? '').trim().isEmpty ||
                isOpenLibraryCover(book.coverUrl)))
          book,
    ];

/// Looks for covers to replace: for each of [books] with no cover, or an
/// Open Library cover that no longer exists, finds the cover Open Library
/// has for the book. A cover that still loads is never touched.
///
/// When [google] is given, a book Open Library has no cover for is looked up
/// on Google Books too. Google stops being asked once it has no more
/// searches for the day.
///
/// [onFix] is called for each cover found, [onProgress] after each book, and
/// the scan stops once [cancelled] returns true. After three failures in a
/// row it gives up, as Open Library cannot be reached.
Future<CoverScanResult> scanCovers(
  List<Book> books,
  OpenLibraryClient client, {
  bool Function()? cancelled,
  void Function(int done, int total)? onProgress,
  void Function(CoverFix fix)? onFix,
  Duration pause = const Duration(milliseconds: 250),
  GoogleBooksClient? google,
}) async {
  final fixes = <CoverFix>[];
  var noMatch = 0;
  var failures = 0;
  var done = 0;
  var stopped = false;
  var unreachable = false;
  var googleQuota = false;
  for (final book in books) {
    if (cancelled?.call() ?? false) {
      stopped = true;
      break;
    }
    final current = (book.coverUrl ?? '').trim();
    CoverProblem? problem;
    if (current.isEmpty) {
      problem = CoverProblem.missing;
    } else {
      final loads = await client.coverLoads(current);
      if (loads == false) problem = CoverProblem.broken;
      if (loads == null) {
        failures++;
      } else {
        failures = 0;
      }
    }
    if (problem != null) {
      String? found;
      var source = 'Open Library';
      var reached = true;
      try {
        final match = await lookupOpenLibraryMatch(client, book);
        failures = 0;
        found = match?.coverUrl;
        if (found != null &&
            (found == current || await client.coverLoads(found) == false)) {
          found = null;
        }
      } catch (_) {
        failures++;
        reached = false;
      }
      if (found == null && reached && google != null && !googleQuota) {
        try {
          final other = (await google.find(book))?.coverUrl;
          if (other != null && other != current) {
            found = other;
            source = 'Google Books';
          }
        } on GoogleQuotaReached {
          googleQuota = true;
        } catch (_) {
          // Google could not be asked; the book stays without a cover.
        }
      }
      if (found != null) {
        final fix = CoverFix(
          book: book,
          problem: problem,
          newUrl: found,
          source: source,
        );
        fixes.add(fix);
        onFix?.call(fix);
      } else if (reached) {
        noMatch++;
      }
      await Future<void>.delayed(pause);
    }
    done++;
    onProgress?.call(done, books.length);
    if (failures >= 3) {
      unreachable = true;
      break;
    }
  }
  return CoverScanResult(
    checked: done,
    fixes: fixes,
    noMatch: noMatch,
    stopped: stopped,
    unreachable: unreachable,
    googleQuotaReached: googleQuota,
  );
}
