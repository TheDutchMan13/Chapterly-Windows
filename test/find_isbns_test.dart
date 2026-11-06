import 'dart:convert';

import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
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
}
