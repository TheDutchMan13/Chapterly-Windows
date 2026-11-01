import 'dart:convert';
import 'dart:typed_data';

import 'package:chapterly/audio/audio_bookmarks.dart';
import 'package:chapterly/audio/audio_library.dart';
import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/cover_hash.dart';
import 'package:chapterly/data/library_health.dart';
import 'package:chapterly/data/notes_search.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/data/quote_of_day.dart';
import 'package:chapterly/data/rating_predict.dart';
import 'package:chapterly/data/reading_time.dart';
import 'package:chapterly/data/stalled.dart';
import 'package:chapterly/data/sync_merge.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:chapterly/data/sync_three_way.dart';
import 'package:chapterly/ebook/ebook_library.dart';
import 'package:chapterly/models/audio_progress.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_format.dart';
import 'package:chapterly/models/quote.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

Book _book(
  String id, {
  String title = 'T',
  String author = 'A',
  Shelf shelf = Shelf.forLater,
  List<String> tags = const [],
  int? rating,
  int? pages,
  int? currentPage,
  BookFormat? format,
  String? isbn,
  String? coverUrl,
  String? notes,
  bool favorite = false,
  DateTime? startedAt,
  DateTime? finishedAt,
  List<LogEntry> log = const [],
  List<Quote> quotes = const [],
  AudioProgress? audio,
  DateTime? updatedAt,
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: shelf,
      addedAt: DateTime(2026),
      tags: tags,
      rating: rating,
      pages: pages,
      currentPage: currentPage,
      format: format,
      isbn: isbn,
      coverUrl: coverUrl,
      notes: notes,
      favorite: favorite,
      startedAt: startedAt,
      finishedAt: finishedAt,
      readingLog: log,
      quotes: quotes,
      audio: audio,
      updatedAt: updatedAt ?? DateTime(2026, 1, 1),
    );

Quote _quote(String text) => Quote(text: text, addedAt: DateTime(2026));

/// A picture for the cover tests: stripes, a gradient, or one colour.
Uint8List _picture(int width, int height, {String kind = 'stripes', int seed = 0}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = switch (kind) {
        'stripes' => ((x * 8 ~/ width) + seed).isEven ? 230 : 20,
        'checks' => (((x * 6 ~/ width) + (y * 6 ~/ height)).isEven) ? 240 : 10,
        'gradient' => (y * 255 ~/ height),
        _ => 128,
      };
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

const _code = 'ABCDEFGHJKMNPQRS';

class _Phone {
  final repository = BookRepository(InMemoryBookStore());
  late final SyncServer server;

  Future<void> start() async {
    await repository.load();
    server = SyncServer(
      token: _code,
      handleSync: (body) async {
        final remote = decodeSyncPayload(body);
        final local = repository.snapshot();
        final merged = mergeLibraries(
          local: local.books,
          localTombstones: local.tombstones,
          remote: remote.books,
          remoteTombstones: remote.tombstones,
        );
        await repository.applySynced(merged.books, merged.tombstones);
        return encodeSyncPayload(merged.books, merged.tombstones);
      },
    );
    await server.start(port: 0);
  }

  String get address => '127.0.0.1:${server.boundPort}';
}

void main() {
  group('predicted rating', () {
    final library = [
      for (var i = 0; i < 4; i++)
        _book('f$i', author: 'Brandon Sanderson', tags: ['fantasy'],
            shelf: Shelf.finished, rating: 5),
      for (var i = 0; i < 4; i++)
        _book('r$i', author: 'Writer $i', tags: ['romance'],
            shelf: Shelf.finished, rating: 2),
    ];

    test('follows the books most like it', () {
      final fantasy = predictRating(library,
          _book('x', author: 'Brandon Sanderson', tags: ['fantasy']))!;
      final romance = predictRating(library, _book('y', tags: ['romance']))!;
      expect(fantasy.stars, greaterThan(4.2));
      expect(romance.stars, lessThan(3));
      expect(fantasy.describe(), contains('similar books'));
    });

    test('needs enough rated books and something in common', () {
      expect(predictRating(library.take(3).toList(), _book('x', tags: ['fantasy'])), isNull);
      expect(predictRating(library, _book('z', author: 'Nobody', tags: ['cooking'])), isNull);
    });
  });

  group('reading time', () {
    test('your speed from log entries with pages and minutes', () {
      final speed = readingSpeed([
        _book('1', log: [
          LogEntry(date: DateTime(2026, 10, 1), pages: 30, minutes: 60),
          LogEntry(date: DateTime(2026, 10, 2), pages: 50, minutes: 60),
          LogEntry(date: DateTime(2026, 10, 3), pages: 99), // no minutes
        ]),
        _book('2', format: BookFormat.audiobook, log: [
          LogEntry(date: DateTime(2026, 10, 1), pages: 500, minutes: 10),
        ]),
      ]);
      expect(speed.yours, isTrue);
      expect(speed.pagesPerHour, 40);
      expect(readingSpeed([]).yours, isFalse);
    });

    test('pages at your speed, and what is left', () {
      const pace = ReadingSpeed(pagesPerHour: 30, yours: true);
      final time = readingTime(
        _book('1', pages: 300, currentPage: 150, shelf: Shelf.inProgress),
        pace: pace,
      )!;
      expect(time.totalMinutes, 600);
      expect(time.leftMinutes, 300);
      expect(time.describe(pagesPerHour: 30), contains('at your 30 pages an hour'));
      expect(readingTime(_book('2'), pace: pace), isNull);
    });

    test('an audiobook by its length and speed', () {
      const link = AudioLink(tracks: [
        AudioTrack(location: 'a', name: 'a.mp3', lengthMs: 600 * 60000),
      ]);
      final time = readingTime(
        _book('1', audio: const AudioProgress(positionMs: 300 * 60000)),
        pace: const ReadingSpeed(pagesPerHour: 40, yours: false),
        audio: link,
        speed: 1.5,
      )!;
      expect(time.listening, isTrue);
      expect(time.totalMinutes, 400);
      expect(time.leftMinutes, 200);
      expect(time.describe(), startsWith('About 6h 40m to listen'));
    });

    test('books that fit the time you have', () {
      const pace = ReadingSpeed(pagesPerHour: 60, yours: true);
      final books = [
        _book('short', pages: 50),
        _book('long', pages: 600),
        _book('nearly', pages: 300, currentPage: 280, shelf: Shelf.inProgress),
        _book('unknown'),
      ];
      final fits = fitsInTime(books, 60, (b) => readingTime(b, pace: pace));
      expect([for (final f in fits) f.book.id], ['nearly', 'short']);
      expect(fits.first.minutes, 20);
    });
  });

  group('stalled books', () {
    final now = DateTime(2026, 11, 1);

    test('by your own rhythm, with a two-week minimum', () {
      final books = [
        // You read every 2 days, so 14 days (the minimum) is the limit.
        _book('active', shelf: Shelf.inProgress, log: [
          for (var d = 1; d <= 29; d += 2)
            LogEntry(date: DateTime(2026, 10, d), pages: 10),
        ]),
        _book('stalled', shelf: Shelf.inProgress, log: [
          LogEntry(date: DateTime(2026, 9, 1), pages: 10),
          LogEntry(date: DateTime(2026, 9, 3), pages: 10),
        ]),
        _book('new', shelf: Shelf.inProgress, startedAt: DateTime(2026, 10, 25)),
        _book('done', shelf: Shelf.finished, log: [
          LogEntry(date: DateTime(2026, 1, 1), pages: 10),
        ]),
      ];
      final stalled = stalledBooks(books, now: now);
      expect([for (final s in stalled) s.book.id], ['stalled']);
      expect(stalled.single.idleDays, 59);
      expect(stalled.single.usualGap, 2);
    });

    test('keep waits another stretch', () {
      final books = [
        _book('stalled', shelf: Shelf.inProgress, startedAt: DateTime(2026, 8, 1)),
      ];
      expect(stalledBooks(books, now: now), hasLength(1));
      expect(
        stalledBooks(books, now: now, snoozed: {'stalled': DateTime(2026, 10, 28)}),
        isEmpty,
      );
    });
  });

  group('library health', () {
    test('ISBN check digits and ISBN-10 to ISBN-13', () {
      expect(isValidIsbn('0-306-40615-2'), isTrue);
      expect(isValidIsbn('0306406153'), isFalse);
      expect(isValidIsbn('978-0-306-40615-7'), isTrue);
      expect(isValidIsbn('9780306406158'), isFalse);
      expect(isValidIsbn('080442957X'), isTrue);
      expect(isValidIsbn('12345'), isFalse);
      expect(isbn10To13('0-306-40615-2'), '9780306406157');
      expect(isbn10To13('080442957X'), '9780804429573');
      expect(isbn10To13('0306406153'), isNull);
    });

    test('finds what is wrong or missing', () {
      final issues = checkLibrary([
        _book('ok', shelf: Shelf.finished, pages: 200, coverUrl: 'x',
            isbn: '9780306406157', startedAt: DateTime(2026, 1, 1),
            finishedAt: DateTime(2026, 2, 1)),
        _book('bad', isbn: '9780306406158', coverUrl: 'x'),
        _book('old', isbn: '0306406152', coverUrl: 'x'),
        _book('nodate', shelf: Shelf.finished, pages: 100, coverUrl: 'x'),
        _book('backwards', shelf: Shelf.finished, pages: 100, coverUrl: 'x',
            startedAt: DateTime(2026, 3, 1), finishedAt: DateTime(2026, 2, 1)),
        _book('past', shelf: Shelf.inProgress, pages: 100, currentPage: 150,
            startedAt: DateTime(2026, 1, 1), coverUrl: 'x'),
        _book('rated', rating: 4, coverUrl: 'x', author: ''),
      ]);
      List<String> ids(HealthIssueKind kind) =>
          [for (final b in issues[kind] ?? const <Book>[]) b.id];
      expect(ids(HealthIssueKind.badIsbn), ['bad']);
      expect(ids(HealthIssueKind.oldIsbn), ['old']);
      expect(ids(HealthIssueKind.noFinishDate), ['nodate']);
      expect(ids(HealthIssueKind.finishBeforeStart), ['backwards']);
      expect(ids(HealthIssueKind.pageBeyondEnd), ['past']);
      expect(ids(HealthIssueKind.ratedUnread), ['rated']);
      expect(ids(HealthIssueKind.noAuthor), ['rated']);
      expect(issues.containsKey(HealthIssueKind.noCover), isFalse);
      expect(issues.values.expand((b) => b).map((b) => b.id), isNot(contains('ok')));
    });
  });

  group('search notes and quotes', () {
    final books = [
      _book('1', title: 'Lighthouse', quotes: [
        _quote('The lighthouse kept its light burning through the storm.'),
        _quote('Nothing about the sea today.'),
      ]),
      _book('2', title: 'Other', notes: 'I loved the ending, the storm scene '
          'was long and slow and the sea went on and on and on for pages.'),
    ];
    final bookmarks = AudioBookmarks()
      ..add('2', AudioBookmark(
        track: 0, trackMs: 0, positionMs: 0, addedAt: DateTime(2026),
        note: 'Remember the lighthouse keeper',
      ));
    final ebooks = {
      '1': EbookLink(
        path: 'x', name: 'x', bytes: 1, format: EbookFormat.epub,
        addedAt: DateTime(2026),
        highlights: [
          EbookHighlight(
            locator: 'c:0:0', text: 'A storm was coming', addedAt: DateTime(2026),
            note: 'foreshadowing',
          ),
        ],
      ),
    };

    test('collects notes, quotes, highlights and bookmark notes', () {
      final docs = collectNotes(books, ebooks: ebooks, bookmarks: bookmarks);
      expect([for (final d in docs) d.source], containsAll(NoteSource.values));
    });

    test('rare words and short texts rank higher, typos are forgiven', () {
      final docs = collectNotes(books, ebooks: ebooks, bookmarks: bookmarks);
      final storm = searchNotes(docs, 'lighthouse storm');
      expect(storm.first.document.text, startsWith('The lighthouse kept'));
      final typo = searchNotes(docs, 'lighthose');
      expect(typo, isNotEmpty);
      expect(typo.first.document.text, contains('lighthouse'));
      expect(searchNotes(docs, 'the and'), isEmpty);
      expect(isMatchedWord('Storms', {'storm'}), isTrue);
    });
  });

  group('quote of the day', () {
    final books = [
      _book('1', rating: 5, quotes: [_quote('First quote, long enough')]),
      _book('2', rating: 2, quotes: [_quote('Second quote, long enough')]),
      _book('3', quotes: [_quote('short')]),
    ];
    final quotes = allQuotes(books);

    test('short quotes are skipped', () {
      expect(quotes, hasLength(2));
    });

    test('never seen first, then the longest ago; the same all day', () {
      final day1 = DateTime(2026, 11, 1, 8);
      final first = quoteOfTheDay(quotes, seen: {}, now: day1)!;
      // Both never seen: the higher-rated book is a little ahead.
      expect(first.book.id, '1');
      final seen = {first.key: day1};
      expect(quoteOfTheDay(quotes, seen: seen, now: day1.add(const Duration(hours: 9)))!.key,
          first.key);
      final day2 = DateTime(2026, 11, 2, 8);
      expect(quoteOfTheDay(quotes, seen: seen, now: day2)!.book.id, '2');
      expect(quoteOfTheDay(quotes, seen: seen, now: day1, skip: 1)!.book.id, '2');
    });

    test('seen days are kept as JSON', () {
      final seen = {'a': DateTime(2026, 11, 1)};
      expect(decodeSeen(encodeSeen(seen)), seen);
      expect(decodeSeen('nonsense'), isEmpty);
    });

    test('settings remember quotes and snoozes', () {
      final settings = AppSettings();
      final now = DateTime(2026, 11, 1);
      settings.markQuoteSeen('k', now);
      expect(settings.quoteSeen['k'], now);
      settings.hideQuoteToday(now);
      expect(settings.quoteHiddenToday(now), isTrue);
      expect(settings.quoteHiddenToday(DateTime(2026, 11, 2)), isFalse);
      settings.snoozeStalled('b', now);
      expect(settings.stalledSnoozed['b'], now);
    });
  });

  group('cover fingerprints', () {
    test('the same picture at another size is the same; others differ', () {
      final big = printCover(_picture(300, 450))!;
      final small = printCover(_picture(100, 150))!;
      final other = printCover(_picture(300, 450, kind: 'checks'))!;
      expect(hashDistance(big.hash, small.hash), lessThanOrEqualTo(5));
      expect(hashDistance(big.hash, other.hash), greaterThan(10));
      expect(big.width, 300);
      expect(coverProblem(big), isNull);
    });

    test('tiny, blank and wide covers look wrong', () {
      expect(coverProblem(printCover(_picture(40, 60))!), startsWith('Tiny'));
      expect(coverProblem(printCover(_picture(300, 450, kind: 'plain'))!),
          startsWith('Blank'));
      expect(coverProblem(printCover(_picture(600, 300))!), startsWith('Wider'));
      expect(printCover(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('a check finds books sharing a cover and remembers prints', () async {
      final stripes = _picture(200, 300);
      final checks = _picture(200, 300, kind: 'checks');
      final dataCover = 'data:image/png;base64,${base64Encode(checks)}';
      var downloads = 0;
      final client = MockClient((request) async {
        downloads++;
        return request.url.path.contains('missing')
            ? http.Response('no', 404)
            : http.Response.bytes(stripes, 200);
      });
      final books = [
        _book('a', coverUrl: 'https://covers.example/a.png'),
        _book('b', coverUrl: 'https://covers.example/b.png'),
        _book('c', coverUrl: dataCover),
        _book('d', coverUrl: 'https://covers.example/missing.png'),
        _book('e'),
      ];
      final prints = CoverPrints();
      final progress = <int>[];
      final report = await checkCovers(
        books,
        prints: prints,
        client: client,
        onProgress: (done, _) => progress.add(done),
      );
      expect(report.sameCover.single.map((b) => b.id), ['a', 'b']);
      expect(report.unreadable.single.id, 'd');
      expect(progress.last, 4);
      expect(downloads, 3);
      await checkCovers(books, prints: prints, client: client);
      expect(downloads, 4); // only the missing one again
    });
  });

  group('three-way sync merge', () {
    test('lists keep additions and removals from both sides', () {
      expect(
        mergeLists(['a', 'b', 'c'], ['a', 'c', 'd'], ['a', 'b', 'c', 'e']),
        ['a', 'c', 'd', 'e'],
      );
    });

    test('fields changed on one side each are both kept', () {
      final merged = mergeBookJson(
        {'rating': 3, 'tags': ['x'], 'notes': 'n', 'audio': {'positionMs': 1}},
        {'rating': 5, 'tags': ['x'], 'notes': 'mine', 'audio': {'positionMs': 1}},
        {'rating': 3, 'tags': ['x', 'y'], 'notes': 'theirs', 'audio': {'positionMs': 9}},
        preferLocal: false,
      );
      expect(merged['rating'], 5);
      expect(merged['tags'], ['x', 'y']);
      expect(merged['notes'], 'theirs'); // changed on both: the newer copy
      expect(merged['audio'], {'positionMs': 9});
    });

    test('only books the newest-copy rule gets wrong are resolved', () {
      final base = _book('1', rating: 3, tags: ['x']);
      final baseJson = {
        '1': jsonDecode(jsonEncode(base.toJson())) as Map<String, Object?>,
        '2': jsonDecode(jsonEncode(_book('2').toJson())) as Map<String, Object?>,
      };
      final now = DateTime(2026, 6, 1);
      final resolved = resolveConflicts(
        base: baseJson,
        local: [
          _book('1', rating: 5, tags: ['x'], updatedAt: DateTime(2026, 2, 1)),
          _book('2', rating: 4, updatedAt: DateTime(2026, 2, 1)),
        ],
        remote: [
          _book('1', rating: 3, tags: ['x', 'y'], updatedAt: DateTime(2026, 3, 1)),
          _book('2', updatedAt: DateTime(2026, 1, 1)),
        ],
        now: now,
      );
      expect(resolved, hasLength(1));
      expect(resolved.single.rating, 5);
      expect(resolved.single.tags, ['x', 'y']);
      expect(resolved.single.updatedAt, now);
    });

    test('a change on each side survives a real sync', () async {
      final phone = _Phone();
      await phone.start();
      addTearDown(phone.server.stop);
      final pc = BookRepository(InMemoryBookStore());
      await pc.load();
      final settings = AppSettings();
      final sync = PcSync(
        repository: pc,
        settings: settings,
        codeStore: MemoryCodeStore(),
        client: SyncClient(pingTimeout: const Duration(seconds: 2)),
      );
      await pc.replaceAll([_book('a', rating: 3, tags: ['x'])]);
      expect(await sync.pair(address: phone.address, code: _code), isNull);
      expect(sync.base.isEmpty, isFalse);

      // The PC rates it; later the phone adds a tag.
      await pc.setRating('a', 5);
      final onPhone = phone.repository.byId('a')!;
      await phone.repository.replaceAll([
        onPhone.copyWith(
          tags: ['x', 'y'],
          updatedAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      ]);

      expect(await sync.syncNow(), isNull);
      expect(pc.byId('a')!.rating, 5);
      expect(pc.byId('a')!.tags, ['x', 'y']);
      expect(phone.repository.byId('a')!.rating, 5);
      expect(phone.repository.byId('a')!.tags, ['x', 'y']);
    });

    test('the last-synced copy is kept in a file', () async {
      final base = SyncBase();
      await base.save([_book('a', rating: 4)]);
      expect(base.books['a']!['rating'], 4);
    });
  });
}
