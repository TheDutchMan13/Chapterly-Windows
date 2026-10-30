import 'package:chapterly/data/backup.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
