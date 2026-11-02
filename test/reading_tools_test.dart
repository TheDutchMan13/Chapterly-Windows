import 'dart:convert';
import 'dart:io';

import 'package:chapterly/audio/audio_bookmarks.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/details_refresh.dart';
import 'package:chapterly/data/notes_export.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/ebook/ebook_library.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/quote.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Book _book({String title = 'Dune', String author = 'Frank Herbert'}) => Book(
      id: 'b',
      title: title,
      author: author,
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
    );

OpenLibraryClient _client(List<Map<String, Object?>> docs) => OpenLibraryClient(
      client: MockClient(
        (request) async => http.Response(jsonEncode({'docs': docs}), 200),
      ),
    );

void main() {
  group('audiobook bookmarks', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('marks_test'));
    tearDown(() => temp.deleteSync(recursive: true));

    AudioBookmark mark(int day, int positionMs, {String note = ''}) =>
        AudioBookmark(
          track: 0,
          trackMs: positionMs,
          positionMs: positionMs,
          addedAt: DateTime(2026, 1, day),
          note: note,
        );

    Future<BookRepository> library() async {
      final repository = BookRepository(InMemoryBookStore());
      await repository.load();
      await repository.replaceAll([
        Book(
          id: 'b',
          title: 'Dune',
          author: 'Frank Herbert',
          shelf: Shelf.inProgress,
          addedAt: DateTime(2026),
        ),
      ]);
      return repository;
    }

    test('are kept with the book in order, edited and removed', () async {
      final repository = await library();
      final later = mark(1, 65000);
      final early = mark(2, 1000, note: 'Start');
      await repository.addBookmark('b', later);
      await repository.addBookmark('b', early);
      expect(
        [for (final m in repository.bookmarksFor('b')) m.positionMs],
        [1000, 65000],
      );
      await repository.setBookmarkNote('b', later, '  The twist ');
      expect(repository.bookmarksFor('b').last.note, 'The twist');
      expect(repository.bookmarksFor('b').first.note, 'Start');
      await repository.removeBookmark('b', early);
      expect(repository.bookmarksFor('b'), hasLength(1));
      expect(repository.bookmarksFor('other'), isEmpty);
      // Saved in the book's JSON (backups and sync) and read back.
      final json = repository.byId('b')!.toJson();
      expect(Book.fromJson(json).audioBookmarks.single.note, 'The twist');
    });

    test('a book without bookmarks has no bookmark field in its JSON', () {
      final book = Book(
        id: 'x',
        title: 'T',
        author: 'A',
        shelf: Shelf.forLater,
        addedAt: DateTime(2026),
      );
      expect(book.toJson().containsKey('audioBookmarks'), isFalse);
    });

    test('the old bookmark file is moved into the books once', () async {
      final repository = await library();
      await repository.addBookmark('b', mark(1, 5000, note: 'Already here'));
      final file = File('${temp.path}/audio_bookmarks.json');
      file.writeAsStringSync(jsonEncode({
        'b': [
          mark(1, 5000, note: 'Already here').toJson(),
          mark(3, 9000, note: 'Moved').toJson(),
        ],
        'gone': [mark(4, 1).toJson()],
      }));
      expect(await moveOldBookmarks(file, repository), 1);
      expect(
        [for (final m in repository.bookmarksFor('b')) m.note],
        ['Already here', 'Moved'],
      );
      expect(file.existsSync(), isFalse);
      expect(File('${temp.path}/audio_bookmarks.moved.json').existsSync(),
          isTrue);
      // A second start finds nothing to move.
      expect(await moveOldBookmarks(file, repository), 0);
    });
  });

  group('notes export', () {
    final data = BookNotesExport(
      title: 'Dune',
      author: 'Frank Herbert',
      notes: 'Loved it.',
      quotes: [Quote(text: 'Fear is the mind-killer.', page: 8, addedAt: DateTime(2026))],
      highlights: [
        EbookHighlight(
          locator: 'x',
          text: 'Line one\nLine two',
          addedAt: DateTime(2026),
          note: 'Good',
        ),
      ],
      marks: const [ExportedMark(place: '1:02:15 · Chapter 4', note: 'Twist')],
    );

    test('Markdown has every part', () {
      final md = notesMarkdown(data);
      expect(md, startsWith('# Dune\n*Frank Herbert*'));
      expect(md, contains('## Notes\n\nLoved it.'));
      expect(md, contains('> Fear is the mind-killer.\n— page 8'));
      expect(md, contains('> Line one\n> Line two\n\nGood'));
      expect(md, contains('- **1:02:15 · Chapter 4**: Twist'));
      expect(data.fileStem, 'Dune - notes');
      expect(data.isEmpty, isFalse);
      expect(
        const BookNotesExport(title: 'X', author: '').isEmpty,
        isTrue,
      );
    });

    test('PDF is made', () async {
      final bytes = await notesPdf(data);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  group('refresh details', () {
    test('only a clear match is used', () {
      final book = _book();
      OpenLibraryBook result(String title, String author) =>
          OpenLibraryBook.fromJson({'title': title, 'author_name': [author]});
      expect(
        bestOpenLibraryMatch(book, [
          result('Dune Messiah', 'Frank Herbert'),
          result('Dune', 'Someone Else'),
          result('Dune', 'Frank Herbert'),
        ])?.author,
        'Frank Herbert',
      );
      expect(bestOpenLibraryMatch(book, [result('Emma', 'Jane Austen')]),
          isNull);
    });

    test('fills blanks and keeps what the book has', () async {
      final repository = BookRepository(InMemoryBookStore());
      await repository.load();
      await repository.add(
        title: 'Dune',
        author: 'Frank Herbert',
        shelf: Shelf.forLater,
        pages: 500,
      );
      final book = repository.allBooks.first;
      final client = _client([
        {
          'key': '/works/OL1W',
          'title': 'Dune',
          'author_name': ['Frank Herbert'],
          'first_publish_year': 1965,
          'isbn': ['9780441172719'],
          'cover_i': 123,
          'number_of_pages_median': 412,
        },
      ]);
      expect(
        await refreshBookDetails(repository, client, book),
        RefreshOutcome.updated,
      );
      final after = repository.byId(book.id)!;
      expect(after.firstPublishYear, 1965);
      expect(after.isbn, '9780441172719');
      expect(after.coverUrl, isNotNull);
      expect(after.pages, 500, reason: 'pages it had are kept');
      expect(
        await refreshBookDetails(repository, client, after),
        RefreshOutcome.unchanged,
      );
      expect(
        await refreshBookDetails(repository, _client([]), _book(title: 'X')),
        RefreshOutcome.notFound,
      );
    });

    test('says so when Open Library cannot be reached', () async {
      final repository = BookRepository(InMemoryBookStore());
      final client = OpenLibraryClient(
        client: MockClient((request) async => throw const SocketException('x')),
      );
      expect(
        await refreshBookDetails(repository, client, _book()),
        RefreshOutcome.failed,
      );
    });
  });
}
