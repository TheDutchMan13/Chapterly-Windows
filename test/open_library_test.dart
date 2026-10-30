import 'dart:convert';

import 'package:chapterly/data/open_library_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses search results', () async {
    final client = OpenLibraryClient(
      client: MockClient((request) async {
        expect(request.url.host, 'openlibrary.org');
        expect(request.url.queryParameters['q'], 'dune');
        return http.Response(
          jsonEncode({
            'docs': [
              {
                'title': 'Dune',
                'author_name': ['Frank Herbert'],
                'first_publish_year': 1965,
                'isbn': ['9780441172719'],
                'cover_i': 123,
              },
              {
                'title': 'Jane Eyre',
                'author_name': ['Charlotte Brontë'],
              },
              {'title': 'Bare minimum'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final results = await client.search('dune');

    expect(results, hasLength(3));
    expect(results[0].title, 'Dune');
    expect(results[0].author, 'Frank Herbert');
    expect(results[0].firstPublishYear, 1965);
    expect(results[0].isbn, '9780441172719');
    expect(results[0].coverUrl, 'https://covers.openlibrary.org/b/id/123-M.jpg');
    expect(results[0].subtitle, 'Frank Herbert · 1965');
    expect(results[1].author, 'Charlotte Brontë');
    expect(results[2].author, 'Unknown author');
    expect(results[2].coverUrl, isNull);
  });

  test('an empty query makes no request', () async {
    var requests = 0;
    final client = OpenLibraryClient(
      client: MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );

    expect(await client.search('   '), isEmpty);
    expect(requests, 0);
  });

  test('a server error throws OpenLibraryException', () async {
    final client = OpenLibraryClient(
      client: MockClient((request) async => http.Response('nope', 500)),
    );

    expect(client.search('dune'), throwsA(isA<OpenLibraryException>()));
  });
}
