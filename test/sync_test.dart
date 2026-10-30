import 'dart:convert';
import 'dart:io';

import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/sync_merge.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(String id, {String title = 'Title', DateTime? updated}) =>
    Book(
      id: id,
      title: title,
      author: 'Author',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      updatedAt: updated,
    );

final _t1 = DateTime(2026, 1, 1);
final _t2 = DateTime(2026, 2, 1);
final _t3 = DateTime(2026, 3, 1);

MergedLibrary _merge({
  List<Book> local = const [],
  Map<String, DateTime> localTombs = const {},
  List<Book> remote = const [],
  Map<String, DateTime> remoteTombs = const {},
}) =>
    mergeLibraries(
      local: local,
      localTombstones: localTombs,
      remote: remote,
      remoteTombstones: remoteTombs,
    );

void main() {
  group('merging two libraries', () {
    test('the newer copy of a book wins', () {
      final result = _merge(
        local: [_book('1', title: 'Old', updated: _t1)],
        remote: [_book('1', title: 'New', updated: _t2)],
      );
      expect(result.books.single.title, 'New');
    });

    test('the local copy wins a tie', () {
      final result = _merge(
        local: [_book('1', title: 'Mine', updated: _t1)],
        remote: [_book('1', title: 'Theirs', updated: _t1)],
      );
      expect(result.books.single.title, 'Mine');
    });

    test('books on only one side are kept', () {
      final result = _merge(
        local: [_book('1', updated: _t1)],
        remote: [_book('2', updated: _t1)],
      );
      expect(result.books.map((b) => b.id), unorderedEquals(['1', '2']));
    });

    test('a permanent deletion beats an older copy', () {
      final result = _merge(
        local: [_book('1', updated: _t1)],
        remoteTombs: {'1': _t2},
      );
      expect(result.books, isEmpty);
      expect(result.tombstones, {'1': _t2});
    });

    test('a change made after a deletion brings the book back', () {
      final result = _merge(
        local: [_book('1', updated: _t3)],
        localTombs: {'1': _t2},
      );
      expect(result.books.single.id, '1');
      expect(result.tombstones, isEmpty);
    });

    test('a deletion on this phone is kept when the PC is out of date', () {
      final result = _merge(
        remote: [_book('1', updated: _t1)],
        localTombs: {'1': _t2},
      );
      expect(result.books, isEmpty);
      expect(result.tombstones.containsKey('1'), isTrue);
    });

    test('the newest deletion time is kept when both sides deleted it', () {
      final result = _merge(
        localTombs: {'1': _t1},
        remoteTombs: {'1': _t2},
      );
      expect(result.tombstones, {'1': _t2});
    });
  });

  group('sync messages', () {
    test('books and deletions survive a round trip', () {
      final text = encodeSyncPayload(
        [_book('1', title: 'Dune', updated: _t2)],
        {'9': _t3},
      );
      final payload = decodeSyncPayload(text);
      expect(payload.books.single.title, 'Dune');
      expect(payload.books.single.updatedAt, _t2);
      expect(payload.tombstones, {'9': _t3});
    });

    test('a message from a newer protocol is refused', () {
      final text = jsonEncode({
        'app': 'chapterly',
        'protocol': syncProtocolVersion + 1,
        'books': [],
        'tombstones': {},
      });
      expect(() => decodeSyncPayload(text), throwsFormatException);
    });

    test('other JSON is refused', () {
      expect(() => decodeSyncPayload('{"x":1}'), throwsFormatException);
      expect(() => decodeSyncPayload('not json'), throwsFormatException);
    });

    test('pairing codes are 16 readable characters', () {
      final code = newSyncCode();
      expect(code, hasLength(16));
      expect(RegExp(r'^[A-HJ-NP-Z2-9]+$').hasMatch(code), isTrue);
      expect(newSyncCode(), isNot(code));
    });
  });

  group('the phone server', () {
    late SyncServer server;
    late HttpClient client;

    setUp(() async {
      server = SyncServer(
        token: 'SECRET',
        handleSync: (body) async => '{"echo":${jsonEncode(body)}}',
      );
      await server.start(port: 0);
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<(int, String)> call(
      String method,
      String path, {
      String? code,
      String? body,
    }) async {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${server.boundPort}$path'),
      );
      if (code != null) request.headers.set('authorization', 'Bearer $code');
      if (body != null) request.write(body);
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      return (response.statusCode, text);
    }

    test('ping works without a code', () async {
      final (status, text) = await call('GET', '/v1/ping');
      expect(status, 200);
      expect(text, contains('chapterly'));
    });

    test('sync refuses a wrong code', () async {
      final (status, _) = await call(
        'POST',
        '/v1/sync',
        code: 'WRONG',
        body: '{}',
      );
      expect(status, 401);
    });

    test('sync with the right code gets the reply', () async {
      final (status, text) = await call(
        'POST',
        '/v1/sync',
        code: 'SECRET',
        body: 'hello',
      );
      expect(status, 200);
      expect(text, '{"echo":"hello"}');
    });
  });

  group('repository sync support', () {
    test('a permanent deletion is remembered as a tombstone', () async {
      final repo = BookRepository(InMemoryBookStore());
      await repo.load();
      await repo.add(title: 'Dune', author: 'Herbert', shelf: Shelf.forLater);
      final id = repo.books.single.id;
      await repo.moveToTrash(id);
      await repo.deleteForever(id);
      expect(repo.snapshot().tombstones.containsKey(id), isTrue);
      expect(repo.snapshot().books, isEmpty);
    });

    test('applying a sync result replaces the library', () async {
      final repo = BookRepository(InMemoryBookStore());
      await repo.load();
      await repo.add(title: 'Mine', author: 'A', shelf: Shelf.forLater);
      await repo.applySynced([_book('x', title: 'Theirs', updated: _t2)], {});
      expect(repo.books.map((b) => b.title), ['Theirs']);
    });

    test('edits stamp the time they were made', () async {
      final repo = BookRepository(InMemoryBookStore());
      await repo.load();
      await repo.add(title: 'Dune', author: 'A', shelf: Shelf.forLater);
      final before = repo.books.single.updatedAt;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.setNotes(repo.books.single.id, 'Edited');
      expect(repo.books.single.updatedAt.isAfter(before), isTrue);
    });
  });
}
