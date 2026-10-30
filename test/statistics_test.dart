import 'package:chapterly/data/statistics.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(
  String id, {
  Shelf shelf = Shelf.finished,
  int? pages,
  int? rating,
  DateTime? finishedAt,
}) =>
    Book(
      id: id,
      title: 'Book $id',
      author: 'Author',
      shelf: shelf,
      addedAt: DateTime(2020),
      pages: pages,
      rating: rating,
      finishedAt: finishedAt,
    );

void main() {
  final books = [
    _book('1', pages: 100, rating: 4, finishedAt: DateTime(2025, 1, 5)),
    _book('2', pages: 300, rating: 5, finishedAt: DateTime(2025, 1, 20)),
    _book('3', finishedAt: DateTime(2025, 3, 2)),
    _book('4', pages: 50, finishedAt: DateTime(2024, 6, 1)),
    _book('5'),
    _book('6', shelf: Shelf.forLater),
  ];

  test('statistics for one year', () {
    final stats = computeStats(books, year: 2025);

    expect(stats.finishedCount, 3);
    expect(stats.pagesRead, 400);
    expect(stats.averageRating, 4.5);
    expect(stats.averagePages, 200);
    expect(stats.longest!.id, '2');
    expect(stats.byMonth[0], 2);
    expect(stats.byMonth[2], 1);
    expect(stats.byMonth[5], 0);
  });

  test('statistics across all years', () {
    final stats = computeStats(books);

    expect(stats.finishedCount, 5);
    expect(stats.pagesRead, 450);
    expect(stats.byYear, {2024: 1, 2025: 3});
    expect(stats.yearsNewestFirst, [2025, 2024]);
    expect(stats.shelfCounts[Shelf.forLater], 1);
    expect(stats.shelfCounts[Shelf.finished], 5);
    expect(stats.finishedWithoutDate, 1);
  });

  test('an empty library gives empty statistics', () {
    final stats = computeStats([]);

    expect(stats.finishedCount, 0);
    expect(stats.averageRating, isNull);
    expect(stats.averagePages, isNull);
    expect(stats.longest, isNull);
    expect(stats.byYear, isEmpty);
  });
}
