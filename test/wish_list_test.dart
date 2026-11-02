import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
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
    expect(find.textContaining('Nothing here yet'), findsOneWidget);

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
