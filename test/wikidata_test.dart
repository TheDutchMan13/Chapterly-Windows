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
  _seriesTests();
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

  test('authors are split into surnames', () {
    expect(authorSurnames('Frank Herbert'), ['herbert']);
    expect(authorSurnames('Neil Gaiman, Terry Pratchett'), ['gaiman', 'pratchett']);
    expect(authorSurnames('Neil Gaiman & Terry Pratchett'), ['gaiman', 'pratchett']);
    expect(authorSurnames('Gaiman and Pratchett'), ['gaiman', 'pratchett']);
    expect(authorSurnames('Gaiman; Pratchett / Moore'),
        ['gaiman', 'pratchett', 'moore']);
    expect(authorSurnames('Herbert, Frank'), containsAll(['herbert']));
    expect(authorSurnames('Gaiman, Pratchett'), ['gaiman', 'pratchett']);
    expect(authorSurnames('J. R. R. Tolkien'), ['tolkien']);
    expect(authorSurnames('Martin Luther King Jr.'), ['king']);
    expect(authorSurnames(''), isEmpty);
  });

  test('a surname must be a whole word in the description', () {
    expect(describesBookBy('English novel by Jane Austen', ['ng']), isFalse);
    expect(describesBookBy('novel set in a lost kingdom', ['king']), isFalse);
    expect(describesBookBy('2011 novel by Celeste Ng', ['ng']), isTrue);
    expect(describesBookBy('1986 novel by Stephen King', ['king']), isTrue);
    expect(describesBookBy('novel by Charlotte Brontë', ['brontë']), isTrue);
  });

  test('only written works are matched', () {
    expect(
      describesBookBy('2021 film based on the novel by Frank Herbert', ['herbert']),
      isFalse,
    );
    expect(describesBookBy('television series based on the novel by Herbert',
        ['herbert']), isFalse);
    expect(describesBookBy('video game based on the book by Herbert', ['herbert']),
        isFalse);
    expect(describesBookBy('album by Frank Herbert', ['herbert']), isFalse);
    expect(describesBookBy('painting by Frank Herbert', ['herbert']), isFalse);
    expect(describesBookBy('space opera novel by Frank Herbert', ['herbert']),
        isTrue);
    expect(describesBookBy('play by William Shakespeare', ['shakespeare']), isTrue);
    expect(describesBookBy('1990 novel by Terry Pratchett and Neil Gaiman',
        authorSurnames('Gaiman, Pratchett')), isTrue);
    expect(describesBookBy('1990 novel by Terry Pratchett and Neil Gaiman',
        authorSurnames('Neil Gaiman, Terry Pratchett')), isTrue);
    expect(describesBookBy('poetry collection', const []), isTrue);
    expect(describesBookBy('2021 film', const []), isFalse);
  });

  test('a film with the same title and author is not matched', () async {
    final client = WikidataClient(
      client: MockClient((request) async => _json({
            'search': [
              {
                'id': 'Q1',
                'label': 'Dune',
                'description': '2021 film based on the novel by Frank Herbert',
              },
            ],
          })),
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

void _seriesTests() {
  MockClient series(List<http.Request> seen) => MockClient((request) async {
        seen.add(request);
        final q = request.url.queryParameters;
        if (q['action'] == 'wbsearchentities') {
          return _json({
            'search': [
              {
                'id': 'Q5',
                'label': 'The Final Empire',
                'description': '2006 novel by Brandon Sanderson',
              },
            ],
          });
        }
        if (q['props'] == 'claims') {
          return _json({
            'entities': {
              'Q5': {
                'claims': {
                  'P179': [
                    {
                      'mainsnak': {
                        'datavalue': {
                          'value': {'id': 'Q9'},
                        },
                      },
                      'qualifiers': {
                        'P1545': [
                          {
                            'datavalue': {'value': '1'},
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            },
          });
        }
        return _json({
          'entities': {
            'Q9': {
              'labels': {
                'en': {'value': 'Mistborn'},
              },
            },
          },
        });
      });

  test('finds the series and the number in it', () async {
    final seen = <http.Request>[];
    final client = WikidataClient(client: series(seen), pause: Duration.zero);
    final found = await client.seriesFor(
        title: 'The Final Empire', author: 'Brandon Sanderson');
    expect(found?.name, 'Mistborn');
    expect(found?.number, 1);
    expect(seen, hasLength(3));
  });

  test('a book with no series, or by someone else, gives null', () async {
    final client = WikidataClient(client: series([]), pause: Duration.zero);
    expect(await client.seriesFor(title: 'The Final Empire', author: 'Other Person'),
        isNull);
  });
}
