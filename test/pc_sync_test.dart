import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/data/sync_covers.dart';
import 'package:chapterly/data/sync_crypto.dart';
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


final _address = Uri.parse('http://192.168.1.170:8765');

/// A phone answering over MockClient: the ping, the hello, and sealed
/// answers, able to misbehave.
class _FakePhone {
  _FakePhone._(this.key, this.replyKey, this.pingSync);

  static Future<_FakePhone> create({
    String? replyCode,
    int? pingSync = 2,
  }) async {
    final key = await SyncKey.fromCode(_code);
    final reply = replyCode == null ? key : await SyncKey.fromCode(replyCode);
    return _FakePhone._(key, reply, pingSync);
  }

  final SyncKey key;
  final SyncKey replyKey;
  final int? pingSync;
  int hellos = 0;

  /// How many sealed requests are answered "unknown challenge".
  int expireNext = 0;

  /// Answer sealed requests with plain JSON instead.
  bool plainReply = false;

  /// Refuse the code in plain, as a phone that can't open the request does.
  bool plainCodeRefusal = false;
  final sealed = <String>[];
  final raw = <http.Request>[];
  List<Book> phoneBooks = [_book('phone')];
  Map<String, DateTime> phoneTombstones = const {};

  /// The status and plain text of the answer to an opened request.
  Future<(int, String)> Function(String method, String path, String plain)?
      answer;

  Future<(int, String)> _defaultAnswer(
    String method,
    String path,
    String plain,
  ) async {
    if (path == '/v2/sync') {
      return (200, encodeSyncPayload(phoneBooks, phoneTombstones));
    }
    if (path == '/v2/covers/missing') return (200, '{"missing":[]}');
    return (404, '{"error":"No such cover."}');
  }

  http.Client get client => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    raw.add(request);
    final path = request.url.path;
    if (path == '/v1/ping') {
      return http.Response(
        jsonEncode({
          'app': 'chapterly',
          'protocol': syncProtocolVersion,
          'sync': ?pingSync,
        }),
        200,
      );
    }
    if (path == '/v2/hello') {
      hellos++;
      return http.Response(jsonEncode({'challenge': 'c$hellos'}), 200);
    }
    final challenge = request.headers['x-chapterly-challenge']!;
    if (expireNext > 0) {
      expireNext--;
      return http.Response('{"error":"challenge"}', 401);
    }
    final plain = utf8.decode(
      await key.open(
        request.bodyBytes,
        requestContext(request.method, path, challenge),
      ),
    );
    sealed.add('${request.method} $path');
    final (status, text) =
        await (answer ?? _defaultAnswer)(request.method, path, plain);
    if (plainCodeRefusal && status == 401) {
      return http.Response('{"error":"code"}', 401);
    }
    if (plainReply) return http.Response(text, status);
    return http.Response.bytes(
      await replyKey.seal(
        utf8.encode(text),
        responseContext(request.method, path, challenge),
      ),
      status,
    );
  }
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
      final phone = await _FakePhone.create();
      phone.answer = (method, path, plain) async => (
            400,
            jsonEncode({'error': 'This sync needs a newer version of Chapterly.'}),
          );
      final client = SyncClient(client: phone.client);
      final session = await client.connect(_address, _code);
      await expectLater(
        client.sync(session, encodeSyncPayload(const [], const {})),
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
    // A phone that refuses the request answers and hangs up without
    // reading the library, which Windows reports as a broken connection.
    Future<String> problemWith(int? probeStatus) async {
      final phone = await _FakePhone.create();
      phone.answer = (method, path, plain) async {
        if (plain == '{}') {
          if (probeStatus == null) throw http.ClientException('gone');
          return (probeStatus, '{"error":"x"}');
        }
        throw http.ClientException('connection forcibly closed');
      };
      phone.plainCodeRefusal = probeStatus == 401;
      final client = SyncClient(client: phone.client);
      try {
        final session = await client.connect(_address, _code);
        await client.sync(session, '{"big":1}');
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

  group('sync version 2', () {
    late BookRepository pc;
    late AppSettings settings;
    late MemoryCodeStore codes;

    setUp(() async {
      pc = BookRepository(InMemoryBookStore());
      await pc.load();
      await pc.replaceAll([_book('pc')]);
      settings = AppSettings();
      codes = MemoryCodeStore();
    });

    PcSync syncWith(_FakePhone phone) => PcSync(
          repository: pc,
          settings: settings,
          codeStore: codes,
          client: SyncClient(client: phone.client),
        );

    test('a sealed sync works and the code never travels', () async {
      final phone = await _FakePhone.create();
      final sync = syncWith(phone);

      expect(
        await sync.pair(address: formatPhoneAddress(_address), code: _code),
        isNull,
      );

      expect(_ids(pc.allBooks), ['pc', 'phone']);
      expect(phone.sealed, contains('POST /v2/sync'));
      for (final request in phone.raw) {
        expect(request.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')));
        expect(latin1.decode(request.bodyBytes, allowInvalid: true),
            isNot(contains(_code)));
        expect(request.headers.values.join(' '), isNot(contains(_code)));
      }
    });

    test('an answer sealed with another code is refused and nothing applied',
        () async {
      final phone = await _FakePhone.create(replyCode: 'ZZZZZZZZZZZZZZZZ');
      final sync = syncWith(phone);

      final problem =
          await sync.pair(address: formatPhoneAddress(_address), code: _code);

      expect(
        problem,
        'The phone at ${_address.host} did not answer with your sync code. '
        'Pair again if you changed the code.',
      );
      expect(_ids(pc.allBooks), ['pc']);
      expect(sync.paired, isFalse);
    });

    test('a plain answer to a sealed request is refused', () async {
      final phone = await _FakePhone.create();
      phone.plainReply = true;
      final client = SyncClient(client: phone.client);
      final session = await client.connect(_address, _code);
      await expectLater(
        client.sync(session, encodeSyncPayload(const [], const {})),
        throwsA(isA<SyncFailure>().having(
            (f) => f.message, 'message', contains('did not answer with your'))),
      );
    });

    test('a phone without sync 2 asks for the phone app to be updated',
        () async {
      final phone = await _FakePhone.create(pingSync: null);
      final client = SyncClient(client: phone.client);
      await expectLater(
        client.ping(_address),
        throwsA(isA<SyncFailure>().having(
            (f) => f.message, 'message', updatePhoneForSyncMessage)),
      );
      final old = await _FakePhone.create(pingSync: 1);
      expect(
        await syncWith(old)
            .pair(address: formatPhoneAddress(_address), code: _code),
        updatePhoneForSyncMessage,
      );
      expect(old.sealed, isEmpty);
    });

    test('an old challenge is renewed once and the request sent again',
        () async {
      final phone = await _FakePhone.create();
      phone.expireNext = 1;
      final sync = syncWith(phone);

      expect(
        await sync.pair(address: formatPhoneAddress(_address), code: _code),
        isNull,
      );
      expect(phone.hellos, 2);
      expect(_ids(pc.allBooks), ['pc', 'phone']);
    });

    test('a challenge refused twice stops the sync', () async {
      final phone = await _FakePhone.create();
      phone.expireNext = 5;
      final client = SyncClient(client: phone.client);
      final session = await client.connect(_address, _code);
      await expectLater(
        client.sync(session, encodeSyncPayload(const [], const {})),
        throwsA(isA<SyncFailure>()),
      );
      expect(phone.hellos, 2);
    });

    test('an answer larger than the cap is refused', () async {
      final phone = await _FakePhone.create();
      phone.answer = (method, path, plain) async =>
          (200, 'x' * (maxCoverReplyBytes + 1));
      final client = SyncClient(client: phone.client);
      final session = await client.connect(_address, _code);
      await expectLater(
        client.getCover(session, coverHash('data:image/jpeg;base64,abcd')),
        throwsA(isA<SyncFailure>()
            .having((f) => f.message, 'message', tooLargeReplyMessage)),
      );
    });

    test('a streamed answer larger than the cap is refused while reading',
        () async {
      final chunk = Uint8List(1024 * 1024);
      final client = SyncClient(
        client: MockClient.streaming((request, body) async {
          await body.drain<void>();
          if (request.url.path == '/v2/hello') {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"challenge":"c1"}')),
              200,
            );
          }
          return http.StreamedResponse(
            Stream.fromIterable(List.filled(101, chunk)),
            200,
          );
        }),
      );
      final session = await client.connect(_address, _code);
      await expectLater(
        client.sync(session, encodeSyncPayload(const [], const {})),
        throwsA(isA<SyncFailure>()
            .having((f) => f.message, 'message', tooLargeReplyMessage)),
      );
    });

    test('dates far ahead in the phone\'s answer are dated now', () async {
      final phone = await _FakePhone.create();
      phone.phoneBooks = [_book('phone', updated: DateTime(2099))];
      phone.phoneTombstones = {'gone': DateTime(2099)};
      final sync = syncWith(phone);

      expect(
        await sync.pair(address: formatPhoneAddress(_address), code: _code),
        isNull,
      );
      final soon = DateTime.now().add(const Duration(days: 1));
      expect(pc.byId('phone')!.updatedAt.isBefore(soon), isTrue);
      expect(pc.snapshot().tombstones['gone']!.isBefore(soon), isTrue);
    });

    test('clampFutureDates keeps dates up to a day ahead', () {
      final now = DateTime(2026, 11, 4, 12);
      final payload = clampFutureDates(
        SyncPayload(
          books: [
            _book('near', updated: now.add(const Duration(hours: 20))),
            _book('far', updated: DateTime(2030)),
          ],
          tombstones: {'a': DateTime(2030), 'b': DateTime(2026, 1, 1)},
        ),
        now: now,
      );
      expect(payload.books.first.updatedAt, now.add(const Duration(hours: 20)));
      expect(payload.books.last.updatedAt, now);
      expect(payload.tombstones, {'a': now, 'b': DateTime(2026, 1, 1)});
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
