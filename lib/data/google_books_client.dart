import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/book.dart';
import 'app_info.dart';
import 'file_match.dart';
import 'open_library_client.dart' show OpenLibraryBook, cleanSubjects;

// The same file is in the Android app; keep the two copies alike.

/// One book as Google Books lists it.
class GoogleBook {
  const GoogleBook({
    required this.title,
    required this.author,
    this.isbn,
    this.pages,
    this.year,
    this.coverUrl,
    this.categories = const [],
  });

  final String title;
  final String author;
  final String? isbn;
  final int? pages;
  final int? year;
  final String? coverUrl;

  /// Google's categories, such as "Fiction / Science Fiction", split into
  /// single words or phrases and cleaned like Open Library's subjects.
  final List<String> categories;

  /// This book in the shape the search and editor screens use for results
  /// from either source. Google has no work key, so there are no editions.
  OpenLibraryBook toLookup() => OpenLibraryBook(
        title: title,
        author: author.isEmpty ? 'Unknown author' : author,
        firstPublishYear: year,
        isbn: isbn,
        coverUrl: coverUrl,
        pages: pages,
      );

  static GoogleBook? fromJson(Object? item) {
    if (item is! Map) return null;
    final info = item['volumeInfo'];
    if (info is! Map) return null;
    final title = info['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final authors = info['authors'];
    String? isbn;
    final ids = info['industryIdentifiers'];
    if (ids is List) {
      for (final id in ids) {
        if (id is Map && id['type'] == 'ISBN_13' && id['identifier'] is String) {
          isbn = id['identifier'] as String;
        }
      }
      if (isbn == null) {
        for (final id in ids) {
          if (id is Map && id['type'] == 'ISBN_10' && id['identifier'] is String) {
            isbn = id['identifier'] as String;
          }
        }
      }
    }
    final pages = info['pageCount'];
    final date = info['publishedDate'];
    final year = date is String && date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
    final links = info['imageLinks'];
    var cover = links is Map ? links['thumbnail'] : null;
    String? coverUrl;
    if (cover is String && cover.isNotEmpty) {
      coverUrl = cover.replaceFirst('http://', 'https://').replaceAll('&edge=curl', '');
    }
    final raw = info['categories'];
    final parts = <String>[];
    if (raw is List) {
      for (final category in raw) {
        parts.addAll(category.toString().split(RegExp(r'\s*/\s*|\s*&\s*')));
      }
    }
    return GoogleBook(
      title: title.trim(),
      author: authors is List ? authors.whereType<String>().join(', ') : '',
      isbn: isbn,
      pages: pages is int && pages > 0 ? pages : null,
      year: year != null && year > 0 ? year : null,
      coverUrl: coverUrl,
      categories: cleanSubjects(parts),
    );
  }
}

/// Google has no more requests for today (no key allows only a few).
class GoogleQuotaReached implements Exception {
  const GoogleQuotaReached();
}

/// Looks books up on Google Books. It works without a key, but the daily
/// limit is low then; a free key raises it. Asks politely: one request at a
/// time, with a pause between them.
class GoogleBooksClient {
  GoogleBooksClient({
    http.Client? client,
    this.apiKey,
    this.pause = const Duration(milliseconds: 500),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// The key from Settings, or null to ask without one. Read for every
  /// request, so a key you paste later is used at once.
  final String? Function()? apiKey;
  final Duration pause;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  static const userAgent = 'Chapterly-Windows/$appVersion '
      '(https://github.com/TheDutchMan13/Chapterly-Windows)';

  /// The books for [query] (Google's search words). Throws
  /// [GoogleQuotaReached] when the day's requests are used up; returns an
  /// empty list for anything else that goes wrong.
  Future<List<GoogleBook>> search(String query, {int max = 5}) async {
    final wait = pause - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final key = apiKey?.call()?.trim();
    try {
      final response = await _client.get(
        Uri.https('www.googleapis.com', '/books/v1/volumes', {
          'q': query,
          'maxResults': '$max',
          'printType': 'books',
          'fields': 'items(volumeInfo(title,authors,publishedDate,pageCount,'
              'categories,imageLinks/thumbnail,industryIdentifiers))',
          if (key != null && key.isNotEmpty) 'key': key,
        }),
        headers: {'User-Agent': userAgent},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 429 || response.statusCode == 403) {
        throw const GoogleQuotaReached();
      }
      if (response.statusCode != 200) return [];
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final items = data is Map ? data['items'] : null;
      if (items is! List) return [];
      return [for (final item in items) ?GoogleBook.fromJson(item)];
    } on GoogleQuotaReached {
      rethrow;
    } on Object {
      return [];
    }
  }

  /// Results for something typed in a search box, in the shape the screens
  /// use for Open Library results. An ISBN is looked up as an ISBN. Throws
  /// [GoogleQuotaReached] when the day's requests are used up.
  Future<List<OpenLibraryBook>> searchLookup(String text, {int max = 15}) async {
    final query = text.trim();
    if (query.isEmpty) return [];
    final digits = query.replaceAll(RegExp(r'[\s-]'), '');
    final isIsbn = RegExp(r'^(\d{9}[\dXx]|\d{13})$').hasMatch(digits);
    final found = await search(isIsbn ? 'isbn:$digits' : query, max: max);
    return [for (final book in found) book.toLookup()];
  }

  /// The Google Books entry that is clearly [book]: by ISBN when it has
  /// one, otherwise by title and author. Null when there is none.
  Future<GoogleBook?> find(Book book) async {
    final isbn = (book.isbn ?? '').replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (isbn.length >= 10) {
      final byIsbn = await search('isbn:$isbn');
      if (byIsbn.isNotEmpty) return bestGoogleMatch(book, byIsbn) ?? byIsbn.first;
    }
    final title = book.title.replaceAll('"', ' ').trim();
    if (title.isEmpty) return null;
    final author = book.author.replaceAll('"', ' ').trim();
    final found = await search(
      'intitle:"$title"${author.isEmpty ? '' : ' inauthor:"$author"'}',
    );
    return bestGoogleMatch(book, found);
  }

  void close() => _client.close();
}

/// The client the search boxes use. Set once at start so it uses the key
/// from Settings; a plain one (no key) is made if it was not set.
GoogleBooksClient? sharedGoogleBooks;

GoogleBooksClient get googleBooksClient =>
    sharedGoogleBooks ??= GoogleBooksClient();

/// The result that is clearly [book]: the same title (or main title) and,
/// when both have one, an author sharing a name.
GoogleBook? bestGoogleMatch(Book book, List<GoogleBook> found) {
  Set<String> words(String text) => {
        for (final word in text
            .toLowerCase()
            .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
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
