import 'dart:convert';
import 'dart:io';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/data/sync_covers.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'phone_sync_core.dart';

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

List<String> _ids(List<Book> books) => [for (final b in books) b.id]..sort();

/// The phone's covers, counting what moves, and able to misbehave.
class _CountingCovers implements SyncCovers {
  _CountingCovers(this.inner);

  final SyncCovers inner;
  int puts = 0;
  int gets = 0;

  /// Say nothing is missing, as a phone that lost its cache would.
  bool lieAboutMissing = false;

  /// Pictures the phone no longer has, and pictures it returns damaged.
  final lost = <String>{};
  final damaged = <String>{};

  @override
  Future<List<String>> missing(List<String> hashes) async =>
      lieAboutMissing ? const [] : inner.missing(hashes);

  @override
  Future<void> put(String hash, String dataUrl) async {
    puts++;
    await inner.put(hash, dataUrl);
  }

  @override
  Future<String?> get(String hash) async {
    gets++;
    if (lost.contains(hash)) return null;
    if (damaged.contains(hash)) return 'data:image/jpeg;base64,damaged';
    return inner.get(hash);
  }
}

/// A phone running the real sync server and the phone app's own merge steps
/// (PhoneSyncCore, the same code as in the Android app).
class _Phone {
  final repository = BookRepository(InMemoryBookStore());
  final settings = AppSettings();
  late final PhoneSyncCore core;
  late final _CountingCovers covers;
  late final SyncServer server;
  Future<void> Function()? duringSync;

  Future<void> start() async {
    await repository.load();
    core = PhoneSyncCore(repository: repository, settings: settings);
    covers = _CountingCovers(core);
    server = SyncServer(
      token: _code,
      handleSync: (body) async {
        final reply = await core.handleSync(body);
        await duringSync?.call();
        return reply;
      },
      covers: covers,
    );
    await server.start(port: 0);
  }

  String get address => '127.0.0.1:${server.boundPort}';
}

/// A tiny server that always gives the same reply, for odd cases.
Future<HttpServer> _replyWith(int status, String body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    await request.drain<void>();
    request.response
      ..statusCode = status
      ..write(body);
    await request.response.close();
  });
  return server;
}

void main() {
  group('address and code', () {
    test('the address gets the sync port unless one is given', () {
      expect(parsePhoneAddress('192.168.1.20')!.port, defaultSyncPort);
      expect(parsePhoneAddress(' 192.168.1.20:9000 ')!.port, 9000);
      expect(parsePhoneAddress('http://192.168.1.20:8765/')!.host,
          '192.168.1.20');
      expect(parsePhoneAddress('phone.local'), isNotNull);
      expect(
        formatPhoneAddress(parsePhoneAddress('192.168.1.20')!),
        '192.168.1.20:8765',
      );
    });

    test('things that are not an address are refused', () {
      expect(parsePhoneAddress(''), isNull);
      expect(parsePhoneAddress('https://192.168.1.20'), isNull);
      expect(parsePhoneAddress('192.168.1.20/v1/sync'), isNull);
    });

    test('the code loses its dashes and spaces', () {
      expect(normalizeSyncCode('abcd-efgh-jkmn-pqrs'), _code);
      expect(normalizeSyncCode('ABCD EFGH JKMN PQRS'), _code);
      expect(normalizeSyncCode('ABCD-EFGH'), isNull);
      expect(normalizeSyncCode('ABCD-EFGH-JKMN-PQR!'), isNull);
    });

    test('changes are counted', () {
      final before = [_book('a'), _book('b'), _book('c')];
      final after = [
        _book('a'),
        _book('b', updated: DateTime(2026, 2)),
        _book('d'),
      ];
      // b changed, c removed, d added.
      expect(countSyncChanges(before, after), 3);
    });
  });

  group('syncing with a phone', () {
    late _Phone phone;
    late BookRepository pc;
    late AppSettings settings;
    late MemoryCodeStore codes;
    late PcSync sync;

    setUp(() async {
      phone = _Phone();
      await phone.start();
      pc = BookRepository(InMemoryBookStore());
      await pc.load();
      settings = AppSettings();
      codes = MemoryCodeStore();
      sync = PcSync(
        repository: pc,
        settings: settings,
        codeStore: codes,
        client: SyncClient(pingTimeout: const Duration(seconds: 2)),
      );
    });

    tearDown(() => phone.server.stop());

    test('pairing syncs both libraries', () async {
      await pc.replaceAll([_book('pc')]);
      await phone.repository.replaceAll([_book('phone')]);

      final problem = await sync.pair(address: phone.address, code: 'abcd-efgh-jkmn-pqrs');

      expect(problem, isNull);
      expect(sync.paired, isTrue);
      expect(settings.syncAddress, phone.address);
      expect(await codes.read(), _code);
      expect(_ids(pc.allBooks), ['pc', 'phone']);
      expect(_ids(phone.repository.allBooks), ['pc', 'phone']);
      expect(settings.lastSyncChanged, 1);
      expect(settings.lastSyncError, isNull);
    });

    test('a wrong code is not saved and nothing changes', () async {
      await pc.replaceAll([_book('pc')]);
      await phone.repository.replaceAll([_book('phone')]);

      final problem = await sync.pair(
        address: phone.address,
        code: 'ZZZZ-ZZZZ-ZZZZ-ZZZZ',
      );

      expect(problem, contains('pairing code is wrong'));
      expect(sync.paired, isFalse);
      expect(await codes.read(), isNull);
      expect(settings.syncAddress, isNull);
      expect(_ids(pc.allBooks), ['pc']);
      expect(_ids(phone.repository.allBooks), ['phone']);
    });

    test('the newest change to a book wins on both sides', () async {
      await pc.replaceAll([_book('a', rating: 2, updated: DateTime(2026, 3))]);
      await phone.repository.replaceAll([
        _book('a', rating: 5, updated: DateTime(2026, 2)),
      ]);
      expect(await sync.pair(address: phone.address, code: _code), isNull);
      expect(pc.byId('a')!.rating, 2);
      expect(phone.repository.byId('a')!.rating, 2);
    });

    test('a book deleted for good on the PC goes from the phone', () async {
      await pc.replaceAll([_book('a'), _book('b')]);
      await phone.repository.replaceAll([_book('a'), _book('b')]);
      await pc.deleteForever('a');

      expect(await sync.pair(address: phone.address, code: _code), isNull);
      expect(_ids(pc.allBooks), ['b']);
      expect(_ids(phone.repository.allBooks), ['b']);
    });

    test('a book in the trash on the PC goes to the trash on the phone',
        () async {
      await pc.replaceAll([_book('a')]);
      await phone.repository.replaceAll([_book('a')]);
      await pc.moveToTrash('a');

      expect(await sync.pair(address: phone.address, code: _code), isNull);
      expect(phone.repository.books, isEmpty);
      expect(phone.repository.trash.single.id, 'a');
    });

    test('a change made on the PC during the sync is kept', () async {
      await pc.replaceAll([_book('a')]);
      await phone.repository.replaceAll([_book('a')]);
      phone.duringSync = () => pc.setRating('a', 4);

      expect(await sync.pair(address: phone.address, code: _code), isNull);
      expect(pc.byId('a')!.rating, 4);
    });

    test('Sync now needs a paired phone', () async {
      expect(await sync.syncNow(), contains('Connect to your phone first'));
    });

    test('Sync now works after pairing', () async {
      expect(await sync.pair(address: phone.address, code: _code), isNull);
      await phone.repository.replaceAll([_book('new')]);
      expect(await sync.syncNow(), isNull);
      expect(_ids(pc.allBooks), ['new']);
    });

    test('forgetting the phone removes the address and code', () async {
      expect(await sync.pair(address: phone.address, code: _code), isNull);
      await sync.forget();
      expect(sync.paired, isFalse);
      expect(await codes.read(), isNull);
      expect(settings.syncAddress, isNull);
    });
  });

  group('covers', () {
    late _Phone phone;
    late BookRepository pc;
    late PcSync sync;

    String picture(String seed, [int size = 3000]) =>
        'data:image/jpeg;base64,${seed * size}';

    Book withCover(String id, String cover) =>
        _book(id).copyWith(coverUrl: () => cover);

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
    });

    tearDown(() => phone.server.stop());

    Future<String?> pair() =>
        sync.pair(address: phone.address, code: _code);

    test('a cover on each side reaches the other', () async {
      await pc.replaceAll([withCover('pc', picture('a'))]);
      await phone.repository.replaceAll([withCover('phone', picture('b'))]);

      expect(await pair(), isNull);

      for (final books in [pc.allBooks, phone.repository.allBooks]) {
        final covers = {for (final b in books) b.id: b.coverUrl};
        expect(covers, {'pc': picture('a'), 'phone': picture('b')});
      }
    });

    test('a library of a thousand books with pictures syncs', () async {
      await pc.replaceAll([
        for (var i = 0; i < 1000; i++)
          withCover('b$i', picture(String.fromCharCode(97 + i % 26), 1000 + i)),
      ]);

      expect(await pair(), isNull);

      expect(phone.repository.allBooks, hasLength(1000));
      expect(
        phone.repository.allBooks.where((b) => isDataCoverUrl(b.coverUrl)),
        hasLength(1000),
      );
      // Each picture went once. The same picture on two books is one.
      expect(phone.covers.puts, 1000);
      expect(phone.covers.gets, 0);

      // Nothing moves on the next sync.
      phone.covers.puts = 0;
      expect(await sync.syncNow(), isNull);
      expect(phone.covers.puts, 0);
      expect(phone.covers.gets, 0);
    });

    test('a picture the phone lost since it was asked is sent again', () async {
      await pc.replaceAll([withCover('pc', picture('a'))]);
      phone.covers.lieAboutMissing = true;

      expect(await pair(), isNull);
      expect(phone.repository.byId('pc')!.coverUrl, picture('a'));
    });

    test('a picture the phone no longer has leaves that book without a cover',
        () async {
      await phone.repository.replaceAll([
        withCover('one', picture('a')),
        withCover('two', picture('b')),
      ]);
      phone.covers.lost.add(coverHash(picture('a')));

      expect(await pair(), isNull);
      expect(pc.byId('one')!.coverUrl, isNull);
      expect(pc.byId('two')!.coverUrl, picture('b'));
    });

    test('a damaged picture from the phone is not kept as a cover', () async {
      await phone.repository.replaceAll([withCover('one', picture('a'))]);
      phone.covers.damaged.add(coverHash(picture('a')));

      expect(await pair(), isNull);
      expect(pc.byId('one')!.coverUrl, isNull);
    });

    test('the copy of the last sync keeps references, not pictures', () async {
      await pc.replaceAll([withCover('pc', picture('a', 20000))]);
      expect(await pair(), isNull);
      expect(sync.base.books['pc']!['coverUrl'], startsWith(coverRefPrefix));
    });
  });

  group('problems get a clear message', () {
    final client = SyncClient(
      pingTimeout: const Duration(seconds: 2),
      syncTimeout: const Duration(seconds: 2),
    );

    Future<String?> pingProblem(String address) async {
      try {
        await client.ping(parsePhoneAddress(address)!);
        return null;
      } on SyncFailure catch (error) {
        return error.message;
      }
    }

    test('nothing listening', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      expect(await pingProblem('127.0.0.1:$port'), startsWith(unreachableMessage));
    });

    test('something that is not Chapterly', () async {
      final server = await _replyWith(200, 'hello');
      addTearDown(() => server.close(force: true));
      expect(
        await pingProblem('127.0.0.1:${server.port}'),
        contains('not a Chapterly phone'),
      );
    });

    test('a phone with a newer protocol', () async {
      final server = await _replyWith(
        200,
        jsonEncode({'app': 'chapterly', 'protocol': syncProtocolVersion + 1}),
      );
      addTearDown(() => server.close(force: true));
      expect(
        await pingProblem('127.0.0.1:${server.port}'),
        contains('Update the Windows app'),
      );
    });

    test('a phone that needs updating', () async {
      final server = await _replyWith(
        400,
        jsonEncode({'error': 'This sync needs a newer version of Chapterly.'}),
      );
      addTearDown(() => server.close(force: true));
      await expectLater(
        client.sync(
          parsePhoneAddress('127.0.0.1:${server.port}')!,
          _code,
          encodeSyncPayload(const [], const {}),
        ),
        throwsA(
          isA<SyncFailure>().having(
            (f) => f.message,
            'message',
            'Update Chapterly on your phone.',
          ),
        ),
      );
    });
  });

  group('a phone that hangs up while the library is sent', () {
    // A phone that refuses the pairing code answers and hangs up without
    // reading the library, which Windows reports as a broken connection.
    Future<String> problemWith(int? probeStatus) async {
      final client = SyncClient(
        client: MockClient((request) async {
          if (request.body == '{}') {
            if (probeStatus == null) throw http.ClientException('gone');
            return http.Response('{"error":"x"}', probeStatus);
          }
          throw http.ClientException('connection forcibly closed');
        }),
      );
      try {
        await client.sync(Uri.parse('http://192.168.1.170:8765'), _code, '{"big":1}');
        return '';
      } on SyncFailure catch (error) {
        return error.message;
      }
    }

    test('a refused code is reported as a wrong code', () async {
      expect(await problemWith(401), contains('pairing code is wrong'));
    });

    test('an accepted code says the phone hung up', () async {
      final message = await problemWith(400);
      expect(message, startsWith(unreachableMessage));
      expect(message, contains('Details (sync)'));
      expect(message, contains('code was accepted'));
    });

    test('a phone that cannot be asked again keeps the details', () async {
      final message = await problemWith(null);
      expect(message, startsWith(unreachableMessage));
      expect(message, contains('Details (sync)'));
      expect(message, isNot(contains('code was accepted')));
    });
  });

  group('fields from a newer phone app', () {
    test('are kept and sent back', () {
      final json = {..._book('a').toJson(), 'mood': 'cosy', 'stars': 4};
      final book = Book.fromJson(json);
      expect(book.extras, {'mood': 'cosy', 'stars': 4});
      expect(book.toJson()['mood'], 'cosy');
      expect(Book.fromMap(book.toMap()).extras, {'mood': 'cosy', 'stars': 4});
      expect(book.copyWith(rating: () => 3).toJson()['stars'], 4);
    });

    test('books from this app have none', () {
      expect(Book.fromJson(_book('a').toJson()).extras, isEmpty);
    });
  });
}
