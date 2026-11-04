import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_info.dart';
import 'open_library_client.dart' show cleanSubjects;

// Windows app only.

/// Looks up the genres Wikidata lists for a book (such as "science fiction
/// novel"). Wikidata's data is free to use (CC0). No account or key is
/// needed. It asks politely: one request at a time, a pause between them,
/// and it stops for the rest of the session if Wikidata says "slow down".
class WikidataClient {
  WikidataClient({
    http.Client? client,
    this.pause = const Duration(milliseconds: 400),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// The least time between two requests (about 150 a minute, under
  /// Wikimedia's limit of 200).
  final Duration pause;

  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// True once Wikidata has asked us to slow down; nothing more is sent.
  bool tooBusy = false;

  static const userAgent = 'Chapterly-Windows/$appVersion '
      '(https://github.com/TheDutchMan13/Chapterly-Windows)';

  Future<Map<String, dynamic>?> _get(Map<String, String> query) async {
    if (tooBusy) return null;
    final wait = pause - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final response = await _client.get(
      Uri.https('www.wikidata.org', '/w/api.php', {
        ...query,
        'format': 'json',
        'origin': '*',
      }),
      headers: {'User-Agent': userAgent, 'Accept-Encoding': 'gzip'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 429 || response.statusCode == 503) {
      tooBusy = true;
      return null;
    }
    if (response.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return data is Map<String, dynamic> ? data : null;
  }

  /// Genres for the book, or an empty list when Wikidata has nothing, is
  /// busy, or cannot be reached. Never throws.
  Future<List<String>> genresFor({
    required String title,
    required String author,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return [];
    try {
      final search = await _get({
        'action': 'wbsearchentities',
        'search': cleanTitle,
        'language': 'en',
        'type': 'item',
        'limit': '5',
      });
      final found = search?['search'];
      if (found is! List) return [];
      final lastName = _lastName(author);
      final ids = <String>[];
      for (final hit in found.whereType<Map<String, dynamic>>()) {
        final label = (hit['label'] ?? '').toString().toLowerCase();
        final description = (hit['description'] ?? '').toString().toLowerCase();
        if (label != cleanTitle.toLowerCase()) continue;
        // Only books: with an author, the description names them; without,
        // it must at least say it is a written work.
        final fits = lastName.isNotEmpty
            ? description.contains(lastName)
            : RegExp(r'novel|book|story|stories|poem|series|comic|manga')
                .hasMatch(description);
        if (fits && hit['id'] is String) ids.add(hit['id'] as String);
      }
      if (ids.isEmpty) return [];

      final entities = await _get({
        'action': 'wbgetentities',
        'ids': ids.join('|'),
        'props': 'claims',
      });
      final byId = entities?['entities'];
      if (byId is! Map) return [];
      var genreIds = <String>[];
      for (final id in ids) {
        genreIds = _genreIds(byId[id]);
        if (genreIds.isNotEmpty) break;
      }
      if (genreIds.isEmpty) return [];

      final labels = await _get({
        'action': 'wbgetentities',
        'ids': genreIds.take(8).join('|'),
        'props': 'labels',
        'languages': 'en',
      });
      final genres = labels?['entities'];
      if (genres is! Map) return [];
      return cleanSubjects([
        for (final id in genreIds.take(8))
          if (genres[id] case {'labels': {'en': {'value': final String v}}}) v,
      ]);
    } on Object {
      return [];
    }
  }

  static String _lastName(String author) {
    final words = author
        .toLowerCase()
        .split(RegExp(r'[\s,]+'))
        .where((w) => w.length > 1)
        .toList();
    if (words.isEmpty) return '';
    // "Herbert, Frank" lists the surname first; "Frank Herbert" last.
    return author.contains(',') ? words.first : words.last;
  }

  /// The genre (P136) item ids in an entity's claims.
  static List<String> _genreIds(Object? entity) {
    if (entity is! Map) return [];
    final claims = entity['claims'];
    final genres = claims is Map ? claims['P136'] : null;
    if (genres is! List) return [];
    final ids = <String>[];
    for (final claim in genres) {
      if (claim case {'mainsnak': {'datavalue': {'value': {'id': final String id}}}}) {
        ids.add(id);
      }
    }
    return ids;
  }

  void close() => _client.close();
}
