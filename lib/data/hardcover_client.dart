import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/book.dart';
import 'app_info.dart';
import 'file_match.dart';

// The same file is in the Android app; keep the two copies alike.

/// Hardcover did not accept the token: it is missing, wrong or expired.
class HardcoverUnauthorized implements Exception {
  const HardcoverUnauthorized();
}

/// A book's series as Hardcover lists it.
class HardcoverSeries {
  const HardcoverSeries({
    required this.title,
    required this.author,
    required this.series,
    this.number,
  });

  /// The title and author of the Hardcover book that matched.
  final String title;
  final String author;
  final String series;

  /// The book's place in the series; null when it is not a whole number.
  final int? number;
}

/// One book of a series on Hardcover.
class HardcoverSeriesBook {
  const HardcoverSeriesBook({required this.number, required this.title});

  final int number;
  final String title;
}

/// Asks Hardcover (hardcover.app) for series: which series a book is in, and
/// which books a series has. Hardcover needs a free account: its token is
/// pasted in Settings. It allows 60 requests a minute, so this waits a
/// second between them.
class HardcoverClient {
  HardcoverClient({
    http.Client? client,
    required this.token,
    this.pause = const Duration(milliseconds: 1100),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// The token from Settings, read for every request.
  final String? Function() token;
  final Duration pause;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  static final endpoint = Uri.https('api.hardcover.app', '/v1/graphql');

  bool get hasToken => (token()?.trim() ?? '').isNotEmpty;

  /// The "data" of a GraphQL answer. Throws [HardcoverUnauthorized] when
  /// the token is not accepted, and something else when Hardcover cannot be
  /// reached.
  Future<Map<String, dynamic>> _query(
    String query,
    Map<String, Object?> variables,
  ) async {
    final raw = token()?.trim() ?? '';
    if (raw.isEmpty) throw const HardcoverUnauthorized();
    final wait = pause - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final response = await _client
        .post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'Authorization':
                raw.toLowerCase().startsWith('bearer ') ? raw : 'Bearer $raw',
            'User-Agent': 'Chapterly/$appVersion '
                '(https://github.com/TheDutchMan13/Chapterly-Android)',
          },
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const HardcoverUnauthorized();
    }
    if (response.statusCode != 200) {
      throw http.ClientException('Hardcover returned ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map) throw const FormatException('Not a GraphQL answer');
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      final text = errors.toString().toLowerCase();
      if (text.contains('jwt') || text.contains('auth')) {
        throw const HardcoverUnauthorized();
      }
    }
    final data = body['data'];
    return data is Map<String, dynamic> ? data : const {};
  }

  /// The series Hardcover has for [book], when it clearly finds the book.
  Future<HardcoverSeries?> seriesFor(Book book) async {
    final title = book.title.trim();
    if (title.isEmpty) return null;
    final data = await _query(
      r'query ($q: String!) { search(query: $q, query_type: "Book", '
      r'per_page: 5, page: 1) { results } }',
      {'q': '$title ${book.author}'.trim()},
    );
    for (final document in _documents(data)) {
      final found = hardcoverSeriesFrom(document);
      if (found == null) continue;
      if (!_sameBook(book, found.title, found.author)) continue;
      return found;
    }
    return null;
  }

  /// The books of the series called [name] (by [author], when given), by
  /// number, leaving out collections. Empty when Hardcover has no such
  /// series.
  Future<List<HardcoverSeriesBook>> seriesBooks(
    String name, {
    String author = '',
  }) async {
    var exact = name.trim();
    if (exact.isEmpty) return const [];
    var series = await _seriesNamed(exact);
    if (series.isEmpty) {
      // The name may be spelled a little differently there.
      final data = await _query(
        r'query ($q: String!) { search(query: $q, query_type: "Series", '
        r'per_page: 5, page: 1) { results } }',
        {'q': '$exact $author'.trim()},
      );
      for (final document in _documents(data)) {
        final other = document['name'];
        if (other is String && other.trim().isNotEmpty &&
            titleScore(exact, other) >= 80) {
          exact = other.trim();
          series = await _seriesNamed(exact);
          break;
        }
      }
    }
    if (series.isEmpty) return const [];
    // With several series of that name, the one by the same author.
    final authorWords = _words(author);
    var chosen = series.first;
    for (final one in series) {
      final by = one['author'];
      final byName = by is Map && by['name'] is String ? by['name'] as String : '';
      if (authorWords.isNotEmpty && _words(byName).intersection(authorWords).isNotEmpty) {
        chosen = one;
        break;
      }
    }
    final entries = chosen['book_series'];
    if (entries is! List) return const [];
    final byNumber = <int, String>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final position = entry['position'];
      final book = entry['book'];
      final title = book is Map ? book['title'] : null;
      if (position is! num || title is! String || title.trim().isEmpty) continue;
      if (position <= 0 || position != position.roundToDouble()) continue;
      byNumber.putIfAbsent(position.round(), () => title.trim());
    }
    final numbers = byNumber.keys.toList()..sort();
    return [
      for (final number in numbers)
        HardcoverSeriesBook(number: number, title: byNumber[number]!),
    ];
  }

  Future<List<Map<String, dynamic>>> _seriesNamed(String name) async {
    final data = await _query(
      r'query ($name: String!) { series(where: {name: {_eq: $name}}, '
      r'limit: 5) { name author { name } book_series(where: {compilation: '
      r'{_eq: false}}, order_by: {position: asc}) { position book { title } '
      r'} } }',
      {'name': name},
    );
    final list = data['series'];
    if (list is! List) return const [];
    return [for (final item in list) if (item is Map<String, dynamic>) item];
  }

  void close() => _client.close();
}

/// The search hits' documents in a "search" answer.
List<Map<String, dynamic>> _documents(Map<String, dynamic> data) {
  final search = data['search'];
  var results = search is Map ? search['results'] : null;
  if (results is String) {
    try {
      results = jsonDecode(results);
    } catch (_) {
      return const [];
    }
  }
  final hits = results is Map ? results['hits'] : null;
  if (hits is! List) return const [];
  return [
    for (final hit in hits)
      if (hit is Map && hit['document'] is Map<String, dynamic>)
        hit['document'] as Map<String, dynamic>,
  ];
}

/// The featured series of one Hardcover search document, or null when it
/// has none.
HardcoverSeries? hardcoverSeriesFrom(Map<String, dynamic> document) {
  final title = document['title'];
  if (title is! String || title.trim().isEmpty) return null;
  final authors = document['author_names'];
  final author =
      authors is List ? authors.whereType<String>().take(2).join(', ') : '';
  String? name;
  Object? position = document['featured_series_position'];
  final featured = document['featured_series'];
  if (featured is Map) {
    final series = featured['series'];
    if (series is Map && series['name'] is String) {
      name = series['name'] as String;
    } else if (featured['name'] is String) {
      name = featured['name'] as String;
    }
    position ??= featured['position'];
  }
  if (name == null || name.trim().isEmpty) return null;
  int? number;
  if (position is num && position > 0 && position == position.roundToDouble()) {
    number = position.round();
  }
  return HardcoverSeries(
    title: title.trim(),
    author: author,
    series: name.trim(),
    number: number,
  );
}

Set<String> _words(String text) => {
      for (final word in text
          .toLowerCase()
          .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
        if (word.length > 2) word,
    };

bool _sameBook(Book book, String title, String author) {
  if (titleScore(book.title, title) < 85) return false;
  final mine = _words(book.author);
  if (mine.isEmpty || author.trim().isEmpty) return true;
  return _words(author).intersection(mine).isNotEmpty;
}

/// The client the screens use. Set once at start so it reads the token from
/// Settings; one without a token is made if it was not set.
HardcoverClient? sharedHardcover;

HardcoverClient get hardcoverClient =>
    sharedHardcover ??= HardcoverClient(token: () => null);
