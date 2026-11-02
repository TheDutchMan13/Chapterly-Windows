import 'dart:convert';

import 'package:chapterly/audio/audio_bookmarks.dart';
import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/duplicates.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/data/sync_merge.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:chapterly/data/sync_three_way.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

const _code = 'ABCDEFGHJKMNPQRS';

Book _book(String id) => Book(
      id: id,
      title: 'Book $id',
      author: 'Author',
      shelf: Shelf.inProgress,
      addedAt: DateTime(2026),
      updatedAt: DateTime(2026, 1, 1),
    );

AudioBookmark _mark(int n, {String note = ''}) => AudioBookmark(
      track: 0,
      trackMs: n * 1000,
      positionMs: n * 1000,
      addedAt: DateTime(2026, 2, n),
      note: note,
    );

/// A phone running the real sync server with the phone app's merge steps.
/// [old]: a phone app before 1.15.0, which drops bookmarks and sends no
/// features.
class _Phone {
  _Phone({this.old = false});

  final bool old;
  final repository = BookRepository(InMemoryBookStore());
  late final SyncServer server;

  Future<void> start() async {
    await repository.load();
    server = SyncServer(
      token: _code,
      handleSync: (body) async {
        var remote = decodeSyncPayload(body).books;
        if (old) {
          remote = [
            for (final b in remote) b.copyWith(audioBookmarks: const []),
          ];
        }
        final local = repository.snapshot();
        final merged = mergeLibraries(
          local: local.books,
          localTombstones: local.tombstones,
          remote: remote,
          remoteTombstones: decodeSyncPayload(body).tombstones,
        );
        await repository.applySynced(merged.books, merged.tombstones);
        return encodeSyncPayload(
          merged.books,
          merged.tombstones,
          features: old ? const [] : syncFeatures,
        );
      },
    );
    await server.start(port: 0);
  }

  String get address => '127.0.0.1:${server.boundPort}';
}

List<String> _notes(BookRepository repository) =>
    [for (final m in repository.bookmarksFor('a')) m.note];

Future<void> _tick() => Future.delayed(const Duration(milliseconds: 5));

void main() {
  group('bookmarks sync with a phone that keeps them', () {
    late _Phone phone;
    late BookRepository pc;
    late PcSync sync;

    setUp(() async {
      phone = _Phone();
      await phone.start();
      pc = BookRepository(InMemoryBookStore());
      await pc.load();
      sync = PcSync(
        repository: pc,
        settings: AppSettings(),
        codeStore: MemoryCodeStore(),
        client: SyncClient(pingTimeout: const Duration(seconds: 2)),
      );
      await pc.replaceAll([_book('a')]);
      await phone.repository.replaceAll([_book('a')]);
      expect(await sync.pair(address: phone.address, code: _code), isNull);
    });

    tearDown(() => phone.server.stop());

    test('added, deleted and edited on either side', () async {
      // Added on the PC.
      await pc.addBookmark('a', _mark(1, note: 'one'));
      expect(await sync.syncNow(), isNull);
      expect(_notes(phone.repository), ['one']);

      // Added on both sides between syncs: both kept.
      await pc.addBookmark('a', _mark(3, note: 'three'));
      await _tick();
      await phone.repository.addBookmark('a', _mark(2, note: 'two'));
      expect(await sync.syncNow(), isNull);
      expect(_notes(pc), ['one', 'two', 'three']);
      expect(_notes(phone.repository), ['one', 'two', 'three']);

      // Deleted on the PC while a note is edited on the phone.
      await pc.removeBookmark('a', _mark(1));
      await _tick();
      await phone.repository.setBookmarkNote('a', _mark(2), 'two, edited');
      expect(await sync.syncNow(), isNull);
      expect(_notes(pc), ['two, edited', 'three']);
      expect(_notes(phone.repository), ['two, edited', 'three']);

      // Deleted on the phone only.
      await _tick();
      await phone.repository.removeBookmark('a', _mark(3));
      expect(await sync.syncNow(), isNull);
      expect(_notes(pc), ['two, edited']);
      expect(_notes(phone.repository), ['two, edited']);
    });

    test('deleted on the phone while another field changes on the PC',
        () async {
      await pc.addBookmark('a', _mark(1, note: 'one'));
      await pc.addBookmark('a', _mark(2, note: 'two'));
      expect(await sync.syncNow(), isNull);
      await phone.repository.removeBookmark('a', _mark(1));
      await _tick();
      await pc.setRating('a', 5);
      expect(await sync.syncNow(), isNull);
      expect(_notes(pc), ['two']);
      expect(_notes(phone.repository), ['two']);
      expect(phone.repository.byId('a')!.rating, 5);
    });
  });

  group('a phone app older than 1.15.0', () {
    late _Phone phone;
    late BookRepository pc;
    late PcSync sync;

    setUp(() async {
      phone = _Phone(old: true);
      await phone.start();
      pc = BookRepository(InMemoryBookStore());
      await pc.load();
      sync = PcSync(
        repository: pc,
        settings: AppSettings(),
        codeStore: MemoryCodeStore(),
        client: SyncClient(pingTimeout: const Duration(seconds: 2)),
      );
      await pc.replaceAll([_book('a')]);
      await phone.repository.replaceAll([_book('a')]);
      expect(await sync.pair(address: phone.address, code: _code), isNull);
    });

    tearDown(() => phone.server.stop());

    test('does not wipe the PC\'s bookmarks, and they stay put', () async {
      await pc.addBookmark('a', _mark(1, note: 'one'));
      expect(await sync.syncNow(), isNull);
      expect(_notes(pc), ['one']);
      final after = pc.byId('a')!.updatedAt;

      // A change on the phone still comes through, bookmarks kept.
      await _tick();
      await phone.repository.setRating('a', 3);
      expect(await sync.syncNow(), isNull);
      expect(pc.byId('a')!.rating, 3);
      expect(_notes(pc), ['one']);

      // Nothing changed: the book is not stamped again and again.
      final stamped = pc.byId('a')!.updatedAt;
      expect(stamped.isBefore(after), isFalse);
      expect(await sync.syncNow(), isNull);
      expect(await sync.syncNow(), isNull);
      expect(pc.byId('a')!.updatedAt, stamped);
      expect(_notes(pc), ['one']);
    });
  });

  group('upgrading from Windows 1.10.0', () {
    // 1.10.0 kept the phone's bookmarks in extras, a field it did not know.
    Map<String, Object?> oldRow(List<AudioBookmark> marks) => {
          ..._book('a').toMap(),
          'audio_bookmarks': null,
          'extras': jsonEncode({
            'audioBookmarks': [for (final m in marks) m.toJson()],
            'futureField': 1,
          }),
        };

    test('bookmarks kept in extras become real bookmarks', () {
      final book = Book.fromMap(oldRow([_mark(1), _mark(2)]));
      expect(book.audioBookmarks, hasLength(2));
      expect(book.extras, {'futureField': 1});
      final json = book.toJson();
      expect((json['audioBookmarks'] as List?)?.length, 2);
      expect(json['futureField'], 1);
    });

    test('a bookmark added after the upgrade does not drop the phone\'s',
        () async {
      final pc = BookRepository(InMemoryBookStore());
      await pc.load();
      await pc.replaceAll([Book.fromMap(oldRow([_mark(1), _mark(2)]))]);
      await pc.addBookmark('a', _mark(3, note: 'new on the PC'));
      final phoneCopy = _book('a').copyWith(
        audioBookmarks: [_mark(1), _mark(2)],
        updatedAt: DateTime(2026, 1, 1),
      );
      final base = {
        'a': jsonDecode(jsonEncode(phoneCopy.toJson())) as Map<String, Object?>,
      };
      // Only the PC changed: its copy is sent as it is, with all three.
      final resolved = resolveConflicts(
        base: base,
        local: pc.books,
        remote: [phoneCopy],
        now: DateTime.now(),
      );
      expect(resolved, isEmpty);
      expect(pc.byId('a')!.audioBookmarks, hasLength(3));
    });
  });

  test('deleting the last bookmark on the phone is not merged again', () {
    final withMark = _book('a').copyWith(audioBookmarks: [_mark(1)]);
    final base = {
      'a': jsonDecode(jsonEncode(withMark.toJson())) as Map<String, Object?>,
    };
    final phone = _book('a').copyWith(updatedAt: DateTime(2026, 3));
    expect(
      resolveConflicts(
        base: base,
        local: [withMark],
        remote: [phone],
        now: DateTime.now(),
      ),
      isEmpty,
    );
  });

  test('merging duplicates keeps the bookmarks of both copies', () {
    final a = _book('a').copyWith(audioBookmarks: [_mark(1)]);
    final b = _book('b').copyWith(audioBookmarks: [_mark(1), _mark(2)]);
    final merged = mergeDuplicateGroup([a, b]);
    expect(merged.audioBookmarks, hasLength(2));
  });

  group('merging bookmark lists', () {
    Map<String, Object?> json(AudioBookmark m) => m.toJson();

    test('matched by when they were added', () {
      final merged = mergeKeyedLists(
        'audioBookmarks',
        [json(_mark(1)), json(_mark(2))],
        [json(_mark(1, note: 'edited')), json(_mark(2)), json(_mark(3))],
        [json(_mark(2)), json(_mark(4))],
        preferLocal: false,
      );
      // 1 was deleted on the phone, but edited on the PC: the edit stays.
      expect(
        [for (final m in merged) AudioBookmark.fromJson(m)!.note],
        ['edited', '', '', ''],
      );
      expect(merged, hasLength(4));
    });

    test('keepPcBookmarks puts back only what the PC had', () {
      final pcBook = _book('a').copyWith(audioBookmarks: [_mark(1)]);
      final kept = keepPcBookmarks(
        [_book('a'), _book('b')],
        [pcBook, _book('b')],
      );
      expect(kept.first.audioBookmarks, hasLength(1));
      expect(kept.last.audioBookmarks, isEmpty);
    });
  });
}
