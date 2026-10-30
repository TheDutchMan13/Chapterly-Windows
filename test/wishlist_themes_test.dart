import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_sorting.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/duplicates.dart';
import 'package:chapterly/data/theme_options.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/models/wish_priority.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book _book(
  String id, {
  WishPriority? priority,
  int? queue,
  DateTime? added,
  Shelf shelf = Shelf.forLater,
  String? buyAt,
  int? pages,
}) =>
    Book(
      id: id,
      title: 'Book $id',
      author: 'Author',
      shelf: shelf,
      addedAt: added ?? DateTime(2026),
      priority: priority,
      queuePosition: queue,
      buyAt: buyAt,
      pages: pages,
    );

List<String> _ids(Iterable<Book> books) => [for (final b in books) b.id];

void main() {
  late BookRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = BookRepository(InMemoryBookStore());
    await repo.load();
  });

  group('wishlist details', () {
    test('survive JSON and the database map', () {
      final book = _book(
        '1',
        priority: WishPriority.high,
        queue: 3,
        buyAt: 'bookshop.org',
      );
      for (final copy in [
        Book.fromJson(book.toJson()),
        Book.fromMap(book.toMap()),
      ]) {
        expect(copy.priority, WishPriority.high);
        expect(copy.queuePosition, 3);
        expect(copy.buyAt, 'bookshop.org');
      }
    });

    test('an unknown priority in a file is ignored', () {
      final json = {..._book('1').toJson(), 'priority': 'urgent'};
      expect(Book.fromJson(json).priority, isNull);
    });

    test('only real web addresses become links', () {
      expect(_book('1', buyAt: 'https://bookshop.org/x').buyLink, isNotNull);
      expect(_book('1', buyAt: 'bookshop.org/books').buyLink, isNotNull);
      expect(_book('1', buyAt: 'Library').buyLink, isNull);
      expect(_book('1', buyAt: 'my local shop.').buyLink, isNull);
      expect(_book('1', buyAt: '  ').buyLink, isNull);
      expect(_book('1').buyLink, isNull);
    });

    test('priority and where to get it can be set and cleared', () async {
      await repo.replaceAll([_book('a'), _book('b')]);
      await repo.setPriority('a', WishPriority.medium);
      expect(repo.byId('a')!.priority, WishPriority.medium);
      await repo.setPriority('a', null);
      expect(repo.byId('a')!.priority, isNull);

      await repo.setBuyAt('a', '  Library  ');
      expect(repo.byId('a')!.buyAt, 'Library');
      await repo.setBuyAt('a', '   ');
      expect(repo.byId('a')!.buyAt, isNull);

      await repo.setPriorityAll({'a', 'b'}, WishPriority.high);
      expect(repo.byId('a')!.priority, WishPriority.high);
      expect(repo.byId('b')!.priority, WishPriority.high);
    });

    test('merging duplicates keeps the priority and where to get it', () {
      final merged = mergeDuplicateGroup([
        _book('1', pages: 100),
        _book('2', priority: WishPriority.high, buyAt: 'Library'),
      ]);
      expect(merged.id, '1');
      expect(merged.priority, WishPriority.high);
      expect(merged.buyAt, 'Library');
    });
  });

  group('Next up order', () {
    test('placed books first, then priority, then the oldest', () async {
      await repo.replaceAll([
        _book('a', added: DateTime(2026, 1, 3), priority: WishPriority.low),
        _book('b', added: DateTime(2026, 1, 2), priority: WishPriority.high),
        _book('c', added: DateTime(2026, 1, 1)),
        _book('d', added: DateTime(2026, 1, 4), queue: 0),
        _book('e', shelf: Shelf.finished),
      ]);
      expect(_ids(repo.nextUp), ['d', 'b', 'a', 'c']);
    });

    test('moving a book to the top places every book', () async {
      await repo.replaceAll([
        _book('a', added: DateTime(2026, 1, 1)),
        _book('b', added: DateTime(2026, 1, 2)),
        _book('c', added: DateTime(2026, 1, 3)),
      ]);
      await repo.moveToTopOfQueue('c');
      expect(_ids(repo.nextUp), ['c', 'a', 'b']);
      expect(repo.byId('c')!.queuePosition, 0);
      expect(repo.byId('b')!.queuePosition, 2);
    });

    test('an order can be saved', () async {
      await repo.replaceAll([_book('a'), _book('b'), _book('c')]);
      await repo.setQueueOrder(['b', 'c', 'a']);
      expect(_ids(repo.nextUp), ['b', 'c', 'a']);
    });

    test('a book that leaves For later loses its place', () async {
      await repo.replaceAll([_book('a'), _book('b')]);
      await repo.moveToTopOfQueue('b');
      await repo.moveTo('b', Shelf.inProgress);
      expect(repo.byId('b')!.queuePosition, isNull);
      await repo.moveTo('b', Shelf.forLater);
      expect(repo.byId('b')!.queuePosition, isNull);
    });

    test('sorting by priority puts high first and none last', () {
      final books = [
        _book('n'),
        _book('l', priority: WishPriority.low),
        _book('h', priority: WishPriority.high),
      ];
      expect(
        _ids(sortBooks(books, SortField.priority, ascending: false)),
        ['h', 'l', 'n'],
      );
      expect(
        _ids(sortBooks(books, SortField.priority, ascending: true)),
        ['l', 'h', 'n'],
      );
    });

    test('sorting by next up starts with the first in line', () {
      final settings = AppSettings()..setSort(SortField.nextUp);
      expect(settings.ascending, isTrue);
      settings.setSort(SortField.priority);
      expect(settings.ascending, isFalse);
    });
  });

  group('themes', () {
    test('the paper look only changes light mode', () {
      final settings = AppSettings()..setPaperLight(true);
      expect(
        buildTheme(settings, Brightness.light).scaffoldBackgroundColor,
        paperColor,
      );
      expect(
        buildTheme(settings, Brightness.dark).scaffoldBackgroundColor,
        isNot(paperColor),
      );
      expect(
        buildTheme(AppSettings(), Brightness.light).scaffoldBackgroundColor,
        isNot(paperColor),
      );
    });

    test('the paper look is remembered', () async {
      final settings = await AppSettings.load();
      expect(settings.paperLight, isFalse);
      settings.setPaperLight(true);
      expect((await AppSettings.load()).paperLight, isTrue);
    });
  });
}
