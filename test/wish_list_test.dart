import 'dart:convert';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/wish_list.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/models/wish_priority.dart';
import 'package:chapterly/screens/wish_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Wish _wish(String id, String title,
        {String author = '', WishPriority? priority, String? where}) =>
    Wish(
      id: id,
      title: title,
      author: author,
      priority: priority,
      where: where,
      addedAt: DateTime(2026),
    );

void main() {
  test('search finds words in any order, typos and accents', () {
    final wishes = [
      _wish('1', 'The Way of Kings', author: 'Brandon Sanderson'),
      _wish('2', 'Jane Eyre', author: 'Charlotte Brontë'),
      _wish('3', 'Dune', author: 'Frank Herbert', where: 'Library'),
    ];
    expect(searchWishes(wishes, 'kings sanderson').map((w) => w.id), ['1']);
    expect(searchWishes(wishes, 'Brandn').map((w) => w.id), ['1']);
    expect(searchWishes(wishes, 'bronte').map((w) => w.id), ['2']);
    expect(searchWishes(wishes, 'library').map((w) => w.id), ['3']);
    expect(searchWishes(wishes, 'nothing here'), isEmpty);
    expect(searchWishes(wishes, ''), hasLength(3));
  });

  test('sorted by priority, then title', () {
    final sorted = sortWishes([
      _wish('1', 'Zed'),
      _wish('2', 'Alpha', priority: WishPriority.low),
      _wish('3', 'Beta', priority: WishPriority.high),
    ]);
    expect(sorted.map((w) => w.id), ['3', '2', '1']);
  });

  test('saved as JSON and damaged entries are skipped', () {
    final text = encodeWishes([
      _wish('1', 'Dune', author: 'Frank Herbert', priority: WishPriority.high),
    ]);
    final back = decodeWishes(text);
    expect(back.single.priority, WishPriority.high);
    expect(back.single.author, 'Frank Herbert');
    expect(decodeWishes('[{"id": 5}, 3, {"id":"x","title":"Ok","addedAt":"2026-01-01"}]')
        .map((w) => w.title), ['Ok']);
    expect(decodeWishes('not json'), isEmpty);
  });

  group('syncing the wish list', () {
    Wish w(String id, String title, DateTime updated,
            {DateTime? deleted, String where = ''}) =>
        Wish(
          id: id,
          title: title,
          addedAt: DateTime(2026),
          updatedAt: updated,
          deletedAt: deleted,
          where: where.isEmpty ? null : where,
        );
    final day1 = DateTime(2026, 3, 1);
    final day2 = DateTime(2026, 3, 2);
    final now = DateTime(2026, 3, 10);

    test('the newer copy of a wish wins, a tie keeps mine', () {
      final merged = mergeWishes(
        [w('1', 'Mine old', day1), w('2', 'Tie mine', day1)],
        [w('1', 'Theirs new', day2), w('2', 'Tie theirs', day1), w('3', 'New', day1)],
        now: now,
      );
      final titles = {for (final x in merged) x.id: x.title};
      expect(titles, {'1': 'Theirs new', '2': 'Tie mine', '3': 'New'});
    });

    test('a delete on one side removes the wish on the other', () {
      final mine = [w('1', 'Dune', day1)];
      final theirs = [w('1', 'Dune', day2, deleted: day2)];
      final merged = mergeWishes(mine, theirs, now: now);
      expect(merged.single.deletedAt, day2);
      expect(activeWishes(merged), isEmpty);
      // An edit made after the delete brings it back.
      final edited = mergeWishes(
        merged,
        [w('1', 'Dune again', DateTime(2026, 3, 5))],
        now: now,
      );
      expect(activeWishes(edited).single.title, 'Dune again');
    });

    test('old deletes are dropped, recent ones kept', () {
      final old = DateTime(2025, 1, 1);
      final merged = mergeWishes(
        [w('1', 'A', old, deleted: old)],
        [w('2', 'B', day1, deleted: day1)],
        now: now,
      );
      expect(merged.map((x) => x.id), ['2']);
    });

    test('settings keep deleted wishes for sync but hide them', () {
      final settings = AppSettings();
      settings.saveWish(w('1', 'Dune', day1));
      expect(settings.wishes.single.updatedAt.isAfter(day1), isTrue);
      settings.deleteWish('1');
      expect(settings.wishes, isEmpty);
      expect(settings.allWishes.single.deletedAt, isNotNull);
      // A wish from the other device arrives and one of ours is replaced.
      settings.mergeWishesFrom([
        w('2', 'Emma', DateTime.now()),
        w('1', 'Dune', day1),
      ]);
      expect(settings.wishes.map((x) => x.id), ['2']);
      // An empty list changes nothing.
      settings.mergeWishesFrom(const []);
      expect(settings.allWishes, hasLength(2));
    });

    test('wishes go through a sync message; an older app sends none', () {
      final text = encodeSyncPayload(
        const [],
        const {},
        wishes: [w('1', 'Dune', day1, where: 'Library')],
      );
      final payload = decodeSyncPayload(text);
      expect(payload.features, contains('wishes'));
      expect(payload.wishes.single.where, 'Library');
      expect(payload.wishes.single.updatedAt, day1);
      final old = jsonDecode(text) as Map<String, dynamic>
        ..remove('wishes')
        ..remove('features');
      final fromOld = decodeSyncPayload(jsonEncode(old));
      expect(fromOld.wishes, isEmpty);
      expect(fromOld.features, isEmpty);
    });
  });

  testWidgets('add, search, and move a wish into the library', (tester) async {
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    final settings = AppSettings();
    await tester.pumpWidget(MaterialApp(
      home: WishListScreen(repository: repository, settings: settings),
    ));
    await tester.pump();
    expect(find.textContaining('Nothing on your wish list yet'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Dune');
    await tester.enterText(
        find.widgetWithText(TextField, 'Author'), 'Frank Herbert');
    await tester.enterText(
        find.widgetWithText(TextField, 'Where to get it'), 'Library');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(settings.wishes.single.title, 'Dune');

    await tester.enterText(find.byType(TextField).first, 'herbert');
    await tester.pumpAndSettle();
    expect(find.text('Dune'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'tolkien');
    await tester.pumpAndSettle();
    expect(find.text('No wishes match.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Move to my library'));
    await tester.pumpAndSettle();
    expect(settings.wishes, isEmpty);
    final book = repository.books.single;
    expect(book.title, 'Dune');
    expect(book.shelf, Shelf.forLater);
    expect(book.buyAt, 'Library');
    expect(tester.takeException(), isNull);
  });
}
