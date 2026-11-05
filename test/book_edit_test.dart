import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_source.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_origin.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/book_info_sheet.dart';
import 'package:chapterly/server/server_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BookRepository repo;

  setUp(() async {
    repo = BookRepository(InMemoryBookStore());
    await repo.load();
  });

  test('a new book keeps its original name and first details', () async {
    final id = await repo.add(
      title: 'Cuba',
      author: 'Ferrer, Ada',
      shelf: Shelf.forLater,
      originName: 'Ferrer, Ada - Cuba (2021).epub',
      originSource: 'Your book server',
    );
    final origin = repo.byId(id)!.origin!;
    expect(origin.name, 'Ferrer, Ada - Cuba (2021).epub');
    expect(origin.source, 'Your book server');
    expect(origin.title, 'Cuba');
    expect(origin.edited, isFalse);
  });

  test('correcting a book keeps the matched details to go back to', () async {
    final id = await repo.add(
      title: 'Cuba',
      author: 'Ferrer, Ada',
      shelf: Shelf.forLater,
      originName: 'Ferrer, Ada - Cuba (2021).epub',
    );
    await repo.editDetails(
      id,
      const BookDetails(
        title: '  Cuba: An American History ',
        author: 'Ada Ferrer',
        series: '',
        isbn: '9781501154584',
        pages: 608,
        year: 2021,
        coverUrl: CoverChange('https://covers.example/cuba.jpg'),
      ),
    );
    var book = repo.byId(id)!;
    expect(book.title, 'Cuba: An American History');
    expect(book.author, 'Ada Ferrer');
    expect(book.series, isNull);
    expect(book.pages, 608);
    expect(book.coverUrl, 'https://covers.example/cuba.jpg');
    expect(book.origin!.edited, isTrue);
    expect(book.origin!.title, 'Cuba');
    expect(book.origin!.name, 'Ferrer, Ada - Cuba (2021).epub');

    await repo.resetDetails(id);
    book = repo.byId(id)!;
    expect(book.title, 'Cuba');
    expect(book.author, 'Ferrer, Ada');
    expect(book.isbn, isNull);
    expect(book.pages, isNull);
    expect(book.origin!.edited, isFalse);
    // The cover is not part of the reset.
    expect(book.coverUrl, 'https://covers.example/cuba.jpg');
  });

  test('a book added before origins gets one at its first correction',
      () async {
    final old = Book(
      id: 'old',
      title: 'Wrong title',
      author: 'Someone',
      shelf: Shelf.finished,
      addedAt: DateTime(2025, 1, 1),
    );
    await repo.importBooks([old]);
    expect(repo.byId('old')!.origin, isNull);
    await repo.editDetails(
      'old',
      const BookDetails(title: 'Right title', author: 'Someone'),
    );
    final book = repo.byId('old')!;
    expect(book.title, 'Right title');
    expect(book.origin!.title, 'Wrong title');
    expect(book.origin!.edited, isTrue);
  });

  test('saving without changes changes nothing', () async {
    final id = await repo.add(title: 'Dune', author: 'Frank Herbert',
        shelf: Shelf.forLater);
    final before = repo.byId(id)!;
    await repo.editDetails(
      id,
      const BookDetails(title: 'Dune', author: 'Frank Herbert'),
    );
    expect(identical(repo.byId(id), before) ||
        repo.byId(id)!.updatedAt == before.updatedAt, isTrue);
    expect(repo.byId(id)!.origin!.edited, isFalse);
  });

  test('an empty title is not saved', () async {
    final id = await repo.add(title: 'Dune', author: '', shelf: Shelf.forLater);
    await repo.editDetails(id, const BookDetails(title: '  ', author: 'X'));
    expect(repo.byId(id)!.title, 'Dune');
  });

  test('the origin survives saving, backups and sync', () {
    final book = Book(
      id: 'b',
      title: 'Cuba: An American History',
      author: 'Ada Ferrer',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026, 11, 5),
      origin: BookOrigin(
        name: 'Ferrer, Ada - Cuba (2021).epub',
        source: 'Your book server',
        title: 'Cuba',
        author: 'Ferrer, Ada',
        editedAt: DateTime(2026, 11, 5, 9),
      ),
    );
    for (final copy in [
      Book.fromMap(book.toMap()),
      Book.fromJson(book.toJson()),
    ]) {
      expect(copy.origin!.name, 'Ferrer, Ada - Cuba (2021).epub');
      expect(copy.origin!.title, 'Cuba');
      expect(copy.origin!.editedAt, DateTime(2026, 11, 5, 9));
      expect(copy.extras, isEmpty);
    }
    final plain = Book(
      id: 'p',
      title: 'T',
      author: '',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
    );
    expect(plain.toJson().containsKey('origin'), isFalse);
  });

  test('the server sends the file name', () {
    final book = ServerBook.fromJson({
      'id': 'x',
      'title': 'Cuba',
      'kind': 'ebook',
      'format': 'epub',
      'fileName': 'Ferrer, Ada - Cuba (2021).epub',
    })!;
    expect(book.originalName, 'Ferrer, Ada - Cuba (2021).epub');
    final older = ServerBook.fromJson({
      'id': 'x',
      'title': 'Cuba',
      'kind': 'ebook',
      'format': 'epub',
    })!;
    expect(older.originalName, isNull);
  });

  test('folder names come from Windows and Linux paths only', () {
    expect(folderOf(r'G:\Books\Dune\01.mp3'), 'Dune');
    expect(folderOf('/books/Dune/01.mp3'), 'Dune');
    expect(folderOf('content://x/y/01.mp3'), isNull);
    expect(folderOf(r'G:\01.mp3'), isNull);
  });

  testWidgets('the info sheet shows the original name and opens the editor',
      (tester) async {
    final id = await repo.add(
      title: 'Cuba',
      author: 'Ferrer, Ada',
      shelf: Shelf.forLater,
      originName: 'Ferrer, Ada - Cuba (2021).epub',
      originSource: 'Your book server',
    );
    await repo.editDetails(
      id,
      const BookDetails(title: 'Cuba: An American History', author: 'Ada Ferrer'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showBookInfo(context, repository: repo, bookId: id),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Ferrer, Ada - Cuba (2021).epub'), findsWidgets);
    expect(find.text('Cuba · Ferrer, Ada'), findsOneWidget);
    expect(find.text('Cuba: An American History'), findsWidgets);

    await tester.tap(find.text('Edit this book'));
    await tester.pumpAndSettle();
    expect(find.text('Edit book'), findsOneWidget);
    expect(find.text('Find match'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Cuba (An American History)',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.byId(id)!.title, 'Cuba (An American History)');
  });
}
