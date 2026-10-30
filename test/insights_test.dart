import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/statistics.dart';
import 'package:chapterly/data/theme_options.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book _finished(
  String id,
  String author, {
  int? rating,
  List<String> tags = const [],
}) =>
    Book(
      id: id,
      title: 'Book $id',
      author: author,
      shelf: Shelf.finished,
      addedAt: DateTime(2026),
      rating: rating,
      tags: tags,
      finishedAt: DateTime(2026, 5, 1),
    );

void main() {
  test('rating breakdown counts every star', () {
    final stats = computeStats([
      _finished('1', 'A', rating: 5),
      _finished('2', 'A', rating: 5),
      _finished('3', 'B', rating: 3),
      _finished('4', 'B'),
    ]);
    expect(stats.ratingCounts, {1: 0, 2: 0, 3: 1, 4: 0, 5: 2});
  });

  test('top authors and tags are counted ignoring case, most first', () {
    final stats = computeStats([
      _finished('1', 'Jane Austen', tags: ['Classic', 'romance']),
      _finished('2', 'jane austen', tags: ['classic']),
      _finished('3', 'Frank Herbert', tags: ['sci-fi']),
      _finished('4', '', tags: ['Classic']),
    ]);
    expect(stats.topAuthors.first.key, 'Jane Austen');
    expect(stats.topAuthors.first.value, 2);
    expect(stats.topAuthors, hasLength(2));
    expect(stats.topTags.first.key, 'Classic');
    expect(stats.topTags.first.value, 3);
  });

  test('top lists keep at most five entries', () {
    final stats = computeStats([
      for (var i = 0; i < 8; i++) _finished('$i', 'Author $i'),
    ]);
    expect(stats.topAuthors, hasLength(5));
  });

  Book reading({int? pages, List<LogEntry> log = const []}) => Book(
        id: 'r',
        title: 'Reading',
        author: 'A',
        shelf: Shelf.inProgress,
        addedAt: DateTime(2026),
        pages: pages,
        startedAt: DateTime(2026, 6, 1),
        readingLog: log,
      );

  test('reading pace and finish estimate', () {
    final book = reading(pages: 300, log: [
      LogEntry(date: DateTime(2026, 6, 1), pages: 100),
      LogEntry(date: DateTime(2026, 6, 2), pages: 50),
    ]);
    final pace = readingPace(book, now: DateTime(2026, 6, 3))!;
    expect(pace.pagesPerDay, 50);
    expect(pace.pagesLeft, 150);
    expect(pace.daysLeft, 3);
    expect(pace.finishEstimate, DateTime(2026, 6, 6));
    expect(pace.describe(), contains('50.0 pages a day'));
    expect(pace.describe(), contains('3 days left'));
  });

  test('pace without a page count has no estimate, and needs a log', () {
    final log = [LogEntry(date: DateTime(2026, 6, 1), pages: 30)];
    final pace = readingPace(reading(log: log), now: DateTime(2026, 6, 1))!;
    expect(pace.pagesPerDay, 30);
    expect(pace.daysLeft, isNull);
    expect(readingPace(reading(), now: DateTime(2026, 6, 1)), isNull);
    expect(
      readingPace(
        reading(log: [LogEntry(date: DateTime(2026, 6, 1), minutes: 10)]),
        now: DateTime(2026, 6, 1),
      ),
      isNull,
    );
  });

  test('pace is only for books in progress', () {
    final book = reading(
      pages: 100,
      log: [LogEntry(date: DateTime(2026, 6, 1), pages: 10)],
    ).copyWith(shelf: Shelf.finished);
    expect(readingPace(book, now: DateTime(2026, 6, 2)), isNull);
  });

  test('a finished page count says it should be finished', () {
    final book = reading(
      pages: 100,
      log: [LogEntry(date: DateTime(2026, 6, 1), pages: 120)],
    );
    final pace = readingPace(book, now: DateTime(2026, 6, 1))!;
    expect(pace.pagesLeft, 0);
    expect(pace.describe(), contains('should be finished'));
  });

  test('backup reminder waits, can be snoozed, and resets after a backup', () {
    final settings = AppSettings();
    final start = DateTime(2026, 1, 1);
    expect(settings.backupDue(bookCount: 0, now: start), isFalse);
    expect(settings.backupDue(bookCount: 3, now: start), isFalse);
    expect(
      settings.backupDue(bookCount: 3, now: DateTime(2026, 1, 30)),
      isFalse,
    );
    expect(
      settings.backupDue(bookCount: 3, now: DateTime(2026, 1, 31)),
      isTrue,
    );

    settings.snoozeBackupReminder(DateTime(2026, 1, 31));
    expect(
      settings.backupDue(bookCount: 3, now: DateTime(2026, 2, 6)),
      isFalse,
    );
    expect(
      settings.backupDue(bookCount: 3, now: DateTime(2026, 2, 7)),
      isTrue,
    );

    settings.markBackedUp(DateTime(2026, 2, 7));
    expect(
      settings.backupDue(bookCount: 3, now: DateTime(2026, 3, 1)),
      isFalse,
    );
    expect(
      settings.backupDue(bookCount: 3, now: DateTime(2026, 3, 9)),
      isTrue,
    );

    settings.setBackupReminder(false);
    expect(
      settings.backupDue(bookCount: 3, now: DateTime(2027, 1, 1)),
      isFalse,
    );
  });

  test('theme mode, pure black and backup settings are saved', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.pureBlack, isFalse);
    expect(settings.backupReminder, isTrue);
    expect(settings.backupDays, 30);

    settings.setThemeMode(ThemeMode.dark);
    settings.setPureBlack(true);
    settings.setBackupDays(60);
    settings.markBackedUp(DateTime(2026, 5, 5));

    final reloaded = await AppSettings.load();
    expect(reloaded.themeMode, ThemeMode.dark);
    expect(reloaded.pureBlack, isTrue);
    expect(reloaded.backupDays, 60);
    expect(reloaded.lastBackup, DateTime(2026, 5, 5));
  });

  test('pure black only changes the dark theme', () {
    final settings = AppSettings()..setPureBlack(true);
    final dark = buildTheme(settings, Brightness.dark);
    final light = buildTheme(settings, Brightness.light);
    expect(dark.colorScheme.surface, Colors.black);
    expect(dark.scaffoldBackgroundColor, Colors.black);
    expect(light.colorScheme.surface, isNot(Colors.black));

    settings.setPureBlack(false);
    expect(
      buildTheme(settings, Brightness.dark).colorScheme.surface,
      isNot(Colors.black),
    );
  });
}
