import 'dart:convert';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_sorting.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/data/rating_text.dart';
import 'package:chapterly/data/statistics.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_format.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late BookRepository repo;

  Future<String> addBook(
    String title, {
    Shelf shelf = Shelf.forLater,
    List<String> tags = const [],
    String author = 'Someone',
    int? pages,
  }) async {
    await repo.add(
      title: title,
      author: author,
      shelf: shelf,
      tags: tags,
      pages: pages,
    );
    return repo.books.firstWhere((b) => b.title == title).id;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = BookRepository(InMemoryBookStore());
    await repo.load();
  });

  group('filters', () {
    test('tags match all or any, and tags can be hidden', () async {
      await addBook('Both', tags: ['a', 'b']);
      await addBook('OnlyA', tags: ['a']);
      await addBook('OnlyB', tags: ['b']);
      await addBook('None');

      List<String> titles(List<Book> books) => [for (final b in books) b.title]
        ..sort();

      expect(
        titles(repo.booksOn(Shelf.forLater, tags: {'a', 'b'})),
        ['Both'],
      );
      expect(
        titles(
          repo.booksOn(Shelf.forLater, tags: {'a', 'b'}, matchAllTags: false),
        ),
        ['Both', 'OnlyA', 'OnlyB'],
      );
      expect(
        titles(repo.booksOn(Shelf.forLater, excludedTags: {'a'})),
        ['None', 'OnlyB'],
      );
      expect(
        titles(
          repo.booksOn(
            Shelf.forLater,
            tags: {'b'},
            excludedTags: {'a'},
          ),
        ),
        ['OnlyB'],
      );
    });

    test('filter by the year a book was finished', () async {
      final a = await addBook('Old', shelf: Shelf.finished);
      final b = await addBook('New', shelf: Shelf.finished);
      await addBook('Unread');
      await repo.setDates(
        a,
        startedAt: null,
        finishedAt: DateTime(2024, 5, 1),
      );
      await repo.setDates(
        b,
        startedAt: null,
        finishedAt: DateTime(2026, 2, 1),
      );
      expect(repo.finishedYears, [2026, 2024]);
      expect(
        [for (final x in repo.booksOn(Shelf.finished, finishYear: 2024)) x.title],
        ['Old'],
      );
      expect(repo.booksOn(Shelf.finished, finishYear: 2025), isEmpty);
    });
  });

  group('bulk edits', () {
    test('change the format and the author of several books', () async {
      final a = await addBook('A');
      final b = await addBook('B');
      await repo.setFormatAll({a, b}, BookFormat.ebook);
      expect(repo.byId(a)!.format, BookFormat.ebook);
      expect(repo.byId(b)!.format, BookFormat.ebook);
      await repo.setFormatAll({a}, null);
      expect(repo.byId(a)!.format, isNull);

      await repo.setAuthorAll({a, b}, '  New Author ');
      expect(repo.byId(a)!.author, 'New Author');
      expect(repo.byId(b)!.author, 'New Author');
      await repo.setAuthorAll({a}, '   ');
      expect(repo.byId(a)!.author, 'New Author');
    });
  });

  group('sorting', () {
    test('by publication year puts unknown years last', () async {
      await repo.add(
        title: 'Old',
        author: 'A',
        shelf: Shelf.forLater,
        firstPublishYear: 1900,
      );
      await repo.add(
        title: 'New',
        author: 'A',
        shelf: Shelf.forLater,
        firstPublishYear: 2020,
      );
      await addBook('Unknown');
      List<String> order(bool ascending) => [
            for (final b in sortBooks(
              repo.books,
              SortField.publicationYear,
              ascending: ascending,
            ))
              b.title,
          ];
      expect(order(true), ['Old', 'New', 'Unknown']);
      expect(order(false), ['New', 'Old', 'Unknown']);
    });

    test('by date modified uses the last change', () async {
      final a = await addBook('A');
      await addBook('B');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.setRating(a, 4);
      final newestFirst = sortBooks(
        repo.books,
        SortField.dateModified,
        ascending: false,
      );
      expect(newestFirst.first.id, a);
    });
  });

  group('settings', () {
    test('defaults for new books are remembered', () async {
      final settings = await AppSettings.load();
      expect(settings.defaultShelf, isNull);
      expect(settings.defaultFormat, isNull);
      expect(settings.defaultTags, isEmpty);

      settings.setDefaultShelf(Shelf.inProgress);
      settings.setDefaultFormat(BookFormat.audiobook);
      settings.setDefaultTags(['owned', 'to-review']);

      final again = await AppSettings.load();
      expect(again.defaultShelf, Shelf.inProgress);
      expect(again.defaultFormat, BookFormat.audiobook);
      expect(again.defaultTags, ['owned', 'to-review']);

      again.setDefaultShelf(null);
      again.setDefaultFormat(null);
      final cleared = await AppSettings.load();
      expect(cleared.defaultShelf, isNull);
      expect(cleared.defaultFormat, isNull);
    });

    test('card and rating options are remembered', () async {
      final settings = await AppSettings.load();
      expect(settings.ratingAsNumber, isFalse);
      expect(settings.showFormatOnCards, isTrue);
      expect(settings.showTagsOnCards, isTrue);
      settings.setRatingAsNumber(true);
      settings.setShowFormatOnCards(false);
      settings.setShowTagsOnCards(false);
      final again = await AppSettings.load();
      expect(again.ratingAsNumber, isTrue);
      expect(again.showFormatOnCards, isFalse);
      expect(again.showTagsOnCards, isFalse);
    });

    test('shelf tab order is saved and always has all four shelves', () async {
      final settings = await AppSettings.load();
      expect(settings.shelfOrder, Shelf.values);
      settings.setShelfOrder([Shelf.unfinished, Shelf.finished]);
      expect(settings.shelfOrder, [
        Shelf.unfinished,
        Shelf.finished,
        Shelf.inProgress,
        Shelf.forLater,
      ]);
      final again = await AppSettings.load();
      expect(again.shelfOrder, settings.shelfOrder);
    });

    test('the yearly pages goal is saved and can be removed', () async {
      final settings = await AppSettings.load();
      expect(settings.pagesGoalFor(2026), isNull);
      settings.setPagesGoal(2026, 5000);
      expect((await AppSettings.load()).pagesGoalFor(2026), 5000);
      expect(settings.goalFor(2026), isNull);
      settings.setPagesGoal(2026, 0);
      expect((await AppSettings.load()).pagesGoalFor(2026), isNull);
    });
  });

  test('ratings show as stars or as a number', () {
    expect(ratingText(3, asNumber: false), '★★★☆☆');
    expect(ratingText(3, asNumber: true), '3/5');
    expect(ratingText(9, asNumber: true), '5/5');
  });

  test('pages are added up per month and per year', () async {
    final a = await addBook('A', shelf: Shelf.finished, pages: 300);
    final b = await addBook('B', shelf: Shelf.finished, pages: 200);
    final c = await addBook('C', shelf: Shelf.finished, pages: 100);
    await repo.setDates(a, startedAt: null, finishedAt: DateTime(2026, 3, 1));
    await repo.setDates(b, startedAt: null, finishedAt: DateTime(2026, 3, 9));
    await repo.setDates(c, startedAt: null, finishedAt: DateTime(2025, 12, 30));
    final stats = computeStats(repo.books, year: 2026);
    expect(stats.pagesByMonth[2], 500);
    expect(stats.pagesByMonth.fold<int>(0, (x, y) => x + y), 500);
    final all = computeStats(repo.books);
    expect(all.pagesByYear, {2025: 100, 2026: 500});
  });

  test('a pages goal says "pages" in its summary', () {
    final status = challengeStatus(
      finished: 1000,
      goal: 3000,
      year: 2025,
      now: DateTime(2026, 1, 1),
    );
    expect(status.describe(unit: 'pages'), '2000 pages to go');
    expect(status.describe(), '2000 to go');
  });

  group('Open Library', () {
    test('Open Library IDs become searches', () {
      expect(openLibraryQuery('dune'), 'dune');
      expect(openLibraryQuery(' ol45804w '), 'key:/works/OL45804W');
      expect(openLibraryQuery('OL7353617M'), 'edition_key:OL7353617M');
      expect(openLibraryQuery('OL23919A'), 'author_key:OL23919A');
      expect(openLibraryQuery('OL12'), 'OL12');
    });

    test('search sends the ID query and keeps the work key', () async {
      String? sentQuery;
      final client = OpenLibraryClient(
        client: MockClient((request) async {
          sentQuery = request.url.queryParameters['q'];
          return http.Response(
            jsonEncode({
              'docs': [
                {'key': '/works/OL45804W', 'title': 'Dune'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final results = await client.search('OL45804W');
      expect(sentQuery, 'key:/works/OL45804W');
      expect(results.single.workKey, '/works/OL45804W');
    });

    test('editions are read and merged into the book', () async {
      Uri? requested;
      final client = OpenLibraryClient(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode({
              'entries': [
                {
                  'title': 'Dune (Ace)',
                  'publishers': ['Ace'],
                  'publish_date': '1990',
                  'number_of_pages': 535,
                  'isbn_13': ['9780441172719'],
                  'covers': [-1, 777],
                },
                {'title': 'Dune (no details)'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final editions = await client.editions('/works/OL45804W');
      expect(requested!.path, '/works/OL45804W/editions.json');
      expect(editions, hasLength(2));
      expect(editions[0].isbn, '9780441172719');
      expect(editions[0].pages, 535);
      expect(editions[0].coverUrl, endsWith('/777-M.jpg'));
      expect(editions[0].subtitle, contains('Ace'));
      expect(editions[1].coverUrl, isNull);

      const work = OpenLibraryBook(
        title: 'Dune',
        author: 'Frank Herbert',
        firstPublishYear: 1965,
        pages: 600,
        workKey: '/works/OL45804W',
      );
      final merged = work.withEdition(editions[0]);
      expect(merged.title, 'Dune');
      expect(merged.pages, 535);
      expect(merged.isbn, '9780441172719');
      final kept = work.withEdition(editions[1]);
      expect(kept.pages, 600);
    });

    test('no work key means no editions and no request', () async {
      final client = OpenLibraryClient(
        client: MockClient((request) async => throw StateError('no request')),
      );
      expect(await client.editions(' '), isEmpty);
    });
  });
}
