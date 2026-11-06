import 'details_refresh.dart';
import 'open_library_client.dart';

// The same file is in the Android app; keep the two copies alike.

/// The covers Open Library has for the book with this [title] and [author]
/// (and [isbn], when known), for choosing one: the covers of the results that
/// are clearly this book, then those of every edition of its work. Throws
/// when Open Library cannot be reached.
Future<List<CoverOption>> findCoverOptions(
  OpenLibraryClient client, {
  required String title,
  required String author,
  String? isbn,
  int max = 30,
}) async {
  final options = <CoverOption>[];
  final seen = <String>{};
  void add(String? url, String label) {
    if (url == null || !seen.add(url)) return;
    options.add(CoverOption(url: url, label: label));
  }

  final matches = <OpenLibraryBook>[];
  final digits = (isbn ?? '').replaceAll(RegExp(r'[^0-9Xx]'), '');
  if (digits.length >= 10) {
    final byIsbn = await client.lookupIsbn(digits);
    if (byIsbn != null) matches.add(byIsbn);
  }
  final query = '$title $author'.trim();
  if (query.isNotEmpty) {
    for (final result in await client.search(query)) {
      if (isOpenLibraryMatch(title, author, result)) matches.add(result);
    }
  }
  for (final match in matches) {
    add(match.coverUrl, 'Open Library match');
  }
  final work = matches.map((m) => m.workKey).whereType<String>().firstOrNull;
  if (work != null) {
    for (final cover in await client.editionCovers(work)) {
      add(cover.url, cover.label);
    }
  }
  return options.take(max).toList();
}
