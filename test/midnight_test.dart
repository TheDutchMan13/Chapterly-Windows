import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/theme_options.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/continue_card.dart';
import 'package:chapterly/widgets/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(String id, Shelf shelf, DateTime changed, {int? pages, int? page}) =>
    Book(
      id: id,
      title: 'Book $id',
      author: 'Someone',
      shelf: shelf,
      addedAt: DateTime(2026, 1, 1),
      updatedAt: changed,
      pages: pages,
      currentPage: page,
    );

void main() {
  test('the continue card picks the book read most recently', () {
    final books = [
      _book('a', Shelf.inProgress, DateTime(2026, 3, 1)),
      _book('b', Shelf.inProgress, DateTime(2026, 4, 1)),
      _book('c', Shelf.finished, DateTime(2026, 5, 1)),
    ];
    expect(ContinueReadingCard.pick(books)?.id, 'b');
    expect(ContinueReadingCard.pick([books[2]]), isNull);
  });

  test('the continue card says how far along a book is', () {
    final book = _book('a', Shelf.inProgress, DateTime(2026, 3, 1),
        pages: 400, page: 100);
    final (label, fraction) = ContinueReadingCard.progressOf(book);
    expect(label, 'Page 100 of 400');
    expect(fraction, closeTo(0.25, 0.001));
  });

  test('books without a cover always get the same colour', () {
    expect(placeholderColour('Dune'), placeholderColour('Dune'));
  });

  testWidgets('the card shows the book and opens it', (tester) async {
    Book? opened;
    final book = _book('a', Shelf.inProgress, DateTime(2026, 3, 1),
        pages: 200, page: 50);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppSettings(), Brightness.dark),
        home: Scaffold(
          body: ContinueReadingCard(book: book, onOpen: (b) => opened = b),
        ),
      ),
    );
    expect(find.text('CONTINUE READING'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    await tester.tap(find.text('CONTINUE READING'));
    expect(opened?.id, 'a');
  });
}
