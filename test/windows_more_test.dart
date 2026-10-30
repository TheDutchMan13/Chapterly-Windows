import 'dart:typed_data';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/bulk_add.dart';
import 'package:chapterly/data/cover_image.dart';
import 'package:chapterly/data/open_library_client.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/data/sync_merge.dart';
import 'package:chapterly/data/sync_plan.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:chapterly/data/table_columns.dart';
import 'package:chapterly/data/window_control.dart';
import 'package:chapterly/data/year_review_pdf.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/mini_timer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

const _code = 'ABCDEFGHJKMNPQRS';

Book _book(
  String id,
  String title, {
  String author = '',
  Shelf shelf = Shelf.forLater,
  int minute = 0,
  int? rating,
  int? pages,
  DateTime? finishedAt,
  DateTime? deletedAt,
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      shelf: shelf,
      addedAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1, 0, minute),
      rating: rating,
      pages: pages,
      finishedAt: finishedAt,
      deletedAt: deletedAt,
    );

/// A phone running the real sync server.
Future<SyncServer> _startPhone(BookRepository phone) async {
  await phone.load();
  final server = SyncServer(
    token: _code,
    handleSync: (body) async {
      final remote = decodeSyncPayload(body);
      final local = phone.snapshot();
      final merged = mergeLibraries(
        local: local.books,
        localTombstones: local.tombstones,
        remote: remote.books,
        remoteTombstones: remote.tombstones,
      );
      await phone.applySynced(merged.books, merged.tombstones);
      return encodeSyncPayload(merged.books, merged.tombstones);
    },
  );
  await server.start(port: 0);
  return server;
}

void main() {
  group('sync plan', () {
    test('describes what changed in a book', () {
      final before = _book('1', 'Dune', rating: 3);
      final after = before.copyWith(
        shelf: Shelf.finished,
        rating: () => 5,
        favorite: true,
      );
      expect(describeChanges(before, after), [
        'Moved to Finished',
        'Rating 3 → 5',
        'Added to favorites',
      ]);
      expect(
        describeChanges(before, before.copyWith(rating: () => null)),
        ['Rating removed'],
      );
      expect(describeChanges(before, before), ['Details changed']);
    });

    test('lists added, changed, trashed, restored and deleted books', () {
      final before = [
        _book('keep', 'Same'),
        _book('edit', 'Edited'),
        _book('trash', 'Trashed'),
        _book('back', 'Restored', deletedAt: DateTime(2026, 1, 1)),
        _book('gone', 'Gone'),
      ];
      final after = [
        before[0],
        before[1].copyWith(
          shelf: Shelf.inProgress,
          updatedAt: DateTime(2026, 2, 1),
        ),
        before[2].copyWith(
          deletedAt: () => DateTime(2026, 2, 1),
          updatedAt: DateTime(2026, 2, 1),
        ),
        before[3].copyWith(
          deletedAt: () => null,
          updatedAt: DateTime(2026, 2, 1),
        ),
        _book('new', 'New'),
      ];
      final changes = diffLibraries(before, after);
      final byId = {for (final c in changes) c.id: c};
      expect(byId.containsKey('keep'), isFalse);
      expect(byId['new']!.kind, ChangeKind.added);
      expect(byId['edit']!.kind, ChangeKind.changed);
      expect(byId['edit']!.details, ['Moved to In progress']);
      expect(byId['trash']!.kind, ChangeKind.trashed);
      expect(byId['back']!.kind, ChangeKind.restored);
      expect(byId['gone']!.kind, ChangeKind.deleted);
      // Sorted by kind, so additions come first and deletions last.
      expect(changes.first.kind, ChangeKind.added);
      expect(changes.last.kind, ChangeKind.deleted);
    });

    test('works out both sides the way a real sync would', () {
      final shared = _book('shared', 'Shared');
      final plan = planSync(
        phoneBooks: [shared, _book('phone', 'From the phone')],
        phoneTombstones: const {},
        pcBooks: [
          shared.copyWith(rating: () => 4, updatedAt: DateTime(2026, 3, 1)),
          _book('pc', 'From the PC'),
        ],
        pcTombstones: const {},
      );
      expect([for (final c in plan.onPc) c.id], ['phone']);
      expect(
        [for (final c in plan.onPhone) c.id]..sort(),
        ['pc', 'shared'],
      );
      expect(plan.removals, 0);
      expect(plan.isEmpty, isFalse);
    });

    test('a book deleted for good on the PC is a removal on the phone', () {
      final plan = planSync(
        phoneBooks: [_book('x', 'Old book')],
        phoneTombstones: const {},
        pcBooks: const [],
        pcTombstones: {'x': DateTime(2026, 5, 1)},
      );
      expect(plan.onPhone.single.kind, ChangeKind.deleted);
      expect(plan.removals, 1);
      expect(plan.signature, 'phone:x:deleted');
    });

    test('says how long ago the last sync was', () {
      final now = DateTime(2026, 10, 30, 12);
      expect(syncedAgoText(null, now), 'Not synced yet');
      expect(syncedAgoText(now, now), 'Synced just now');
      expect(
        syncedAgoText(now.subtract(const Duration(minutes: 5)), now),
        'Synced 5 min ago',
      );
      expect(
        syncedAgoText(now.subtract(const Duration(hours: 1)), now),
        'Synced 1 hour ago',
      );
      expect(
        syncedAgoText(now.subtract(const Duration(hours: 30)), now),
        'Synced yesterday',
      );
      expect(
        syncedAgoText(now.subtract(const Duration(days: 4)), now),
        'Synced 4 days ago',
      );
    });
  });

  group('preview and automatic sync with a real phone', () {
    late BookRepository pc;
    late BookRepository phone;
    late AppSettings settings;
    late PcSync sync;
    late SyncServer server;

    setUp(() async {
      pc = BookRepository(InMemoryBookStore());
      await pc.load();
      phone = BookRepository(InMemoryBookStore());
      server = await _startPhone(phone);
      settings = AppSettings();
      sync = PcSync(
        repository: pc,
        settings: settings,
        codeStore: MemoryCodeStore(),
        client: SyncClient(pingTimeout: const Duration(seconds: 2)),
      );
      expect(
        await sync.pair(address: '127.0.0.1:${server.boundPort}', code: _code),
        isNull,
      );
    });

    tearDown(() => server.stop());

    test('a preview shows both sides and changes nothing', () async {
      await phone.add(title: 'Phone book', author: 'A', shelf: Shelf.forLater);
      await pc.add(title: 'PC book', author: 'B', shelf: Shelf.finished);

      final result = await sync.preview();
      expect(result.problem, isNull);
      final plan = result.plan!;
      expect([for (final c in plan.onPc) c.title], ['Phone book']);
      expect([for (final c in plan.onPhone) c.title], ['PC book']);

      // Nothing moved yet.
      expect([for (final b in phone.books) b.title], ['Phone book']);
      expect([for (final b in pc.books) b.title], ['PC book']);

      expect(await sync.syncNow(), isNull);
      expect(phone.books.length, 2);
      expect(pc.books.length, 2);
    });

    test('an automatic sync holds back removals for review', () async {
      await pc.add(title: 'Doomed', author: 'C', shelf: Shelf.forLater);
      expect(await sync.syncNow(), isNull);
      expect(phone.books.length, 1);

      await pc.deleteForever(pc.books.single.id);
      expect(await sync.autoSync(), isFalse);
      expect(sync.pendingReview?.removals, 1);
      expect(phone.books.length, 1, reason: 'the phone keeps it for now');

      sync.dismissPending();
      expect(sync.pendingReview, isNull);
      expect(await sync.autoSync(), isFalse);
      expect(sync.pendingReview, isNull, reason: 'the same plan stays hidden');

      expect(await sync.syncNow(), isNull);
      expect(phone.books, isEmpty);
    });

    test('an automatic sync applies harmless changes by itself', () async {
      await phone.add(title: 'New on phone', author: 'D', shelf: Shelf.forLater);
      expect(await sync.autoSync(), isTrue);
      expect(pc.books.single.title, 'New on phone');
      expect(sync.pendingReview, isNull);
    });

    test('with the preview switched off, removals sync straight away', () async {
      await pc.add(title: 'Doomed', author: 'C', shelf: Shelf.forLater);
      expect(await sync.syncNow(), isNull);
      await pc.deleteForever(pc.books.single.id);
      settings.setReviewSync(false);
      expect(await sync.autoSync(), isTrue);
      expect(phone.books, isEmpty);
    });

    test('a background tick syncs when due and reports changes', () async {
      final reported = <int>[];
      sync.onBackgroundSync = reported.add;
      await phone.add(title: 'Later', author: 'E', shelf: Shelf.forLater);
      final now = DateTime.now();

      // Paired a moment ago, so nothing is due yet.
      await sync.runBackgroundTick(now);
      expect(pc.books, isEmpty);

      await sync.runBackgroundTick(now.add(const Duration(minutes: 16)));
      expect(pc.books.single.title, 'Later');
      expect(reported, [1]);
    });
  });

  group('background sync timing', () {
    test('only when paired, switched on and the interval has passed', () {
      final settings = AppSettings();
      final sync = PcSync(
        repository: BookRepository(InMemoryBookStore()),
        settings: settings,
        codeStore: MemoryCodeStore(),
      );
      expect(sync.backgroundSyncDue(DateTime.now()), isFalse);
      settings.setSyncEveryMinutes(0);
      expect(settings.syncEveryMinutes, 0);
    });
  });

  group('bulk add', () {
    test('cleans up the pasted list', () {
      expect(
        parseBulkLines('  Dune\n\n- The Hobbit\n* dune\n1. Emma\r\n2) Persuasion'),
        ['Dune', 'The Hobbit', 'Emma', 'Persuasion'],
      );
    });

    test('recognises ISBNs and checks their digits', () {
      expect(isbnFromLine('978-0-441-01359-3'), '9780441013593');
      expect(isbnFromLine('ISBN: 0441013597'), '0441013597');
      expect(isbnFromLine('080442957X'), '080442957X');
      expect(isbnFromLine('9780441013594'), isNull);
      expect(isbnFromLine('Dune'), isNull);
    });

    test('splits a title from its author', () {
      expect(
        splitTitleAuthor('Klara and the Sun by Kazuo Ishiguro'),
        (title: 'Klara and the Sun', author: 'Kazuo Ishiguro'),
      );
      expect(
        splitTitleAuthor('Dune - Frank Herbert'),
        (title: 'Dune', author: 'Frank Herbert'),
      );
      expect(splitTitleAuthor('Emma'), (title: 'Emma', author: ''));
    });

    test('spots books already in the library', () {
      final library = [
        _book('1', 'Dune', author: 'Frank Herbert'),
        _book('2', 'Emma', author: 'Jane Austen', deletedAt: DateTime(2026)),
      ];
      expect(alreadyInLibrary(library, 'dune', ''), isTrue);
      expect(alreadyInLibrary(library, 'Dune!', 'frank herbert'), isTrue);
      expect(alreadyInLibrary(library, 'Dune', 'Someone Else'), isFalse);
      expect(alreadyInLibrary(library, 'Emma', ''), isFalse,
          reason: 'the trash does not count');
    });

    test('looks everything up and marks what to add', () async {
      final items = [
        for (final line in ['Dune', 'Unknown thing', '9780441013594', 'Emma'])
          BulkItem(line),
      ];
      var updates = 0;
      await lookUpAll(
        items,
        lookUp: (line) async {
          if (line == 'Emma') throw Exception('offline');
          if (line != 'Dune') return null;
          return const OpenLibraryBook(title: 'Dune', author: 'Frank Herbert');
        },
        library: [_book('1', 'Dune', author: 'Frank Herbert')],
        onUpdate: () => updates++,
        workers: 2,
      );
      expect(updates, 4);
      expect(items[0].status, BulkStatus.found);
      expect(items[0].owned, isTrue);
      expect(items[0].include, isFalse);
      expect(items[1].status, BulkStatus.notFound);
      expect(items[1].include, isTrue, reason: 'added as typed');
      expect(items[2].isbn, isNull, reason: 'bad check digit');
      expect(items[3].status, BulkStatus.failed);
      expect(items[3].include, isTrue);
    });

    test('an ISBN with no match cannot be added', () async {
      final item = BulkItem('9780441013593');
      await lookUpAll(
        [item],
        lookUp: (_) async => null,
        library: const [],
        onUpdate: () {},
      );
      expect(item.addable, isFalse);
      expect(item.include, isFalse);
    });
  });

  group('table view', () {
    final books = [
      _book('a', 'Banana', rating: 3, pages: 200),
      _book('b', 'apple', rating: 5),
      _book('c', 'Cherry', pages: 100),
    ];

    test('sorts by a column with empty cells last both ways', () {
      List<String> titles(List<Book> list) => [for (final b in list) b.title];
      expect(
        titles(sortByColumn(books, TableColumn.title, ascending: true)),
        ['apple', 'Banana', 'Cherry'],
      );
      expect(
        titles(sortByColumn(books, TableColumn.rating, ascending: false)),
        ['apple', 'Banana', 'Cherry'],
      );
      expect(
        titles(sortByColumn(books, TableColumn.pages, ascending: true)),
        ['Cherry', 'Banana', 'apple'],
      );
      expect(
        titles(sortByColumn(books, TableColumn.pages, ascending: false)),
        ['Banana', 'Cherry', 'apple'],
      );
    });

    test('shows each cell as text', () {
      String text(TableColumn column) => cellText(
            books.first,
            column,
            date: (d) => '${d.year}',
            rating: (r) => '$r stars',
          );
      expect(text(TableColumn.rating), '3 stars');
      expect(text(TableColumn.pages), '200');
      expect(text(TableColumn.shelf), 'For later');
      expect(text(TableColumn.finished), '');
      expect(text(TableColumn.added), '2026');
    });

    test('title and cover can be changed', () async {
      final repository = BookRepository(InMemoryBookStore());
      await repository.load();
      await repository.add(title: 'Old', author: 'X', shelf: Shelf.forLater);
      final id = repository.books.single.id;
      await repository.setTitle(id, '  New  ');
      expect(repository.byId(id)!.title, 'New');
      await repository.setTitle(id, '   ');
      expect(repository.byId(id)!.title, 'New');
      await repository.setCover(id, 'data:image/jpeg;base64,AAAA');
      expect(repository.byId(id)!.coverUrl, 'data:image/jpeg;base64,AAAA');
      await repository.setCover(id, null);
      expect(repository.byId(id)!.coverUrl, isNull);
    });
  });

  group('covers from the PC', () {
    test('recognises picture files', () {
      expect(isCoverImageFile(r'C:\Pics\cover.JPG'), isTrue);
      expect(isCoverImageFile('cover.webp'), isTrue);
      expect(isCoverImageFile('backup.json'), isFalse);
      expect(isCoverImageFile('noextension'), isFalse);
    });

    test('shrinks a big picture to a small JPEG data cover', () {
      final picture = img.Image(width: 1200, height: 1800);
      img.fill(picture, color: img.ColorRgb8(200, 100, 50));
      final png = Uint8List.fromList(img.encodePng(picture));

      final cover = shrinkToDataCover(png)!;
      expect(cover, startsWith('data:image/jpeg;base64,'));
      expect(isDataCover(cover), isTrue);
      final decoded = img.decodeJpg(bytesFromDataCover(cover)!)!;
      expect(decoded.width, coverWidth);
      expect(decoded.height, 600);
      expect(cover.length, lessThan(100000));
    });

    test('leaves a small picture its size, and rejects non-pictures', () {
      final picture = img.Image(width: 100, height: 150);
      final cover =
          shrinkToDataCover(Uint8List.fromList(img.encodePng(picture)))!;
      expect(img.decodeJpg(bytesFromDataCover(cover)!)!.width, 100);
      expect(shrinkToDataCover(Uint8List.fromList([1, 2, 3])), isNull);
      expect(bytesFromDataCover('https://example.com/a.jpg'), isNull);
    });
  });

  group('year in review PDF', () {
    final books = [
      _book(
        'a',
        'Second',
        author: 'B',
        shelf: Shelf.finished,
        rating: 4,
        pages: 300,
        finishedAt: DateTime(2026, 6, 1),
      ),
      _book(
        'b',
        'First',
        author: 'A',
        shelf: Shelf.finished,
        finishedAt: DateTime(2026, 2, 1),
      ),
      _book(
        'c',
        'Last year',
        shelf: Shelf.finished,
        finishedAt: DateTime(2025, 6, 1),
      ),
      _book(
        'd',
        'Binned',
        shelf: Shelf.finished,
        finishedAt: DateTime(2026, 3, 1),
        deletedAt: DateTime(2026, 4, 1),
      ),
    ];

    test('lists the books finished that year in order', () {
      final reads = finishedIn(books, 2026);
      expect([for (final r in reads) r.title], ['First', 'Second']);
      expect(reads.last.rating, 4);
      expect(reads.last.pages, 300);
    });

    test('counts a book read twice in the same year twice', () {
      final twice = books.first.copyWith(
        previousReadings: [Reading(finishedAt: DateTime(2026, 1, 5))],
      );
      expect(finishedIn([twice], 2026).length, 2);
    });

    test('makes a PDF', () async {
      final bytes = await buildYearReviewPdf(books, 2026);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final empty = await buildYearReviewPdf(const [], 2020);
      expect(String.fromCharCodes(empty.take(5)), '%PDF-');
    });
  });

  group('small timer window', () {
    test('shrinks to a small window on top and puts it back', () async {
      final window = NoWindowControl()
        ..bounds = const Rect.fromLTWH(100, 100, 1200, 800)
        ..maximized = true;
      final mini = MiniTimer(window: window);
      final watch = ReadingStopwatch();
      addTearDown(watch.dispose);

      await mini.enter(watch);
      expect(mini.active, isTrue);
      expect(mini.stopwatch, same(watch));
      expect(window.onTop, isTrue);
      expect(window.maximized, isFalse);
      expect(window.bounds.size, MiniTimer.size);
      expect(window.bounds.right, 1300 - 24);
      expect(window.minimumSize.width, lessThan(MiniTimer.size.width));

      await mini.leave();
      expect(mini.active, isFalse);
      expect(window.onTop, isFalse);
      expect(window.bounds, const Rect.fromLTWH(100, 100, 1200, 800));
      expect(window.minimumSize, normalMinimumSize);
      expect(window.maximized, isTrue);
    });

    test('the stopwatch keeps time and shows a clock', () {
      expect(formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '01:02:03');
      final watch = ReadingStopwatch();
      addTearDown(watch.dispose);
      expect(watch.isRunning, isFalse);
      watch.toggle();
      expect(watch.isRunning, isTrue);
      watch.toggle();
      expect(watch.isRunning, isFalse);
    });
  });

  group('settings', () {
    test('sync preview, sync interval and table view are remembered',
        () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      expect(settings.reviewSync, isTrue);
      expect(settings.syncEveryMinutes, 15);
      settings.setReviewSync(false);
      settings.setSyncEveryMinutes(30);
      settings.setDisplay(DisplayMode.table);

      final again = await AppSettings.load();
      expect(again.reviewSync, isFalse);
      expect(again.syncEveryMinutes, 30);
      expect(again.display, DisplayMode.table);
    });
  });
}
