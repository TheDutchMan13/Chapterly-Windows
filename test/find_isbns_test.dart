import 'dart:convert';

import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/google_books_client.dart';
import 'package:chapterly/data/isbn_update.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The same tests are in the Android app.

OpenLibraryClient _fake() => OpenLibraryClient(
      client: MockClient((request) async {
        final query = request.url.queryParameters['q'] ?? '';
        final docs = <Map<String, Object?>>[];
        if (query.contains('Foundation')) {
          docs.add({
            'key': '/works/OL1W',
            'title': 'Foundation',
            'author_name': ['Isaac Asimov'],
            'isbn': ['0553293354'],
          });
        } else if (query.contains('Wool')) {
          docs.add({
            'key': '/works/OL2W',
            'title': 'Wool',
            'author_name': ['Hugh Howey'],
          });
        }
        return http.Response(jsonEncode({'docs': docs}), 200);
      }),
    );

void main() {
  test('isbn13Of converts a valid ISBN-10 and rejects bad ones', () {
    expect(isbn13Of('0553293354'), '9780553293357');
    expect(isbn13Of('9780553293357'), '9780553293357');
    expect(isbn13Of('0553293355'), isNull);
    expect(isbn13Of(null), isNull);
  });

  test('a scan finds ISBN-13s for books without one', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    final foundation = await repository.add(
        title: 'Foundation', author: 'Isaac Asimov', shelf: Shelf.forLater);
    await repository.add(
        title: 'Wool', author: 'Hugh Howey', shelf: Shelf.forLater);
    await repository.add(
        title: 'Has one',
        author: 'A',
        shelf: Shelf.forLater,
        isbn: '9780553293357');
    final books = booksWithoutIsbn(repository.allBooks);
    expect(books, hasLength(2));
    final result = await scanIsbns(books, _fake(), pause: Duration.zero);
    expect(result.checked, 2);
    expect(result.noMatch, 1);
    expect(result.fixes.single.book.id, foundation);
    expect(result.fixes.single.isbn, '9780553293357');
  });

  test('Google Books gives the ISBN Open Library does not have', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(
        title: 'Wool', author: 'Hugh Howey', shelf: Shelf.forLater);
    await repository.add(
        title: 'Nothing anywhere', author: 'Nobody', shelf: Shelf.forLater);
    var asked = 0;
    final google = GoogleBooksClient(
      pause: Duration.zero,
      client: MockClient((request) async {
        asked++;
        final query = request.url.queryParameters['q'] ?? '';
        final items = query.contains('Wool')
            ? [
                {
                  'volumeInfo': {
                    'title': 'Wool',
                    'authors': ['Hugh Howey'],
                    'industryIdentifiers': [
                      {'type': 'ISBN_13', 'identifier': '9781476735771'},
                    ],
                  },
                },
              ]
            : <Object>[];
        return http.Response(jsonEncode({'items': items}), 200);
      }),
    );
    final books = booksWithoutIsbn(repository.allBooks);
    final without = await scanIsbns(books, _fake(), pause: Duration.zero);
    expect(without.fixes, isEmpty);
    expect(asked, 0);

    final result =
        await scanIsbns(books, _fake(), pause: Duration.zero, google: google);
    expect(result.fixes, hasLength(1));
    expect(result.fixes.single.isbn, '9781476735771');
    expect(result.fixes.single.source, 'Google Books');
    expect(result.noMatch, 1);
    expect(result.googleQuotaReached, isFalse);
  });

  test('a Google quota stops asking Google but not the scan', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(
        title: 'Foundation', author: 'Isaac Asimov', shelf: Shelf.forLater);
    await repository.add(
        title: 'Wool', author: 'Hugh Howey', shelf: Shelf.forLater);
    await repository.add(
        title: 'Dune', author: 'Frank Herbert', shelf: Shelf.forLater);
    var asked = 0;
    final google = GoogleBooksClient(
      pause: Duration.zero,
      client: MockClient((_) async {
        asked++;
        return http.Response('{}', 429);
      }),
    );
    final result = await scanIsbns(
      booksWithoutIsbn(repository.allBooks),
      _fake(),
      pause: Duration.zero,
      google: google,
    );
    expect(result.checked, 3);
    expect(result.googleQuotaReached, isTrue);
    expect(asked, 1);
    expect(result.fixes.single.source, 'Open Library');
  });
}
