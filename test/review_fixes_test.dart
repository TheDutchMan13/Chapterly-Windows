import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/csv.dart';
import 'package:chapterly/data/profile_files.dart';
import 'package:chapterly/data/profiles.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/server/server_downloads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late BookRepository repo;

  Future<String> addBook(String title) =>
      repo.add(title: title, author: 'Someone', shelf: Shelf.forLater);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = BookRepository(InMemoryBookStore());
    await repo.load();
  });

  group('Undo takes back only what the change did', () {
    test('a rating given after a move is kept', () async {
      final a = await addBook('A');
      final before = [repo.byId(a)!];
      await repo.moveAllTo({a}, Shelf.finished);
      await repo.setRating(a, 4);
      await repo.putBack(before);
      expect(repo.byId(a)!.shelf, Shelf.forLater);
      expect(repo.byId(a)!.rating, 4);
    });

    test('a book the change left alone is not touched', () async {
      final a = await addBook('A');
      final b = await addBook('B');
      await repo.addToCollectionAll({a}, 'Beach');
      final before = [repo.byId(a)!, repo.byId(b)!];
      await repo.addToCollectionAll({a, b}, 'Beach');
      await repo.setNotes(a, 'kept');
      final stampB = repo.byId(b)!.updatedAt;
      await repo.putBack(before);
      // A was already on Beach: the change did nothing to it.
      expect(repo.byId(a)!.collections, ['Beach']);
      expect(repo.byId(a)!.notes, 'kept');
      // B was put on it, and is taken off again.
      expect(repo.byId(b)!.collections, isEmpty);
      expect(repo.byId(b)!.updatedAt.isBefore(stampB), isFalse);
    });

    test('tags added by Tag my library come off', () async {
      final a = await addBook('A');
      final before = [repo.byId(a)!];
      await repo.addTagsToBooks({
        a: ['Fantasy'],
      });
      await repo.putBack(before);
      expect(repo.byId(a)!.tags, isEmpty);
    });

    test('a tag of your own added after Tag my library is not lost',
        () async {
      final a = await addBook('A');
      final before = [repo.byId(a)!];
      await repo.addTagsToBooks({
        a: ['Fantasy'],
      });
      await repo.addTagToAll({a}, 'Mine');
      await repo.putBack(before);
      // Tags are one field: changed again since, so they are left as they
      // are rather than losing your own tag.
      expect(repo.byId(a)!.tags, containsAll(['Fantasy', 'Mine']));
    });
  });

  test('a bulk change that changes nothing keeps the time', () async {
    final a = await addBook('A');
    await repo.addTagToAll({a}, 'X');
    final stamp = repo.byId(a)!.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.addTagToAll({a}, 'x');
    expect(repo.byId(a)!.updatedAt, stamp);
  });

  test('a restored backup counts as changed now and is not removed again',
      () async {
    final a = await addBook('A');
    final old = repo.byId(a)!;
    await repo.deleteForever(a);
    expect(repo.snapshot().tombstones, contains(a));
    final restoredAt = DateTime.now();
    await repo.restoreBackup([old]);
    expect(repo.snapshot().tombstones, isNot(contains(a)));
    expect(repo.byId(a)!.updatedAt.isBefore(restoredAt), isFalse);
  });

  test('CSV cells a spreadsheet would run are written as text', () {
    final book = Book(
      id: 'x',
      title: '=HYPERLINK("http://evil","click")',
      author: '@me',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026, 1, 1),
    );
    final csv = encodeBooksCsv([book]);
    expect(csv, contains("'=HYPERLINK"));
    expect(csv, contains("'@me"));
    final back = importBooksFromCsv(csv).books.single;
    expect(back.title, book.title);
    expect(back.author, '@me');
  });

  test('backup folders of two profiles never meet', () {
    final a = Profile(
      id: 'aaaa1111',
      name: 'Anna!',
      color: 0,
      createdAt: DateTime(2026),
    );
    final b = Profile(
      id: 'bbbb2222',
      name: 'Anna?',
      color: 0,
      createdAt: DateTime(2026),
    );
    expect(profileBackupFolder(a), isNot(profileBackupFolder(b)));
    expect(profileBackupFolder(a), 'Anna_ (aaaa1111)');
  });

  test('names from the server stay in the books folder', () {
    expect(serverFormats, isNot(contains('exe')));
    expect(safeTrackName(0, '../../evil.mp3'), isNot(contains('/')));
    expect(safeTrackName(1, '..'), '002 track');
    expect(safeTrackName(2, 'CON.'), '003 CON');
  });

  test('a long track name is shortened before its extension', () {
    final long = safeTrackName(0, '${'a' * 200}.mp3');
    expect(long, endsWith('a.mp3'));
    expect(long.length, lessThanOrEqualTo(154));
    final dotted = safeTrackName(1, '${'b' * 148}. . .M4B');
    expect(dotted, endsWith('b.m4b'));
    expect(safeTrackName(2, 'c' * 300, format: 'mp3'), endsWith('c.mp3'));
    expect(safeTrackName(3, 'Intro', format: 'mp3'), '004 Intro.mp3');
    expect(safeTrackName(4, 'Intro.m4a', format: 'mp3'), '005 Intro.m4a');
    expect(safeTrackName(5, 'Intro', format: 'epub'), '006 Intro');
    expect(isInside(r'C:\books', r'C:\books\server-x.epub'), isTrue);
    expect(isInside(r'C:\books', r'C:\books\..\x.epub'), isFalse);
    expect(isInside(r'C:\books', r'C:\other\x.epub'), isFalse);
  });
}
