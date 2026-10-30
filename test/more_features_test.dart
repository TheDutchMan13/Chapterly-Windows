import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/backup.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_sorting.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/csv.dart';
import 'package:chapterly/data/date_format.dart';
import 'package:chapterly/data/statistics.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_format.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late BookRepository repo;

  Future<String> addBook(String title, {BookFormat? format}) async {
    await repo.add(
      title: title,
      author: 'Someone',
      shelf: Shelf.forLater,
      format: format,
    );
    return repo.books.firstWhere((b) => b.title == title).id;
  }

  setUp(() async {
    repo = BookRepository(InMemoryBookStore());
    await repo.load();
  });

  test('series: list in order and find the next book', () async {
    final two = await addBook('Two');
    final one = await addBook('One');
    final other = await addBook('Other');
    await repo.setSeries(two, 'Saga', 2);
    await repo.setSeries(one, ' saga ', 1);
    await repo.setSeries(other, 'Else', 1);

    expect(repo.booksInSeries('Saga').map((b) => b.title), ['One', 'Two']);
    expect(repo.nextInSeries(repo.byId(one)!)!.title, 'Two');
    expect(repo.nextInSeries(repo.byId(two)!), isNull);

    await repo.setSeries(one, '', 5);
    expect(repo.byId(one)!.series, isNull);
    expect(repo.byId(one)!.seriesNumber, isNull);
  });

  test('putBack undoes a bulk move', () async {
    final a = await addBook('A');
    final before = [repo.byId(a)!];
    await repo.moveAllTo({a}, Shelf.finished);
    expect(repo.byId(a)!.shelf, Shelf.finished);
    await repo.putBack(before);
    expect(repo.byId(a)!.shelf, Shelf.forLater);
    expect(repo.byId(a)!.finishedAt, isNull);
  });

  test('read again can use an earlier start date', () async {
    final id = await addBook('Dune');
    await repo.moveTo(id, Shelf.finished);
    await repo.readAgain(id, startedAt: DateTime(2026, 3, 4));
    expect(repo.byId(id)!.startedAt, DateTime(2026, 3, 4));
    expect(repo.byId(id)!.previousReadings, hasLength(1));
  });

  test('log entries can hold minutes, and empty ones are ignored', () async {
    final id = await addBook('Dune');
    await repo.addLogEntry(id, DateTime(2026, 4, 1), 0, minutes: 45);
    await repo.addLogEntry(id, DateTime(2026, 4, 2), 10, minutes: 20);
    await repo.addLogEntry(id, DateTime(2026, 4, 3), 0);
    final log = repo.byId(id)!.readingLog;
    expect(log, hasLength(2));
    final stats = computeStats(repo.books);
    expect(stats.loggedMinutes, 65);
    expect(stats.loggedPages, 10);
  });

  test('old log entries without minutes still load', () {
    final book = Book.fromJson({
      'id': '1',
      'title': 'T',
      'author': 'A',
      'shelf': 'finished',
      'readingLog': [
        {'date': '2026-01-01T00:00:00.000', 'pages': 12},
      ],
    });
    expect(book.readingLog.single.pages, 12);
    expect(book.readingLog.single.minutes, 0);
  });

  test('reading streak counts days in a row', () async {
    final id = await addBook('Dune');
    final now = DateTime(2026, 6, 10, 15);
    await repo.addLogEntry(id, DateTime(2026, 6, 10, 9), 5);
    await repo.addLogEntry(id, DateTime(2026, 6, 9, 21), 0, minutes: 10);
    await repo.addLogEntry(id, DateTime(2026, 6, 8), 7);
    await repo.addLogEntry(id, DateTime(2026, 6, 5), 7);
    expect(currentStreak(repo.books, now: now), 3);
    expect(pagesLoggedOn(repo.books, now), 5);

    // Nothing today yet: yesterday keeps the streak alive.
    expect(currentStreak(repo.books, now: DateTime(2026, 6, 11)), 3);
    // A gap of a full day ends it.
    expect(currentStreak(repo.books, now: DateTime(2026, 6, 12)), 0);
  });

  test('sort by format and favorites first', () async {
    final a = await addBook('A', format: BookFormat.ebook);
    final b = await addBook('B', format: BookFormat.paperback);
    final c = await addBook('C');
    await repo.setFavorite(c, favorite: true);

    final byFormat = sortBooks(repo.books, SortField.format, ascending: true);
    expect(byFormat.map((x) => x.id), [b, a, c]);

    final favs = sortBooks(repo.books, SortField.favorite, ascending: false);
    expect(favs.first.id, c);
  });

  test('monthly goal is saved', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    expect(settings.monthlyGoal, isNull);
    settings.setMonthlyGoal(2);
    expect((await AppSettings.load()).monthlyGoal, 2);
    settings.setMonthlyGoal(0);
    expect((await AppSettings.load()).monthlyGoal, isNull);
  });

  test('minutes are shown as hours and minutes', () {
    expect(formatMinutes(45), '45m');
    expect(formatMinutes(120), '2h');
    expect(formatMinutes(125), '2h 5m');
  });

  test('series, minutes and CSV survive backup and CSV round trips', () {
    final book = Book(
      id: '1',
      title: 'Dune',
      author: 'Frank',
      shelf: Shelf.finished,
      addedAt: DateTime(2026),
      series: 'Dune Chronicles',
      seriesNumber: 1,
      readingLog: [
        LogEntry(date: DateTime(2026, 1, 2), minutes: 30),
      ],
    );
    final restored = decodeBackup(encodeBackup([book])).single;
    expect(restored.series, 'Dune Chronicles');
    expect(restored.seriesNumber, 1);
    expect(restored.readingLog.single.minutes, 30);

    final fromCsv = importBooksFromCsv(encodeBooksCsv([book])).books.single;
    expect(fromCsv.series, 'Dune Chronicles');
    expect(fromCsv.seriesNumber, 1);
  });

  test('map round trip keeps series', () {
    final book = Book(
      id: '1',
      title: 'T',
      author: 'A',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      series: 'S',
      seriesNumber: 3,
    );
    final copy = Book.fromMap(book.toMap());
    expect(copy.series, 'S');
    expect(copy.seriesNumber, 3);
  });
}
