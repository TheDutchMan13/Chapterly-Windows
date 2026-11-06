import 'package:chapterly/data/series.dart';
import 'package:chapterly/data/series_detect.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

// The same tests are in the Android app.

Book _book(String id, String title, String series, int number,
        {String author = 'Jeff Lindsay'}) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      series: series,
      seriesNumber: number,
    );

void main() {
  test('names that differ by Series, Saga, The or punctuation share a key', () {
    expect(seriesMergeKey('Dexter Series'), seriesMergeKey('dexter'));
    expect(seriesMergeKey('The Expanse'), seriesMergeKey('Expanse'));
    expect(seriesMergeKey('Mistborn Trilogy'), seriesMergeKey('Mistborn'));
    expect(seriesMergeKey('Lord-of-the Rings Saga'),
        seriesMergeKey('Lord of the Rings'));
    // A name that is only a filler word is kept.
    expect(seriesMergeKey('Series'), 'series');
  });

  test('two spellings of one series become one, keeping the bigger group', () {
    final books = [
      for (var i = 1; i <= 8; i++) _book('a$i', 'Dexter $i', 'Dexter', i),
      _book('b3', 'Dexter in the Dark', 'Dexter Series', 3),
      _book('b8', 'Dexter is Delicious', 'Dexter Series', 8),
    ];
    final merges = findSeriesMerges(books);
    expect(merges, hasLength(1));
    expect(merges.single.target, 'Dexter');
    expect(merges.single.names, ['Dexter Series']);
    expect(merges.single.bookIds, ['b3', 'b8']);
  });

  test('different authors with the same short name are not joined', () {
    final books = [
      _book('1', 'One', 'Cycle', 1, author: 'Ann Lee'),
      _book('2', 'Two', 'Cycle Series', 1, author: 'Bob Jones'),
    ];
    expect(findSeriesMerges(books), isEmpty);
  });

  test('series in titles use the spelling you already have', () {
    final books = [
      _book('1', 'Dexter 1', 'Dexter', 1),
      Book(
        id: '2',
        title: 'Dexter Series Book 2: Dearly Devoted Dexter',
        author: 'Jeff Lindsay',
        shelf: Shelf.forLater,
        addedAt: DateTime(2026),
      ),
    ];
    final guess = detectSeries(books).single;
    expect(guess.series, 'Dexter');
    expect(guess.number, 2);
  });
}
