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

    test('are kept in order, edited, removed and saved', () async {
      final file = File('${temp.path}/marks.json');
      final store = AudioBookmarks(file: file);
      final later = AudioBookmark(
        track: 1,
        trackMs: 5000,
        positionMs: 65000,
        addedAt: DateTime(2026, 1, 1),
      );
      final early = AudioBookmark(
        track: 0,
        trackMs: 1000,
        positionMs: 1000,
        addedAt: DateTime(2026, 1, 2),
        note: 'Start',
      );
      await store.add('b', later);
      await store.add('b', early);
      expect([for (final m in store.forBook('b')) m.positionMs], [1000, 65000]);
      await store.setNote('b', later, '  The twist ');
      final loaded = await AudioBookmarks.load(file);
      expect(loaded.forBook('b').last.note, 'The twist');
      expect(loaded.forBook('b').first.note, 'Start');
      await loaded.remove('b', early);
      expect(loaded.forBook('b'), hasLength(1));
      expect(loaded.forBook('other'), isEmpty);
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
