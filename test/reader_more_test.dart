import 'dart:async';
import 'dart:io';

import 'package:chapterly/audio/audio_files.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/statistics.dart';
import 'package:chapterly/ebook/ebook_files.dart';
import 'package:chapterly/ebook/ebook_library.dart';
import 'package:chapterly/ebook/reader_stats.dart';
import 'package:chapterly/ebook/reader_style.dart';
import 'package:chapterly/ebook/reader_tools.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/reader_stats_card.dart';
import 'package:chapterly/screens/reader_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The same file is in the Android and the Windows app.

EbookLink _link(String path, {EbookFormat format = EbookFormat.epub}) =>
    EbookLink(
      path: path,
      name: 'Emma.epub',
      bytes: 1200,
      format: format,
      addedAt: DateTime(2026, 10, 31),
    );

class _Files implements EbookFiles {
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

/// A voice that "reads" at once and remembers what it read.
class _Speaker implements Speaker {
  final said = <String>[];
  double rate = 1;
  Completer<void>? hold;

  @override
  Future<void> speak(String text) async {
    said.add(text);
    final wait = hold;
    if (wait != null) await wait.future;
  }

  @override
  Future<void> stop() async {
    final wait = hold;
    hold = null;
    if (wait != null && !wait.isCompleted) wait.complete();
  }

  @override
  Future<void> setRate(double rate) async => this.rate = rate;

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('chapterly_reader_more_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('highlights keep their colour and note', () async {
    final file = File('${temp.path}/ebook_library.json');
    final library = await EbookLibrary.load(file);
    await library.setLink('b1', _link('${temp.path}/b1.epub'));
    await library.addHighlight(
      'b1',
      EbookHighlight(
        locator: 'r:2:10:40',
        text: 'handsome, clever, and rich',
        addedAt: DateTime(2026, 10, 31),
        colour: HighlightColour.green,
      ),
    );
    await library.updateHighlight('b1', 'r:2:10:40', note: () => '  Emma! ');

    final again = await EbookLibrary.load(file);
    var highlight = again.linkFor('b1')!.highlights.single;
    expect(highlight.colour, HighlightColour.green);
    expect(highlight.note, 'Emma!');

    await again.updateHighlight(
      'b1',
      'r:2:10:40',
      colour: HighlightColour.pink,
      note: () => '   ',
    );
    highlight = again.linkFor('b1')!.highlights.single;
    expect(highlight.colour, HighlightColour.pink);
    expect(highlight.note, isNull);

    // Without a colour in the file, a highlight is yellow.
    expect(
      EbookHighlight.fromJson({'locator': 'x', 'text': 't'})!.colour,
      HighlightColour.yellow,
    );
  });

  test('a book can have its own look; device settings stay shared', () async {
    final library = EbookLibrary();
    await library.setLink('b1', _link('${temp.path}/b1.epub'));
    await library.setLink('b2', _link('${temp.path}/b2.epub'));
    await library.setPrefs(const ReaderPrefs(fontSize: 18));

    await library.setOwnLook('b1', own: true);
    expect(library.hasOwnLook('b1'), isTrue);
    await library.applyPrefs(
      'b1',
      library.prefsFor('b1').copyWith(
            fontSize: 26,
            theme: ReaderTheme.black,
            speechRate: 1.5,
          ),
    );
    // The look stays with b1; the reading speed is for every book.
    expect(library.prefsFor('b1').fontSize, 26);
    expect(library.prefsFor('b1').theme, ReaderTheme.black);
    expect(library.prefsFor('b2').fontSize, 18);
    expect(library.prefsFor('b2').theme, ReaderTheme.paper);
    expect(library.prefsFor('b2').speechRate, 1.5);

    // A book without its own look changes the usual settings.
    await library.applyPrefs(
      'b2',
      library.prefsFor('b2').copyWith(fontSize: 20),
    );
    expect(library.prefs.fontSize, 20);
    expect(library.prefsFor('b1').fontSize, 26);

    await library.setOwnLook('b1', own: false);
    expect(library.prefsFor('b1').fontSize, 20);
  });

  test('new reader settings are saved and kept within limits', () {
    final prefs = const ReaderPrefs().copyWith(
      pageView: true,
      keepScreenOn: false,
      volumeKeys: false,
      brightness: () => 0.4,
      speechRate: 1.25,
    );
    final again = ReaderPrefs.fromJson(prefs.toJson());
    expect(again, prefs);
    expect(const ReaderPrefs().copyWith(speechRate: 9).speechRate,
        ReaderPrefs.maxSpeechRate);
    expect(const ReaderPrefs().copyWith(brightness: () => -1).brightness,
        greaterThan(0));
    expect(
      const ReaderPrefs().copyWith(brightness: () => 0.4).copyWith(
            brightness: () => null,
          ),
      const ReaderPrefs(),
    );
  });

  test('time in the reader adds up per day and gives a reading speed',
      () async {
    final library = EbookLibrary();
    await library.setLink('b1', _link('${temp.path}/b1.epub'));
    final day = DateTime(2026, 10, 30, 21);
    await library.addReaderTime('b1', day, minutes: 20, progress: 0.05);
    await library.addReaderTime('b1', day, minutes: 10, progress: 0.05);
    await library.addReaderTime('b1', DateTime(2026, 10, 31),
        minutes: 30, progress: 0.1);
    final link = library.linkFor('b1')!;
    expect(link.days, hasLength(2));
    expect(link.days.first.minutes, 30);

    // A fifth of a 300-page book in an hour.
    final stats = readerStatsFor(link, bookPages: 300);
    expect(stats.minutes, 60);
    expect(stats.daysRead, 2);
    expect(stats.pagesPerHour, closeTo(60, 0.01));
    expect(readerStatsFor(link).pagesPerHour, isNull);

    final summary = readerSummary(
      library.links,
      bookPages: (_) => 300,
      now: DateTime(2026, 10, 31, 12),
    );
    expect(summary.totalMinutes, 60);
    expect(summary.lastWeekMinutes, 60);
    expect(summary.longestStreak, 2);
    expect(summary.topBooks.single, ('b1', 60));
    expect(pagesPerHourText(summary.pagesPerHour!), 'About 60 pages an hour');
  });

  test('only new reading counts toward speed, not jumps or going back', () {
    var step = newReading(0.2, 0.25);
    expect(step.read, closeTo(0.05, 1e-9));
    expect(step.mark, 0.25);
    step = newReading(0.25, 0.1);
    expect(step.read, 0);
    expect(step.mark, 0.25);
    step = newReading(0.25, 0.9);
    expect(step.read, 0);
    expect(step.mark, 0.9);
  });

  test('runs of days', () {
    expect(longestRun([]), 0);
    expect(
      longestRun([
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 3),
        DateTime(2026, 10, 10),
      ]),
      3,
    );
  });

  test('the longest streak in the reading log', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(title: 'Emma', author: 'J', shelf: Shelf.inProgress);
    final id = repository.books.single.id;
    for (final day in [1, 2, 3, 4, 8, 9]) {
      await repository.addLogEntry(id, DateTime(2026, 10, day), 10);
    }
    expect(longestStreak(repository.books), 4);
  });

  test('replacing a book file keeps its own look and its time', () async {
    final library = EbookLibrary();
    final booksDir = Directory('${temp.path}/books');
    var stamp = 1000;
    DateTime now() => DateTime.fromMillisecondsSinceEpoch(stamp++);
    await addBookFile(
      library: library,
      files: _Files(),
      booksDir: booksDir,
      bookId: 'b1',
      picked: const PickedFile(location: 'a', name: 'Emma.epub'),
      now: now,
    );
    await library.setOwnLook('b1', own: true);
    await library.addReaderTime('b1', DateTime(2026, 10, 31),
        minutes: 15, progress: 0.02);
    await addBookFile(
      library: library,
      files: _Files(),
      booksDir: booksDir,
      bookId: 'b1',
      picked: const PickedFile(location: 'b', name: 'Emma.pdf'),
      now: now,
    );
    final link = library.linkFor('b1')!;
    expect(link.format, EbookFormat.pdf);
    expect(link.prefs, isNotNull);
    expect(link.days.single.minutes, 15);
  });

  test('opening a book moves it to In progress; the end is the end', () {
    expect(shelfOnOpen(Shelf.forLater), Shelf.inProgress);
    expect(shelfOnOpen(Shelf.unfinished), Shelf.inProgress);
    expect(shelfOnOpen(Shelf.inProgress), isNull);
    expect(shelfOnOpen(Shelf.finished), isNull);
    expect(reachedEnd(0.999), isTrue);
    expect(reachedEnd(0.9), isFalse);
    expect(reachedEnd(double.nan), isFalse);
  });

  test('a word or two can be looked up', () {
    expect(canLookUp('serendipity'), isTrue);
    expect(canLookUp('  '), isFalse);
    expect(canLookUp('a\nb'), isFalse);
    expect(canLookUp('x' * 80), isFalse);
    final uri = dictionaryUri('  cheval   de frise ');
    expect(uri.host, 'en.wiktionary.org');
    expect(uri.queryParameters['search'], 'cheval de frise');
  });

  test('text is read aloud in whole sentences', () {
    expect(speechChunks(''), isEmpty);
    final short = speechChunks('One. Two!\n\nThree?');
    expect(short, ['One. Two! Three?']);
    final long = speechChunks(
      List.filled(30, 'This sentence is about forty letters long.').join(' '),
      size: 100,
    );
    expect(long.length, greaterThan(5));
    for (final piece in long) {
      expect(piece.length, lessThanOrEqualTo(100));
      expect(piece, endsWith('.'));
    }
    // A run-on text with no stops is still cut up.
    final runOn = speechChunks(List.filled(200, 'word').join(' '), size: 50);
    expect(runOn.every((p) => p.length <= 100), isTrue);
  });

  test('reading aloud goes on to the next page and stops at the end',
      () async {
    final speaker = _Speaker();
    final aloud = ReadAloud(speaker);
    var pages = 0;
    final read = <int>[];
    await aloud.start(
      pieces: ['a', 'b'],
      onPiece: read.add,
      more: () async => ++pages < 3 ? ['p$pages'] : null,
    );
    expect(speaker.said, ['a', 'b', 'p1', 'p2']);
    expect(read, [0, 1, 0, 0]);
    expect(aloud.playing, isFalse);
    aloud.dispose();
  });

  test('reading aloud can be stopped', () async {
    final speaker = _Speaker()..hold = Completer<void>();
    final aloud = ReadAloud(speaker);
    final done = aloud.start(
      pieces: ['a', 'b', 'c'],
      more: () async => null,
    );
    await Future<void>.delayed(Duration.zero);
    expect(aloud.playing, isTrue);
    await aloud.stop();
    await done;
    expect(speaker.said, ['a']);
    expect(aloud.playing, isFalse);
    await aloud.setRate(1.5);
    expect(speaker.rate, 1.5);
    aloud.dispose();
  });

  test('highlight colours stay readable on dark pages', () {
    for (final colour in HighlightColour.values) {
      expect(
        highlightColour(colour, ReaderTheme.black).computeLuminance(),
        lessThan(highlightColour(colour, ReaderTheme.paper).computeLuminance()),
      );
      expect(highlightSwatch(colour), highlightColour(colour, ReaderTheme.white));
    }
    expect(speedText(1), '1×');
    expect(speedText(1.25), '1.25×');
    expect(speedText(1.5), '1.5×');
  });

  testWidgets('Statistics shows time in the reader', (tester) async {
    final repository = BookRepository(InMemoryBookStore());
    await tester.runAsync(() async {
      await repository.load();
      await repository.add(
        title: 'Emma',
        author: 'J',
        shelf: Shelf.inProgress,
        pages: 300,
      );
    });
    final id = repository.books.single.id;
    final library = EbookLibrary();
    await tester.runAsync(() async {
      await library.setLink(id, _link('${temp.path}/b1.epub'));
      await library.addReaderTime(id, DateTime.now(),
          minutes: 90, progress: 0.1);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReaderStatsCard(repository: repository, library: library),
          ),
        ),
      ),
    );
    expect(find.text('In the reader on this device'), findsOneWidget);
    expect(find.text('Emma'), findsOneWidget);
    expect(find.text('About 20 pages an hour'), findsOneWidget);
  });
}
