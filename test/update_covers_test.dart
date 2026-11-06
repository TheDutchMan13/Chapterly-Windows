import 'dart:convert';

import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/cover_options.dart';
import 'package:chapterly/data/cover_update.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The same tests are in the Android app.

OpenLibraryClient _fake() {
  return OpenLibraryClient(
    client: MockClient((request) async {
      final path = request.url.path;
      if (request.url.host == 'covers.openlibrary.org') {
        // 111 is gone; every other cover exists.
        return http.Response('', path.contains('/111-') ? 404 : 200);
      }
      if (path == '/search.json') {
        final query = request.url.queryParameters['q'] ?? '';
        final docs = query.contains('Dexter')
            ? [
                {
                  'key': '/works/OL1W',
                  'title': 'Darkly Dreaming Dexter',
                  'author_name': ['Jeff Lindsay'],
                  'cover_i': 333,
                },
                {
                  'key': '/works/OL2W',
                  'title': 'Something Else Entirely',
                  'author_name': ['Another Person'],
                  'cover_i': 999,
                },
              ]
            : <Map<String, Object?>>[];
        return http.Response(jsonEncode({'docs': docs}), 200);
      }
      if (path == '/works/OL1W/editions.json') {
        return http.Response(
          jsonEncode({
            'entries': [
              {
                'title': 'Darkly Dreaming Dexter',
                'publishers': ['Orion'],
                'publish_date': '2005',
                'covers': [333, 444],
              },
              {'title': 'No cover here'},
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    }),
  );
}

void main() {
  test('only books with no cover or an Open Library cover are candidates',
      () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    Future<String> add(String title, String? cover) => repository.add(
          title: title,
          author: 'A',
          shelf: Shelf.forLater,
          coverUrl: cover,
        );
    final none = await add('None', null);
    final ol = await add('OL', 'https://covers.openlibrary.org/b/id/5-M.jpg');
    await add('Google', 'https://books.google.com/x.jpg');
    await add('Picture', 'data:image/jpeg;base64,AAAA');
    final ids = coverCandidates(repository.allBooks).map((b) => b.id).toSet();
    expect(ids, {none, ol});
  });

  test('a scan finds covers for missing and broken ones only', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    Future<String> add(String title, String? cover) => repository.add(
          title: title,
          author: 'Jeff Lindsay',
          shelf: Shelf.forLater,
          coverUrl: cover,
        );
    final missing = await add('Darkly Dreaming Dexter', null);
    final broken = await add(
      'Darkly Dreaming Dexter: A Novel',
      'https://covers.openlibrary.org/b/id/111-M.jpg',
    );
    await add(
      'Dexter in the Dark',
      'https://covers.openlibrary.org/b/id/222-M.jpg',
    );
    final result = await scanCovers(
      coverCandidates(repository.allBooks),
      _fake(),
      pause: Duration.zero,
    );
    expect(result.checked, 3);
    expect(result.unreachable, isFalse);
    expect({for (final f in result.fixes) f.book.id}, {missing, broken});
    for (final fix in result.fixes) {
      expect(fix.newUrl, 'https://covers.openlibrary.org/b/id/333-M.jpg');
    }
    await repository.setCoversFor({
      for (final f in result.fixes) f.book.id: f.newUrl,
    });
    expect(repository.byId(missing)!.coverUrl, endsWith('/333-M.jpg'));
    expect(repository.byId(broken)!.coverUrl, endsWith('/333-M.jpg'));
  });

  test('the scan gives up when Open Library cannot be reached', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    for (var i = 0; i < 6; i++) {
      await repository.add(
        title: 'Book $i',
        author: 'A',
        shelf: Shelf.forLater,
        coverUrl: 'https://covers.openlibrary.org/b/id/$i-M.jpg',
      );
    }
    final offline = OpenLibraryClient(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    final result = await scanCovers(
      coverCandidates(repository.allBooks),
      offline,
      pause: Duration.zero,
    );
    expect(result.unreachable, isTrue);
    expect(result.checked, 3);
    expect(result.fixes, isEmpty);
  });

  test('cover options list the matches, then every edition cover', () async {
    final options = await findCoverOptions(
      _fake(),
      title: 'Darkly Dreaming Dexter',
      author: 'Jeff Lindsay',
    );
    expect(options.map((o) => o.url), [
      'https://covers.openlibrary.org/b/id/333-M.jpg',
      'https://covers.openlibrary.org/b/id/444-M.jpg',
    ]);
    expect(options.last.label, 'Orion · 2005');
  });
}
