import 'dart:convert';

import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/cover_size.dart';
import 'package:chapterly/data/file_details.dart';
import 'package:chapterly/data/google_books_client.dart';
import 'package:chapterly/data/hardcover_client.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/fix_library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The same tests are in the Android app.

Book _book(String id, String title, {String? series, int? number}) => Book(
      id: id,
      title: title,
      author: 'Jeff Lindsay',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      series: series,
      seriesNumber: number,
      coverUrl: 'https://example.com/$id.jpg',
      isbn: '9780385518345',
    );

void main() {
  test('larger covers for Open Library and Google, others left alone', () {
    expect(largerCover('https://covers.openlibrary.org/b/id/12-M.jpg'),
        'https://covers.openlibrary.org/b/id/12-L.jpg');
    expect(largerCover('https://covers.openlibrary.org/b/isbn/97801-S.jpg?default=false'),
        'https://covers.openlibrary.org/b/isbn/97801-L.jpg?default=false');
    final google = largerCover(
        'https://books.google.com/books/content?id=x&printsec=frontcover&img=1&zoom=1');
    expect(google, contains('fife=w600-h900'));
    expect(largerCover(google), google);
    expect(hasLargerCover(google), isFalse);
    expect(hasLargerCover('https://example.com/a.jpg'), isFalse);
    expect(hasLargerCover('data:image/jpeg;base64,AAAA'), isFalse);
  });

  test('series parts like "Book 3" and "3.0" give a number', () {
    expect(seriesPartNumber('3'), 3);
    expect(seriesPartNumber('Book 3'), 3);
    expect(seriesPartNumber('3.0'), 3);
    expect(seriesPartNumber('2.5'), isNull);
    expect(seriesPartNumber(''), isNull);
  });

  test('Hardcover gives the series of a matching book, and a series list',
      () async {
    final bodies = <String>[];
    final hardcover = HardcoverClient(
      token: () => 'abc',
      pause: Duration.zero,
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer abc');
        bodies.add(request.body);
        if (request.body.contains('query_type: \\"Book\\"')) {
          return http.Response(
            jsonEncode({
              'data': {
                'search': {
                  'results': {
                    'hits': [
                      {
                        'document': {
                          'title': 'Something Else',
                          'author_names': ['Someone'],
                          'featured_series': {
                            'position': 1,
                            'series': {'name': 'Nope'},
                          },
                        },
                      },
                      {
                        'document': {
                          'title': 'Dexter in the Dark',
                          'author_names': ['Jeff Lindsay'],
                          'featured_series_position': 3,
                          'featured_series': {
                            'series': {'name': 'Dexter'},
                          },
                        },
                      },
                    ],
                  },
                },
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {
              'series': [
                {
                  'name': 'Dexter',
                  'author': {'name': 'Jeff Lindsay'},
                  'book_series': [
                    {'position': 1, 'book': {'title': 'Darkly Dreaming Dexter'}},
                    {'position': 1.5, 'book': {'title': 'A short story'}},
                    {'position': 2, 'book': {'title': 'Dearly Devoted Dexter'}},
                  ],
                },
              ],
            },
          }),
          200,
        );
      }),
    );
    final found = await hardcover.seriesFor(_book('1', 'Dexter in the Dark'));
    expect(found!.series, 'Dexter');
    expect(found.number, 3);
    final books = await hardcover.seriesBooks('Dexter', author: 'Jeff Lindsay');
    expect([for (final b in books) '${b.number} ${b.title}'],
        ['1 Darkly Dreaming Dexter', '2 Dearly Devoted Dexter']);

    final refused = HardcoverClient(
      token: () => 'bad',
      pause: Duration.zero,
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    expect(refused.seriesFor(_book('1', 'X')),
        throwsA(isA<HardcoverUnauthorized>()));
    expect(HardcoverClient(token: () => null).hasToken, isFalse);
  });

  testWidgets('Fix library finds a series spelled two ways and applies it',
      (tester) async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.replaceAll([
      _book('1', 'Darkly Dreaming Dexter', series: 'Dexter', number: 1),
      _book('2', 'Dearly Devoted Dexter', series: 'Dexter', number: 2),
      _book('3', 'Dexter in the Dark', series: 'Dexter Series', number: 3),
    ]);
    final offline = MockClient((_) async => http.Response('{}', 404));
    await tester.pumpWidget(MaterialApp(
      home: FixLibraryScreen(
        repository: repository,
        client: OpenLibraryClient(client: offline),
        hardcover: HardcoverClient(token: () => null, client: offline),
        google: GoogleBooksClient(client: offline, pause: Duration.zero),
      ),
    ));
    for (final step in ['From your book files', 'ISBNs', 'Covers', 'Larger covers']) {
      await tester.tap(find.text(step));
      await tester.pump();
    }
    await tester.tap(find.text('Check my library'));
    await tester.pumpAndSettle();
    expect(find.text('Dexter Series → Dexter'), findsOneWidget);
    await tester.tap(find.text('Apply 1 change'));
    await tester.pumpAndSettle();
    expect(
      repository.allBooks.firstWhere((b) => b.id == '3').series,
      'Dexter',
    );
    expect(repository.allBooks.firstWhere((b) => b.id == '3').seriesNumber, 3);
  });
}
