// The same file is in the Android app; keep the two copies alike.

/// The larger picture of a cover from Open Library or Google Books, when
/// [url] is one of theirs: Open Library's "L" size instead of "S" or "M",
/// and a 600 pixel wide Google picture instead of its small thumbnail.
/// Anything else is returned as it is.
String largerCover(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return url;
  if (uri.host == 'covers.openlibrary.org') {
    return url.replaceFirstMapped(
      RegExp(r'-[SM]\.jpg(\?|$)'),
      (m) => '-L.jpg${m[1]}',
    );
  }
  if (uri.host == 'books.google.com' && uri.path == '/books/content') {
    if (uri.queryParameters['fife'] == 'w600-h900') return url;
    final query = Map<String, String>.of(uri.queryParameters)
      ..remove('fife')
      ..['fife'] = 'w600-h900';
    return uri.replace(queryParameters: query).toString();
  }
  return url;
}

/// Whether [largerCover] would give a bigger picture for [url].
bool hasLargerCover(String? url) =>
    url != null && url.trim().isNotEmpty && largerCover(url) != url;
