import 'dart:convert';
import 'dart:io';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/auto_backup.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/csv.dart';
import 'package:chapterly/data/kindle_clippings.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/data/statistics.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_format.dart';
import 'package:chapterly/models/quote.dart';
import 'package:chapterly/models/rating_aspect.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book _book(
  String id,
  String title, {
  String author = 'Someone',
  Shelf shelf = Shelf.forLater,
  int? pages,
  int? currentPage,
  List<LogEntry> log = const [],
  List<String> tags = const [],
  DateTime? startedAt,
  DateTime? finishedAt,
  List<Quote> quotes = const [],
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: shelf,
      addedAt: DateTime(2026),
      pages: pages,
      currentPage: currentPage,
      readingLog: log,
      tags: tags,
      startedAt: startedAt,
      finishedAt: finishedAt,
      quotes: quotes,
    );

void main() {
  late BookRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = BookRepository(InMemoryBookStore());
    await repo.load();
  });

  group('current page and rating details', () {
    test('survive the database and backup formats', () {
      final book = Book(
        id: '1',
        title: 'T',
        author: 'A',
        shelf: Shelf.inProgress,
        addedAt: DateTime(2026),
        currentPage: 42,
        aspectRatings: const {'plot': 4, 'pacing': 2},
      );
      final fromMap = Book.fromMap(book.toMap());
      expect(fromMap.currentPage, 42);
      expect(fromMap.aspectRatings, {'plot': 4, 'pacing': 2});
      final fromJson = Book.fromJson(
        jsonDecode(jsonEncode(book.toJson())) as Map<String, dynamic>,
      );
      expect(fromJson.currentPage, 42);
      expect(fromJson.aspectRatings, {'plot': 4, 'pacing': 2});
    });

    test('bad aspect ratings are dropped when reading', () {
      final json = _book('1', 'T').toJson()
        ..['aspectRatings'] = {'plot': 9, 'writing': 3, 'pacing': 'x'};
      expect(Book.fromJson(json).aspectRatings, {'writing': 3});
    });

    test('progress uses the current page, or else the reading log', () {
      final byPage = _book('1', 'T', pages: 200, currentPage: 50);
      expect(byPage.progressPage, 50);
      expect(byPage.progress, 0.25);
      final byLog = _book(
        '2',
        'T',
        pages: 100,
        log: [
          LogEntry(date: DateTime(2026, 1, 1), pages: 30),
          LogEntry(date: DateTime(2026, 1, 2), pages: 20),
        ],
      );
      expect(byLog.progressPage, 50);
      expect(byLog.progress, 0.5);
      expect(_book('3', 'T').progress, isNull);
      expect(_book('4', 'T', pages: 10, currentPage: 30).progress, 1.0);
    });

    test('the repository sets and clears them', () async {
      await repo.add(title: 'T', author: 'A', shelf: Shelf.inProgress);
      final id = repo.books.single.id;
      await repo.setCurrentPage(id, 120);
      expect(repo.byId(id)!.currentPage, 120);
      await repo.setCurrentPage(id, 0);
      expect(repo.byId(id)!.currentPage, isNull);

      await repo.setAspectRating(id, RatingAspect.plot, 5);
      await repo.setAspectRating(id, RatingAspect.writing, 3);
      expect(repo.byId(id)!.aspectRatings, {'plot': 5, 'writing': 3});
      await repo.setAspectRating(id, RatingAspect.plot, null);
      expect(repo.byId(id)!.aspectRatings, {'writing': 3});

      await repo.setCurrentPage(id, 80);
      await repo.readAgain(id);
      expect(repo.byId(id)!.currentPage, isNull);
    });

    test('the reading pace works from the current page alone', () {
      final book = _book(
        '1',
        'T',
        shelf: Shelf.inProgress,
        pages: 300,
        currentPage: 100,
        startedAt: DateTime(2026, 3, 1),
      );
      final pace = readingPace(book, now: DateTime(2026, 3, 10));
      expect(pace, isNotNull);
      expect(pace!.pagesRead, 100);
      expect(pace.pagesLeft, 200);
      expect(pace.pagesPerDay, closeTo(10, 0.001));
      expect(readingPace(_book('2', 'T', shelf: Shelf.inProgress)), isNull);
    });
  });

  group('tag goals', () {
    test('count finished readings with the tag in that year', () {
      final books = [
        _book('1', 'A', shelf: Shelf.finished, tags: ['Sci-Fi'],
            finishedAt: DateTime(2026, 2, 1)),
        _book('2', 'B', shelf: Shelf.finished, tags: ['sci-fi'],
            finishedAt: DateTime(2025, 2, 1)),
        _book('3', 'C', shelf: Shelf.finished, tags: ['fantasy'],
            finishedAt: DateTime(2026, 3, 1)),
        _book('4', 'D', tags: ['sci-fi']),
      ];
      expect(finishedWithTag(books, 'sci-fi', 2026), 1);
      expect(finishedWithTag(books, 'SCI-FI', 2025), 1);
      expect(finishedWithTag(books, 'horror', 2026), 0);
    });

    test('are saved per year and can be removed', () async {
      final settings = await AppSettings.load();
      settings.setTagGoal(2026, 'sci-fi', 10);
      settings.setTagGoal(2026, 'fantasy', 3);
      settings.setTagGoal(2025, 'sci-fi', 5);
      final again = await AppSettings.load();
      expect(again.tagGoalsFor(2026), {'sci-fi': 10, 'fantasy': 3});
      expect(again.tagGoalsFor(2025), {'sci-fi': 5});
      expect(again.tagGoalsFor(2024), isEmpty);
      again.setTagGoal(2026, 'fantasy', null);
      expect((await AppSettings.load()).tagGoalsFor(2026), {'sci-fi': 10});
    });
  });

  group('Kindle highlights', () {
    const clippings = '﻿Dune (Dune Chronicles, Book 1) (Frank Herbert)\r\n'
        '- Your Highlight on page 12 | Location 180-182 | Added on Monday, '
        'January 1, 2024 10:05:00 PM\r\n'
        '\r\n'
        'Fear is the mind-killer.\r\n'
        '==========\r\n'
        'Dune (Dune Chronicles, Book 1) (Frank Herbert)\r\n'
        '- Your Note on page 12 | Location 182 | Added on Monday, January 1, '
        '2024 10:06:00 PM\r\n'
        '\r\n'
        'my note\r\n'
        '==========\r\n'
        'Dune (Dune Chronicles, Book 1) (Frank Herbert)\r\n'
        '- Your Bookmark on page 20 | Location 300 | Added on Monday, '
        'January 1, 2024 10:07:00 PM\r\n'
        '\r\n'
        '\r\n'
        '==========\r\n'
        'The Hobbit (Tolkien, J.R.R.)\r\n'
        '- Your Highlight at location 50-51 | Added on Tuesday, 2 January '
        '2024 08:15:00\r\n'
        '\r\n'
        'In a hole in the ground there lived a hobbit.\r\n'
        '==========\r\n';

    test('highlights are read; notes and bookmarks are skipped', () {
      final parsed = parseKindleClippings(clippings);
      expect(parsed, hasLength(2));
      expect(parsed[0].title, 'Dune (Dune Chronicles, Book 1)');
      expect(parsed[0].author, 'Frank Herbert');
      expect(parsed[0].text, 'Fear is the mind-killer.');
      expect(parsed[0].page, 12);
      expect(parsed[0].addedAt, DateTime(2024, 1, 1, 22, 5));
      expect(parsed[1].title, 'The Hobbit');
      expect(parsed[1].author, 'Tolkien, J.R.R.');
      expect(parsed[1].page, isNull);
      expect(parsed[1].addedAt, DateTime(2024, 1, 2, 8, 15));
    });

    test('highlights are matched to books by title', () {
      final books = [
        _book('dune', 'Dune', author: 'Frank Herbert'),
        _book(
          'hobbit',
          'The Hobbit: or There and Back Again',
          author: 'J.R.R. Tolkien',
          quotes: [
            Quote(text: 'Old  quote', addedAt: DateTime(2025)),
          ],
        ),
      ];
      final parsed = [
        ...parseKindleClippings(clippings),
        const KindleClipping(
          title: 'Dune (Dune Chronicles, Book 1)',
          author: 'Frank Herbert',
          text: 'Fear is the mind-killer.',
        ),
        const KindleClipping(
          title: 'The Hobbit',
          author: 'Tolkien',
          text: 'old quote',
        ),
        const KindleClipping(
          title: 'Unknown Book',
          author: 'Someone',
          text: 'Words',
        ),
      ];
      final match = matchClippings(books, parsed, now: DateTime(2026));
      expect(match.quotesByBook['dune']!.single.text,
          'Fear is the mind-killer.');
      expect(match.quotesByBook['dune']!.single.page, 12);
      expect(match.quotesByBook['hobbit'], hasLength(1));
      expect(match.added, 2);
      expect(match.alreadySaved, 2);
      expect(match.unmatchedTitles, ['Unknown Book']);
    });

    test('with two books of the same title the author decides', () {
      final books = [
        _book('austen', 'Emma', author: 'Jane Austen'),
        _book('smith', 'Emma', author: 'Alexander McCall Smith'),
      ];
      final match = matchClippings(books, const [
        KindleClipping(
          title: 'Emma',
          author: 'Smith, Alexander McCall',
          text: 'A line',
        ),
      ]);
      expect(match.quotesByBook.keys, ['smith']);
    });

    test('the repository adds quotes to several books', () async {
      await repo.add(title: 'A', author: 'X', shelf: Shelf.finished);
      await repo.add(title: 'B', author: 'X', shelf: Shelf.finished);
      final a = repo.books.firstWhere((b) => b.title == 'A').id;
      final b = repo.books.firstWhere((b) => b.title == 'B').id;
      await repo.addQuotesToBooks({
        a: [Quote(text: 'one', addedAt: DateTime(2026))],
        b: [
          Quote(text: 'two', addedAt: DateTime(2026)),
          Quote(text: 'three', page: 3, addedAt: DateTime(2026)),
        ],
      });
      expect(repo.byId(a)!.quotes.map((q) => q.text), ['one']);
      expect(repo.byId(b)!.quotes.map((q) => q.text), ['two', 'three']);
    });
  });

  group('CSV from other apps', () {
    test('StoryGraph export', () {
      const csv = 'Title,Authors,Contributors,ISBN/UID,Format,Read Status,'
          'Date Added,Last Date Read,Dates Read,Read Count,Moods,Pace,'
          'Star Rating,Review,Tags,Owned?\n'
          'Project Hail Mary,Andy Weir,,9780593135204,digital,read,2023/01/02,'
          '2023/02/10,2023/01/05-2023/02/10,1,adventurous,fast,4.5,'
          '"Loved it, truly.",sci-fi,No\n'
          'Piranesi,Susanna Clarke,,9781635575996,paperback,did-not-finish,'
          '2023/03/01,,,0,,,,,,\n'
          'Dune,Frank Herbert,,,audio,to-read,2023/04/01,,,0,,,,,,\n';
      final result = importBooksFromCsv(csv, now: DateTime(2026));
      expect(result.books, hasLength(3));
      final phm = result.books[0];
      expect(phm.author, 'Andy Weir');
      expect(phm.isbn, '9780593135204');
      expect(phm.format, BookFormat.ebook);
      expect(phm.shelf, Shelf.finished);
      expect(phm.finishedAt, DateTime(2023, 2, 10));
      expect(phm.addedAt, DateTime(2023, 1, 2));
      expect(phm.rating, 5);
      expect(phm.notes, 'Loved it, truly.');
      expect(phm.tags, ['sci-fi']);
      expect(result.books[1].shelf, Shelf.unfinished);
      expect(result.books[2].shelf, Shelf.forLater);
      expect(result.books[2].format, BookFormat.audiobook);
    });

    test('Libib export, skipping films', () {
      const header = 'item_type,title,creators,first_name,last_name,'
          'ean_isbn13,upc_isbn10,description,publisher,publish_date,group,'
          'tags,notes,price,length,number_of_discs,number_of_players,'
          'age_group,ensemble,aspect_ratio,esrb,rating,review,review_date,'
          'status,began,completed,added,copies';
      String row(Map<String, String> values) => [
            for (final name in header.split(','))
              '"${(values[name] ?? '').replaceAll('"', '""')}"',
          ].join(',');
      final csv = [
        header,
        row({
          'item_type': 'book',
          'title': 'The Martian',
          'creators': 'Andy Weir',
          'ean_isbn13': '9780553418026',
          'publish_date': '2014-02-11',
          'tags': 'space, survival',
          'length': '384',
          'rating': '4',
          'status': 'Completed',
          'began': '2022-05-01',
          'completed': '2022-05-20',
          'added': '2022-04-30',
        }),
        row({
          'item_type': 'movie',
          'title': 'Alien',
          'creators': 'Ridley Scott',
          'status': 'Not begun',
        }),
        row({
          'item_type': 'book',
          'title': 'Leviathan Wakes',
          'creators': 'James S. A. Corey',
          'publish_date': '2011',
          'length': '592',
          'status': 'In progress',
        }),
      ].join('\n');
      final result = importBooksFromCsv(csv, now: DateTime(2026));
      expect(result.books, hasLength(2));
      expect(result.skipped, 1);
      final martian = result.books[0];
      expect(martian.author, 'Andy Weir');
      expect(martian.isbn, '9780553418026');
      expect(martian.firstPublishYear, 2014);
      expect(martian.pages, 384);
      expect(martian.rating, 4);
      expect(martian.shelf, Shelf.finished);
      expect(martian.startedAt, DateTime(2022, 5, 1));
      expect(martian.finishedAt, DateTime(2022, 5, 20));
      expect(martian.addedAt, DateTime(2022, 4, 30));
      expect(martian.tags, ['space', 'survival']);
      expect(result.books[1].shelf, Shelf.inProgress);
      expect(result.books[1].firstPublishYear, 2011);
    });
  });

  group('subjects', () {
    test('library labels and codes are left out', () {
      expect(
        cleanSubjects([
          'Science fiction',
          'Fiction',
          'Accessible book',
          'Protected DAISY',
          'nyt:hardcover-fiction=2020',
          'Desert planets',
          'science fiction',
          'A subject with a really very long name that goes on',
        ]),
        ['Science fiction', 'Desert planets'],
      );
      expect(cleanSubjects(null), isEmpty);
    });

    test('found by ISBN, or by title when the ISBN gives nothing', () async {
      final queries = <String>[];
      final client = OpenLibraryClient(
        client: MockClient((request) async {
          final q = request.url.queryParameters['q']!;
          queries.add(q);
          final subjects = q.startsWith('isbn:')
              ? ['Accessible book']
              : ['Science fiction', 'Desert planets'];
          return http.Response(
            jsonEncode({
              'docs': [
                {'key': '/works/OL1W', 'subject': subjects},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final subjects = await client.subjectsFor(
        title: 'Dune',
        author: 'Frank Herbert',
        isbn: '978-0441172719',
      );
      expect(subjects, ['Science fiction', 'Desert planets']);
      expect(queries, [
        'isbn:9780441172719',
        'title:"Dune" author:"Frank Herbert"',
      ]);
    });
  });

  group('automatic backups', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('chapterly_test_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('are due when switched on and the time has passed', () async {
      final settings = await AppSettings.load();
      final now = DateTime(2026, 10, 29, 12);
      expect(settings.autoBackupDue(now), isFalse);
      settings.setAutoBackup(true);
      expect(settings.autoBackupDue(now), isTrue);
      settings.recordAutoBackup(at: now, path: '/x/y.json');
      expect(settings.autoBackupDue(now.add(const Duration(days: 6))), isFalse);
      expect(settings.autoBackupDue(now.add(const Duration(days: 7))), isTrue);
      settings.setAutoBackupDays(1);
      expect(settings.autoBackupDue(now.add(const Duration(days: 1))), isTrue);

      final again = await AppSettings.load();
      expect(again.autoBackup, isTrue);
      expect(again.autoBackupDays, 1);
      expect(again.lastAutoBackupAt, now);
      expect(again.lastAutoBackupPath, '/x/y.json');
      again.recordAutoBackupError('disk full');
      expect((await AppSettings.load()).lastAutoBackupError, 'disk full');
    });

    test('file names sort by date', () {
      expect(
        autoBackupFileName(DateTime(2026, 3, 4, 5, 6)),
        'chapterly-auto-2026-03-04-0506.json',
      );
    });

    test('only the newest five are kept', () async {
      final folder = Directory('${temp.path}/backups');
      await folder.create();
      for (var day = 1; day <= 6; day++) {
        await File('${folder.path}/${autoBackupFileName(DateTime(2026, 1, day))}')
            .writeAsString('{}');
      }
      await File('${folder.path}/other.json').writeAsString('{}');
      final path = await writeAutoBackup(
        content: '{"app":"chapterly"}',
        folders: [folder],
        now: DateTime(2026, 2, 1),
      );
      expect(await File(path).readAsString(), '{"app":"chapterly"}');
      final names = [
        for (final entity in folder.listSync())
          entity.uri.pathSegments.last,
      ]..sort();
      expect(names, [
        'chapterly-auto-2026-01-03-0000.json',
        'chapterly-auto-2026-01-04-0000.json',
        'chapterly-auto-2026-01-05-0000.json',
        'chapterly-auto-2026-01-06-0000.json',
        'chapterly-auto-2026-02-01-0000.json',
        'other.json',
      ]);
    });

    test('the next folder is used when the first cannot be written', () async {
      final blocked = File('${temp.path}/not-a-folder');
      await blocked.writeAsString('x');
      final fallback = Directory('${temp.path}/fallback');
      final path = await writeAutoBackup(
        content: '{}',
        folders: [Directory(blocked.path), fallback],
        now: DateTime(2026, 2, 1),
      );
      expect(path, startsWith(fallback.path));
    });
  });
}
