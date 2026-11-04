import 'package:chapterly/data/backup.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

class _BrokenStore extends InMemoryBookStore {
  bool broken = false;

  @override
  Future<void> replaceAll(List<Book> books) async {
    if (broken) throw StateError('disk full');
    await super.replaceAll(books);
  }
}

Book _copy(String id, String title, DateTime updated) => Book(
      id: id,
      title: title,
      author: 'A',
      shelf: Shelf.forLater,
      addedAt: DateTime(2025),
      updatedAt: updated,
    );

void main() {
  test('a backup with the same book twice keeps the newest copy', () {
    final text = encodeBackup([
      _copy('1', 'Old', DateTime(2025, 1)),
      _copy('2', 'Other', DateTime(2025, 1)),
      _copy('1', 'New', DateTime(2025, 3)),
      _copy('1', 'Middle', DateTime(2025, 2)),
    ]);
    final books = decodeBackup(text);
    expect([for (final b in books) b.id], ['1', '2']);
    expect(books.first.title, 'New');
  });

  test('replacing the library keeps it as it was when saving fails',
      () async {
    final store = _BrokenStore();
    final repo = BookRepository(store);
    await repo.load();
    await repo.replaceAll([_copy('a', 'Kept', DateTime(2025))]);
    store.broken = true;
    await expectLater(
      repo.replaceAll([_copy('b', 'New', DateTime(2025))]),
      throwsStateError,
    );
    expect([for (final b in repo.allBooks) b.id], ['a']);
    store.broken = false;
    await repo.replaceAll([
      _copy('c', 'One', DateTime(2025)),
      _copy('c', 'Two', DateTime(2026)),
    ]);
    expect([for (final b in repo.allBooks) b.title], ['Two']);
  });

  test('a backup restores the same books', () {
    final books = [
      Book(
        id: '1',
        title: 'Dune',
        author: 'Frank Herbert',
        shelf: Shelf.finished,
        addedAt: DateTime(2025, 1, 2),
        tags: const ['sci-fi'],
        rating: 5,
        pages: 604,
        finishedAt: DateTime(2025, 2, 3),
      ),
      Book(
        id: '2',
        title: 'Emma',
        author: '',
        shelf: Shelf.forLater,
        addedAt: DateTime(2025, 1, 3),
      ),
    ];

    final restored = decodeBackup(encodeBackup(books));

    expect(restored, hasLength(2));
    expect(restored[0].title, 'Dune');
    expect(restored[0].tags, ['sci-fi']);
    expect(restored[0].rating, 5);
    expect(restored[0].pages, 604);
    expect(restored[0].finishedAt, DateTime(2025, 2, 3));
    expect(restored[1].shelf, Shelf.forLater);
    expect(restored[1].author, '');
  });

  test('files that are not Chapterly backups are rejected', () {
    expect(() => decodeBackup('not json'), throwsA(isA<FormatException>()));
    expect(() => decodeBackup('[]'), throwsA(isA<FormatException>()));
    expect(
      () => decodeBackup('{"app": "other", "books": []}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodeBackup('{"app": "chapterly", "books": [1]}'),
      throwsA(isA<FormatException>()),
    );
  });
}
