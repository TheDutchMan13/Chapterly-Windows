import '../models/book.dart';
import 'cover_store.dart';

/// Where books are saved. The app uses SQLite; tests use the in-memory one.
/// Cover pictures are kept apart from the books (see cover_store.dart): a
/// book saved with a picture inside it is saved with a reference instead.
abstract interface class BookStore implements CoverStore {
  Future<List<Book>> loadAll();
  Future<void> save(Book book);
  Future<void> saveAll(List<Book> books);
  Future<void> replaceAll(List<Book> books);
  Future<void> remove(String id);

  /// Books removed for good, with the time they were removed. Kept so that a
  /// sync does not bring them back from another device.
  Future<Map<String, DateTime>> loadTombstones();
  Future<void> saveTombstones(Map<String, DateTime> tombstones);
}

class InMemoryBookStore extends MemoryCoverStore implements BookStore {
  final Map<String, Book> _books = {};
  Map<String, DateTime> _tombstones = {};

  @override
  Future<Map<String, DateTime>> loadTombstones() async => {..._tombstones};

  @override
  Future<void> saveTombstones(Map<String, DateTime> tombstones) async {
    _tombstones = {...tombstones};
  }

  @override
  Future<List<Book>> loadAll() async => _books.values.toList();

  @override
  Future<void> save(Book book) async {
    final kept = await keepCoverApart(book, this);
    _books[kept.id] = kept;
  }

  @override
  Future<void> saveAll(List<Book> books) async {
    for (final book in await keepCoversApart(books, this)) {
      _books[book.id] = book;
    }
  }

  @override
  Future<void> replaceAll(List<Book> books) async {
    final kept = await keepCoversApart(books, this);
    _books.clear();
    for (final book in kept) {
      _books[book.id] = book;
    }
  }

  @override
  Future<void> remove(String id) async {
    _books.remove(id);
  }
}
