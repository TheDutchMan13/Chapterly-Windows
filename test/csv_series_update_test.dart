import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/csv.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

// The same tests are in the Android app.

void main() {
  test('a CSV import can update the series of books you already have',
      () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    final dexter = await repository.add(
      title: 'Dexter in the Dark',
      author: 'Jeff Lindsay',
      shelf: Shelf.forLater,
    );
    final same = await repository.add(
      title: 'Killing Floor',
      author: 'Lee Child',
      shelf: Shelf.forLater,
    );
    await repository.setSeriesFor({same: ('Jack Reacher', 1)});
    final untouched = await repository.add(
      title: 'Freedom',
      author: 'Sebastian Junger',
      shelf: Shelf.forLater,
    );

    final file = importBooksFromCsv(
      'Title,Author,Shelf,Series,Series Number\n'
      'Dexter in the Dark,Jeff Lindsay,For later,Dexter,3\n'
      'Killing Floor,Lee Child,For later,Jack Reacher,1\n'
      'Freedom,Sebastian Junger,For later,,\n'
      'Wool,Hugh Howey,For later,Silo,1\n',
    );
    final updates = repository.seriesUpdates(file.books);
    expect(updates.keys, [dexter]);
    expect(updates[dexter], ('Dexter', 3));

    await repository.setSeriesFor(updates);
    final book = repository.allBooks.firstWhere((b) => b.id == dexter);
    expect(book.series, 'Dexter');
    expect(book.seriesNumber, 3);
    expect(repository.allBooks.firstWhere((b) => b.id == untouched).series,
        isNull);
    // The new book is not touched by the update, only by importing.
    expect(repository.newBookCount(file.books), 1);
  });
}
