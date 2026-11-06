import 'dart:convert';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/google_books_client.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/screens/search_screen.dart';
import 'package:chapterly/widgets/lookup_source_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The same tests are in the Android app.

void main() {
  testWidgets('the search screen can open on Google Books with a search',
      (tester) async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    String? asked;
    sharedGoogleBooks = GoogleBooksClient(
      pause: Duration.zero,
      client: MockClient((request) async {
        asked = request.url.queryParameters['q'];
        return http.Response(
          jsonEncode({
            'items': [
              {
                'volumeInfo': {
                  'title': 'Dune',
                  'authors': ['Frank Herbert'],
                  'publishedDate': '1965',
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(() => sharedGoogleBooks = null);
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(
        repository: repository,
        client: OpenLibraryClient(
          client: MockClient((_) async => http.Response('{"docs":[]}', 200)),
        ),
        settings: AppSettings(),
        initialQuery: 'dune',
        initialSource: LookupSource.googleBooks,
      ),
    ));
    await tester.pumpAndSettle();
    expect(asked, 'dune');
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Frank Herbert · 1965'), findsOneWidget);
    // Google has no editions to choose from.
    expect(find.byTooltip('Choose an edition'), findsNothing);
  });
}
