import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/data/sync_merge.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:chapterly/data/wish_list.dart';
import 'package:flutter_test/flutter_test.dart';

const _code = 'ABCDEFGHJKMNPQRS';

Wish _wish(String id, String title, {String where = ''}) => Wish(
      id: id,
      title: title,
      addedAt: DateTime(2026),
      where: where.isEmpty ? null : where,
    );

/// A phone running the real sync server with the phone app's steps. [old]:
/// a phone app without a wish list, which ignores `wishes` and sends none.
class _Phone {
  _Phone({this.old = false});

  final bool old;
  final repository = BookRepository(InMemoryBookStore());
  final settings = AppSettings();
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
        if (old) {
          return encodeSyncPayload(
            merged.books,
            merged.tombstones,
            features: const [],
          );
        }
        settings.mergeWishesFrom(remote.wishes);
        return encodeSyncPayload(
          merged.books,
          merged.tombstones,
          wishes: settings.allWishes,
        );
      },
    );
    await server.start(port: 0);
  }

  String get address => '127.0.0.1:${server.boundPort}';
}

List<String> _titles(AppSettings settings) =>
    [for (final w in sortWishes(settings.wishes)) w.title];

Future<void> _tick() => Future.delayed(const Duration(milliseconds: 5));

void main() {
  group('the wish list syncs with the phone', () {
    late _Phone phone;
    late AppSettings pcSettings;
    late PcSync sync;

    Future<void> setUpPair({bool old = false}) async {
      phone = _Phone(old: old);
      await phone.start();
      final pc = BookRepository(InMemoryBookStore());
      await pc.load();
      pcSettings = AppSettings();
      sync = PcSync(
        repository: pc,
        settings: pcSettings,
        codeStore: MemoryCodeStore(),
        client: SyncClient(pingTimeout: const Duration(seconds: 2)),
      );
      expect(await sync.pair(address: phone.address, code: _code), isNull);
    }

    tearDown(() => phone.server.stop());

    test('added, edited and deleted on either side', () async {
      await setUpPair();
      pcSettings.saveWish(_wish('1', 'Dune'));
      phone.settings.saveWish(_wish('2', 'Emma'));
      expect(await sync.syncNow(), isNull);
      expect(_titles(pcSettings), ['Dune', 'Emma']);
      expect(_titles(phone.settings), ['Dune', 'Emma']);

      // Edited on the PC, deleted on the phone (a different wish).
      await _tick();
      pcSettings.saveWish(_wish('1', 'Dune Messiah', where: 'Library'));
      phone.settings.deleteWish('2');
      expect(await sync.syncNow(), isNull);
      expect(_titles(pcSettings), ['Dune Messiah']);
      expect(_titles(phone.settings), ['Dune Messiah']);
      expect(phone.settings.wishes.single.where, 'Library');

      // The phone edits the same wish later: the newer copy wins.
      await _tick();
      phone.settings.saveWish(
        phone.settings.wishes.single.copyWith(title: 'Children of Dune'),
      );
      expect(await sync.syncNow(), isNull);
      expect(_titles(pcSettings), ['Children of Dune']);

      // Deleted on the PC: gone on the phone, and it stays gone.
      await _tick();
      pcSettings.deleteWish('1');
      expect(await sync.syncNow(), isNull);
      expect(await sync.syncNow(), isNull);
      expect(_titles(pcSettings), isEmpty);
      expect(_titles(phone.settings), isEmpty);
    });

    test('nothing changes when nothing changed', () async {
      await setUpPair();
      pcSettings.saveWish(_wish('1', 'Dune'));
      expect(await sync.syncNow(), isNull);
      final stamp = pcSettings.allWishes.single.updatedAt;
      expect(await sync.syncNow(), isNull);
      expect(await sync.syncNow(), isNull);
      expect(pcSettings.allWishes.single.updatedAt, stamp);
      expect(phone.settings.allWishes.single.updatedAt, stamp);
    });
  });

  test('a phone app without a wish list leaves the PC list alone', () async {
    final phone = _Phone(old: true);
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
    expect(await sync.pair(address: phone.address, code: _code), isNull);
    settings.saveWish(_wish('1', 'Dune'));
    expect(await sync.syncNow(), isNull);
    expect(await sync.syncNow(), isNull);
    expect(_titles(settings), ['Dune']);
    expect(phone.settings.allWishes, isEmpty);
  });
}
