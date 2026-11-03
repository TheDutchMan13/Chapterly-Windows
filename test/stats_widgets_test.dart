import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_format.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/statistics_screen.dart';
import 'package:chapterly/screens/stats_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  test('every shelf has its own colour', () {
    final colours = {for (final shelf in Shelf.values) shelfColor(shelf)};
    expect(colours, hasLength(Shelf.values.length));
  });

  testWidgets('a tile shows its number and label', (tester) async {
    await tester.pumpWidget(_wrap(const StatTile(
      label: 'Time read',
      value: '1h 4m',
      icon: Icons.schedule,
      color: statsCoral,
    )));
    expect(find.text('1h 4m'), findsOneWidget);
    expect(find.text('Time read'), findsOneWidget);
  });

  testWidgets('the shelf block lists every shelf with its count',
      (tester) async {
    await tester.pumpWidget(_wrap(const ShelfBreakdown(counts: {
      Shelf.forLater: 1065,
      Shelf.unfinished: 1,
    })));
    expect(find.text('1,066 books'), findsNothing);
    expect(find.text('1066 books'), findsOneWidget);
    for (final shelf in Shelf.values) {
      expect(find.text(shelf.label), findsOneWidget, reason: shelf.label);
    }
    expect(find.text('1065'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));
  });

  testWidgets('the shelf block works with no books at all', (tester) async {
    await tester.pumpWidget(_wrap(const ShelfBreakdown(counts: {})));
    expect(find.text('0 books'), findsOneWidget);
  });

  testWidgets('bar rows show each label and number', (tester) async {
    await tester.pumpWidget(_wrap(const BarRows(title: 'By format', rows: [
      ('Paperback', 7, statsBlue),
      ('E-book', 3, statsViolet),
    ])));
    expect(find.text('By format'), findsOneWidget);
    expect(find.text('Paperback'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the Statistics page shows the new tiles, shelves and formats',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.replaceAll([
      Book(
        id: '1',
        title: 'Wanted',
        author: 'A',
        shelf: Shelf.wishlist,
        addedAt: DateTime(2026, 1),
      ),
      Book(
        id: '3',
        title: 'Done',
        author: 'C',
        shelf: Shelf.finished,
        addedAt: DateTime(2026, 1),
        finishedAt: DateTime(2026, 3),
        format: BookFormat.paperback,
      ),
      Book(
        id: '2',
        title: 'Later',
        author: 'B',
        shelf: Shelf.forLater,
        addedAt: DateTime(2026, 1),
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: StatisticsScreen(
        repository: repository,
        settings: AppSettings(),
        fileIo: const FileIo(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(StatTile), findsWidgets);
    expect(find.text('Books finished'), findsOneWidget);
    expect(find.byType(ShelfBreakdown), findsOneWidget);
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('By format'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
