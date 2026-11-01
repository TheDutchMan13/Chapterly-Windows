import 'package:chapterly/audio/audio_library.dart';
import 'package:chapterly/audio/listen_controller.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/duplicates.dart';
import 'package:chapterly/data/file_match.dart';
import 'package:chapterly/data/forecast.dart';
import 'package:chapterly/data/format_sync.dart';
import 'package:chapterly/data/fuzzy.dart';
import 'package:chapterly/data/recommend.dart';
import 'package:chapterly/data/series_detect.dart';
import 'package:chapterly/data/tag_suggest.dart';
import 'package:chapterly/data/taste.dart';
import 'package:chapterly/ebook/ebook_library.dart';
import 'package:chapterly/models/audio_progress.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_format.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'audio_test.dart' show FakeEngine, FakeFiles;

Book _book(
  String id, {
  String title = 'T',
  String author = 'A',
  Shelf shelf = Shelf.forLater,
  List<String> tags = const [],
  int? rating,
  int? pages,
  int? currentPage,
  String? series,
  int? number,
  BookFormat? format,
  String? isbn,
  bool favorite = false,
  DateTime? startedAt,
  DateTime? finishedAt,
  List<LogEntry> log = const [],
  AudioProgress? audio,
  DateTime? addedAt,
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: shelf,
      addedAt: addedAt ?? DateTime(2026),
      tags: tags,
      rating: rating,
      pages: pages,
      currentPage: currentPage,
      series: series,
      seriesNumber: number,
      format: format,
      isbn: isbn,
      favorite: favorite,
      startedAt: startedAt,
      finishedAt: finishedAt,
      readingLog: log,
      audio: audio,
    );

const _twoFiles = AudioLink(tracks: [
  AudioTrack(location: 'a', name: 'a.mp3', lengthMs: 60 * 60000),
  AudioTrack(location: 'b', name: 'b.mp3', lengthMs: 60 * 60000),
]);

void main() {
  group('fuzzy text', () {
    test('folds accents and punctuation', () {
      expect(foldText('Brontë, Charlotte!'), 'bronte charlotte');
      expect(foldedWords('  The  Hobbit '), ['the', 'hobbit']);
    });

    test('edit distance counts a swap as one typo', () {
      expect(editDistance('dune', 'dune'), 0);
      expect(editDistance('dnue', 'dune'), 1);
      expect(editDistance('sanderson', 'sandersen'), 1);
      expect(editDistance('kitten', 'sitting'), 3);
      expect(editDistance('abc', 'xyzxyz', max: 2), 3);
      expect(similarity('abcd', 'abcd'), 1);
    });

    test('near words allow typos by length and partial words', () {
      expect(isNearWord('sandersn', 'sanderson'), isTrue);
      expect(isNearWord('sandr', 'sanderson'), isTrue);
      expect(isNearWord('dun', 'dune'), isFalse); // too short for a typo
      expect(isNearWord('tolkein', 'tolkien'), isTrue);
      expect(isNearWord('herbert', 'pratchett'), isFalse);
    });

    test('a correctly spelled word is not widened', () {
      final plan = SearchPlan.build('dune', {'dune', 'june'});
      expect(plan.corrected, isFalse);
      expect(plan.matchesFolded('june'), isFalse);
    });

    test('a word found nowhere is corrected to library words', () {
      final plan = SearchPlan.build('brandn', {'brandon', 'sanderson', 'mistborn'});
      expect(plan.corrected, isTrue);
      expect(plan.matchesFolded('mistborn brandon sanderson'), isTrue);
    });
  });

  group('library search', () {
    late BookRepository repository;

    setUp(() async {
      repository = BookRepository(InMemoryBookStore());
      await repository.load();
      await repository.add(
        title: 'Mistborn',
        author: 'Brandon Sanderson',
        shelf: Shelf.forLater,
        tags: ['fantasy'],
      );
      await repository.add(
        title: 'Jane Eyre',
        author: 'Charlotte Brontë',
        shelf: Shelf.forLater,
      );
      await repository.add(title: 'June', author: 'X', shelf: Shelf.forLater);
    });

    List<String> titles(String query) =>
        [for (final b in repository.booksOn(Shelf.forLater, query: query)) b.title];

    test('finds typos, words in any order and names without accents', () {
      expect(titles('Brandn Sanderson'), ['Mistborn']);
      expect(titles('sanderson mistborn'), ['Mistborn']);
      expect(titles('bronte'), ['Jane Eyre']);
      expect(titles('fantasy'), ['Mistborn']);
    });

    test('a correct word only finds what it says', () {
      expect(titles('june'), ['June']);
    });
  });

  group('finish forecast', () {
    final today = DateTime(2026, 10, 31, 15);

    test('recent days count more than old ones', () {
      final first = DateTime(2026, 10, 1);
      final slowThenFast = {
        for (var d = 1; d <= 20; d++) DateTime(2026, 10, d): 5.0,
        for (var d = 21; d <= 31; d++) DateTime(2026, 10, d): 40.0,
      };
      final rate = recentRate(slowThenFast, first, today);
      // The plain average is about 17; recent days pull it up.
      expect(rate, greaterThan(22));
      expect(rate, lessThan(40));
    });

    test('pages from the reading log', () {
      final book = _book(
        '1',
        shelf: Shelf.inProgress,
        pages: 400,
        currentPage: 100,
        startedAt: DateTime(2026, 10, 22),
        log: [
          for (var d = 22; d <= 31; d++)
            LogEntry(date: DateTime(2026, 10, d), pages: 10),
        ],
      );
      final forecast = forecastFinish(book, now: today)!;
      expect(forecast.basis, ForecastBasis.pages);
      expect(forecast.perDay, closeTo(10, 0.01));
      expect(forecast.daysLeft, 30);
      expect(forecast.date, DateTime(2026, 11, 30));
      expect(forecast.describe(), contains('30 days left'));
    });

    test('only books in progress, and only with something to go on', () {
      expect(forecastFinish(_book('1', pages: 300), now: today), isNull);
      expect(
        forecastFinish(_book('2', shelf: Shelf.inProgress, pages: 300), now: today),
        isNull,
      );
    });

    test('listening time against what is left of the audiobook', () {
      final book = _book(
        '1',
        shelf: Shelf.inProgress,
        audio: const AudioProgress(positionMs: 60 * 60000, lengthMs: 120 * 60000),
        log: [
          for (var d = 25; d <= 31; d++)
            LogEntry(date: DateTime(2026, 10, d), minutes: 30),
        ],
      );
      final normal = forecastFinish(book, audio: _twoFiles, now: today)!;
      expect(normal.basis, ForecastBasis.listening);
      expect(normal.daysLeft, 2); // 60 minutes left at 30 a day
      final fast = forecastFinish(book, audio: _twoFiles, speed: 2, now: today)!;
      expect(fast.daysLeft, 1);
    });

    test('the reader progress of a book file', () {
      final link = EbookLink(
        path: 'x.epub',
        name: 'x.epub',
        bytes: 1,
        format: EbookFormat.epub,
        addedAt: DateTime(2026),
        position: const EbookPosition(locator: 'c:3:0.0', progress: 0.4),
        days: [
          for (var d = 28; d <= 31; d++)
            EbookDay(
              day: DateTime(2026, 10, d),
              minutes: 30,
              progress: 0.1 * (d - 27),
            ),
        ],
      );
      final forecast = forecastFinish(
        _book('1', shelf: Shelf.inProgress),
        ebook: link,
        now: today,
      )!;
      expect(forecast.basis, ForecastBasis.reader);
      expect(forecast.daysLeft, 6); // 60% left at 10% a day
    });

    test('the way you read most recently wins', () {
      final book = _book(
        '1',
        shelf: Shelf.inProgress,
        pages: 300,
        currentPage: 150,
        log: [LogEntry(date: DateTime(2026, 9, 1), pages: 150)],
        audio: const AudioProgress(positionMs: 60 * 60000, lengthMs: 120 * 60000),
      );
      final withListening = book.copyWith(readingLog: [
        ...book.readingLog,
        LogEntry(date: DateTime(2026, 10, 31), minutes: 60),
      ]);
      expect(
        forecastFinish(withListening, audio: _twoFiles, now: today)!.basis,
        ForecastBasis.listening,
      );
    });

    test('the yearly goal: on track, or how much to catch up', () {
      final finished = [
        for (var m = 1; m <= 10; m++)
          for (var k = 0; k < 3; k++)
            _book('$m-$k', shelf: Shelf.finished, finishedAt: DateTime(2026, m, 5 + k)),
      ];
      final onTrack = forecastGoal(finished, goal: 30, year: 2026, now: today)!;
      expect(onTrack.finished, 30);
      expect(onTrack.describe(), startsWith('Goal reached'));

      final behind = forecastGoal(finished, goal: 60, year: 2026, now: today)!;
      expect(behind.projected, lessThan(60));
      expect(behind.describe(), contains('gets you to 60'));

      final close = forecastGoal(finished, goal: 34, year: 2026, now: today)!;
      expect(close.projected, greaterThanOrEqualTo(34));
      expect(close.reachedOn, isNotNull);
      expect(close.describe(), startsWith('On track'));

      expect(forecastGoal(finished, goal: 30, year: 2025, now: today), isNull);
      expect(
        forecastGoal(finished, goal: 30, year: 2026, now: DateTime(2026, 1, 3)),
        isNull,
      );
    });
  });

  group('recommendations', () {
    final library = [
      _book('liked1', title: 'Mistborn', author: 'Brandon Sanderson',
          shelf: Shelf.finished, rating: 5, tags: ['fantasy', 'magic']),
      _book('liked2', title: 'Elantris', author: 'Brandon Sanderson',
          shelf: Shelf.finished, rating: 5, tags: ['fantasy']),
      _book('disliked', title: 'Gone Girl', author: 'Gillian Flynn',
          shelf: Shelf.finished, rating: 1, tags: ['thriller']),
      _book('s1', title: 'Way of Kings', author: 'Brandon Sanderson',
          shelf: Shelf.finished, rating: 4, series: 'Stormlight', number: 1),
    ];
    final candidates = [
      _book('c-thriller', title: 'Sharp Objects', author: 'Gillian Flynn',
          tags: ['thriller']),
      _book('c-fantasy', title: 'Warbreaker', author: 'Brandon Sanderson',
          tags: ['fantasy', 'magic']),
      _book('c-other', title: 'Cookbook', author: 'Chef', tags: ['cooking']),
      _book('c-next', title: 'Words of Radiance', author: 'X',
          series: 'Stormlight', number: 2),
    ];

    test('ranks by taste, next in a series first', () {
      final ranked = recommend([...library, ...candidates], candidates);
      expect(ranked.first.book.id, 'c-next');
      expect(ranked.first.nextInSeries, isTrue);
      expect(ranked[1].book.id, 'c-fantasy');
      expect(ranked[1].becauseOf?.id, anyOf('liked1', 'liked2'));
      expect(ranked[1].describe(), contains('Because you liked'));
      expect(ranked.last.book.id, 'c-thriller');
    });

    test('taste weights', () {
      expect(tasteWeight(library[0]), 2);
      expect(tasteWeight(library[2]), -2);
      expect(tasteWeight(_book('x', shelf: Shelf.finished)), 0.5);
      expect(tasteWeight(_book('y', shelf: Shelf.unfinished)), -1);
      expect(tasteWeight(_book('z')), 0);
    });

    test('similar books share author and tags', () {
      final similar = similarBooks([...library, ...candidates], library[0]);
      expect(similar.first.$1.id, 'c-fantasy');
      expect(similar.map((p) => p.$1.id), isNot(contains('c-other')));
    });
  });

  group('taste profile', () {
    test('needs enough rated books', () {
      expect(tasteProfile([_book('1', shelf: Shelf.finished, rating: 5)]), isNull);
    });

    test('finds what you rate higher and lower, pulled to the average', () {
      final books = [
        for (var i = 0; i < 6; i++)
          _book('f$i', shelf: Shelf.finished, rating: 5, tags: ['fantasy'],
              author: 'Author $i'),
        for (var i = 0; i < 6; i++)
          _book('r$i', shelf: Shelf.finished, rating: 2, tags: ['romance'],
              author: 'Writer $i'),
      ];
      final taste = tasteProfile(books)!;
      expect(taste.average, 3.5);
      expect(taste.likes.first.label, 'fantasy');
      // 1.5 above the average, shrunk by 6 / 9.
      expect(taste.likes.first.difference, closeTo(1.0, 0.01));
      expect(taste.dislikes.first.label, 'romance');
      expect(taste.likes.first.describe(), 'You rate fantasy 1.0 star higher (6 books)');
    });
  });

  group('possible duplicates', () {
    test('typos, subtitles and edition names', () {
      final found = findPossibleDuplicates([
        _book('1', title: 'The Name of the Wind', author: 'Patrick Rothfuss'),
        _book('2', title: 'The Name of the Wnd', author: 'Patrick Rothfuss'),
        _book('3', title: 'Dune', author: 'Frank Herbert'),
        _book('4', title: 'Dune: Deluxe Edition', author: 'Frank Herbert'),
        _book('5', title: 'Neuromancer (Anniversary Edition)', author: 'William Gibson'),
        _book('6', title: 'Neuromancer', author: 'W. Gibson'),
      ]);
      final keys = {for (final p in found) p.key};
      expect(keys, contains(PossibleDuplicate.pairKey('1', '2')));
      expect(keys, contains(PossibleDuplicate.pairKey('3', '4')));
      expect(keys, contains(PossibleDuplicate.pairKey('5', '6')));
    });

    test('not books of a series, other authors, exact or dismissed ones', () {
      final books = [
        _book('1', title: 'Mistborn: The Final Empire', author: 'Brandon Sanderson'),
        _book('2', title: 'Mistborn: The Well of Ascension', author: 'Brandon Sanderson'),
        _book('3', title: 'The Expanse Book 1', author: 'James Corey'),
        _book('4', title: 'The Expanse Book 2', author: 'James Corey'),
        _book('5', title: 'Emma', author: 'Jane Austen'),
        _book('6', title: 'Emma', author: 'Someone Else'),
        _book('7', title: 'Persuasion', author: 'Jane Austen'),
        _book('8', title: 'Persuasion', author: 'Jane Austen'),
        _book('9', title: 'Sense and Sensibilty', author: 'Jane Austen'),
        _book('10', title: 'Sense and Sensibility', author: 'Jane Austen'),
      ];
      final found = findPossibleDuplicates(
        books,
        dismissed: {PossibleDuplicate.pairKey('9', '10')},
      );
      expect(found, isEmpty);
    });
  });

  group('series in titles', () {
    test('clear patterns', () {
      expect(seriesInTitle('The Final Empire (Mistborn, #1)'),
          (series: 'Mistborn', number: 1));
      expect(seriesInTitle('Leviathan Wakes (The Expanse Book 1)'),
          (series: 'The Expanse', number: 1));
      expect(seriesInTitle('The Way of Kings: Book One of the Stormlight Archive'),
          (series: 'Stormlight Archive', number: 1));
      expect(seriesInTitle('Mistborn, Book 2: The Well of Ascension'),
          (series: 'Mistborn', number: 2));
      expect(seriesInTitle('Wheel of Time Vol. IV'),
          (series: 'Wheel of Time', number: 4));
      expect(seriesInTitle('The Book Thief'), isNull);
      expect(seriesInTitle('Fahrenheit 451'), isNull);
      expect(seriesInTitle('Catch-22'), isNull);
    });

    test('uses your spelling and needs two books for a bare number', () {
      final guesses = detectSeries([
        _book('1', title: 'Old', series: 'The Expanse', number: 1),
        _book('2', title: 'Caliban\'s War (the expanse, #2)'),
        _book('3', title: 'Discworld 3: Equal Rites'),
        _book('4', title: 'Discworld 4: Mort'),
        _book('5', title: 'Apollo 13: The Mission'),
      ]);
      expect([for (final g in guesses) g.describe()],
          ['Discworld #3', 'Discworld #4', 'The Expanse #2']);
    });
  });

  group('tag suggestions', () {
    test('subjects that fit your tags, and tags on the same author', () {
      final library = [
        _book('1', author: 'Brandon Sanderson', tags: ['Fantasy', 'Magic systems']),
        _book('2', author: 'Brandon Sanderson', tags: ['Fantasy']),
        _book('3', author: 'Other', tags: ['Science fiction', 'Dragons']),
      ];
      final book = _book('new', author: 'Brandon Sanderson');
      final suggestions = suggestTags(
        book,
        [...library, book],
        subjects: ['Epic fantasy', 'Dragons', 'Heists'],
      );
      final tags = [for (final s in suggestions) s.tag];
      expect(tags.first, 'Fantasy');
      expect(tags, contains('Dragons'));
      expect(tags, contains('Magic systems'));
      final heists = suggestions.firstWhere((s) => s.tag == 'Heists');
      expect(heists.isNew, isTrue);
    });

    test('subject fit', () {
      expect(subjectFit('Dragons', 'dragon'), 1);
      expect(subjectFit('Epic fantasy', 'fantasy'), 0.8);
      expect(subjectFit('Sciense fiction', 'science fiction'), 0.75);
      expect(subjectFit('History', 'fantasy'), 0);
    });
  });

  group('audiobook and book file', () {
    final ebook = EbookLink(
      path: 'x.pdf',
      name: 'x.pdf',
      bytes: 1,
      format: EbookFormat.pdf,
      addedAt: DateTime(2026),
      pageCount: 201,
      position: const EbookPosition(locator: '41', progress: 0.2),
    );

    test('both places, and whether they are apart', () {
      final book = _book(
        '1',
        audio: const AudioProgress(positionMs: 60 * 60000, trackCount: 2, track: 1),
      );
      final places = formatPositions(book, audio: _twoFiles, ebook: ebook)!;
      expect(places.audio, 0.5);
      expect(places.reader, 0.2);
      expect(places.apart, isTrue);
      expect(places.audioAhead, isTrue);
      expect(formatPositions(book, audio: _twoFiles), isNull);
    });

    test('the place in each for a share of the book', () async {
      final progress = audioProgressAt(_twoFiles, 0.75);
      expect(progress.track, 1);
      expect(progress.trackMs, 30 * 60000);
      expect(progress.positionMs, 90 * 60000);
      final page = await readerPositionAt(ebook, 0.5);
      expect(page!.locator, '101');
      final unknown = await readerPositionAt(
        EbookLink(
          path: 'y.pdf',
          name: 'y.pdf',
          bytes: 1,
          format: EbookFormat.pdf,
          addedAt: DateTime(2026),
        ),
        0.5,
      );
      expect(unknown, isNull);
    });
  });

  group('file matching', () {
    final books = [
      _book('1', title: 'The Name of the Wind', author: 'Patrick Rothfuss'),
      _book('2', title: 'Mistborn: The Final Empire', author: 'Brandon Sanderson'),
      _book('3', title: 'Mistborn 2', author: 'Brandon Sanderson'),
    ];

    test('a typo in the title or the author still matches', () {
      final matches = findMatchingBooks(
        books,
        title: 'The Name of the Wnid',
        author: 'Patrick Rothfus',
      );
      expect(matches.first.book.id, '1');
      expect(isSureMatch(matches), isTrue);
    });

    test('noise words and word order', () {
      expect(titleScore('The Name of the Wind', 'The Name of the Wind Unabridged'),
          greaterThanOrEqualTo(65));
      expect(titleScore('Mistborn 2', 'Mistborn 3'), 0);
      expect(titleScore('Wind and Truth', 'Truth and Wind'), 70);
    });
  });

  group('smart rewind', () {
    test('more the longer the pause', () {
      expect(rewindAfterPause(const Duration(seconds: 5)), Duration.zero);
      expect(rewindAfterPause(const Duration(seconds: 30)), const Duration(seconds: 2));
      expect(rewindAfterPause(const Duration(minutes: 5)), const Duration(seconds: 5));
      expect(rewindAfterPause(const Duration(minutes: 30)), const Duration(seconds: 10));
      expect(rewindAfterPause(const Duration(hours: 3)), const Duration(seconds: 20));
      expect(rewindAfterPause(const Duration(days: 2)), const Duration(seconds: 30));
    });

    test('the player goes back after a pause, not after a jump', () async {
      final repository = BookRepository(InMemoryBookStore());
      await repository.load();
      await repository.add(title: 'Dune', author: 'F', shelf: Shelf.inProgress);
      final id = repository.books.single.id;
      final library = AudioLibrary();
      await library.setLink(id, _twoFiles);
      final engine = FakeEngine(const [Duration(hours: 1), Duration(hours: 1)]);
      var now = DateTime(2026, 10, 31, 20);
      final controller = ListenController(
        repository: repository,
        library: library,
        files: FakeFiles({}),
        engine: () => engine,
        now: () => now,
        saveEvery: const Duration(hours: 1),
      )..smartRewind = true;
      addTearDown(controller.dispose);

      await controller.open(id);
      await pumpEventQueue();
      engine.position = const Duration(minutes: 10);
      await controller.pause();
      await pumpEventQueue();
      now = now.add(const Duration(minutes: 5));
      await controller.play();
      expect(engine.position, const Duration(minutes: 9, seconds: 55));

      await controller.pause();
      await pumpEventQueue();
      now = now.add(const Duration(hours: 2));
      await controller.seekTo(0, const Duration(minutes: 20));
      await controller.play();
      expect(engine.position, const Duration(minutes: 20));
    });
  });
}
