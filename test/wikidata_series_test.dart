import 'dart:convert';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/wikidata_client.dart';
import 'package:chapterly/data/wikidata_series.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('fills in series Wikidata knows, asks once, and respects the switch',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final q = request.url.queryParameters;
      if (q['action'] == 'wbsearchentities') {
        return _json({
          'search': [
            {
              'id': 'Q5',
              'label': q['search'],
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
    final repo = BookRepository(InMemoryBookStore());
    await repo.load();
    final id = await repo.add(
        title: 'The Final Empire',
        author: 'Brandon Sanderson',
        shelf: Shelf.forLater);
    final settings = AppSettings();
    final watcher = WikidataSeries.start(
      repo,
      settings,
      client: WikidataClient(client: client, pause: Duration.zero),
    );
    // Off by default: nothing is asked.
    expect(await watcher.run(), 0);
    expect(calls, 0);
    settings.setWikidataSeries(true);
    expect(await watcher.run(), 1);
    expect(repo.byId(id)!.series, 'Mistborn');
    expect(settings.autoSeriesApplied, contains(id));
    // Asked once only.
    final before = calls;
    expect(await watcher.run(), 0);
    expect(calls, before);
  });
}
