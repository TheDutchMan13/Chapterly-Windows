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
      final surnames = authorSurnames(author);
      final ids = <String>[];
      for (final hit in found.whereType<Map<String, dynamic>>()) {
        final label = (hit['label'] ?? '').toString().toLowerCase();
        final description = (hit['description'] ?? '').toString();
        if (label != cleanTitle.toLowerCase()) continue;
        if (describesBookBy(description, surnames) && hit['id'] is String) {
          ids.add(hit['id'] as String);
        }
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

  /// The series Wikidata lists for the book ("part of the series", P179)
  /// and its number in it (the "series ordinal", P1545), or null when
  /// Wikidata has nothing, is busy, or cannot be reached. Never throws.
  Future<({String name, int? number})?> seriesFor({
    required String title,
    required String author,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return null;
    try {
      final search = await _get({
        'action': 'wbsearchentities',
        'search': cleanTitle,
        'language': 'en',
        'type': 'item',
        'limit': '5',
      });
      final found = search?['search'];
      if (found is! List) return null;
      final surnames = authorSurnames(author);
      final ids = <String>[];
      for (final hit in found.whereType<Map<String, dynamic>>()) {
        final label = (hit['label'] ?? '').toString().toLowerCase();
        final description = (hit['description'] ?? '').toString();
        if (label != cleanTitle.toLowerCase()) continue;
        if (describesBookBy(description, surnames) && hit['id'] is String) {
          ids.add(hit['id'] as String);
        }
      }
      if (ids.isEmpty) return null;

      final entities = await _get({
        'action': 'wbgetentities',
        'ids': ids.join('|'),
        'props': 'claims',
      });
      final byId = entities?['entities'];
      if (byId is! Map) return null;
      String? seriesId;
      int? number;
      for (final id in ids) {
        final entity = byId[id];
        final claims = entity is Map ? entity['claims'] : null;
        final parts = claims is Map ? claims['P179'] : null;
        if (parts is! List) continue;
        for (final claim in parts) {
          if (claim case {'mainsnak': {'datavalue': {'value': {'id': final String sid}}}}) {
            seriesId = sid;
            if (claim case {'qualifiers': {'P1545': [{'datavalue': {'value': final String n}}, ...]}}) {
              number = int.tryParse(n.trim());
            }
            break;
          }
        }
        if (seriesId != null) break;
      }
      if (seriesId == null) return null;

      final labels = await _get({
        'action': 'wbgetentities',
        'ids': seriesId,
        'props': 'labels',
        'languages': 'en',
      });
      final series = labels?['entities'];
      final entity = series is Map ? series[seriesId] : null;
      if (entity case {'labels': {'en': {'value': final String v}}}) {
        final name = v.trim();
        if (name.isNotEmpty) {
          return (name: name, number: number != null && number > 0 ? number : null);
        }
      }
      return null;
    } on Object {
      return null;
    }
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

final _writtenWork = RegExp(
  r'\b(novels?|books?|story|stories|novellas?|poems?|poetry|series|comics?|'
  r'manga|short story collection|plays?)\b',
  caseSensitive: false,
);

final _notWritten = RegExp(
  r'\b(films?|television|tv series|episodes?|video games?|albums?|songs?|'
  r'(?<!space )operas?)\b',
  caseSensitive: false,
);

const _suffixes = {'jr', 'sr', 'ii', 'iii', 'iv'};

/// The surname of one author's name: the last word ("Frank Herbert",
/// "J. R. R. Tolkien"), leaving out "Jr." and the like.
String? _surnameOf(String name) {
  final words = [
    for (final word in name.split(RegExp(r'\s+')))
      if (word.replaceAll('.', '').length > 1 &&
          !_suffixes.contains(word.replaceAll('.', '').toLowerCase()))
        word.replaceAll(RegExp(r'^[.]+|[.]+$'), ''),
  ];
  return words.isEmpty ? null : words.last.toLowerCase();
}

/// The surnames of the authors in [author], lower case. Authors are split on
/// "&", " and ", ";" and "/". A comma splits authors too ("Neil Gaiman,
/// Terry Pratchett"), except in "Herbert, Frank" (two single words): that
/// may be one author written surname first, or two surnames, so both words
/// are kept.
List<String> authorSurnames(String author) {
  final surnames = <String>[];
  final people = author.split(RegExp(r'\s*(?:&|;|/|\band\b)\s*',
      caseSensitive: false));
  for (final person in people) {
    final parts = [
      for (final part in person.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    if (parts.isEmpty) continue;
    final singleWords = parts.every((part) => !part.contains(' '));
    if (parts.length == 2 && singleWords) {
      for (final part in parts) {
        final word = _surnameOf(part);
        if (word != null) surnames.add(word);
      }
      continue;
    }
    for (final part in parts) {
      final surname = _surnameOf(part);
      if (surname != null && !_suffixes.contains(surname)) {
        surnames.add(surname);
      }
    }
  }
  return surnames.toSet().toList();
}

/// Whether a Wikidata [description] is of a written work (not a film, an
/// album or the like) by one of the authors with [surnames], as a whole
/// word. With no surnames, a written work is enough.
bool describesBookBy(String description, List<String> surnames) {
  if (!_writtenWork.hasMatch(description)) return false;
  if (_notWritten.hasMatch(description)) return false;
  if (surnames.isEmpty) return true;
  return surnames.any(
    (surname) => RegExp(
      '(?<![\\p{L}\\p{N}])${RegExp.escape(surname)}(?![\\p{L}\\p{N}])',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(description),
  );
}
