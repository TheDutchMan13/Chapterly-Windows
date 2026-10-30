import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(String id, String title, {String author = 'Someone'}) => Book(
      id: id,
      title: title,
      author: author,
      shelf: Shelf.forLater,
      addedAt: DateTime.fromMillisecondsSinceEpoch(1000 * int.parse(id)),
    );

void main() {
  late InMemoryBookStore store;
  late BookRepository repo;

  setUp(() async {
    store = InMemoryBookStore();
    repo = BookRepository(store);
    await repo.load();
  });

  test('adds a book to a shelf and moves it', () async {
    await repo.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.forLater);
    expect(repo.booksOn(Shelf.forLater).single.title, 'Dune');

    final id = repo.booksOn(Shelf.forLater).single.id;
    await repo.moveTo(id, Shelf.finished);

    expect(repo.booksOn(Shelf.forLater), isEmpty);
    expect(repo.booksOn(Shelf.finished).single.title, 'Dune');
  });

  test('changes are saved and survive a reload', () async {
    await repo.add(
      title: 'Dune',
      author: 'Frank Herbert',
      shelf: Shelf.forLater,
      tags: ['sci-fi'],
      pages: 604,
    );
    final id = repo.booksOn(Shelf.forLater).single.id;
    await repo.moveTo(id, Shelf.inProgress);
    await repo.setRating(id, 4);

    final reloaded = BookRepository(store);
    await reloaded.load();

    final book = reloaded.booksOn(Shelf.inProgress).single;
    expect(book.title, 'Dune');
    expect(book.tags, ['sci-fi']);
    expect(book.pages, 604);
    expect(book.rating, 4);
    expect(book.startedAt, isNotNull);
  });

  test('removing a book deletes it from the store', () async {
    await repo.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.finished);
    await repo.deleteForever(repo.booksOn(Shelf.finished).single.id);

    final reloaded = BookRepository(store);
    await reloaded.load();
    expect(reloaded.booksOn(Shelf.finished), isEmpty);
  });

  test('filtering by tags requires every selected tag', () async {
    await repo.add(
      title: 'Dune',
      author: 'Frank Herbert',
      shelf: Shelf.finished,
      tags: ['sci-fi', 'favorite'],
    );
    await repo.add(
      title: 'Emma',
      author: 'Jane Austen',
      shelf: Shelf.finished,
      tags: ['classic'],
    );

    expect(repo.booksOn(Shelf.finished), hasLength(2));
    expect(repo.booksOn(Shelf.finished, tags: {'sci-fi'}).single.title, 'Dune');
    expect(
      repo.booksOn(Shelf.finished, tags: {'sci-fi', 'classic'}),
      isEmpty,
    );
    expect(repo.allTags, ['classic', 'favorite', 'sci-fi']);
  });

  test('setTags replaces the tags on a book', () async {
    await repo.add(
      title: 'Dune',
      author: 'Frank Herbert',
      shelf: Shelf.finished,
      tags: ['old'],
    );
    final id = repo.booksOn(Shelf.finished).single.id;
    await repo.setTags(id, ['new']);

    expect(repo.byId(id)!.tags, ['new']);
    expect(repo.allTags, ['new']);
  });

  test('a rating can be set and cleared', () async {
    await repo.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.finished);
    final id = repo.booksOn(Shelf.finished).single.id;

    await repo.setRating(id, 5);
    expect(repo.byId(id)!.rating, 5);

    await repo.setRating(id, null);
    expect(repo.byId(id)!.rating, isNull);
  });

  test('moving to In progress and Finished stamps the dates once', () async {
    await repo.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.forLater);
    final id = repo.booksOn(Shelf.forLater).single.id;

    await repo.moveTo(id, Shelf.inProgress);
    final started = repo.byId(id)!.startedAt;
    expect(started, isNotNull);
    expect(repo.byId(id)!.finishedAt, isNull);

    await repo.moveTo(id, Shelf.finished);
    expect(repo.byId(id)!.finishedAt, isNotNull);
    expect(repo.byId(id)!.startedAt, started);
  });

  test('dates can be set and cleared by hand', () async {
    await repo.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.finished);
    final id = repo.booksOn(Shelf.finished).single.id;

    await repo.setDates(
      id,
      startedAt: DateTime(2025, 1, 2),
      finishedAt: DateTime(2025, 1, 20),
    );
    expect(repo.byId(id)!.startedAt, DateTime(2025, 1, 2));
    expect(repo.byId(id)!.finishedAt, DateTime(2025, 1, 20));

    await repo.setDates(id, startedAt: null, finishedAt: DateTime(2025, 1, 20));
    expect(repo.byId(id)!.startedAt, isNull);
    expect(repo.byId(id)!.finishedAt, DateTime(2025, 1, 20));
  });

  test('pages can be set and cleared', () async {
    await repo.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.finished);
    final id = repo.booksOn(Shelf.finished).single.id;

    await repo.setPages(id, 604);
    expect(repo.byId(id)!.pages, 604);
    await repo.setPages(id, null);
    expect(repo.byId(id)!.pages, isNull);
  });

  test('importBooks skips books already in the library', () async {
    await repo.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.finished);

    final added = await repo.importBooks([
      _book('1', 'dune', author: 'FRANK HERBERT'),
      _book('2', 'Emma', author: 'Jane Austen'),
      _book('3', 'Emma', author: 'Jane Austen'),
    ]);

    expect(added, 1);
    expect(repo.books, hasLength(2));

    final reloaded = BookRepository(store);
    await reloaded.load();
    expect(reloaded.books, hasLength(2));
  });

  test('replaceAll swaps the whole library', () async {
    await repo.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.finished);

    await repo.replaceAll([_book('1', 'Emma'), _book('2', 'Persuasion')]);

    expect(repo.books.map((b) => b.title), ['Persuasion', 'Emma']);
    final reloaded = BookRepository(store);
    await reloaded.load();
    expect(reloaded.books, hasLength(2));
  });

  test('parseTags trims, drops empty entries and duplicates', () {
    expect(parseTags(' sci-fi, Favorites,, SCI-FI ,'), ['sci-fi', 'Favorites']);
    expect(parseTags(''), isEmpty);
  });

  test('a book round-trips through its database map', () {
    final book = Book(
      id: '1',
      title: 'Dune',
      author: 'Frank Herbert',
      shelf: Shelf.inProgress,
      addedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      tags: const ['a', 'b'],
      isbn: '123',
      coverUrl: 'https://example.com/c.jpg',
      firstPublishYear: 1965,
      pages: 604,
      rating: 4,
      startedAt: DateTime(2025, 1, 2),
      finishedAt: DateTime(2025, 1, 20),
    );
    final copy = Book.fromMap(book.toMap());

    expect(copy.id, '1');
    expect(copy.shelf, Shelf.inProgress);
    expect(copy.addedAt, book.addedAt);
    expect(copy.tags, ['a', 'b']);
    expect(copy.isbn, '123');
    expect(copy.coverUrl, 'https://example.com/c.jpg');
    expect(copy.firstPublishYear, 1965);
    expect(copy.pages, 604);
    expect(copy.rating, 4);
    expect(copy.startedAt, DateTime(2025, 1, 2));
    expect(copy.finishedAt, DateTime(2025, 1, 20));
  });

  test('a book round-trips through JSON', () {
    final book = Book(
      id: '1',
      title: 'Dune',
      author: 'Frank Herbert',
      shelf: Shelf.finished,
      addedAt: DateTime(2025, 3, 4, 5, 6),
      tags: const ['a'],
      rating: 5,
      finishedAt: DateTime(2025, 3, 9),
    );
    final copy = Book.fromJson(book.toJson());

    expect(copy.shelf, Shelf.finished);
    expect(copy.addedAt, book.addedAt);
    expect(copy.tags, ['a']);
    expect(copy.rating, 5);
    expect(copy.startedAt, isNull);
    expect(copy.finishedAt, DateTime(2025, 3, 9));
  });
}
