import 'dart:convert';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/book_insights.dart';
import 'package:chapterly/screens/duplicates_screen.dart';
import 'package:chapterly/screens/read_next_screen.dart';
import 'package:chapterly/screens/series_screen.dart';
import 'package:chapterly/screens/statistics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Book _book(
  String id,
  String title, {
  String author = 'A',
  Shelf shelf = Shelf.forLater,
  List<String> tags = const [],
  int? rating,
  String? series,
  int? number,
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: shelf,
      addedAt: DateTime(2026, 1, int.tryParse(id) ?? 1),
      tags: tags,
      rating: rating,
      series: series,
      seriesNumber: number,
      finishedAt: shelf == Shelf.finished ? DateTime(2026, 3) : null,
    );

Future<BookRepository> _repository(List<Book> books) async {
  final repository = BookRepository(InMemoryBookStore());
  await repository.load();
  await repository.replaceAll(books);
  return repository;
}

void main() {
  testWidgets('possible duplicates can be merged or set aside', (tester) async {
    final repository = await _repository([
      _book('1', 'The Name of the Wind', author: 'Patrick Rothfuss'),
      _book('2', 'The Name of the Wnd', author: 'Patrick Rothfuss'),
    ]);
    final settings = AppSettings();
    await tester.pumpWidget(MaterialApp(
      home: DuplicatesScreen(repository: repository, settings: settings),
    ));
    expect(find.text('Possible duplicates'), findsOneWidget);
    expect(find.text('Almost the same title'), findsOneWidget);
    await tester.tap(find.text('Not the same'));
    await tester.pumpAndSettle();
    expect(find.text('No duplicates found.'), findsOneWidget);
    expect(settings.notDuplicates, hasLength(1));
  });

  testWidgets('series found in titles are set', (tester) async {
    final repository = await _repository([
      _book('1', 'The Final Empire (Mistborn, #1)'),
      _book('2', 'The Well of Ascension (Mistborn, #2)'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: SeriesScreen(repository: repository, onOpenBook: (_) {}),
    ));
    await tester.tap(find.text('Find series in titles'));
    await tester.pumpAndSettle();
    expect(find.text('Mistborn #1'), findsOneWidget);
    await tester.tap(find.text('Set 2'));
    await tester.pumpAndSettle();
    expect(repository.byId('2')!.series, 'Mistborn');
    expect(repository.byId('2')!.seriesNumber, 2);
  });

  testWidgets('Read next picks the best match and says why', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = await _repository([
      _book('1', 'Mistborn', author: 'Brandon Sanderson',
          shelf: Shelf.finished, rating: 5, tags: ['fantasy']),
      _book('2', 'Warbreaker', author: 'Brandon Sanderson', tags: ['fantasy']),
      _book('3', 'A Cookbook', author: 'Chef', tags: ['cooking']),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: ReadNextScreen(
        repository: repository,
        settings: AppSettings(),
        fileIo: const FileIo(),
      ),
    ));
    expect(find.text('Warbreaker'), findsOneWidget);
    expect(find.textContaining('Because you liked Mistborn'), findsOneWidget);
    await tester.tap(find.text('Next match'));
    await tester.pump();
    expect(find.text('A Cookbook'), findsOneWidget);
  });

  testWidgets('tag suggestions add the tags you pick', (tester) async {
    final repository = await _repository([
      _book('1', 'Mistborn', author: 'Brandon Sanderson', tags: ['Fantasy']),
      _book('2', 'Warbreaker', author: 'Brandon Sanderson'),
    ]);
    final client = OpenLibraryClient(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'docs': [
                {
                  'key': '/works/1',
                  'subject': ['Epic fantasy', 'Heists'],
                },
              ],
            }),
            200,
          )),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showTagSuggestions(
            context,
            repository: repository,
            book: repository.byId('2')!,
            client: client,
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Fantasy'), findsOneWidget);
    expect(find.text('Heists (new tag)'), findsOneWidget);
    await tester.tap(find.text('Add 1'));
    await tester.pumpAndSettle();
    expect(repository.byId('2')!.tags, ['Fantasy']);
  });

  testWidgets('Statistics shows your taste', (tester) async {
    tester.view.physicalSize = const Size(1400, 4000);
    addTearDown(tester.view.reset);
    final repository = await _repository([
      for (var i = 1; i <= 6; i++)
        _book('$i', 'F$i', shelf: Shelf.finished, rating: 5, tags: ['fantasy'],
            author: 'Author $i'),
      for (var i = 7; i <= 12; i++)
        _book('$i', 'R$i', shelf: Shelf.finished, rating: 2, tags: ['romance'],
            author: 'Writer $i'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: StatisticsScreen(
        repository: repository,
        settings: AppSettings(),
        fileIo: const FileIo(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Your taste'), 300);
    expect(find.text('Your taste'), findsOneWidget);
    expect(find.textContaining('You rate fantasy'), findsOneWidget);
  });
}
