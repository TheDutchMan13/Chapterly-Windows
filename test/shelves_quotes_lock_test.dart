import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/collections.dart';
import 'package:chapterly/data/duplicates.dart';
import 'package:chapterly/data/pin_lock.dart';
import 'package:chapterly/data/statistics.dart';
import 'package:chapterly/data/year_review.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late BookRepository repo;

  Future<String> addBook(
    String title, {
    String author = 'Someone',
    String? isbn,
  }) async {
    await repo.add(
      title: title,
      author: author,
      shelf: Shelf.forLater,
      isbn: isbn,
    );
    return repo.books.firstWhere((b) => b.title == title).id;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = BookRepository(InMemoryBookStore());
    await repo.load();
  });

  test('shelves of your own: add, list, rename and delete', () async {
    final a = await addBook('A');
    final b = await addBook('B');
    await repo.addToCollectionAll({a, b}, 'Beach');
    await repo.setCollections(b, ['Beach', 'Gifts']);
    expect(repo.booksInCollection('Beach').length, 2);
    expect(repo.booksInCollection('Gifts').map((x) => x.title), ['B']);
    expect(repo.collectionNamesInUse, containsAll(['Beach', 'Gifts']));

    await repo.renameCollection('Beach', 'Summer');
    expect(repo.booksInCollection('Summer').length, 2);
    expect(repo.booksInCollection('Beach'), isEmpty);

    await repo.deleteCollection('Summer');
    expect(repo.collectionNamesInUse, ['Gifts']);
  });

  test('allCollectionNames merges settings and names in use', () async {
    final settings = await AppSettings.load();
    settings.addCollection('Zebra');
    final a = await addBook('A');
    await repo.addToCollectionAll({a}, 'apple');
    expect(allCollectionNames(settings, repo), ['apple', 'Zebra']);
  });

  test('quotes can be added and removed', () async {
    final id = await addBook('Quoted');
    await repo.addQuote(id, '  Hello there  ', page: 42);
    await repo.addQuote(id, 'No page');
    await repo.addQuote(id, '   ');
    var book = repo.byId(id)!;
    expect(book.quotes.length, 2);
    expect(book.quotes.first.text, 'Hello there');
    expect(book.quotes.first.page, 42);
    expect(book.quotes.last.page, isNull);

    await repo.removeQuote(id, 0);
    book = repo.byId(id)!;
    expect(book.quotes.map((q) => q.text), ['No page']);
  });

  test('quotes and shelves survive a JSON round trip', () async {
    final id = await addBook('Round');
    await repo.addQuote(id, 'Words', page: 7);
    await repo.setCollections(id, ['Keep']);
    final copy = Book.fromJson(repo.byId(id)!.toJson());
    expect(copy.collections, ['Keep']);
    expect(copy.quotes.single.text, 'Words');
    expect(copy.quotes.single.page, 7);
  });

  test('duplicates are found by ISBN or by title and author', () async {
    await addBook('The Hobbit', author: 'Tolkien');
    await addBook('the  hobbit!', author: 'TOLKIEN');
    await addBook('Dune', isbn: '9780261102217');
    await addBook('Dune (new cover)', isbn: '9780261102217');
    await addBook('Unique');
    final groups = repo.findDuplicates();
    expect(groups.length, 2);
    expect(groups.every((g) => g.length == 2), isTrue);
  });

  test('merging keeps one book with the details of both', () async {
    final a = await addBook('The Hobbit', author: 'Tolkien');
    final b = await addBook('The Hobbit', author: 'Tolkien');
    await repo.addQuote(b, 'A quote');
    await repo.setCollections(b, ['Fantasy']);
    final group = repo.findDuplicates().single;
    await repo.mergeDuplicates(group);
    expect(repo.books.length, 1);
    expect(repo.trash.length, 1);
    final kept = repo.books.single;
    expect([a, b], contains(kept.id));
    expect(kept.quotes.length, 1);
    expect(kept.collections, ['Fantasy']);
    expect(findDuplicateGroups(repo.books), isEmpty);
  });

  test('year in review counts the finished books of that year', () {
    final books = [
      Book(
        id: '1',
        title: 'Early',
        author: 'A',
        shelf: Shelf.finished,
        addedAt: DateTime(2026),
        rating: 5,
        finishedAt: DateTime(2026, 3, 1),
      ),
      Book(
        id: '2',
        title: 'Later',
        author: 'B',
        shelf: Shelf.finished,
        addedAt: DateTime(2026),
        rating: 3,
        finishedAt: DateTime(2026, 3, 20),
      ),
      Book(
        id: '3',
        title: 'Old',
        author: 'C',
        shelf: Shelf.finished,
        addedAt: DateTime(2025),
        finishedAt: DateTime(2025, 6, 1),
      ),
    ];
    final review = computeYearReview(books, 2026);
    expect(review.stats.finishedCount, 2);
    expect(review.busiestMonth, 3);
    expect(review.topRated.first.title, 'Early');
  });

  test('reading challenge shows books to go and pace', () {
    final status = challengeStatus(
      finished: 10,
      goal: 24,
      year: 2026,
      now: DateTime(2026, 7, 2),
    );
    expect(status.remaining, 14);
    expect(status.progress, closeTo(10 / 24, 0.001));
    expect(status.ahead, isNotNull);
    expect(status.describe(), contains('14 to go'));

    final past = challengeStatus(
      finished: 30,
      goal: 24,
      year: 2025,
      now: DateTime(2026, 7, 2),
    );
    expect(past.remaining, 0);
    expect(past.ahead, isNull);
    expect(past.describe(), 'Goal reached!');
  });

  test('PIN is stored hashed and checked', () async {
    final salt = newPinSalt();
    expect(hashPin('1234', salt), hashPin('1234', salt));
    expect(hashPin('1234', salt), isNot(hashPin('1235', salt)));

    final settings = await AppSettings.load();
    expect(settings.pinEnabled, isFalse);
    settings.setPin('4821');
    expect(settings.pinEnabled, isTrue);
    expect(settings.checkPin('4821'), isTrue);
    expect(settings.checkPin('0000'), isFalse);

    final reloaded = await AppSettings.load();
    expect(reloaded.checkPin('4821'), isTrue);
    reloaded.clearPin();
    expect(reloaded.pinEnabled, isFalse);
    expect((await AppSettings.load()).pinEnabled, isFalse);
  });

  test('sync status and shelf names are remembered', () async {
    final settings = await AppSettings.load();
    expect(settings.lastSyncAt, isNull);
    final at = DateTime(2026, 10, 1, 9, 30);
    settings.recordSync(at: at, changed: 3);
    settings.recordSyncError('boom');
    settings.addCollection('Gifts');
    settings.addCollection('gifts');

    final reloaded = await AppSettings.load();
    expect(reloaded.lastSyncAt, at);
    expect(reloaded.lastSyncChanged, 3);
    expect(reloaded.lastSyncError, 'boom');
    expect(reloaded.collections, ['Gifts']);
    reloaded.recordSync(at: at, changed: 0);
    expect(reloaded.lastSyncError, isNull);
  });
}
