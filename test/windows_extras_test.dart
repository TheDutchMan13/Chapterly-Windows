import 'dart:convert';
import 'dart:io';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/backup.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/dropped_file.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/data/phone_finder.dart';
import 'package:chapterly/data/sync_merge.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:chapterly/data/update_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _code = 'ABCDEFGHJKMNPQRS';

const _clippings = '﻿Dune (Frank Herbert)\r\n'
    '- Your Highlight on page 12 | Location 180-182 | Added on Monday, '
    'January 1, 2024 10:05:00 PM\r\n'
    '\r\n'
    'Fear is the mind-killer.\r\n'
    '==========\r\n';

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
  group('finding the phone', () {
    test('home-network addresses are recognised', () {
      expect(isPrivateIPv4('192.168.1.20'), isTrue);
      expect(isPrivateIPv4('10.0.0.5'), isTrue);
      expect(isPrivateIPv4('172.16.4.1'), isTrue);
      expect(isPrivateIPv4('172.32.4.1'), isFalse);
      expect(isPrivateIPv4('8.8.8.8'), isFalse);
      expect(isPrivateIPv4('127.0.0.1'), isFalse);
      expect(isPrivateIPv4('192.168.1'), isFalse);
      expect(isPrivateIPv4('192.168.1.300'), isFalse);
    });

    test('every neighbour is tried once, but not this PC', () {
      final hosts = candidateAddresses([
        '192.168.1.20',
        '192.168.1.21',
        '8.8.8.8',
      ]);
      expect(hosts.length, 252);
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
      expect(hosts, isNot(contains('192.168.1.20')));
      expect(hosts.toSet().length, hosts.length);
    });

    test('the scan keeps the order and ignores failures', () async {
      final found = await scanHosts(
        ['a', 'b', 'c', 'd'],
        (host) async {
          if (host == 'c') throw const SocketException('no');
          return host == 'd' || host == 'b';
        },
        workers: 2,
      );
      expect(found, ['b', 'd']);
    });

    test('a probe finds a real phone and skips a closed port', () async {
      final phone = BookRepository(InMemoryBookStore());
      final server = await _startPhone(phone);
      addTearDown(server.stop);
      final client = SyncClient(pingTimeout: const Duration(seconds: 2));

      expect(
        await probeHost('127.0.0.1', client, port: server.boundPort!),
        isTrue,
      );

      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closed = socket.port;
      await socket.close();
      expect(await probeHost('127.0.0.1', client, port: closed), isFalse);
    });
  });

  group('sync when Chapterly opens', () {
    late BookRepository pc;
    late AppSettings settings;
    late PcSync sync;

    setUp(() async {
      pc = BookRepository(InMemoryBookStore());
      await pc.load();
      settings = AppSettings();
      sync = PcSync(
        repository: pc,
        settings: settings,
        codeStore: MemoryCodeStore(),
        client: SyncClient(pingTimeout: const Duration(seconds: 2)),
      );
    });

    test('does nothing when not paired', () async {
      expect(await sync.syncOnOpen(), isFalse);
      expect(settings.lastSyncAt, isNull);
    });

    test('syncs when the phone is there', () async {
      final phone = BookRepository(InMemoryBookStore());
      final server = await _startPhone(phone);
      addTearDown(server.stop);
      final address = '127.0.0.1:${server.boundPort}';
      expect(await sync.pair(address: address, code: _code), isNull);

      expect(await sync.syncOnOpen(), isTrue);
    });

    test('stays quiet when the phone is not there', () async {
      final phone = BookRepository(InMemoryBookStore());
      final server = await _startPhone(phone);
      final address = '127.0.0.1:${server.boundPort}';
      expect(await sync.pair(address: address, code: _code), isNull);
      await server.stop();

      expect(await sync.syncOnOpen(), isFalse);
      expect(settings.lastSyncError, isNull);
    });

    test('can be switched off', () async {
      final phone = BookRepository(InMemoryBookStore());
      final server = await _startPhone(phone);
      addTearDown(server.stop);
      final address = '127.0.0.1:${server.boundPort}';
      expect(await sync.pair(address: address, code: _code), isNull);
      settings.setSyncOnOpen(false);

      expect(await sync.syncOnOpen(), isFalse);
    });

    test('a new address for the phone is checked and saved', () async {
      final phone = BookRepository(InMemoryBookStore());
      final server = await _startPhone(phone);
      addTearDown(server.stop);
      final address = '127.0.0.1:${server.boundPort}';

      expect(await sync.changeAddress('not an address/x'), isNotNull);
      expect(await sync.changeAddress(address), isNull);
      expect(settings.syncAddress, address);
    });
  });

  group('update check', () {
    String release(String tag, {bool prerelease = false}) => jsonEncode({
          'tag_name': tag,
          'html_url': 'https://github.com/TheDutchMan13/Chapterly-Windows/'
              'releases/tag/$tag',
          'draft': false,
          'prerelease': prerelease,
        });

    test('versions are compared number by number', () {
      expect(isNewerVersion('v1.2.0', '1.1.0'), isTrue);
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
      expect(isNewerVersion('v1.1', '1.1.0'), isFalse);
      expect(isNewerVersion('v1.0.9', '1.1.0'), isFalse);
      expect(isNewerVersion('v2.0.0+5', '1.9.9'), isTrue);
      expect(isNewerVersion('nightly', '1.1.0'), isFalse);
    });

    test('only a newer, finished release counts', () {
      expect(parseLatestRelease(release('v1.2.0'), current: '1.1.0')?.version,
          '1.2.0');
      expect(parseLatestRelease(release('v1.1.0'), current: '1.1.0'), isNull);
      expect(
        parseLatestRelease(release('v1.2.0', prerelease: true),
            current: '1.1.0'),
        isNull,
      );
      expect(parseLatestRelease('not json', current: '1.1.0'), isNull);
    });

    test('GitHub answers are handled', () async {
      Future<AvailableUpdate?> ask(int status, String body) => checkForUpdate(
            client: MockClient((_) async => http.Response(body, status)),
            current: '1.1.0',
          );
      expect((await ask(200, release('v1.3.0')))?.version, '1.3.0');
      expect(await ask(200, release('v1.1.0')), isNull);
      expect(await ask(404, '{}'), isNull);
      await expectLater(ask(500, ''), throwsA(isA<UpdateCheckFailure>()));
    });

    test('the daily check respects the switch and the day', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(release('v9.0.0'), 200);
      });
      final settings = AppSettings();
      final now = DateTime(2026, 10, 30, 12);

      expect(
        (await checkForUpdateIfDue(settings, client: client, now: now))
            ?.version,
        '9.0.0',
      );
      expect(
        await checkForUpdateIfDue(
          settings,
          client: client,
          now: now.add(const Duration(hours: 3)),
        ),
        isNull,
      );
      settings.setCheckUpdates(false);
      expect(
        await checkForUpdateIfDue(
          settings,
          client: client,
          now: now.add(const Duration(days: 2)),
        ),
        isNull,
      );
      expect(calls, 1);
    });

    test('the switches are remembered', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      expect(settings.syncOnOpen, isTrue);
      expect(settings.checkUpdates, isTrue);
      settings
        ..setSyncOnOpen(false)
        ..setCheckUpdates(false);
      final again = await AppSettings.load();
      expect(again.syncOnOpen, isFalse);
      expect(again.checkUpdates, isFalse);
    });
  });

  group('dropped files', () {
    test('each kind is recognised', () {
      expect(
        detectDroppedFile('My Clippings.txt', _clippings),
        DroppedFileKind.kindle,
      );
      expect(
        detectDroppedFile('backup.json', encodeBackup(const [])),
        DroppedFileKind.backup,
      );
      expect(
        detectDroppedFile('books.CSV', 'title,author\nDune,Herbert\n'),
        DroppedFileKind.csv,
      );
      expect(
        detectDroppedFile('other.json', '{"hello": 1}'),
        DroppedFileKind.unknown,
      );
      expect(
        detectDroppedFile('photo.txt', 'just some text'),
        DroppedFileKind.unknown,
      );
    });

    test('the invisible start mark is removed', () {
      expect(stripBom('﻿abc'), 'abc');
      expect(stripBom('abc'), 'abc');
    });
  });
}
