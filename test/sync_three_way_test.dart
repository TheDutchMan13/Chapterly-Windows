import 'dart:convert';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/data/sync_merge.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:chapterly/data/sync_three_way.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/reading.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

const _code = 'ABCDEFGHJKMNPQRS';

Book _book(String id, {DateTime? updated, int? rating}) => Book(
      id: id,
      title: 'Book $id',
      author: 'Author',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      rating: rating,
      updatedAt: updated ?? DateTime(2026, 1, 1),
    );

/// A phone running the real sync server, with the same merge steps as the
/// phone app's PhoneSync.
class _Phone {
  final repository = BookRepository(InMemoryBookStore());
  late final SyncServer server;
  Future<void> Function()? duringSync;

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
        await duringSync?.call();
        return encodeSyncPayload(merged.books, merged.tombstones);
      },
    );
    await server.start(port: 0);
  }

  String get address => '127.0.0.1:${server.boundPort}';
}
void main() {
  group('a change on the PC during a sync', () {
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
      await pc.replaceAll([_book('a', rating: 1)]);
      await phone.repository.replaceAll([_book('a', rating: 1)]);
      expect(await sync.pair(address: phone.address, code: _code), isNull);
    });

    tearDown(() => phone.server.stop());

    for (final (name, request) in [('the read', 1), ('the send', 2)]) {
      test('during $name request survives the next sync', () async {
        var calls = 0;
        phone.duringSync = () async {
          calls++;
          if (calls == request) await pc.setRating('a', 4);
        };
        expect(await sync.syncNow(), isNull);
        phone.duringSync = null;
        expect(await sync.syncNow(), isNull);
        expect(pc.byId('a')!.rating, 4);
        expect(phone.repository.byId('a')!.rating, 4);
      });
    }
  });

  group('lists of items with an identity', () {
    final day = DateTime(2026, 10, 30).toIso8601String();
    final other = DateTime(2026, 10, 29).toIso8601String();
    Map<String, Object?> entry(String date, int minutes, {int pages = 0}) =>
        {'date': date, 'pages': pages, 'minutes': minutes};

    test('minutes added to the same day on both sides add up', () {
      final merged = mergeKeyedLists(
        'readingLog',
        [entry(day, 30)],
        [entry(day, 40)],
        [entry(day, 50), entry(other, 5)],
        preferLocal: true,
      );
      expect(merged, [entry(other, 5), entry(day, 60)]);
    });

    test('removed on one side and unchanged on the other is removed', () {
      final merged = mergeKeyedLists(
        'readingLog',
        [entry(day, 30), entry(other, 10)],
        [entry(day, 30)],
        [entry(day, 35), entry(other, 10)],
        preferLocal: false,
      );
      expect(merged, [entry(day, 35)]);
    });

    test('two identical entries on one day are both kept', () {
      final merged = mergeKeyedLists(
        'readingLog',
        const [],
        [entry(day, 10), entry(day, 10)],
        const [],
        preferLocal: true,
      );
      expect(merged, hasLength(2));
    });

    test('a quote edited on one side replaces its earlier self', () {
      final added = DateTime(2026).toIso8601String();
      final merged = mergeKeyedLists(
        'quotes',
        [{'text': 'old', 'addedAt': added}],
        [{'text': 'new', 'addedAt': added}],
        [{'text': 'old', 'addedAt': added}, {'text': 'other', 'addedAt': day}],
        preferLocal: true,
      );
      expect([for (final q in merged) (q as Map)['text']], ['new', 'other']);
    });

    test('a whole book: listening on both sides on the same day', () {
      final d = DateTime(2026, 10, 30);
      final base = _book('a').copyWith(readingLog: [LogEntry(date: d, minutes: 30)]);
      final mine = _book('a', updated: DateTime(2026, 2))
          .copyWith(readingLog: [LogEntry(date: d, minutes: 40)]);
      final theirs = _book('a', updated: DateTime(2026, 3))
          .copyWith(readingLog: [LogEntry(date: d, minutes: 50)]);
      final resolved = resolveConflicts(
        base: {'a': jsonDecode(jsonEncode(base.toJson())) as Map<String, Object?>},
        local: [mine],
        remote: [theirs],
        now: DateTime(2026, 6),
      );
      expect(resolved.single.readingLog.single.minutes, 60);
    });
  });
}
