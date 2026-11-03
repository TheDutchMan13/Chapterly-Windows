import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/reading_nudge.dart';
import 'package:chapterly/models/audio_progress.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/reminder_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The same tests are in the other app.

Book _book(
  String id, {
  Shelf shelf = Shelf.inProgress,
  DateTime? updated,
  DateTime? finishedAt,
  AudioProgress? audio,
  int? page,
  int? pages,
}) =>
    Book(
      id: id,
      title: 'Book $id',
      author: 'Author $id',
      shelf: shelf,
      addedAt: DateTime(2026),
      updatedAt: updated ?? DateTime(2026, 1, 1),
      finishedAt: finishedAt,
      audio: audio,
      currentPage: page,
      pages: pages,
    );

void main() {
  group('the widget', () {
    test('shows the audiobook in the player, with play state', () {
      final content = widgetContent(
        [
          _book('a', updated: DateTime(2026, 3)),
          _book('b', audio: const AudioProgress(positionMs: 1800000, lengthMs: 7200000)),
        ],
        playerBookId: 'b',
        playing: true,
      );
      expect(content.title, 'Book b');
      expect(content.author, 'Author b');
      expect(content.detail, '25% · 1 h 30 min left');
      expect(content.audio, isTrue);
      expect(content.playing, isTrue);
    });

    test('otherwise the book you touched last on In progress', () {
      final content = widgetContent([
        _book('old', updated: DateTime(2026, 1), page: 10, pages: 100),
        _book('new', updated: DateTime(2026, 5), page: 120, pages: 400),
        _book('done', shelf: Shelf.finished, updated: DateTime(2026, 6)),
      ]);
      expect(content.title, 'Book new');
      expect(content.detail, 'Page 120 of 400');
      expect(content.audio, isFalse);
    });

    test('says so when nothing is in progress', () {
      final content = widgetContent([_book('x', shelf: Shelf.forLater)]);
      expect(content.title, 'Nothing in progress');
      expect(content.bookId, isNull);
    });
  });

  group('the reminder', () {
    final july = DateTime(2026, 7, 1);
    List<Book> finished(int count) => [
          for (var i = 0; i < count; i++)
            _book('f$i', shelf: Shelf.finished, finishedAt: DateTime(2026, 1 + i % 6, 3)),
        ];

    test('speaks when you are behind this year\'s goal', () {
      final text = reminderText(finished(3), goal: 30, now: july);
      expect(text, contains("You've read 3 of 30 books"));
    });

    test('is quiet on track, without a goal, or early in the year', () {
      expect(reminderText(finished(20), goal: 30, now: july), isNull);
      expect(reminderText(finished(3), goal: null, now: july), isNull);
      expect(reminderText(finished(0), goal: 30, now: DateTime(2026, 1, 5)), isNull);
    });
  });

  testWidgets('turning the reminder on asks first, and picks a time',
      (tester) async {
    final settings = AppSettings();
    var allow = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => ReminderSettings(
            settings: settings,
            where: 'as a notification',
            askPermission: () async => allow,
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Reading reminder'));
    await tester.pumpAndSettle();
    expect(settings.reminderOn, isFalse);
    expect(find.textContaining('Notifications are off'), findsOneWidget);
    allow = true;
    await tester.tap(find.text('Reading reminder'));
    await tester.pumpAndSettle();
    expect(settings.reminderOn, isTrue);
    expect(find.textContaining('Every day at 20:00'), findsOneWidget);
    expect(find.text('Reminder time'), findsOneWidget);
    settings.setReminder(minutes: 7 * 60 + 30);
    await tester.pumpAndSettle();
    expect(find.text('07:30'), findsOneWidget);
    expect(formatMinutes(0), '00:00');
  });
}
