import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late BookRepository repo;

  Future<String> addBook(String title) async {
    await repo.add(title: title, author: 'Someone', shelf: Shelf.forLater);
    return repo.books.firstWhere((b) => b.title == title).id;
  }

  List<String> shelvesOf(String id) => repo.byId(id)!.collections;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = BookRepository(InMemoryBookStore());
    await repo.load();
  });

  test('moving books from one of your shelves to another', () async {
    final a = await addBook('A');
    final b = await addBook('B');
    final c = await addBook('C');
    await repo.addToCollectionAll({a, b, c}, 'Beach');
    await repo.addToCollectionAll({b}, 'Gifts');

    await repo.moveBetweenCollections({a, b}, from: 'Beach', to: 'Summer');

    expect(shelvesOf(a), ['Summer']);
    // B was also on Gifts: it keeps that, and is not put on Summer twice.
    expect(shelvesOf(b), ['Gifts', 'Summer']);
    expect(shelvesOf(c), ['Beach']);
    expect(repo.booksInCollection('Beach').map((x) => x.title), ['C']);
  });

  test('moving is not case sensitive and never repeats a shelf', () async {
    final a = await addBook('A');
    await repo.addToCollectionAll({a}, 'Beach');
    await repo.addToCollectionAll({a}, 'Summer');

    await repo.moveBetweenCollections({a}, from: 'beach', to: 'summer');

    expect(shelvesOf(a), ['Summer']);
  });

  test('a book that is not on the old shelf is put on the new one', () async {
    final a = await addBook('A');
    await repo.moveBetweenCollections({a}, from: 'Beach', to: 'Summer');
    expect(shelvesOf(a), ['Summer']);
  });

  test('moving to the same shelf changes nothing', () async {
    final a = await addBook('A');
    await repo.addToCollectionAll({a}, 'Beach');
    final stamp = repo.byId(a)!.updatedAt;
    await repo.moveBetweenCollections({a}, from: 'Beach', to: 'BEACH');
    expect(shelvesOf(a), ['Beach']);
    expect(repo.byId(a)!.updatedAt, stamp);
  });

  test('removing books from a shelf keeps the books', () async {
    final a = await addBook('A');
    final b = await addBook('B');
    await repo.addToCollectionAll({a, b}, 'Beach');
    await repo.addToCollectionAll({a}, 'Gifts');

    await repo.removeFromCollectionAll({a}, 'Beach');

    expect(shelvesOf(a), ['Gifts']);
    expect(shelvesOf(b), ['Beach']);
    expect(repo.books.map((x) => x.title), containsAll(['A', 'B']));
  });

  test('removing from a shelf only touches books on it', () async {
    final a = await addBook('A');
    final b = await addBook('B');
    await repo.addToCollectionAll({b}, 'Beach');
    final stamp = repo.byId(a)!.updatedAt;

    await repo.removeFromCollectionAll({a, b}, 'Beach');

    expect(shelvesOf(b), isEmpty);
    expect(repo.byId(a)!.updatedAt, stamp);
  });

  test('undo puts the shelves back', () async {
    final a = await addBook('A');
    await repo.addToCollectionAll({a}, 'Beach');
    final before = [repo.byId(a)!];

    await repo.moveBetweenCollections({a}, from: 'Beach', to: 'Summer');
    await repo.putBack(before);

    expect(shelvesOf(a), ['Beach']);
  });
}
