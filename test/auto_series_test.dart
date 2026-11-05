import 'package:chapterly/data/auto_series.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/series_detect.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

// The same tests are in the Android app.

void main() {
  late BookRepository repo;

  setUp(() async {
    repo = BookRepository(InMemoryBookStore());
    await repo.load();
  });

  Future<String> add(String title) =>
      repo.add(title: title, author: 'A', shelf: Shelf.forLater);

  test('setSeriesFor sets several books at once and ignores blanks', () async {
    final a = await add('One');
    final b = await add('Two');
    final c = await add('Three');
    await repo.setSeriesFor({a: ('Saga', 1), b: ('Saga', 2), c: ('  ', 3)});
    expect(repo.byId(a)!.series, 'Saga');
    expect(repo.byId(b)!.seriesNumber, 2);
    expect(repo.byId(c)!.series, isNull);
  });

  test('guesses already applied, or for a book with a series, are skipped',
      () async {
    final a = await add('Mistborn, Book 1: The Final Empire');
    final b = await add('Mistborn, Book 2: The Well of Ascension');
    final c = await add('The Expanse Book 3');
    await repo.setSeries(c, 'My own name', 3);
    final guesses = detectSeries(repo.books);
    expect(guesses.map((g) => g.book.id), containsAll([a, b]));
    final picked = pickAutoSeries(guesses, alreadySet: {b});
    expect([for (final g in picked) g.book.id], [a]);
  });
}
