import 'package:chapterly/data/auto_tag.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(String id, String title, String author, [List<String> tags = const []]) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      tags: tags,
    );

SubjectLookup _subjects(Map<String, List<String>> byTitle) =>
    (book) async => byTitle[book.title] ?? const [];

void main() {
  group('planBookTags', () {
    test('a sure Open Library match is ticked', () async {
      final library = [
        _book('1', 'Dune', 'Frank Herbert', ['Space opera']),
        _book('2', 'Hyperion', 'Dan Simmons'),
      ];
      final plan = await planBookTags(
        library[1],
        library,
        subjects: _subjects({'Hyperion': ['Space opera']}),
      );
      expect(plan.checkedTags, ['Space opera']);
    });

    test('an unsure match is offered but not ticked', () async {
      final library = [
        _book('1', 'Dune', 'Frank Herbert', ['Sci-Fi']),
        _book('2', 'Firefly Tales', 'Someone'),
      ];
      final plan = await planBookTags(
        library[1],
        library,
        subjects: _subjects({'Firefly Tales': ['Space westerns']}),
      );
      expect(plan.checkedTags, isEmpty);
      expect(plan.proposals.single.tag, 'Space westerns');
      expect(plan.proposals.single.isNew, isTrue);
    });

    test('a book Open Library does not know gets nothing, with the reason',
        () async {
      final library = [_book('1', 'My Diary', 'Me')];
      final plan = await planBookTags(
        library[0],
        library,
        subjects: _subjects({}),
      );
      expect(plan.proposals, isEmpty);
      expect(plan.note, 'Open Library has nothing on this book');
    });
  });

  test('planTags stops when asked and says how far it got', () async {
    final library = [
      _book('1', 'A', 'X'),
      _book('2', 'B', 'Y'),
      _book('3', 'C', 'Z'),
    ];
    final seen = <int>[];
    var stop = false;
    final plans = await planTags(
      library,
      library,
      subjects: (book) async {
        if (book.title == 'B') stop = true;
        return const [];
      },
      stopped: () => stop,
      onProgress: (done, total, book) => seen.add(done),
    );
    expect(plans.map((p) => p.book.title), ['A', 'B']);
    expect(seen.last, 2);
  });

  test('tagNames lists your tags, the most used first', () {
    final names = tagNames([
      _book('1', 'A', 'X', ['Fantasy', 'Classics']),
      _book('2', 'B', 'X', ['fantasy']),
    ]);
    expect(names, ['Fantasy', 'Classics']);
  });

  group('runTagTest', () {
    final library = [
      _book('1', 'Dune', 'Frank Herbert', ['Space opera']),
      _book('2', 'Emma', 'Jane Austen', ['Romance']),
      _book('3', 'Other', 'Zed', ['Space opera', 'Romance']),
    ];
    final subjects = _subjects({
      'Dune': ['Space opera'],
      'Other': ['Romance'],
    });

    test('scores Open Library against your own tags', () async {
      final report = await runTagTest(library, subjects: subjects);
      final score = report.openLibrary;
      expect(score.books, 3);
      expect(score.yourTags, 4);
      expect(score.found, 2);
      expect(score.suggested, 2);
      expect(score.right, 2);
      expect(score.booksHit, 2);
      expect(score.booksEmpty, 1);
    });

    test('picks a spread of at most the asked number of books', () {
      final many = [
        for (var i = 0; i < 300; i++) _book('$i', 'Book $i', 'A', ['T']),
        _book('x', 'Untagged', 'A'),
      ];
      final picked = pickTestBooks(many);
      expect(picked, hasLength(150));
      expect(picked.every((b) => b.tags.isNotEmpty), isTrue);
    });
  });

  test('addTagsToBooks adds each book its own tags, without repeats',
      () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.replaceAll([
      _book('1', 'A', 'X', ['Fantasy']),
      _book('2', 'B', 'Y'),
    ]);
    await repository.addTagsToBooks({
      '1': ['fantasy', 'Dragons'],
      '2': ['Classics', ' '],
    });
    expect(repository.byId('1')!.tags, ['Fantasy', 'Dragons']);
    expect(repository.byId('2')!.tags, ['Classics']);
  });
}
