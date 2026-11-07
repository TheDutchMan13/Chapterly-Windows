import 'dart:convert';

import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/cover_store.dart';
import 'package:chapterly/data/duplicates.dart';
import 'package:chapterly/data/sync_covers.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

String _picture(String seed) =>
    'data:image/jpeg;base64,${base64Encode(utf8.encode('picture $seed' * 40))}';

Book _book(String id, {String? cover, String title = 'Book'}) => Book(
      id: id,
      title: '$title $id',
      author: 'Author',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      coverUrl: cover,
    );

void main() {
  test('a picture added to a book is kept apart; the book holds a reference',
      () async {
    final store = InMemoryBookStore();
    final repository = BookRepository(store);
    await repository.load();
    final id = await repository.add(
      title: 'Dune',
      author: 'Frank Herbert',
      shelf: Shelf.forLater,
      coverUrl: _picture('a'),
    );
    final cover = repository.byId(id)!.coverUrl!;
    expect(cover, startsWith(coverRefPrefix));
    expect(await repository.readCover(hashOfCoverRef(cover)!), _picture('a'));
    // The saved book holds the reference too.
    expect((await store.loadAll()).single.coverUrl, cover);
    // A backup holds the picture.
    final withPictures = await repository.withPictures(repository.allBooks);
    expect(withPictures.single.coverUrl, _picture('a'));
  });

  test('changing a cover keeps the new picture apart, and undo puts it back',
      () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    final id = await repository.add(
      title: 'Dune',
      author: 'F',
      shelf: Shelf.forLater,
      coverUrl: _picture('a'),
    );
    final before = repository.allBooks.toList();
    await repository.setCoversFor({id: _picture('b')});
    final now = repository.byId(id)!.coverUrl!;
    expect(now, coverRef(coverHash(_picture('b'))));
    await repository.putBack(before);
    expect(repository.byId(id)!.coverUrl, coverRef(coverHash(_picture('a'))));
  });

  test('a restored library with many pictures is moved apart in one go',
      () async {
    final store = InMemoryBookStore();
    final repository = BookRepository(store);
    await repository.load();
    final books = [
      for (var i = 0; i < 30; i++) _book('b$i', cover: _picture('${i % 20}')),
    ];
    await repository.replaceAll(books);
    expect(
      repository.allBooks.every((b) => b.coverUrl!.startsWith(coverRefPrefix)),
      isTrue,
    );
    expect(await store.coverHashes(), hasLength(20));
  });

  test('pictures no book uses are removed when the library is opened',
      () async {
    final store = InMemoryBookStore();
    await store.saveAll([_book('1', cover: _picture('a'))]);
    await store.writeCover(coverHash(_picture('old')), _picture('old'));
    expect(await store.coverHashes(), hasLength(2));
    final repository = BookRepository(store);
    await repository.load();
    expect(await store.coverHashes(), {coverHash(_picture('a'))});
  });

  test('after a sync, pictures that came in are kept and lost ones dropped',
      () async {
    final store = MemoryCoverStore();
    final pool = CoverPool()..add(_picture('new'));
    final books = [
      _book('1', cover: coverRef(coverHash(_picture('new')))),
      _book('2', cover: coverRef(coverHash(_picture('gone')))),
      _book('3', cover: 'https://example.com/c.jpg'),
    ];
    final kept = await keepPoolCovers(books, pool, store);
    final out = withoutLostCovers(books, kept);
    expect(out[0].coverUrl, books[0].coverUrl);
    expect(out[1].coverUrl, isNull);
    expect(out[2].coverUrl, books[2].coverUrl);
    expect(await store.readCover(coverHash(_picture('new'))), _picture('new'));
  });

  test('possible duplicates are worked out again only after a change',
      () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(title: 'The Hobbit', author: 'J Tolkien', shelf: Shelf.forLater);
    await repository.add(title: 'The Hobit', author: 'J Tolkien', shelf: Shelf.forLater);
    final first = repository.possibleDuplicates();
    expect(first, hasLength(1));
    expect(identical(repository.possibleDuplicates(), first), isTrue);
    expect(repository.possibleDuplicates(dismissed: {first.single.key}), isEmpty);
    await repository.add(title: 'Emma', author: 'Jane Austen', shelf: Shelf.forLater);
    expect(identical(repository.possibleDuplicates(), first), isFalse);
    expect(findPossibleDuplicates(repository.books), hasLength(1));
  });
}
