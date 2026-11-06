import 'dart:convert';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/google_books_client.dart';
import 'package:chapterly/data/google_books_fill.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The same tests are in the Android app.

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _dune = {
  'items': [
    {
      'volumeInfo': {
        'title': 'Dune',
        'authors': ['Frank Herbert'],
        'publishedDate': '1990-09-01',
        'pageCount': 535,
        'categories': ['Fiction / Science Fiction / Space Opera'],
        'imageLinks': {
          'thumbnail': 'http://books.google.com/books/content?id=x&zoom=1&edge=curl',
        },
        'industryIdentifiers': [
          {'type': 'ISBN_10', 'identifier': '0441172717'},
          {'type': 'ISBN_13', 'identifier': '9780441172719'},
        ],
      },
    },
  ],
};

void main() {
  test('reads a volume: ISBN-13, pages, year, https cover and categories', () {
    final book = GoogleBook.fromJson((_dune['items']! as List).first)!;
    expect(book.isbn, '9780441172719');
    expect(book.pages, 535);
    expect(book.year, 1990);
    expect(book.coverUrl, startsWith('https://'));
    expect(book.coverUrl, isNot(contains('edge=curl')));
    expect(book.categories, contains('Science Fiction'));
  });

  test('works without a key, sends the key when there is one, and stops on 403',
      () async {
    final seen = <Uri>[];
    var status = 200;
    final http.Client mock = MockClient((request) async {
      seen.add(request.url);
      return _json(_dune, status);
    });
    String? key;
    final client = GoogleBooksClient(
        client: mock, apiKey: () => key, pause: Duration.zero);
    await client.search('isbn:9780441172719');
    expect(seen.last.queryParameters.containsKey('key'), isFalse);
    key = 'abc';
    await client.search('isbn:9780441172719');
    expect(seen.last.queryParameters['key'], 'abc');
    status = 403;
    expect(client.search('x'), throwsA(isA<GoogleQuotaReached>()));
  });

  test('fills blanks only, asks once, is off by default, and pauses on quota',
      () async {
    var quota = false;
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return quota ? _json({}, 429) : _json(_dune);
    });
    final repo = BookRepository(InMemoryBookStore());
    await repo.load();
    final id = await repo.add(
        title: 'Dune', author: 'Frank Herbert', shelf: Shelf.forLater);
    await repo.setPages(id, 600);
    final other = await repo.add(
        title: 'Dune', author: 'Frank Herbert Jr', shelf: Shelf.forLater);
    final settings = AppSettings();
    final fill = GoogleBooksFill.start(
      repo,
      settings,
      client: GoogleBooksClient(client: mock, pause: Duration.zero),
    );
    expect(await fill.run(), 0);
    expect(calls, 0);
    settings.setUseGoogleBooks(true);
    expect(await fill.run(), greaterThan(0));
    final book = repo.byId(id)!;
    expect(book.isbn, '9780441172719');
    expect(book.firstPublishYear, 1990);
    expect(book.pages, 600, reason: 'a page count you have is kept');
    expect(book.tags, isNotEmpty);
    expect(settings.googleBooksAsked, contains(id));
    expect(settings.googleBooksAsked, contains(other));
    final before = calls;
    expect(await fill.run(), 0);
    expect(calls, before, reason: 'each book is asked about once');
    // A new book, and Google has no requests left today.
    await repo.add(title: 'Emma', author: 'Jane Austen', shelf: Shelf.forLater);
    quota = true;
    expect(await fill.run(), 0);
    expect(settings.googleBooksPausedOn, isNotNull);
    final paused = calls;
    expect(await fill.run(), 0);
    expect(calls, paused, reason: 'nothing more is asked today');
    // A new key tries again.
    settings.setGoogleBooksKey('mykey');
    expect(settings.googleBooksPausedOn, isNull);
  });
}
