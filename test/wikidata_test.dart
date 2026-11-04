import 'dart:convert';

import 'package:chapterly/data/auto_tag.dart';
import 'package:chapterly/data/wikidata_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

MockClient _wikidata(List<http.Request> seen) => MockClient((request) async {
      seen.add(request);
      return switch (request.url.queryParameters['action']) {
        'wbsearchentities' => _json({
            'search': [
              {'id': 'Q1', 'label': 'Dune', 'description': '2021 film'},
              {
                'id': 'Q2',
                'label': 'Dune',
                'description': '1965 novel by Frank Herbert',
              },
            ],
          }),
        'wbgetentities' when request.url.queryParameters['props'] == 'claims' =>
          _json({
            'entities': {
              'Q2': {
                'claims': {
                  'P136': [
                    {
                      'mainsnak': {
                        'datavalue': {
                          'value': {'id': 'Q10'},
                        },
                      },
                    },
                  ],
                },
              },
            },
          }),
        _ => _json({
            'entities': {
              'Q10': {
                'labels': {
                  'en': {'value': 'Science fiction'},
                },
              },
            },
          }),
      };
    });

void main() {
  test('finds the genres of the matching book and identifies itself', () async {
    final seen = <http.Request>[];
    final client = WikidataClient(client: _wikidata(seen), pause: Duration.zero);
    final genres = await client.genresFor(title: 'Dune', author: 'Frank Herbert');
    expect(genres, ['Science fiction']);
    expect(seen, hasLength(3));
    expect(seen.first.headers['User-Agent'], contains('Chapterly-Windows'));
    expect(seen.first.headers['User-Agent'], contains('github.com'));
  });

  test('a book by someone else is not matched', () async {
    final client =
        WikidataClient(client: _wikidata([]), pause: Duration.zero);
    expect(await client.genresFor(title: 'Dune', author: 'Someone Else'), isEmpty);
  });

  test('stops asking after a 429', () async {
    var calls = 0;
    final client = WikidataClient(
      client: MockClient((_) async {
        calls++;
        return http.Response('slow down', 429);
      }),
      pause: Duration.zero,
    );
    expect(await client.genresFor(title: 'Dune', author: 'Frank Herbert'), isEmpty);
    expect(client.tooBusy, isTrue);
    expect(await client.genresFor(title: 'Emma', author: 'Jane Austen'), isEmpty);
    expect(calls, 1);
  });

  test('network errors give an empty list', () async {
    final client = WikidataClient(
      client: MockClient((_) async => throw Exception('offline')),
      pause: Duration.zero,
    );
    expect(await client.genresFor(title: 'Dune', author: 'Frank Herbert'), isEmpty);
  });

  test('mergeSubjects drops repeats ignoring capitals', () {
    expect(
      mergeSubjects(['Space opera', 'Fantasy'], ['fantasy', 'Novel']),
      ['Space opera', 'Fantasy', 'Novel'],
    );
  });
}
