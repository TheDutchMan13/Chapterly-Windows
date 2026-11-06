import 'dart:convert';

import 'package:chapterly/data/cover_options.dart';
import 'package:chapterly/data/google_books_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The same tests are in the Android app.

const _items = {
  'items': [
    {
      'volumeInfo': {
        'title': 'Dune',
        'authors': ['Frank Herbert'],
        'publishedDate': '1990-09-01',
        'pageCount': 535,
        'imageLinks': {'thumbnail': 'http://books.google.com/a.jpg'},
        'industryIdentifiers': [
          {'type': 'ISBN_13', 'identifier': '9780441172719'},
        ],
      },
    },
    {
      'volumeInfo': {
        'title': 'Dune',
        'authors': ['Frank Herbert'],
        'publishedDate': '2005',
        'imageLinks': {'thumbnail': 'http://books.google.com/a.jpg'},
      },
    },
    {
      'volumeInfo': {
        'title': 'Dune Messiah',
        'imageLinks': {'thumbnail': 'http://books.google.com/b.jpg'},
      },
    },
  ],
};

void main() {
  test('a typed search gives results in the shape the screens use', () async {
    final queries = <String>[];
    final client = GoogleBooksClient(
      pause: Duration.zero,
      client: MockClient((request) async {
        queries.add(request.url.queryParameters['q']!);
        return http.Response(jsonEncode(_items), 200);
      }),
    );
    final byName = await client.searchLookup('dune herbert');
    expect(queries.last, 'dune herbert');
    expect(byName.first.title, 'Dune');
    expect(byName.first.author, 'Frank Herbert');
    expect(byName.first.isbn, '9780441172719');
    expect(byName.first.pages, 535);
    expect(byName.first.firstPublishYear, 1990);
    expect(byName.first.coverUrl, startsWith('https://'));
    expect(byName.first.workKey, isNull);
    expect(byName.last.author, 'Unknown author');

    await client.searchLookup('978-0-441-17271-9');
    expect(queries.last, 'isbn:9780441172719');
    expect(await client.searchLookup('   '), isEmpty);
  });

  test('search says so when the day\'s requests are used up', () async {
    final client = GoogleBooksClient(
      pause: Duration.zero,
      client: MockClient((_) async => http.Response('{}', 429)),
    );
    expect(client.searchLookup('dune'), throwsA(isA<GoogleQuotaReached>()));
  });

  test('cover options skip repeats and books without a cover', () async {
    final client = GoogleBooksClient(
      pause: Duration.zero,
      client: MockClient((_) async => http.Response(jsonEncode(_items), 200)),
    );
    final options = await findGoogleCoverOptions(
      client,
      title: 'Dune',
      author: 'Frank Herbert',
    );
    expect(options.map((o) => o.url), [
      'https://books.google.com/a.jpg',
      'https://books.google.com/b.jpg',
    ]);
    expect(options.first.label, 'Frank Herbert · 1990');
  });
}
