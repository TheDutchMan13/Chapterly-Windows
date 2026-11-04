import 'dart:io';

import 'package:chapterly/audio/audio_files.dart';
import 'package:chapterly/audio/audio_library.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/library_scan.dart';
import 'package:chapterly/ebook/ebook_files.dart';
import 'package:chapterly/ebook/ebook_library.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Copies by writing a few bytes to the target.
class _Copier implements EbookFiles {
  @override
  Future<PickedFile?> pickBook() async => null;

  @override
  Future<int> copy(PickedFile picked, String path) async {
    await File(path).writeAsString('book');
    return 4;
  }

  @override
  Future<void> release(PickedFile picked) async {}
}

/// No audio is used in these tests.
class _NoAudio implements AudioFiles {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ScanDecision _file(
  String name, {
  String title = '',
  String author = '',
  ScanKind kind = ScanKind.book,
}) {
  final item = ScanItem(
    kind: kind,
    key: '$kind|$name',
    name: name,
    files: [PickedFile(location: '/library/$name', name: name)],
  )
    ..title = title
    ..author = author;
  return ScanDecision(item, ScanOutcome.review);
}

void main() {
  late BookRepository repository;
  late LibraryScanner scanner;
  late EbookLibrary ebooks;
  late Directory folder;

  setUp(() async {
    folder = Directory.systemTemp.createTempSync('add_all_files');
    addTearDown(() => folder.deleteSync(recursive: true));
    repository = BookRepository(InMemoryBookStore());
    await repository.load();
    ebooks = EbookLibrary();
    scanner = LibraryScanner(
      repository: repository,
      ebookLibrary: ebooks,
      ebookFiles: _Copier(),
      booksDir: folder,
      audioFiles: _NoAudio(),
      audioLibrary: AudioLibrary(),
      memory: ScanMemory(),
    );
  });

  test('every file becomes a new book on the chosen shelf', () async {
    final result = await scanner.addAllAsNewBooks(
      [
        _file('Dune.epub', title: 'Dune', author: 'Frank Herbert'),
        _file('Emma.epub', title: 'Emma', author: 'Jane Austen'),
      ],
      shelf: Shelf.forLater,
    );

    expect(result.added, 2);
    expect(result.left, 0);
    final books = repository.books;
    expect(books.map((b) => b.title), unorderedEquals(['Dune', 'Emma']));
    expect(books.every((b) => b.shelf == Shelf.forLater), isTrue);
    expect(books.every((b) => ebooks.linkFor(b.id) != null), isTrue);
  });

  test('a file with no title inside is named from its file name', () async {
    await scanner.addAllAsNewBooks(
      [_file('Dune Messiah - Frank Herbert.epub')],
      shelf: Shelf.finished,
    );

    final book = repository.books.single;
    expect(book.title, 'Dune Messiah');
    expect(book.author, 'Frank Herbert');
    expect(book.shelf, Shelf.finished);
  });

  test('a second ebook of the same book stays in the list', () async {
    final result = await scanner.addAllAsNewBooks(
      [
        _file('Dune.epub', title: 'Dune', author: 'Frank Herbert'),
        // Same title and author in a different format: it would replace the
        // first file, so it is left for you to look at.
        _file('Dune.pdf', title: 'dune', author: 'FRANK HERBERT'),
      ],
      shelf: Shelf.forLater,
    );

    expect(result.added, 1);
    expect(result.left, 1);
    expect(repository.books, hasLength(1));
    expect(result.summary, contains('1 still needs a look'));
  });

  test('a file with nothing to name it by stays in the list', () async {
    final result = await scanner.addAllAsNewBooks(
      [_file('')],
      shelf: Shelf.forLater,
    );

    expect(result.added, 0);
    expect(result.left, 1);
    expect(repository.books, isEmpty);
  });

  test('it tells how far it has got', () async {
    final seen = <String>[];
    await scanner.addAllAsNewBooks(
      [
        _file('A.epub', title: 'A', author: 'X'),
        _file('B.epub', title: 'B', author: 'X'),
      ],
      shelf: Shelf.forLater,
      onProgress: (done, total) => seen.add('$done/$total'),
    );
    expect(seen, ['1/2', '2/2']);
  });

  test('the summary reads naturally', () {
    expect(
      const AddAllResult(added: 1, joined: 0, left: 0).summary,
      'Added 1 book.',
    );
    expect(
      const AddAllResult(added: 12, joined: 2, left: 3).summary,
      'Added 12 books. 2 files went to a book just added. '
      '3 still need a look.',
    );
  });
}
