// The same file is in both apps (lib/data/series_check.dart).

import 'hardcover_client.dart';
import 'series.dart';

/// Books Hardcover lists in one of your series that you do not have.
class SeriesGap {
  const SeriesGap({required this.series, required this.missing});

  final SeriesInfo series;
  final List<HardcoverSeriesBook> missing;

  /// The highest number you have in the series.
  int get highestOwned {
    var top = 0;
    for (final book in series.books) {
      final number = book.seriesNumber;
      if (number != null && number > top) top = number;
    }
    return top;
  }

  /// Missing books numbered after the last one you have: most likely new.
  List<HardcoverSeriesBook> get newer => [
        for (final book in missing)
          if (book.number > highestOwned) book,
      ];
}

/// What a check of every series found.
class SeriesCheckResult {
  const SeriesCheckResult({
    required this.gaps,
    required this.checked,
    required this.notFound,
    required this.failed,
  });

  /// Series with books you do not have, newest-first books first.
  final List<SeriesGap> gaps;

  /// How many series were asked about.
  final int checked;

  /// Series Hardcover does not know.
  final List<String> notFound;

  /// Series that could not be checked (Hardcover could not be reached).
  final List<String> failed;
}

/// The books in [series] you do not have, by the numbers in [all].
List<HardcoverSeriesBook> missingFrom(
  SeriesInfo series,
  List<HardcoverSeriesBook> all,
) {
  final have = {
    for (final book in series.books)
      if (book.seriesNumber != null) book.seriesNumber!,
  };
  return [
    for (final book in all)
      if (!have.contains(book.number)) book,
  ]..sort((a, b) => a.number.compareTo(b.number));
}

/// Asks Hardcover about every series in [series], one after another (it
/// allows about one request a second). Calls [onProgress] after each with
/// how many are done. Stops early when [cancelled] returns true. A token
/// Hardcover does not accept ends the check with [HardcoverUnauthorized].
Future<SeriesCheckResult> checkAllSeries(
  List<SeriesInfo> series,
  HardcoverClient client, {
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  final gaps = <SeriesGap>[];
  final notFound = <String>[];
  final failed = <String>[];
  var done = 0;
  for (final one in series) {
    if (cancelled?.call() ?? false) break;
    try {
      final all = await client.seriesBooks(one.name, author: one.author);
      if (all.isEmpty) {
        notFound.add(one.name);
      } else {
        final missing = missingFrom(one, all);
        if (missing.isNotEmpty) {
          gaps.add(SeriesGap(series: one, missing: missing));
        }
      }
    } on HardcoverUnauthorized {
      rethrow;
    } catch (_) {
      failed.add(one.name);
    }
    done++;
    onProgress?.call(done, series.length);
  }
  // Series with newer books first, then by name.
  gaps.sort((a, b) {
    final newer = b.newer.isNotEmpty ? 1 : 0;
    final older = a.newer.isNotEmpty ? 1 : 0;
    if (newer != older) return newer - older;
    return a.series.name.toLowerCase().compareTo(b.series.name.toLowerCase());
  });
  return SeriesCheckResult(
    gaps: gaps,
    checked: done,
    notFound: notFound,
    failed: failed,
  );
}
