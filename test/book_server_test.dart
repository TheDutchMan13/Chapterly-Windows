import 'dart:convert';
import 'dart:io';

import 'package:chapterly/audio/audio_library.dart';
import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/ebook/ebook_library.dart';
import 'package:chapterly/models/audio_bookmark.dart';
import 'package:chapterly/models/audio_progress.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/book_format.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/server_screen.dart';
import 'package:chapterly/data/sync_covers.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_three_way.dart';
import 'package:chapterly/data/wish_list.dart';
import 'package:chapterly/server/library_sync.dart';
import 'package:chapterly/server/server_client.dart';
import 'package:chapterly/server/server_downloads.dart';
import 'package:chapterly/server/server_platform.dart';
import 'package:chapterly/server/server_state.dart';
import 'package:chapterly/server/server_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'server_fake.dart';

AudioBookmark _mark(int n, {String note = ''}) => AudioBookmark(
      track: 0,
      trackMs: n * 1000,
      positionMs: n * 1000,
      addedAt: DateTime(2026, 2, n, 10),
      note: note,
    );

/// A phone with a library, the reader's and player's parts, and a server.
class _Phone {
  _Phone(this.server);

  final FakeServer server;
  final repository = BookRepository(InMemoryBookStore());
  final ebooks = EbookLibrary();
  final audio = AudioLibrary();
  final state = ServerState();
  final open = <String>{};
  final moved = <String, AudioProgress>{};
  late final Directory dir;
  late final ServerSync sync;
  late final ServerDownloads downloads;
  final settings = AppSettings();
  late final LibrarySync library;

  Future<void> setUp() async {
    await repository.load();
    dir = await Directory.systemTemp.createTemp('chapterly_server_test');
    sync = ServerSync(
      state: state,
      repository: repository,
      ebooks: ebooks,
      isOpen: (bookId, kind) => open.contains(bookId),
      onAudioMoved: (bookId, progress) async => moved[bookId] = progress,
      clientFor: (address, token) => server.client(token: token),
      sendAfter: const Duration(hours: 1),
    );
    downloads = ServerDownloads(
      sync: sync,
      repository: repository,
      ebooks: ebooks,
      booksDir: Directory('${dir.path}/books'),
      audio: audio,
      audioDir: Directory('${dir.path}/audio'),
    );
    library = LibrarySync(
      sync: sync,
      repository: repository,
      settings: settings,
      base: SyncBase(),
    );
    await state.connect(Uri.parse('http://100.1.2.3:8780'), server.token, 'hans');
  }

  Future<void> tearDown() async {
    sync.dispose();
    await dir.delete(recursive: true);
  }

  Future<ServerBook> serverBook(String id) async {
    final page = await server.client().books();
    return page.books.firstWhere((b) => b.id == id);
  }

  Future<String> download(String id) async {
    final result = await downloads.download(await serverBook(id));
    expect(result.problem, isNull);
    return result.bookId!;
  }

  ServerLink ebook(String bookId) => state.linkFor(bookId, 'ebook')!;
  ServerLink audiobook(String bookId) => state.linkFor(bookId, 'audiobook')!;

  Future<void> readTo(String bookId, double fraction, {String cfi = 'epubcfi(/6/4)'}) =>
      ebooks.setPosition(bookId, EbookPosition(locator: cfi, progress: fraction));
}

/// The file behind a player location: a file:// address on the phone, a
/// path on the PC.
String _audioPath(String location) =>
    location.startsWith('file:') ? Uri.parse(location).toFilePath() : location;

class _MemoryTokens implements TokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> delete() async => value = null;
}

void main() {
  group('the server address you type', () {
    test('gets http and the default port', () {
      expect(parseServerAddress('100.72.125.106:8780').toString(),
          'http://100.72.125.106:8780');
      expect(parseServerAddress('100.72.125.106').toString(),
          'http://100.72.125.106:8780');
      expect(parseServerAddress(' http://box:9000/opds ').toString(),
          'http://box:9000');
      expect(parseServerAddress('https://books.example').toString(),
          'https://books.example');
      expect(parseServerAddress(''), isNull);
      expect(parseServerAddress('ftp://box'), isNull);
    });
  });

  group('places as the server keeps them', () {
    test('a PDF page and this reader\'s EPUB places come back', () {
      const pdf = EbookPosition(locator: '12', progress: 0.3);
      final text = encodeEbookPosition(EbookFormat.pdf, pdf);
      expect(text, 'pdf-page:12');
      expect(decodeEbookPosition(EbookFormat.pdf, text, 0.3)!.locator, '12');
      const epub = EbookPosition(locator: 'epubcfi(/6/8!/4/2)', progress: 0.5);
      final epubText = encodeEbookPosition(EbookFormat.epub, epub);
      expect(epubText, '$localEpubPositionKind:epubcfi(/6/8!/4/2)');
      expect(decodeEbookPosition(EbookFormat.epub, epubText, 0.5)!.locator,
          'epubcfi(/6/8!/4/2)');
    });

    test('another reader\'s EPUB place becomes how far through the book', () {
      final across = decodeEbookPosition(EbookFormat.epub, 'epub-other:3|120', 0.4)!;
      expect(across.locator, progressLocator(0.4));
      expect(progressFromLocator(across.locator), 0.4);
      // ...and is sent on as such, never as this reader's own place.
      expect(encodeEbookPosition(EbookFormat.epub, across), 'epub-progress:0.40000');
      expect(decodeEbookPosition(EbookFormat.epub, 'epub-progress:0.40000', 0.4)!.locator,
          progressLocator(0.4));
    });

    test('the wrong kind of place is not used', () {
      expect(decodeEbookPosition(EbookFormat.pdf, '$localEpubPositionKind:x', 0.4), isNull);
      expect(decodeEbookPosition(EbookFormat.pdf, 'pdf-page:abc', 0.4), isNull);
      expect(decodeEbookPosition(EbookFormat.epub, '', 0.4), isNull);
    });

    test('audiobook places go both ways', () {
      const progress = AudioProgress(
        positionMs: 90000, lengthMs: 600000, track: 1, trackMs: 30000, trackCount: 3,
      );
      final back = decodeAudioPosition(encodeAudioPosition(progress))!;
      expect([back.positionMs, back.track, back.trackMs, back.trackCount],
          [90000, 1, 30000, 3]);
      expect(decodeAudioPosition('pdf-page:3'), isNull);
      expect(decodeAudioPosition('audio:not json'), isNull);
    });
  });

  group('bookmark changes', () {
    test('the first sync sends everything, dated when added', () {
      final changes = bookmarkChanges(
        base: null,
        local: [_mark(1, note: 'one')],
        now: '2026-11-02T00:00:00.000Z',
      );
      expect(changes.single.note, 'one');
      expect(changes.single.updatedAt, DateTime(2026, 2, 1, 10).toUtc().toIso8601String());
      expect(changes.single.deletedAt, isNull);
    });

    test('added, edited and deleted since the last sync', () {
      final base = bookmarkBase([_mark(1, note: 'one'), _mark(2, note: 'two')]);
      final changes = bookmarkChanges(
        base: base,
        local: [_mark(1, note: 'one, edited'), _mark(3, note: 'three')],
        now: 'NOW',
      );
      final byNote = {for (final c in changes) c.note: c};
      expect(byNote['one, edited']!.updatedAt, 'NOW');
      expect(byNote['three']!.updatedAt, isNot('NOW'));
      expect(byNote['two']!.deletedAt, 'NOW');
      expect(byNote['two']!.positionMs, 2000);
      expect(changes, hasLength(3));
      expect(bookmarkChanges(base: bookmarkBase([_mark(1)]), local: [_mark(1)], now: 'NOW'),
          isEmpty);
    });
  });

  group('syncing places', () {
    late FakeServer server;
    late _Phone phone;

    setUp(() async {
      server = FakeServer()
        ..addBook('dune', 'Dune', author: 'Frank Herbert')
        ..addBook('pdf', 'Foundation', author: 'Isaac Asimov', format: 'pdf')
        ..addBook('hail', 'Project Hail Mary',
            author: 'Andy Weir', kind: 'audiobook', format: 'm4b', durationMs: 600000);
      phone = _Phone(server);
      await phone.setUp();
    });

    tearDown(() => phone.tearDown());

    test('a place read here is sent once', () async {
      final id = await phone.download('dune');
      await phone.readTo(id, 0.42);
      await phone.sync.send();
      expect(server.progress['dune']!['fraction'], 0.42);
      expect(server.progress['dune']!['position'], '$localEpubPositionKind:epubcfi(/6/4)');
      final puts = server.requests.where((r) => r == 'PUT /v1/progress/dune').length;
      await phone.sync.send();
      expect(server.requests.where((r) => r == 'PUT /v1/progress/dune').length, puts);
    });

    test('a place that could not be sent goes next time', () async {
      final id = await phone.download('dune');
      await phone.readTo(id, 0.3);
      server.away = true;
      await phone.sync.send();
      expect(phone.ebook(id).dirty, isTrue);
      expect(phone.sync.problem, contains('cannot reach'));
      server.away = false;
      await phone.sync.syncNow();
      expect(server.progress['dune']!['fraction'], 0.3);
      expect(phone.ebook(id).dirty, isFalse);
      expect(phone.sync.problem, isNull);
    });

    test('a further place from another device is taken, one behind is not',
        () async {
      final id = await phone.download('dune');
      await phone.readTo(id, 0.2);
      await phone.sync.send();
      server.save('dune', 0.6, '$localEpubPositionKind:epubcfi(/6/20)');
      expect(await phone.sync.receive(), 1);
      expect(phone.ebooks.linkFor(id)!.position!.locator, 'epubcfi(/6/20)');
      expect(phone.ebooks.linkFor(id)!.position!.progress, 0.6);
      // Nothing new: nothing moves, and the taken place is not sent back.
      final puts = server.requests.where((r) => r.startsWith('PUT')).length;
      expect(await phone.sync.receive(), 0);
      await phone.sync.send();
      expect(server.requests.where((r) => r.startsWith('PUT')).length, puts);
    });

    test('a book open in the reader is never moved under you', () async {
      final id = await phone.download('dune');
      await phone.readTo(id, 0.1);
      await phone.sync.send();
      server.save('dune', 0.9, '$localEpubPositionKind:far');
      phone.open.add(id);
      expect(await phone.sync.receive(), 0);
      expect(phone.ebooks.linkFor(id)!.position!.progress, 0.1);
      phone.open.clear();
      expect(await phone.sync.receive(), 1);
    });

    test('a place from the other device\'s reader is found by how far in',
        () async {
      final other = localEpubPositionKind == 'epub-cfi' ? 'epub-win' : 'epub-cfi';
      final id = await phone.download('dune');
      await phone.readTo(id, 0.1);
      await phone.sync.send();
      server.save('dune', 0.5, '$other:3|200');
      expect(await phone.sync.receive(), 1);
      expect(phone.ebooks.linkFor(id)!.position!.locator, progressLocator(0.5));
      expect(phone.ebooks.linkFor(id)!.position!.progress, 0.5);
    });

    test('PDF pages move between devices', () async {
      final id = await phone.download('pdf');
      server.save('pdf', 0.5, 'pdf-page:40');
      expect(await phone.sync.receive(), 1);
      expect(phone.ebooks.linkFor(id)!.position!.locator, '40');
    });

    test('starting a finished book again goes back on purpose', () async {
      final id = await phone.download('dune');
      await phone.readTo(id, 0.98);
      await phone.sync.send();
      await phone.readTo(id, 0.02);
      await phone.sync.send();
      expect(server.progress['dune']!['fraction'], 0.02);
      // ...and the old place is not taken back.
      expect(await phone.sync.receive(), 0);
      expect(phone.ebooks.linkFor(id)!.position!.progress, 0.02);
    });

    test('going back a little does not overwrite the furthest place', () async {
      final id = await phone.download('dune');
      await phone.readTo(id, 0.5);
      await phone.sync.send();
      await phone.readTo(id, 0.45);
      await phone.sync.send();
      expect(server.progress['dune']!['fraction'], 0.5);
      expect(await phone.sync.receive(), 0);
      expect(phone.ebooks.linkFor(id)!.position!.progress, 0.45);
    });

    test('audiobook places sync both ways', () async {
      final id = await phone.download('hail');
      await phone.repository.setAudioProgress(
        id,
        const AudioProgress(positionMs: 60000, lengthMs: 600000),
      );
      await phone.sync.send();
      expect(server.progress['hail']!['fraction'], closeTo(0.1, 0.0001));
      server.save('hail', 0.5, encodeAudioPosition(
        const AudioProgress(positionMs: 300000, lengthMs: 600000),
      ));
      expect(await phone.sync.receive(), 1);
      expect(phone.repository.byId(id)!.audio!.positionMs, 300000);
    });

    test('an audiobook whose length the player has not found uses the server\'s',
        () async {
      final id = await phone.download('hail');
      await phone.repository.setAudioProgress(
        id,
        const AudioProgress(positionMs: 150000),
      );
      expect(phone.sync.placeOf(phone.audiobook(id))!.fraction, closeTo(0.25, 0.0001));
    });

    test('takeLatest moves a book on just before it opens', () async {
      final id = await phone.download('dune');
      await phone.readTo(id, 0.1);
      await phone.sync.send();
      server.save('dune', 0.7, '$localEpubPositionKind:later');
      expect(await phone.sync.takeLatest(id, 'ebook'), isTrue);
      expect(phone.ebooks.linkFor(id)!.position!.locator, 'later');
      server.away = true;
      expect(await phone.sync.takeLatest(id, 'ebook'), isFalse);
    });
  });

  group('syncing audiobook bookmarks', () {
    late FakeServer server;
    late _Phone phone;
    late String id;

    setUp(() async {
      server = FakeServer()
        ..addBook('hail', 'Project Hail Mary',
            author: 'Andy Weir', kind: 'audiobook', format: 'm4b', durationMs: 600000);
      phone = _Phone(server);
      await phone.setUp();
      id = await phone.download('hail');
    });

    tearDown(() => phone.tearDown());

    List<String> notes() => [for (final m in phone.repository.bookmarksFor(id)) m.note];

    test('added here, added elsewhere, deleted on either side', () async {
      await phone.repository.addBookmark(id, _mark(1, note: 'here'));
      await phone.sync.syncBookmarks(phone.audiobook(id));
      expect(server.bookmarks['hail']!.values.single['note'], 'here');

      // Another device adds one.
      final other = _mark(2, note: 'elsewhere');
      server.bookmarks['hail']![other.addedAt.toIso8601String()] = {
        'track': 0, 'trackMs': 2000, 'positionMs': 2000,
        'addedAt': other.addedAt.toIso8601String(), 'note': 'elsewhere',
        'updatedAt': '2026-11-01T13:00:00.000Z', 'deletedAt': null,
      };
      await phone.sync.syncBookmarks(phone.audiobook(id));
      expect(notes(), ['here', 'elsewhere']);

      // Deleted here: the server learns of it.
      await phone.repository.removeBookmark(id, _mark(1));
      await phone.sync.syncBookmarks(phone.audiobook(id));
      final here = server.bookmarks['hail']![_mark(1).addedAt.toIso8601String()]!;
      expect(here['deletedAt'], isNotNull);
      expect(notes(), ['elsewhere']);

      // Deleted elsewhere: gone here too.
      server.bookmarks['hail']![other.addedAt.toIso8601String()]!
        ..['deletedAt'] = '2099-01-01T00:00:00.000Z'
        ..['updatedAt'] = '2099-01-01T00:00:00.000Z';
      await phone.sync.syncBookmarks(phone.audiobook(id));
      expect(notes(), isEmpty);
    });

    test('a note edited here is sent', () async {
      await phone.repository.addBookmark(id, _mark(1, note: 'old'));
      await phone.sync.syncBookmarks(phone.audiobook(id));
      await phone.repository.setBookmarkNote(id, _mark(1), 'new');
      await phone.sync.syncBookmarks(phone.audiobook(id));
      expect(server.bookmarks['hail']!.values.single['note'], 'new');
      expect(notes(), ['new']);
    });
  });

  group('downloading books', () {
    late FakeServer server;
    late _Phone phone;

    setUp(() async {
      server = FakeServer()
        ..addBook('dune', 'Dune', author: 'Frank Herbert',
            series: 'Dune Chronicles', seriesIndex: 1)
        ..addBook('hail', 'Project Hail Mary',
            author: 'Andy Weir', kind: 'audiobook', format: 'm4b', durationMs: 600000)
        ..addBook('mobi', 'Old Thing', format: 'mobi');
      phone = _Phone(server);
      await phone.setUp();
    });

    tearDown(() => phone.tearDown());

    test('a new ebook goes on For later with its file and saved place', () async {
      server.save('dune', 0.3, '$localEpubPositionKind:epubcfi(/6/10)');
      final id = await phone.download('dune');
      final book = phone.repository.byId(id)!;
      expect(book.title, 'Dune');
      expect(book.author, 'Frank Herbert');
      expect(book.shelf, Shelf.forLater);
      expect(book.format, BookFormat.ebook);
      expect(book.series, 'Dune Chronicles');
      expect(book.seriesNumber, 1);
      final link = phone.ebooks.linkFor(id)!;
      expect(File(link.path).readAsStringSync(), 'file of Dune');
      expect(link.format, EbookFormat.epub);
      expect(link.position!.locator, 'epubcfi(/6/10)');
      expect(phone.downloads.localBookFor(await phone.serverBook('dune')), id);
    });

    test('a book already in your library gets the file, not a second copy',
        () async {
      await phone.repository.add(
        title: 'Dune', author: 'Frank Herbert', shelf: Shelf.finished,
      );
      final mine = phone.repository.books.first.id;
      final id = await phone.download('dune');
      expect(id, mine);
      expect(phone.repository.books, hasLength(1));
      expect(phone.ebooks.linkFor(mine), isNotNull);
    });

    test('a book that already has a file here is only linked', () async {
      await phone.repository.add(
        title: 'Dune', author: 'Frank Herbert', shelf: Shelf.inProgress,
      );
      final mine = phone.repository.books.first.id;
      await phone.ebooks.setLink(
        mine,
        EbookLink(
          path: '/somewhere/dune.epub', name: 'dune.epub', bytes: 10,
          format: EbookFormat.epub, addedAt: DateTime(2026),
        ),
      );
      final result = await phone.downloads.download(await phone.serverBook('dune'));
      expect(result.matchedExisting, isTrue);
      expect(result.bookId, mine);
      expect(phone.ebooks.linkFor(mine)!.path, '/somewhere/dune.epub');
      expect(server.requests.where((r) => r.endsWith('/file')), isEmpty);
      expect(phone.ebook(mine).serverId, 'dune');
    });

    test('a different author is not the same book', () async {
      await phone.repository.add(
        title: 'Dune', author: 'Someone Else', shelf: Shelf.finished,
      );
      await phone.download('dune');
      expect(phone.repository.books, hasLength(2));
    });

    test('an audiobook is linked to the player with its length', () async {
      final id = await phone.download('hail');
      expect(phone.repository.byId(id)!.format, BookFormat.audiobook);
      final track = phone.audio.linkFor(id)!.tracks.single;
      expect(track.location, audioLocationFor(_audioPath(track.location)));
      expect(track.lengthMs, 600000);
      expect(File(_audioPath(track.location)).existsSync(), isTrue);
    });

    test('a failed download leaves nothing behind', () async {
      server.downloadStatus = 500;
      final result = await phone.downloads.download(await phone.serverBook('dune'));
      expect(result.problem, isNotNull);
      expect(phone.repository.books, isEmpty);
      final dir = Directory('${phone.dir.path}/books');
      expect(dir.existsSync() ? dir.listSync() : const [], isEmpty);
    });

    test('a kind of file the reader cannot open is refused', () async {
      final result = await phone.downloads.download(await phone.serverBook('mobi'));
      expect(result.problem, contains('EPUB and PDF'));
      expect(phone.repository.books, isEmpty);
    });

    test('cleaning up deletes only audio no book uses', () async {
      final id = await phone.download('hail');
      final kept = _audioPath(phone.audio.linkFor(id)!.tracks.single.location);
      final stray = File('${phone.dir.path}/audio/stray.m4b')..writeAsStringSync('x');
      await phone.downloads.cleanUp();
      expect(File(kept).existsSync(), isTrue);
      expect(stray.existsSync(), isFalse);
      // Disconnecting keeps the downloads that books still use.
      await phone.state.disconnect();
      await phone.downloads.cleanUp();
      expect(File(kept).existsSync(), isTrue);
    });
  });

  group('what the review found', () {
    late FakeServer server;
    late _Phone phone;

    setUp(() async {
      server = FakeServer()
        ..addBook('dune', 'Dune', author: 'Frank Herbert')
        ..addBook('dune-audio', 'Dune', author: 'Frank Herbert',
            kind: 'audiobook', format: 'm4b', durationMs: 600000)
        ..addBook('hail', 'Project Hail Mary',
            author: 'Andy Weir', kind: 'audiobook', format: 'm4b', durationMs: 600000)
        ..addBook('emma', 'Emma', author: 'Jane Austen');
      phone = _Phone(server);
      await phone.setUp();
    });

    tearDown(() => phone.tearDown());

    test('a lower place sent before taking still takes the further one',
        () async {
      final id = await phone.download('dune');
      await phone.readTo(id, 0.2);
      await phone.sync.send();
      server.save('dune', 0.6, '$localEpubPositionKind:pc-place');
      await phone.readTo(id, 0.25);
      await phone.sync.send(); // the server keeps 0.6
      expect(await phone.sync.receive(), 1);
      expect(phone.ebooks.linkFor(id)!.position!.locator, 'pc-place');
    });

    test('a loaded audiobook is told to go to a place taken from elsewhere',
        () async {
      final id = await phone.download('hail');
      await phone.repository.setAudioProgress(
          id, const AudioProgress(positionMs: 60000, lengthMs: 600000));
      await phone.sync.send();
      server.save('hail', 0.5, encodeAudioPosition(const AudioProgress(
          positionMs: 300000, lengthMs: 600000, trackMs: 300000)));
      expect(await phone.sync.receive(), 1);
      expect(phone.moved[id]!.trackMs, 300000);
    });

    test('starting a book again on another device reaches this one',
        () async {
      final id = await phone.download('dune');
      await phone.readTo(id, 0.95);
      await phone.sync.send();
      // The other device starts again.
      server.save('dune', 0.02, '$localEpubPositionKind:start', reset: true);
      // This one turns a page before it has heard: the server says no...
      await phone.readTo(id, 0.96);
      await phone.sync.send();
      expect(server.progress['dune']!['position'], '$localEpubPositionKind:start');
      // ...and taking places brings the start here.
      expect(await phone.sync.receive(), 1);
      expect(phone.ebooks.linkFor(id)!.position!.locator, 'start');
    });

    test('starting again while away is sent as starting again', () async {
      final id = await phone.download('dune');
      await phone.readTo(id, 0.95);
      await phone.sync.send();
      phone.sync.start();
      server.away = true;
      await phone.readTo(id, 0.03);
      await Future<void>.delayed(Duration.zero);
      await phone.readTo(id, 0.2); // read on past 10% before it could go
      await phone.sync.send();
      server.away = false;
      await phone.sync.send();
      expect(server.progress['dune']!['fraction'], 0.2);
      expect(server.progress['dune']!['resetAt'], isNotNull);
    });

    test('a bookmark added while bookmarks sync is not lost', () async {
      final id = await phone.download('hail');
      await phone.repository.addBookmark(id, _mark(1, note: 'first'));
      server.during = (method, path) async {
        if (method == 'PUT' && path.endsWith('/bookmarks')) {
          server.during = null;
          await phone.repository.addBookmark(id, _mark(2, note: 'meanwhile'));
        }
      };
      await phone.sync.syncBookmarks(phone.audiobook(id));
      expect([for (final m in phone.repository.bookmarksFor(id)) m.note],
          ['first', 'meanwhile']);
      await phone.sync.syncBookmarks(phone.audiobook(id));
      expect([for (final m in server.bookmarks['hail']!.values) m['note']],
          containsAll(['first', 'meanwhile']));
    });

    test('a book gone from the server is let go, and others still sync',
        () async {
      final gone = await phone.download('dune-audio');
      final kept = await phone.download('hail');
      await phone.repository.addBookmark(kept, _mark(1, note: 'kept'));
      server.books.remove('dune-audio');
      await phone.repository.setAudioProgress(
          gone, const AudioProgress(positionMs: 1000, lengthMs: 600000));
      await phone.sync.syncNow();
      expect(phone.sync.problem, isNull);
      expect(phone.state.linkOf('dune-audio'), isNull);
      expect(server.bookmarks['hail']!.values.single['note'], 'kept');
    });

    test('two downloads at once each get their own book', () async {
      final results = await Future.wait([
        phone.downloads.download(await phone.serverBook('dune')),
        phone.downloads.download(await phone.serverBook('emma')),
      ]);
      final titles = {
        for (final r in results) phone.repository.byId(r.bookId!)!.title,
      };
      expect(titles, {'Dune', 'Emma'});
      for (final r in results) {
        expect(phone.ebooks.linkFor(r.bookId!), isNotNull);
      }
    });

    test('a book\'s ebook and audiobook from the server are the same book',
        () async {
      final ebook = await phone.download('dune');
      final audio = await phone.download('dune-audio');
      expect(audio, ebook);
      expect(phone.repository.books, hasLength(1));
      expect(phone.ebook(ebook).serverId, 'dune');
      expect(phone.audiobook(ebook).serverId, 'dune-audio');
    });
  });

  group('audiobooks of several files', () {
    late FakeServer server;
    late _Phone phone;

    setUp(() async {
      server = FakeServer()
        ..addBook('parts', 'Project Hail Mary', author: 'Andy Weir',
            kind: 'audiobook', format: 'mp3', durationMs: 3000,
            parts: [[1, 1], [2, 2, 2], [3]]);
      phone = _Phone(server);
      await phone.setUp();
    });

    tearDown(() => phone.tearDown());

    test('every part is downloaded, in order, into a folder of its own',
        () async {
      final id = await phone.download('parts');
      final tracks = phone.audio.linkFor(id)!.tracks;
      expect(tracks, hasLength(3));
      expect([for (final t in tracks) t.name],
          ['001 Part 1.mp3', '002 Part 2.mp3', '003 Part 3.mp3']);
      final paths = [for (final t in tracks) _audioPath(t.location)];
      expect([for (final p in paths) File(p).readAsBytesSync()], [[1, 1], [2, 2, 2], [3]]);
      expect({for (final p in paths) File(p).parent.path}, hasLength(1));
      expect([for (final t in tracks) t.lengthMs], [1000, 1000, 1000]);
    });

    test('parts with very long names keep their extension', () async {
      server.trackNames['parts'] = [
        '${'Chapter one ' * 20}.mp3',
        'Chapter two ' * 20,
        'Three',
      ];
      final id = await phone.download('parts');
      final tracks = phone.audio.linkFor(id)!.tracks;
      expect(tracks, hasLength(3));
      for (final track in tracks) {
        expect(track.name, endsWith('.mp3'));
        expect(File(_audioPath(track.location)).existsSync(), isTrue);
      }
      await phone.downloads.cleanUp();
      for (final track in tracks) {
        expect(File(_audioPath(track.location)).existsSync(), isTrue);
      }
    });

    test('a part that fails leaves nothing behind', () async {
      server.downloadStatus = 500;
      final result = await phone.downloads.download(await phone.serverBook('parts'));
      expect(result.problem, isNotNull);
      expect(phone.repository.books, isEmpty);
      final dir = Directory('${phone.dir.path}/audio');
      expect(dir.existsSync() ? dir.listSync() : const [], isEmpty);
    });

    test('removing the audio lets clean-up delete the folder', () async {
      final id = await phone.download('parts');
      final folder = File(_audioPath(phone.audio.linkFor(id)!.tracks.first.location)).parent;
      await phone.audio.remove(id);
      await phone.downloads.cleanUp();
      expect(folder.existsSync(), isFalse);
    });
  });

  group('sending books and managing downloads', () {
    late FakeServer server;
    late _Phone pc;
    late _Phone phone;

    setUp(() async {
      server = FakeServer()
        ..addBook('dune', 'Dune', author: 'Frank Herbert')
        ..addBook('parts', 'Project Hail Mary', author: 'Andy Weir',
            kind: 'audiobook', format: 'mp3', parts: [[1, 1], [2, 2]]);
      pc = _Phone(server);
      phone = _Phone(server);
      await pc.setUp();
      await phone.setUp();
    });

    tearDown(() async {
      await pc.tearDown();
      await phone.tearDown();
    });

    test('a book sent from one device downloads on the other', () async {
      expect(pc.state.device, isNot(phone.state.device));
      expect(await pc.downloads.sendToOthers(await pc.serverBook('dune')), isNull);
      // Not back to the device that sent it.
      expect(await pc.downloads.receiveSent(), isEmpty);
      expect(await phone.downloads.receiveSent(), ['Dune']);
      expect(phone.repository.books.single.title, 'Dune');
      expect(phone.ebooks.linkFor(phone.repository.books.single.id), isNotNull);
      expect(server.received['dune'], {phone.state.device});
      // Nothing waiting: nothing happens.
      expect(await phone.downloads.receiveSent(), isEmpty);
    });

    test('a sent book reaches every other device', () async {
      final tablet = _Phone(server);
      await tablet.setUp();
      addTearDown(tablet.tearDown);
      await pc.downloads.sendToOthers(await pc.serverBook('dune'));
      expect(await phone.downloads.receiveSent(), ['Dune']);
      expect(await tablet.downloads.receiveSent(), ['Dune']);
      expect(await phone.downloads.receiveSent(), isEmpty);
    });

    test('a book that could not come waits for next time', () async {
      await pc.downloads.sendToOthers(await pc.serverBook('dune'));
      server.downloadStatus = 500;
      expect(await phone.downloads.receiveSent(), isEmpty);
      expect(server.received['dune'], isNull);
      server.downloadStatus = null;
      expect(await phone.downloads.receiveSent(), ['Dune']);
    });

    test('a book already here is just taken off the list', () async {
      await phone.download('dune');
      await pc.downloads.sendToOthers(await pc.serverBook('dune'));
      expect(await phone.downloads.receiveSent(), isEmpty);
      expect(server.received['dune'], {phone.state.device});
      expect(phone.repository.books, hasLength(1));
    });

    test('the device id is kept', () async {
      final dir = await Directory.systemTemp.createTemp('chapterly_device');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/book_server.json');
      final first = await ServerState.load(file);
      final again = await ServerState.load(file);
      expect(again.device, first.device);
      expect(first.device, matches(RegExp(r'^[A-Za-z0-9_-]{6,64}$')));
    });

    test('downloads show their size, and removing one keeps the book', () async {
      final dune = await phone.download('dune');
      final audio = await phone.download('parts');
      final items = await phone.downloads.downloaded();
      expect({for (final i in items) i.title: i.bytes},
          {'Dune': 'file of Dune'.length, 'Project Hail Mary': 4});
      final ebook = items.firstWhere((i) => i.title == 'Dune');
      final path = phone.ebooks.linkFor(dune)!.path;
      await phone.downloads.removeFile(ebook);
      expect(File(path).existsSync(), isFalse);
      expect(phone.ebooks.linkFor(dune), isNull);
      expect(phone.repository.byId(dune), isNotNull);
      final folder = File(_audioPath(phone.audio.linkFor(audio)!.tracks.first.location)).parent;
      await phone.downloads.removeFile(
          (await phone.downloads.downloaded()).single);
      expect(folder.existsSync(), isFalse);
      expect(await phone.downloads.downloaded(), isEmpty);
      // ...and it can come again.
      await phone.download('dune');
      expect(phone.repository.books, hasLength(2));
    });
  });

  group('syncing the whole library', () {
    late FakeServer server;
    late _Phone phone;
    late _Phone pc;

    setUp(() async {
      server = FakeServer();
      phone = _Phone(server);
      pc = _Phone(server);
      await phone.setUp();
      await pc.setUp();
    });

    tearDown(() async {
      await phone.tearDown();
      await pc.tearDown();
    });

    Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

    test('a book added on one device reaches the other', () async {
      final id = await phone.repository.add(
          title: 'Dune', author: 'Frank Herbert', shelf: Shelf.inProgress);
      expect(await phone.library.syncNow(), 0);
      expect(await pc.library.syncNow(), 1);
      expect(pc.repository.byId(id)!.title, 'Dune');
      expect(pc.state.librarySyncedAt, isNotNull);
    });

    test('different changes to the same book on both devices both stay',
        () async {
      final id = await phone.repository.add(
          title: 'Dune', author: 'Frank Herbert', shelf: Shelf.inProgress);
      await phone.library.syncNow();
      await pc.library.syncNow();
      await tick();
      await phone.repository.setRating(id, 5);
      await tick();
      await pc.repository.setNotes(id, 'Spice!');
      await phone.library.syncNow();
      await pc.library.syncNow();
      await phone.library.syncNow();
      for (final device in [phone, pc]) {
        final book = device.repository.byId(id)!;
        expect(book.rating, 5);
        expect(book.notes, 'Spice!');
      }
    });

    test('a book deleted on one device goes on the other', () async {
      final id = await phone.repository.add(
          title: 'Emma', author: 'Jane Austen', shelf: Shelf.forLater);
      await phone.library.syncNow();
      await pc.library.syncNow();
      await pc.repository.deleteForever(id);
      await pc.library.syncNow();
      await phone.library.syncNow();
      expect(phone.repository.byId(id), isNull);
    });

    test('another device saving at the same moment is merged, not lost',
        () async {
      await phone.repository.add(title: 'Mine', author: 'A', shelf: Shelf.forLater);
      await pc.repository.add(title: 'Theirs', author: 'B', shelf: Shelf.forLater);
      var raced = false;
      server.during = (method, path) async {
        if (method == 'PUT' && path == '/v1/library' && !raced) {
          raced = true;
          // The PC saves between the phone's reading and saving.
          server.during = null;
          await pc.library.syncNow();
        }
      };
      await phone.library.syncNow();
      expect(raced, isTrue);
      await pc.library.syncNow();
      expect({for (final b in phone.repository.books) b.title}, {'Mine', 'Theirs'});
      expect({for (final b in pc.repository.books) b.title}, {'Mine', 'Theirs'});
    });

    test('a change made here while syncing keeps the other device\'s change',
        () async {
      final id = await phone.repository.add(
          title: 'Dune', author: 'Frank Herbert', shelf: Shelf.inProgress);
      await phone.library.syncNow();
      await pc.library.syncNow();
      await tick();
      await pc.repository.setRating(id, 5);
      await pc.library.syncNow();
      server.during = (method, path) async {
        if (method == 'PUT' && path == '/v1/library') {
          server.during = null;
          await tick();
          // A note added on the phone while its upload is on the way.
          await phone.repository.setNotes(id, 'Spice!');
        }
      };
      await phone.library.syncNow();
      expect(phone.repository.byId(id)!.rating, 5);
      expect(phone.repository.byId(id)!.notes, 'Spice!');
      await phone.library.syncNow();
      await pc.library.syncNow();
      for (final device in [phone, pc]) {
        expect(device.repository.byId(id)!.rating, 5);
        expect(device.repository.byId(id)!.notes, 'Spice!');
      }
    });

    test('a library saved by a newer Chapterly says so, and changes nothing',
        () async {
      server.library = '{"app":"chapterly","protocol":99,"books":[]}';
      server.libraryVersion = 3;
      await phone.repository.add(title: 'Mine', author: 'A', shelf: Shelf.forLater);
      await expectLater(
        phone.library.syncNow(),
        throwsA(isA<ServerFailure>().having((f) => f.message, 'message', contains('newer'))),
      );
      expect(server.libraryVersion, 3);
      expect(phone.repository.books, hasLength(1));
    });

    test('a damaged library on the server says so, not "update"', () async {
      server.library = '{"app":"chapterly","protocol":2}';
      server.libraryVersion = 3;
      await expectLater(
        phone.library.syncNow(),
        throwsA(isA<ServerFailure>().having(
          (f) => f.message,
          'message',
          allOf(contains('could not be read'), isNot(contains('Update'))),
        )),
      );
      expect(server.libraryVersion, 3);
    });

    test('dates far ahead on the server are dated now', () async {
      final ahead = Book(
        id: 'ahead',
        title: 'From the future',
        author: 'A',
        shelf: Shelf.forLater,
        addedAt: DateTime(2026),
        updatedAt: DateTime(2099),
      );
      server.library = encodeSyncPayload([ahead], {'gone': DateTime(2099)});
      server.libraryVersion = 1;
      await phone.library.syncNow();
      final soon = DateTime.now().add(const Duration(days: 1));
      expect(phone.repository.byId('ahead')!.updatedAt.isBefore(soon), isTrue);
      expect(phone.repository.snapshot().tombstones['gone']!.isBefore(soon),
          isTrue);
    });

    test('the wish list comes along', () async {
      phone.settings.saveWish(Wish(id: 'w1', title: 'Dune Messiah', addedAt: DateTime(2026)));
      await phone.library.syncNow();
      await pc.library.syncNow();
      expect(pc.settings.wishes.single.title, 'Dune Messiah');
    });

    String picture(String seed, [int size = 4000]) =>
        'data:image/jpeg;base64,${seed * size}';

    test('a cover reaches the other device, and the library holds no picture',
        () async {
      final cover = picture('a');
      final id = await phone.repository.add(
          title: 'Dune', author: 'F', shelf: Shelf.forLater, coverUrl: cover);
      await phone.library.syncNow();
      // What the server keeps names the cover; the picture is kept apart.
      expect(server.library, isNot(contains('data:image')));
      expect(server.library, contains(coverRef(coverHash(cover))));
      expect(server.covers.keys, [coverHash(cover)]);

      expect(await pc.library.syncNow(), 1);
      expect(pc.repository.byId(id)!.coverUrl, cover);
    });

    test('a cover a device has is not fetched or sent again', () async {
      final cover = picture('a');
      await phone.repository.add(
          title: 'Dune', author: 'F', shelf: Shelf.forLater, coverUrl: cover);
      await phone.library.syncNow();
      await pc.library.syncNow();
      server.requests.clear();
      await phone.library.syncNow();
      await pc.library.syncNow();
      expect(
        server.requests.where(
            (r) => r.contains('/v1/covers/') && !r.endsWith('/missing')),
        isEmpty,
      );
    });

    test('a changed cover and a changed rating on two devices both stay',
        () async {
      final id = await phone.repository.add(
          title: 'Dune', author: 'F', shelf: Shelf.forLater,
          coverUrl: picture('a'));
      await phone.library.syncNow();
      await pc.library.syncNow();
      await tick();
      final fresh = picture('b');
      await phone.repository.replaceAll([
        phone.repository.byId(id)!.copyWith(
              coverUrl: () => fresh,
              updatedAt: DateTime.now(),
            ),
      ]);
      await tick();
      await pc.repository.setRating(id, 4);
      await phone.library.syncNow();
      await pc.library.syncNow();
      await phone.library.syncNow();
      for (final device in [phone, pc]) {
        final book = device.repository.byId(id)!;
        expect(book.coverUrl, fresh);
        expect(book.rating, 4);
      }
    });

    test('a cover the server lost leaves the book without one and the sync goes on',
        () async {
      final id = await phone.repository.add(
          title: 'Dune', author: 'F', shelf: Shelf.forLater,
          coverUrl: picture('a'));
      await phone.repository.add(
          title: 'Emma', author: 'J', shelf: Shelf.forLater,
          coverUrl: picture('b'));
      await phone.library.syncNow();
      server.covers.remove(coverHash(picture('a')));

      expect(await pc.library.syncNow(), 2);
      expect(pc.repository.byId(id)!.coverUrl, isNull);
      expect(
        pc.repository.books.where((b) => b.title == 'Emma').single.coverUrl,
        picture('b'),
      );
    });

    test('a damaged cover is not kept', () async {
      final id = await phone.repository.add(
          title: 'Dune', author: 'F', shelf: Shelf.forLater,
          coverUrl: picture('a'));
      await phone.library.syncNow();
      final name = coverHash(picture('a'));
      // The server hands back something that is not that picture.
      server.covers[name] = picture('z');
      expect(await pc.library.syncNow(), 1);
      expect(pc.repository.byId(id)!.coverUrl, isNull);
    });

    test('an older library with the pictures inside is still read', () async {
      final cover = picture('a');
      final id = await phone.repository.add(
          title: 'Dune', author: 'F', shelf: Shelf.forLater, coverUrl: cover);
      // As an earlier version saved it: the picture inside the book.
      final book = phone.repository.byId(id)!;
      server.library = jsonEncode(
        jsonDecode(encodeSyncPayload([book], const {})),
      );
      server.libraryVersion = 1;
      expect(await pc.library.syncNow(), 1);
      expect(pc.repository.byId(id)!.coverUrl, cover);
      // And what is saved back names it.
      expect(server.library, isNot(contains('data:image')));
    });

    test('a library of a thousand books syncs with a small message', () async {
      // About 40 KB of picture per book: 40 MB, as in a real library.
      for (var i = 0; i < 1000; i++) {
        await phone.repository.add(
          title: 'Book $i',
          author: 'A',
          shelf: Shelf.forLater,
          coverUrl: picture(String.fromCharCode(97 + i % 26), 1000 + i),
        );
      }
      await phone.library.syncNow();
      expect(server.library!.length, lessThan(900 * 1000));
      expect(await pc.library.syncNow(), 1000);
      expect(pc.repository.books, hasLength(1000));
      expect(
        pc.repository.books.where((b) => isDataCoverUrl(b.coverUrl)),
        hasLength(1000),
      );
      // A second sync moves no pictures.
      server.requests.clear();
      await pc.library.syncNow();
      expect(
        server.requests.where(
            (r) => r.contains('/v1/covers/') && !r.endsWith('/missing')),
        isEmpty,
      );
    });

    test('switched off, nothing is sent', () async {
      await phone.state.setLibrarySync(false);
      await phone.repository.add(title: 'Dune', author: 'F', shelf: Shelf.forLater);
      expect(await phone.library.syncNow(), 0);
      expect(server.library, isNull);
      expect(server.requests.where((r) => r.contains('/v1/library')), isEmpty);
      // The choice is kept.
      await phone.state.setLibrarySync(true);
      expect(phone.state.librarySync, isTrue);
    });
  });

  test('a note on a highlight goes on the quote and syncs with the book',
      () async {
    final server = FakeServer();
    final phone = _Phone(server);
    final pc = _Phone(server);
    await phone.setUp();
    await pc.setUp();
    addTearDown(phone.tearDown);
    addTearDown(pc.tearDown);
    final id = await pc.repository.add(title: 'Dune', author: 'F', shelf: Shelf.inProgress);
    await pc.repository.addQuote(id, 'Fear is the mind-killer.', page: 8);
    await pc.repository.setQuoteNote(id, ' Fear is the mind-killer. ', 'The litany');
    // No such quote: nothing happens.
    await pc.repository.setQuoteNote(id, 'Something else', 'x');
    await pc.library.syncNow();
    await phone.library.syncNow();
    final quote = phone.repository.byId(id)!.quotes.single;
    expect(quote.note, 'The litany');
    expect(quote.page, 8);
    await pc.repository.setQuoteNote(id, 'Fear is the mind-killer.', '  ');
    expect(pc.repository.byId(id)!.quotes.single.note, isNull);
  });

  group('the server state on this device', () {
    test('is saved and read back, and a damaged file starts again', () async {
      final dir = await Directory.systemTemp.createTemp('chapterly_state');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/book_server.json');
      final state = await ServerState.load(file);
      await state.connect(Uri.parse('http://100.1.2.3:8780'), 'tok', 'hans');
      await state.setLink(const ServerLink(
          serverId: 's1', bookId: 'a', kind: 'ebook', pushed: 0.5));
      final again = await ServerState.load(file);
      expect(again.connected, isTrue);
      expect(again.name, 'hans');
      expect(again.linkFor('a', 'ebook')!.pushed, 0.5);
      expect(again.bookIdFor('s1'), 'a');
      file.writeAsStringSync('{broken');
      expect((await ServerState.load(file)).connected, isFalse);
    });

    test('a token store keeps the token out of the file', () async {
      final dir = await Directory.systemTemp.createTemp('chapterly_state');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/book_server.json');
      final tokens = _MemoryTokens();
      final state = await ServerState.load(file, tokens: tokens);
      await state.connect(Uri.parse('http://100.1.2.3:8780'), 'tok-123', 'hans');
      expect(file.readAsStringSync(), isNot(contains('tok-123')));
      expect(tokens.value, 'tok-123');
      final again = await ServerState.load(file, tokens: tokens);
      expect(again.connected, isTrue);
      expect(again.token, 'tok-123');
      await again.disconnect();
      expect(tokens.value, isNull);
      // A token lost from the store means connecting again.
      await again.connect(Uri.parse('http://100.1.2.3:8780'), 'tok-123', 'hans');
      tokens.value = null;
      expect((await ServerState.load(file, tokens: tokens)).connected, isFalse);
    });

    test('one book here per book there, and another server starts afresh',
        () async {
      final state = ServerState();
      await state.connect(Uri.parse('http://100.1.2.3:8780'), 'tok', 'hans');
      await state.setLink(const ServerLink(serverId: 's1', bookId: 'a', kind: 'ebook'));
      await state.setLink(const ServerLink(serverId: 's1', bookId: 'b', kind: 'ebook'));
      expect([for (final l in state.links) l.bookId], ['b']);
      // A book's ebook and audiobook each have their own.
      await state.setLink(const ServerLink(serverId: 's2', bookId: 'b', kind: 'audiobook'));
      expect(state.links, hasLength(2));
      await state.setLink(const ServerLink(serverId: 's3', bookId: 'b', kind: 'ebook'));
      expect([for (final l in state.links) l.serverId]..sort(), ['s2', 's3']);
      await state.connect(Uri.parse('http://100.9.9.9:8780'), 'tok', 'hans');
      expect(state.links, isEmpty);
    });
  });

  group('the Book server screen', () {
    late FakeServer server;
    late _Phone phone;

    setUp(() async {
      server = FakeServer()
        ..addBook('dune', 'Dune', author: 'Frank Herbert')
        ..addBook('hail', 'Project Hail Mary',
            author: 'Andy Weir', kind: 'audiobook', format: 'm4b', durationMs: 39720000);
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2220);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ServerScreen(
          repository: phone.repository,
          settings: AppSettings(),
          fileIo: const FileIo(),
          sync: phone.sync,
          downloads: phone.downloads,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('connects with an address and token', (tester) async {
      await tester.runAsync(() async {
        phone = _Phone(server);
        await phone.setUp();
        await phone.state.disconnect();
      });
      await pump(tester);
      expect(find.text('Connect'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Address'), '100.1.2.3');
      await tester.enterText(find.widgetWithText(TextField, 'Token'), 'wrong');
      await tester.runAsync(() async {
        await tester.tap(find.text('Connect'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('did not accept the token'), findsOneWidget);
      expect(phone.state.connected, isFalse);

      await tester.enterText(find.widgetWithText(TextField, 'Token'), server.token);
      await tester.runAsync(() async {
        await tester.tap(find.text('Connect'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(phone.state.connected, isTrue);
      expect(phone.state.address.toString(), 'http://100.1.2.3:8780');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(phone.tearDown);
    });

    testWidgets('a page that fails waits to be asked again', (tester) async {
      for (var n = 0; n < 60; n++) {
        server.addBook('b$n', 'Book ${n.toString().padLeft(2, '0')}');
      }
      server.failBooksFrom = 50;
      await tester.runAsync(() async {
        phone = _Phone(server);
        await phone.setUp();
      });
      await pump(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -20000));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pumpAndSettle();
      }
      final tries = server.requests.where((r) => r == 'GET /v1/books').length;
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pumpAndSettle();
      }
      expect(server.requests.where((r) => r == 'GET /v1/books').length, tries);
      expect(find.text('Load more'), findsOneWidget);
      server.failBooksFrom = null;
      await tester.tap(find.text('Load more'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(find.text('Book 59'), findsOneWidget);
      await tester.runAsync(phone.tearDown);
    });

    testWidgets('sends a book on, and lists and removes downloads',
        (tester) async {
      await tester.runAsync(() async {
        phone = _Phone(server);
        await phone.setUp();
        await phone.download('dune');
      });
      await pump(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Send to my other devices'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('will download on your other devices'), findsOneWidget);
      expect(server.sends.keys, contains('dune'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // The list measures files first (with a spinner), so wait for it.
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.tap(find.byTooltip('Downloads'));
      await tester.pump();
      await waitFor(find.textContaining('1 book uses'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 book uses'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove the file (the book stays)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
      expect(phone.ebooks.linkFor(phone.repository.books.single.id), isNull);
      // Opened again, the list is empty; the book is still in the library.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Downloads'));
      await tester.pump();
      await waitFor(find.text('No books from the server on this device.'));
      expect(find.text('No books from the server on this device.'), findsOneWidget);
      expect(phone.repository.books, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.runAsync(phone.tearDown);
    });

    testWidgets('lists, searches and downloads books', (tester) async {
      await tester.runAsync(() async {
        phone = _Phone(server);
        await phone.setUp();
      });
      await pump(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Project Hail Mary'), findsOneWidget);
      expect(find.textContaining('Audiobook, 11 h 2 min'), findsOneWidget);
      expect(find.textContaining('2 books · signed in as hans'), findsOneWidget);

      await tester.tap(find.text('Audiobooks'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsNothing);
      await tester.tap(find.text('All'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'herbert');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Project Hail Mary'), findsNothing);
      expect(find.text('Dune'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Download'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('is in your library'), findsOneWidget);
      expect(find.byTooltip('In your library'), findsOneWidget);
      expect(phone.repository.books.single.title, 'Dune');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(phone.tearDown);
    });
  });
}
