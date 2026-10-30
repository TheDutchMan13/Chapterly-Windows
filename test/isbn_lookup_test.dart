import 'dart:convert';

import 'package:chapterly/data/open_library_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('looks a book up by ISBN and ignores dashes', () async {
    String? query;
    final client = OpenLibraryClient(
      client: MockClient((request) async {
        query = request.url.queryParameters['q'];
        return _json({
          'docs': [
            {
              'title': 'Dune',
              'author_name': ['Frank Herbert'],
              'first_publish_year': 1965,
            },
          ],
        });
      }),
    );

    final book = await client.lookupIsbn('978-0-441-17271-9');

    expect(query, 'isbn:9780441172719');
    expect(book, isNotNull);
    expect(book!.title, 'Dune');
  });

  test('returns null when Open Library has no match', () async {
    final client = OpenLibraryClient(
      client: MockClient((request) async => _json({'docs': []})),
    );

    expect(await client.lookupIsbn('9780000000002'), isNull);
  });

  test('an ISBN with no digits makes no request', () async {
    var requests = 0;
    final client = OpenLibraryClient(
      client: MockClient((request) async {
        requests++;
        return _json({'docs': []});
      }),
    );

    expect(await client.lookupIsbn('---'), isNull);
    expect(requests, 0);
  });
}
