import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/cover_hash.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/quote.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/book_detail_screen.dart';
import 'package:chapterly/screens/library_health_screen.dart';
import 'package:chapterly/screens/library_screen.dart';
import 'package:chapterly/screens/notes_search_screen.dart';
import 'package:chapterly/screens/read_next_screen.dart';
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
  int? pages,
  String? isbn,
  DateTime? startedAt,
  List<Quote> quotes = const [],
  List<LogEntry> log = const [],
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: shelf,
      addedAt: DateTime(2026, 1, int.tryParse(id) ?? 1),
      tags: tags,
      rating: rating,
      pages: pages,
      isbn: isbn,
      startedAt: startedAt,
      quotes: quotes,
      readingLog: log,
      finishedAt: shelf == Shelf.finished ? DateTime(2026, 3) : null,
      updatedAt: DateTime(2026, 1, 1),
    );

Future<BookRepository> _repository(List<Book> books) async {
  final repository = BookRepository(InMemoryBookStore());
  await repository.load();
  await repository.replaceAll(books);
  return repository;
}

void _bigWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('Library health lists problems and fixes old ISBNs',
      (tester) async {
    _bigWindow(tester);
    final repository = await _repository([
      _book('1', 'Old ISBN', isbn: '0306406152'),
      _book('2', 'Bad ISBN', isbn: '9780306406158'),
      _book('3', 'Stalled', shelf: Shelf.inProgress,
          startedAt: DateTime(2025, 1, 1), pages: 100),
    ]);
    final settings = AppSettings();
    await tester.pumpWidget(MaterialApp(
      home: LibraryHealthScreen(
        repository: repository,
        settings: settings,
        onOpenBook: (_) {},
        coverPrints: CoverPrints(),
      ),
    ));
    expect(find.textContaining('ISBN is not valid'), findsOneWidget);
    expect(find.textContaining('Stalled on In progress'), findsOneWidget);
    await tester.tap(find.textContaining('ISBN-10 can become ISBN-13'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change all to ISBN-13'));
    await tester.pumpAndSettle();
    expect(repository.byId('1')!.isbn, '9780306406157');
    expect(find.textContaining('ISBN-10 can become ISBN-13'), findsNothing);

    await tester.tap(find.textContaining('Stalled on In progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stalled on In progress'), findsNothing);
  });

  testWidgets('Search notes and quotes finds and marks words', (tester) async {
    final repository = await _repository([
      _book('1', 'Lighthouse', quotes: [
        Quote(text: 'The lighthouse kept burning', addedAt: DateTime(2026)),
      ]),
    ]);
    Book? opened;
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => NotesSearchScreen(
                repository: repository,
                onOpenBook: (book) => opened = book,
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lighthose');
    await tester.pump();
    expect(find.textContaining('Quote · Lighthouse'), findsOneWidget);
    await tester.tap(find.textContaining('Quote · Lighthouse'));
    await tester.pumpAndSettle();
    expect(opened?.id, '1');
  });

  testWidgets('the book page shows reading time and a predicted rating',
      (tester) async {
    _bigWindow(tester);
    final repository = await _repository([
      for (var i = 1; i <= 5; i++)
        _book('$i', 'Fantasy $i', author: 'Brandon Sanderson',
            tags: ['fantasy'], shelf: Shelf.finished, rating: 5),
      _book('9', 'New one', author: 'Brandon Sanderson', tags: ['fantasy'],
          pages: 400),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: BookDetailScreen(
        repository: repository,
        settings: AppSettings(),
        fileIo: const FileIo(),
        bookId: '9',
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();
    expect(find.text('Reading time'), findsOneWidget);
    expect(find.textContaining('About 10h to read'), findsOneWidget);
    expect(find.text('Predicted rating'), findsOneWidget);
  });

  testWidgets('Read next filters by the time you have', (tester) async {
    _bigWindow(tester);
    final repository = await _repository([
      _book('1', 'Short one', pages: 30),
      _book('2', 'Long one', pages: 900),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: ReadNextScreen(
        repository: repository,
        settings: AppSettings(),
        fileIo: const FileIo(),
      ),
    ));
    await tester.tap(find.text('1 hour'));
    await tester.pump();
    expect(find.text('Short one'), findsOneWidget);
    expect(find.text('Long one'), findsNothing);
  });

  testWidgets('the Library shows the quote of the day and stalled books',
      (tester) async {
    _bigWindow(tester);
    final repository = await _repository([
      _book('1', 'Quoted', quotes: [
        Quote(text: 'A quote worth reading again', addedAt: DateTime(2026)),
      ]),
      _book('2', 'Forgotten', shelf: Shelf.inProgress,
          startedAt: DateTime(2025, 1, 1)),
    ]);
    final settings = AppSettings();
    final pcSync = PcSync(
      repository: repository,
      settings: settings,
      codeStore: MemoryCodeStore(),
    );
    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        repository: repository,
        client: OpenLibraryClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
        settings: settings,
        pcSync: pcSync,
        fileIo: const FileIo(),
      ),
    ));
    await tester.pump();
    expect(find.text('A quote worth reading again'), findsOneWidget);
    expect(find.textContaining('"Forgotten" has not moved'), findsOneWidget);
    expect(settings.quoteSeen, hasLength(1));

    await tester.tap(find.text('Keep reading'));
    await tester.pump();
    expect(find.textContaining('has not moved'), findsNothing);
    await tester.tap(find.byTooltip('Hide for today (turn it off in Settings)'));
    await tester.pump();
    expect(find.text('A quote worth reading again'), findsNothing);
  });
}
