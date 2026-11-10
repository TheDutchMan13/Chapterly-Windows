import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/library_screen.dart';
import 'package:chapterly/screens/read_next_screen.dart';
import 'package:chapterly/screens/tag_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Book _book(
  String id,
  String title,
  Shelf shelf, [
  List<String> tags = const [],
]) => Book(
  id: id,
  title: title,
  author: 'A',
  shelf: shelf,
  addedAt: DateTime(2026, 1, int.parse(id)),
  updatedAt: DateTime(2026, 1, 1),
  tags: tags,
);

Future<BookRepository> _repository(List<Book> books) async {
  final repository = BookRepository(InMemoryBookStore());
  await repository.load();
  await repository.replaceAll(books);
  return repository;
}

Future<void> _library(
  WidgetTester tester,
  BookRepository repository, [
  AppSettings? given,
]) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = given ?? AppSettings();
  final pcSync = PcSync(
    repository: repository,
    settings: settings,
    codeStore: MemoryCodeStore(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: LibraryScreen(
        repository: repository,
        client: OpenLibraryClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        settings: settings,
        pcSync: pcSync,
        fileIo: const FileIo(),
      ),
    ),
  );
  await tester.pump();
}

/// Scrolls the filter bar (it scrolls sideways, and builds only what is on
/// screen) until [finder] is showing.
Future<void> _scrollBarTo(WidgetTester tester, Finder finder) async {
  final bar = find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    ),
    matching: find.byType(Scrollable),
  );
  // Back to the start first: scrolling only goes forward.
  await tester.drag(bar, const Offset(6000, 0));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 200, scrollable: bar);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('chipTags', () {
    final counts = {for (var i = 0; i < 30; i++) 'tag$i': 30 - i, 'Zebra': 100};

    test('shows the most used, and every tag in use in the filter', () {
      final shown = chipTags(counts, {'tag29'});
      expect(shown.length, visibleTagCount);
      expect(shown.first, 'tag29');
      expect(shown, contains('Zebra'));
      expect(shown, isNot(contains('tag25')));
    });

    test('a filter with more tags than the limit keeps them all', () {
      final inUse = {for (var i = 0; i < 15; i++) 'tag${29 - i}'};
      expect(chipTags(counts, inUse).toSet(), inUse);
    });

    test('ties are alphabetical and a tag that is gone is dropped', () {
      expect(chipTags({'b': 1, 'a': 1, 'c': 1}, {'gone'}, limit: 2), [
        'a',
        'b',
      ]);
    });
  });

  testWidgets('the library opens on the first shelf that has books', (
    tester,
  ) async {
    final repository = await _repository([
      _book('1', 'Waiting one', Shelf.forLater),
      _book('2', 'Waiting two', Shelf.forLater),
    ]);
    await _library(tester, repository);
    // Finished is empty, so For later is showing.
    expect(find.text('Waiting one'), findsOneWidget);
    expect(find.text('Waiting two'), findsOneWidget);
  });

  testWidgets('it opens on Finished when that has books', (tester) async {
    final repository = await _repository([
      _book('1', 'Done', Shelf.finished),
      _book('2', 'Waiting', Shelf.forLater),
    ]);
    await _library(tester, repository);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Waiting'), findsNothing);
  });

  testWidgets('an empty library still opens', (tester) async {
    await _library(tester, await _repository([]));
    expect(find.textContaining('Finished'), findsWidgets);
  });

  testWidgets('many tags: a few chips and an All tags list that filters', (
    tester,
  ) async {
    final repository = await _repository([
      for (var i = 1; i <= 40; i++)
        _book('$i', 'Book $i', Shelf.forLater, ['tag$i', if (i <= 3) 'common']),
    ]);
    await _library(tester, repository);
    // Far fewer chips than the 41 tags (the bar scrolls sideways, so
    // look past what is on screen).
    expect(
      find.byType(FilterChip, skipOffstage: false).evaluate().length,
      lessThan(25),
    );
    await _scrollBarTo(tester, find.text('All tags (41)'));
    expect(find.text('All tags (41)'), findsOneWidget);
    await _scrollBarTo(tester, find.text('common'));
    expect(find.text('common'), findsOneWidget);
    expect(find.text('tag40', skipOffstage: false), findsNothing);
    await _scrollBarTo(tester, find.text('All tags (41)'));
    await tester.tap(find.text('All tags (41)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'tag40');
    await tester.pump();
    expect(find.text('1 books'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'tag40'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    // The chosen tag now shows as a chip, and only its book is listed.
    await _scrollBarTo(tester, find.widgetWithText(FilterChip, 'tag40'));
    expect(find.widgetWithText(FilterChip, 'tag40'), findsOneWidget);
    expect(find.text('Book 40'), findsOneWidget);
    expect(find.text('Book 1'), findsNothing);
  });

  testWidgets('a tag can be hidden from the All tags list', (tester) async {
    final repository = await _repository([
      for (var i = 1; i <= 20; i++)
        _book('$i', 'Book $i', Shelf.forLater, ['t$i', if (i == 1) 'skip']),
    ]);
    await _library(tester, repository);
    await _scrollBarTo(tester, find.text('All tags (21)'));
    await tester.tap(find.text('All tags (21)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'skip');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'skip'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'skip'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Book 1'), findsNothing);
    expect(find.text('Book 2'), findsOneWidget);
  });

  testWidgets('few tags show no All tags chip', (tester) async {
    final repository = await _repository([
      _book('1', 'One', Shelf.forLater, ['a', 'b']),
    ]);
    await _library(tester, repository);
    expect(find.textContaining('All tags', skipOffstage: false), findsNothing);
  });

  testWidgets('Read next lists a few tags and the rest under All tags', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = await _repository([
      for (var i = 1; i <= 30; i++)
        _book('$i', 'Book $i', Shelf.forLater, ['tag$i']),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ReadNextScreen(
          repository: repository,
          settings: AppSettings(),
          fileIo: const FileIo(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('All tags (30)'), findsOneWidget);
    expect(
      find.byType(FilterChip, skipOffstage: false).evaluate().length,
      lessThan(25),
    );
    await tester.tap(find.text('All tags (30)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'tag30');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'tag30'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'tag30'), findsOneWidget);
  });
}
