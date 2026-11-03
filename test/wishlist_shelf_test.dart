import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final wanted = Book(
    id: 'w',
    title: 'Wanted',
    author: 'Someone',
    shelf: Shelf.wishlist,
    addedAt: DateTime(2026, 11, 3),
  );

  test('a Wishlist book is saved and read back on Wishlist', () {
    expect(Book.fromMap(wanted.toMap()).shelf, Shelf.wishlist);
    expect(Book.fromJson(wanted.toJson()).shelf, Shelf.wishlist);
  });

  test('a Wishlist book keeps its shelf through a sync message', () {
    final payload = decodeSyncPayload(encodeSyncPayload([wanted], const {}));
    expect(payload.books.single.shelf, Shelf.wishlist);
  });

  test('moving a book to Wishlist sets no dates and leaves Next up', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    final id = await repository.add(
      title: 'Later',
      author: 'Someone',
      shelf: Shelf.forLater,
    );
    await repository.moveToTopOfQueue(id);
    expect(repository.byId(id)!.queuePosition, isNotNull);

    await repository.moveTo(id, Shelf.wishlist);

    final book = repository.byId(id)!;
    expect(book.shelf, Shelf.wishlist);
    expect(book.startedAt, isNull);
    expect(book.finishedAt, isNull);
    expect(book.queuePosition, isNull);
    expect(repository.booksOn(Shelf.wishlist).map((b) => b.id), [id]);
  });
}
