import 'package:chapterly/data/backup.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/csv.dart';
import 'package:chapterly/data/statistics.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_format.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryBookStore store;
  late BookRepository repo;

  Future<String> addBook(
    String title, {
    Shelf shelf = Shelf.forLater,
    List<String> tags = const [],
    BookFormat? format,
  }) async {
    await repo.add(
      title: title,
      author: 'Author of $title',
      shelf: shelf,
      tags: tags,
      format: format,
    );
    return repo.books.firstWhere((b) => b.title == title).id;
  }

  setUp(() async {
    store = InMemoryBookStore();
    repo = BookRepository(store);
    await repo.load();
  });

  test('search finds title, author, ISBN and tags', () async {
    await addBook('Dune', tags: ['sci-fi']);
    await addBook('Emma');
    expect(repo.booksOn(Shelf.forLater, query: 'dun').single.title, 'Dune');
    expect(repo.booksOn(Shelf.forLater, query: 'author of emma'), hasLength(1));
    expect(repo.booksOn(Shelf.forLater, query: 'SCI').single.title, 'Dune');
    expect(repo.booksOn(Shelf.forLater, query: 'zzz'), isEmpty);
  });

  test('favorite and format filters', () async {
    final dune = await addBook('Dune', format: BookFormat.ebook);
    await addBook('Emma', format: BookFormat.paperback);
    await repo.setFavorite(dune, favorite: true);
    expect(repo.booksOn(Shelf.forLater, favoritesOnly: true).single.title,
        'Dune');
    expect(
      repo.booksOn(Shelf.forLater, formats: {BookFormat.paperback}).single.title,
      'Emma',
    );
  });

  test('trash hides books, restore brings them back', () async {
    final id = await addBook('Dune');
    await repo.moveToTrash(id);
    expect(repo.books, isEmpty);
    expect(repo.trash.single.title, 'Dune');
    expect(repo.allTags, isEmpty);

    await repo.restore(id);
    expect(repo.books.single.title, 'Dune');
    expect(repo.trash, isEmpty);
  });

  test('trash survives a reload and can be emptied', () async {
    final id = await addBook('Dune');
    await repo.moveToTrash(id);
    final reloaded = BookRepository(store);
    await reloaded.load();
    expect(reloaded.trash, hasLength(1));
    await reloaded.emptyTrash();
    expect(reloaded.trash, isEmpty);
    expect((await store.loadAll()), isEmpty);
  });

  test('bulk move, tag and trash', () async {
    final a = await addBook('A');
    final b = await addBook('B', tags: ['x']);
    await repo.moveAllTo({a, b}, Shelf.inProgress);
    expect(repo.booksOn(Shelf.inProgress), hasLength(2));
    expect(repo.byId(a)!.startedAt, isNotNull);

    await repo.addTagToAll({a, b}, 'X');
    expect(repo.byId(a)!.tags, ['X']);
    expect(repo.byId(b)!.tags, ['x']);

    await repo.trashAll({a, b});
    expect(repo.books, isEmpty);
  });

  test('notes are trimmed and can be cleared', () async {
    final id = await addBook('Dune');
    await repo.setNotes(id, '  Loved it  ');
    expect(repo.byId(id)!.notes, 'Loved it');
    await repo.setNotes(id, '   ');
    expect(repo.byId(id)!.notes, isNull);
  });

  test('reading log keeps entries in date order', () async {
    final id = await addBook('Dune');
    await repo.addLogEntry(id, DateTime(2026, 2, 2), 30);
    await repo.addLogEntry(id, DateTime(2026, 2, 1), 20);
    expect(repo.byId(id)!.readingLog.map((e) => e.pages), [20, 30]);
    await repo.removeLogEntry(id, 0);
    expect(repo.byId(id)!.readingLog.single.pages, 30);
  });

  test('read again saves the old reading and starts a new one', () async {
    final id = await addBook('Dune', shelf: Shelf.finished);
    await repo.setRating(id, 4);
    await repo.setDates(
      id,
      startedAt: DateTime(2025, 1, 1),
      finishedAt: DateTime(2025, 1, 10),
    );
    await repo.readAgain(id);

    final book = repo.byId(id)!;
    expect(book.shelf, Shelf.inProgress);
    expect(book.rating, isNull);
    expect(book.finishedAt, isNull);
    expect(book.previousReadings.single.rating, 4);
    expect(book.previousReadings.single.finishedAt, DateTime(2025, 1, 10));
  });

  test('re-reads count in the statistics', () async {
    final id = await addBook('Dune', shelf: Shelf.finished);
    await repo.setPages(id, 400);
    await repo.setDates(
      id,
      startedAt: null,
      finishedAt: DateTime(2025, 5, 1),
    );
    await repo.readAgain(id);
    await repo.moveTo(id, Shelf.finished);
    await repo.setDates(id, startedAt: null, finishedAt: DateTime(2026, 5, 1));

    final all = computeStats(repo.books);
    expect(all.finishedCount, 2);
    expect(all.pagesRead, 800);
    expect(computeStats(repo.books, year: 2025).finishedCount, 1);
  });

  test('logged pages are summed per year', () async {
    final id = await addBook('Dune');
    await repo.addLogEntry(id, DateTime(2025, 3, 1), 10);
    await repo.addLogEntry(id, DateTime(2026, 3, 1), 25);
    expect(computeStats(repo.books).loggedPages, 35);
    final year = computeStats(repo.books, year: 2026);
    expect(year.loggedPages, 25);
    expect(year.loggedByMonth[2], 25);
  });

  test('everything round-trips through a backup', () async {
    final id = await addBook('Dune', format: BookFormat.audiobook);
    await repo.setFavorite(id, favorite: true);
    await repo.setNotes(id, 'Great');
    await repo.addLogEntry(id, DateTime(2026, 1, 1), 12);
    await repo.moveTo(id, Shelf.finished);
    await repo.readAgain(id);
    await repo.moveToTrash(id);

    final restored = decodeBackup(encodeBackup(repo.allBooks)).single;
    expect(restored.format, BookFormat.audiobook);
    expect(restored.favorite, isTrue);
    expect(restored.notes, 'Great');
    expect(restored.deletedAt, isNotNull);
    expect(restored.previousReadings.single.log.single.pages, 12);
  });

  test('map round trip keeps new fields', () {
    final book = Book(
      id: '1',
      title: 'T',
      author: 'A',
      shelf: Shelf.finished,
      addedAt: DateTime(2026),
      format: BookFormat.hardcover,
      favorite: true,
      notes: 'n',
      deletedAt: DateTime(2026, 2),
    );
    final copy = Book.fromMap(book.toMap());
    expect(copy.format, BookFormat.hardcover);
    expect(copy.favorite, isTrue);
    expect(copy.deletedAt, DateTime(2026, 2));
  });

  test('formats are understood from other apps', () {
    expect(parseBookFormat('Kindle Edition'), BookFormat.ebook);
    expect(parseBookFormat('Mass Market Paperback'), BookFormat.paperback);
    expect(parseBookFormat('Audible Audio'), BookFormat.audiobook);
    expect(parseBookFormat('Hardcover'), BookFormat.hardcover);
    expect(parseBookFormat('Spiral'), isNull);
  });

  test('csv keeps format, favorite and notes', () {
    final book = Book(
      id: '1',
      title: 'Dune',
      author: 'Frank',
      shelf: Shelf.finished,
      addedAt: DateTime(2026),
      format: BookFormat.ebook,
      favorite: true,
      notes: 'Spice, sand',
    );
    final copy = importBooksFromCsv(encodeBooksCsv([book])).books.single;
    expect(copy.format, BookFormat.ebook);
    expect(copy.favorite, isTrue);
    expect(copy.notes, 'Spice, sand');
  });
}
