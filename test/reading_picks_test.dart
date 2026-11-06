import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/author_page.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/csv.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/data/goodreads_export.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/data/read_next_picks.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_format.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/author_books_screen.dart';
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
  int? rating,
  String? series,
  int? number,
  DateTime? added,
  List<String> tags = const [],
  String? isbn,
  BookFormat? format,
  String? notes,
  int? pages,
  List<Reading> previous = const [],
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: shelf,
      addedAt: added ?? DateTime(2026, 1, int.tryParse(id) ?? 1),
      rating: rating,
      series: series,
      seriesNumber: number,
      tags: tags,
      isbn: isbn,
      format: format,
      notes: notes,
      pages: pages,
      previousReadings: previous,
      finishedAt: shelf == Shelf.finished ? DateTime(2026, 3, 4) : null,
    );

Future<BookRepository> _repository(List<Book> books) async {
  final repository = BookRepository(InMemoryBookStore());
  await repository.load();
  await repository.replaceAll(books);
  return repository;
}

void main() {
  group('Goodreads export', () {
    test('writes Goodreads columns that Chapterly can read back', () {
      final books = [
        _book('1', 'The Way of Kings',
            author: 'Brandon Sanderson',
            shelf: Shelf.finished,
            rating: 5,
            series: 'The Stormlight Archive',
            number: 1,
            isbn: '0765326353',
            format: BookFormat.hardcover,
            pages: 1007,
            tags: ['Epic Fantasy'],
            notes: 'Loved it, "really"'),
        _book('2', 'Dune', author: 'Frank Herbert', shelf: Shelf.inProgress),
        _book('3', 'Gave up', shelf: Shelf.unfinished),
        _book('4', 'Want it', shelf: Shelf.wishlist),
      ];
      final csv = encodeGoodreadsCsv(books);
      final rows = parseCsv(csv);
      expect(rows.first, goodreadsColumns);
      final header = rows.first;
      String cell(int row, String column) => rows[row][header.indexOf(column)];

      expect(rows, hasLength(5));
      expect(cell(1, 'Title'),
          'The Way of Kings (The Stormlight Archive, #1)');
      expect(cell(1, 'Author l-f'), 'Sanderson, Brandon');
      // Written as ="0765326353", the way Goodreads keeps ISBNs as text.
      expect(csv, contains(',="0765326353",="9780765326355",'));
      expect(cell(1, 'ISBN'), '=0765326353');
      expect(cell(1, 'ISBN13'), '=9780765326355');
      expect(cell(1, 'My Rating'), '5');
      expect(cell(1, 'Binding'), 'Hardcover');
      expect(cell(1, 'Date Read'), '2026/03/04');
      expect(cell(1, 'Exclusive Shelf'), 'read');
      expect(cell(1, 'Bookshelves'), 'epic-fantasy');
      expect(cell(1, 'Private Notes'), 'Loved it, "really"');
      expect(cell(1, 'My Review'), '');
      expect(cell(1, 'Read Count'), '1');
      expect(cell(2, 'Exclusive Shelf'), 'currently-reading');
      expect(cell(2, 'My Rating'), '0');
      expect(cell(3, 'Exclusive Shelf'), 'did-not-finish');
      expect(cell(4, 'Exclusive Shelf'), 'to-read');
      expect(cell(4, 'Bookshelves'), 'wishlist');

      final back = importBooksFromCsv(csv).books;
      expect(back, hasLength(4));
      expect(back.first.isbn, '9780765326355');
      expect(back.first.shelf, Shelf.finished);
      expect(back.first.rating, 5);
      expect(back.first.format, BookFormat.hardcover);
      expect(back[1].shelf, Shelf.inProgress);
    });

    test('leaves out deleted books and guards formulas', () {
      final deleted = Book(
        id: 'x',
        title: 'Gone',
        author: 'A',
        shelf: Shelf.finished,
        addedAt: DateTime(2026),
        deletedAt: DateTime(2026, 2),
      );
      final csv = encodeGoodreadsCsv([deleted, _book('1', '=SUM(A1)')]);
      expect(csv, isNot(contains('Gone')));
      expect(parseCsv(csv)[1][1], "'=SUM(A1)");
    });

    test('counts re-reads', () {
      final csv = encodeGoodreadsCsv([
        _book('1', 'Again', shelf: Shelf.finished, previous: [
          Reading(finishedAt: DateTime(2020)),
        ]),
      ]);
      final rows = parseCsv(csv);
      expect(rows[1][rows.first.indexOf('Read Count')], '2');
    });
  });

  group('author pages', () {
    test('finds books with the author among several and sums them up', () {
      final books = [
        _book('1', 'Good Omens',
            author: 'Terry Pratchett & Neil Gaiman',
            shelf: Shelf.finished,
            rating: 4,
            pages: 400),
        _book('2', 'Mort',
            author: 'Terry Pratchett',
            shelf: Shelf.finished,
            rating: 5,
            pages: 300),
        _book('3', 'Sourcery', author: 'terry  pratchett'),
        _book('4', 'Coraline', author: 'Neil Gaiman'),
      ];
      final found = booksByAuthor(books, 'Terry Pratchett');
      expect([for (final b in found) b.title]..sort(),
          ['Good Omens', 'Mort', 'Sourcery']);
      final summary = summarizeAuthor(found);
      expect(summary.owned, 3);
      expect(summary.finished, 2);
      expect(summary.waiting, 1);
      expect(summary.averageRating, 4.5);
      expect(summary.pagesRead, 700);
      expect(summary.describe(), contains('average 4.5★'));
    });

    testWidgets('shows your books and the ones you do not have',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = await _repository([
        _book('1', 'Mort', author: 'Terry Pratchett', shelf: Shelf.finished),
      ]);
      final client = OpenLibraryClient(
        client: MockClient((_) async => http.Response(
              '{"docs":[{"key":"/works/1","title":"Mort",'
              '"author_name":["Terry Pratchett"]},{"key":"/works/2",'
              '"title":"Guards! Guards!","author_name":["Terry Pratchett"]}]}',
              200,
            )),
      );
      await tester.pumpWidget(MaterialApp(
        home: AuthorBooksScreen(
          repository: repository,
          client: client,
          author: 'Terry Pratchett',
          settings: AppSettings(),
          fileIo: const FileIo(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Your books'), findsOneWidget);
      expect(find.text('Mort'), findsOneWidget);
      expect(find.text('Not in your library'), findsOneWidget);
      expect(find.text('Guards! Guards!'), findsOneWidget);
      expect(find.textContaining('1 finished'), findsOneWidget);
    });
  });

  group('read next picks', () {
    test('suggests the next book in a series you started', () {
      final all = [
        _book('1', 'Mistborn', series: 'Mistborn', number: 1,
            shelf: Shelf.finished),
        _book('2', 'Well of Ascension', series: 'Mistborn', number: 2,
            shelf: Shelf.finished),
        _book('3', 'Hero of Ages', series: 'mistborn', number: 3),
        _book('4', 'Alloy of Law', series: 'Mistborn', number: 4),
        _book('5', 'Eye of the World', series: 'Wheel of Time', number: 1),
        _book('6', 'Book Two', series: 'Started', number: 2),
        _book('7', 'Book One', series: 'Started', number: 1,
            shelf: Shelf.inProgress),
      ];
      final waiting = [for (final b in all) if (b.shelf == Shelf.forLater) b];
      final picks = nextInSeries(all, waiting);
      expect([for (final p in picks) p.book.title], ['Hero of Ages']);
      expect(picks.single.why, 'Next in mistborn: you finished #2');
    });

    test('suggests authors you rated well and the longest waiting', () {
      final all = [
        _book('1', 'Mort', author: 'Terry Pratchett', shelf: Shelf.finished,
            rating: 5),
        _book('2', 'Bad', author: 'Meh Writer', shelf: Shelf.finished,
            rating: 2),
        _book('3', 'Sourcery', author: 'Terry Pratchett',
            added: DateTime(2024, 6)),
        _book('4', 'Worse', author: 'Meh Writer', added: DateTime(2019)),
        _book('5', 'New', author: 'Someone', added: DateTime(2026, 5)),
      ];
      final waiting = [for (final b in all) if (b.shelf == Shelf.forLater) b];
      final picks = readNextPicks(all, waiting, now: DateTime(2026, 6));
      expect([for (final p in picks[ReadNextReason.authorYouLike]!) p.book.id],
          ['3']);
      expect(picks[ReadNextReason.authorYouLike]!.single.why,
          'You finished 1 by Terry Pratchett, average 5.0★');
      expect([for (final p in picks[ReadNextReason.waitingLongest]!) p.book.id],
          ['4', '5']);
      expect(picks[ReadNextReason.waitingLongest]!.first.why,
          'Waiting since 2019 (7 years)');
    });

    testWidgets('Read next lists more places to start', (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = await _repository([
        _book('1', 'Mistborn', series: 'Mistborn', number: 1,
            shelf: Shelf.finished, rating: 5),
        _book('2', 'Well of Ascension', series: 'Mistborn', number: 2),
        _book('3', 'Unrelated', author: 'B'),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: ReadNextScreen(
          repository: repository,
          settings: AppSettings(),
          fileIo: const FileIo(),
        ),
      ));
      await tester.pumpAndSettle();
      // Whichever book the top pick is, the other one is listed below it.
      expect(find.text('Well of Ascension'), findsOneWidget);
      expect(find.text('Unrelated'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
