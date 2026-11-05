import 'package:chapterly/audio/audio_library.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/match_review.dart';
import 'package:chapterly/data/statistics.dart';
import 'package:chapterly/models/audio_progress.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_origin.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/review_matches_screen.dart';
import 'package:chapterly/server/new_server_books.dart';
import 'package:chapterly/server/server_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The same tests are in the Android app.

Book _book(String title, String author, {String? file}) {
  final book = Book(
    id: title,
    title: title,
    author: author,
    shelf: Shelf.forLater,
    addedAt: DateTime(2026),
  );
  return book.copyWith(origin: () => BookOrigin.of(book, name: file));
}

ServerBook _server(String id, DateTime? added) => ServerBook(
      id: id,
      title: 'Book $id',
      author: 'Someone',
      kind: 'ebook',
      format: 'epub',
      size: 1,
      addedAt: added,
    );

void main() {
  group('Review matches', () {
    test('a right match is alike, even with a subtitle and no author', () {
      final wager = _book('The Wager: A Tale of Shipwreck, Mutiny and Murder',
          'David Grann', file: 'the-wager-grann.epub');
      expect(matchSimilarity(wager), 1.0);
      final atlas =
          _book('Atlas Shrugged', 'Ayn Rand', file: 'Atlas Shrugged (1957).epub');
      expect(matchSimilarity(atlas), 1.0);
    });

    test('a wrong author or a different book is doubtful', () {
      final dune = _book('Dune', 'Brian Herbert', file: 'Dune - Frank Herbert.m4b');
      final atlas = _book('Atlas', 'Jenny Weaver', file: 'Atlas Shrugged.epub');
      final other = _book('Cooking at Home', 'Ann Lee', file: 'Sapiens.epub');
      expect(matchSimilarity(dune), lessThan(doubtfulBelow));
      expect(matchSimilarity(atlas), lessThan(doubtfulBelow));
      final found = doubtfulMatches([dune, atlas, other]);
      expect(found.first.book.title, 'Cooking at Home');
      expect(found.first.percent, '0%');
      expect(found, hasLength(3));
    });

    test('one typo in a long word still matches', () {
      final book = _book('Shipwreck', 'Ann Lee', file: 'Shipwrek - Ann Lee.epub');
      expect(matchSimilarity(book), 1.0);
    });

    test('books without a file name, corrected or confirmed are left out',
        () async {
      final repo = BookRepository(InMemoryBookStore());
      await repo.load();
      final id = await repo.add(
        title: 'Cooking at Home',
        author: 'Ann Lee',
        shelf: Shelf.forLater,
        originName: 'Sapiens.epub',
      );
      await repo.add(title: 'No file', author: 'X', shelf: Shelf.forLater);
      expect(doubtfulMatches(repo.books), hasLength(1));
      await repo.confirmMatch(id);
      expect(doubtfulMatches(repo.books), isEmpty);
      expect(fineMatchCount(repo.books), 1);
      final origin = repo.byId(id)!.origin!;
      expect(origin.matchConfirmed, isTrue);
      final back = BookOrigin.fromJson(origin.toJson())!;
      expect(back.matchConfirmed, isTrue);
      expect(back.withEditedAt(DateTime(2026)).matchConfirmed, isTrue);
    });

    testWidgets('the screen lists a doubtful book and "It\'s right" hides it',
        (tester) async {
      final repo = BookRepository(InMemoryBookStore());
      await repo.load();
      await repo.add(
        title: 'Cooking at Home',
        author: 'Ann Lee',
        shelf: Shelf.forLater,
        originName: 'Sapiens.epub',
      );
      await tester.pumpWidget(
          MaterialApp(home: ReviewMatchesScreen(repository: repo)));
      expect(find.text('Sapiens.epub'), findsOneWidget);
      expect(find.text('0% alike'), findsOneWidget);
      await tester.tap(find.text("It's right"));
      await tester.pumpAndSettle();
      expect(find.text('Sapiens.epub'), findsNothing);
    });
  });

  group('New on your book server', () {
    test('the first look sees everything; later only newer books', () {
      final recent = [
        _server('3', DateTime.utc(2026, 11, 5)),
        _server('2', DateTime.utc(2026, 11, 4)),
        _server('1', DateTime.utc(2026, 11, 1)),
      ];
      final first = pickNewServerBooks(recent, seenAt: null, isLinked: (_) => false);
      expect(first.books, isEmpty);
      expect(first.newest, DateTime.utc(2026, 11, 5));
      final later = pickNewServerBooks(
        recent,
        seenAt: DateTime.utc(2026, 11, 2),
        isLinked: (id) => id == '2',
      );
      expect([for (final b in later.books) b.id], ['3']);
    });

    test('the server sends when a book was added', () {
      final book = ServerBook.fromJson({
        'id': 'a',
        'title': 'T',
        'kind': 'ebook',
        'format': 'epub',
        'addedAt': '2026-11-05T10:00:00+00:00',
      })!;
      expect(book.addedAt, DateTime.utc(2026, 11, 5, 10));
    });
  });

  test('each audiobook keeps its own speed', () async {
    final library = AudioLibrary();
    await library.setSpeed(1.5, bookId: 'a');
    expect(library.speedFor('a'), 1.5);
    await library.setSpeed(1.2, bookId: 'b');
    expect(library.speedFor('a'), 1.5);
    expect(library.speedFor('b'), 1.2);
    // A book without its own speed plays at the last one chosen.
    expect(library.speedFor('c'), 1.2);
  });

  test('hours listened adds up finished audiobooks', () {
    final book = Book(
      id: 'a',
      title: 'Listened',
      author: 'X',
      shelf: Shelf.finished,
      addedAt: DateTime(2026),
      finishedAt: DateTime(2026, 3, 1),
      audio: const AudioProgress(positionMs: 0, lengthMs: 3 * 3600000),
    );
    expect(computeStats([book], year: 2026).listenedMs, 3 * 3600000);
    expect(computeStats([book], year: 2025).listenedMs, 0);
  });

  test('an import preview counts only the new books', () async {
    final repo = BookRepository(InMemoryBookStore());
    await repo.load();
    await repo.add(title: 'Dune', author: 'Frank Herbert', shelf: Shelf.finished);
    final incoming = [
      Book(id: 'x', title: 'Dune', author: 'Frank Herbert', shelf: Shelf.finished, addedAt: DateTime(2026)),
      Book(id: 'y', title: 'Emma', author: 'Jane Austen', shelf: Shelf.forLater, addedAt: DateTime(2026)),
      Book(id: 'z', title: 'Emma', author: 'Jane Austen', shelf: Shelf.forLater, addedAt: DateTime(2026)),
    ];
    expect(repo.newBookCount(incoming), 1);
    expect(await repo.importBooks(incoming), 1);
  });
}
