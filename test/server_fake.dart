import 'dart:convert';
import 'dart:typed_data';

import 'package:chapterly/server/server_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A book server in memory that behaves like Chapterly-Server: the
/// furthest place wins (unless reset), bookmarks merge by addedAt with the
/// newer updatedAt winning. Shared by the phone and PC tests.
class FakeServer {
  FakeServer({this.token = 'secret-token', this.name = 'hans'});

  final String token;
  final String name;
  final books = <String, Map<String, Object?>>{};
  final files = <String, Uint8List>{};
  final tracks = <String, List<Uint8List>>{};
  final progress = <String, Map<String, Object?>>{};
  final bookmarks = <String, Map<String, Map<String, Object?>>>{};
  final requests = <String>[];

  /// Set to make every request fail as if the server were away.
  bool away = false;

  /// Set to make downloads fail with this status.
  int? downloadStatus;

  /// Set to make pages of the library from this offset on fail.
  int? failBooksFrom;

  /// Runs while a request is being answered, to change things meanwhile.
  Future<void> Function(String method, String path)? during;
  int _clock = 0;

  /// Server times go up by a second per save, like a real clock.
  String _stamp() {
    _clock++;
    return DateTime.utc(2026, 11, 1, 12, 0, _clock).toIso8601String();
  }

  void addBook(
    String id,
    String title, {
    String author = '',
    String kind = 'ebook',
    String format = 'epub',
    List<int>? bytes,
    int? durationMs,
    String? series,
    double? seriesIndex,
    List<List<int>>? parts,
  }) {
    final data = Uint8List.fromList(bytes ?? utf8.encode('file of $title'));
    files[id] = data;
    if (parts != null) {
      tracks[id] = [for (final p in parts) Uint8List.fromList(p)];
    }
    books[id] = {
      'id': id,
      'title': title,
      'author': author,
      'series': series,
      'seriesIndex': seriesIndex,
      'kind': kind,
      'format': format,
      'size': parts == null ? data.length : parts.fold<int>(0, (s, p) => s + p.length),
      'trackCount': parts?.length ?? 1,
      'durationMs': durationMs,
      'hasCover': false,
      'addedAt': '2026-11-01T00:00:00Z',
    };
  }

  /// Saves a place, as the real server does (also how a test plays
  /// another device).
  Map<String, Object?> save(String id, double fraction, String position,
      {bool reset = false, String? base}) {
    final old = progress[id];
    final resetAt = old?['resetAt'] as String?;
    final stale = !reset && resetAt != null && base != null &&
        base.compareTo(resetAt) < 0;
    final apply = reset ||
        old == null ||
        (!stale && fraction >= (old['fraction'] as double));
    if (apply) {
      final stamp = _stamp();
      progress[id] = {
        'bookId': id,
        'fraction': fraction,
        'position': position,
        'updatedAt': stamp,
        'resetAt': reset ? stamp : resetAt,
      };
    }
    return {'applied': apply, 'progress': progress[id]};
  }

  ServerClient client({String? token}) => ServerClient(
        address: Uri.parse('http://100.1.2.3:8780'),
        token: token ?? this.token,
        client: httpClient,
      );

  MockClient get httpClient => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    requests.add('${request.method} $path');
    if (away) throw http.ClientException('away');
    await during?.call(request.method, path);
    if (path == '/v1/ping') {
      return _json({'app': 'chapterly-server', 'protocol': 1});
    }
    if (request.headers['Authorization'] != 'Bearer $token') {
      return _json({'detail': 'Wrong or missing token.'}, 401);
    }
    final parts = path.split('/');
    if (path == '/v1/me') return _json({'name': name});
    if (path == '/v1/books') {
      final q = (request.url.queryParameters['q'] ?? '').toLowerCase();
      final kind = request.url.queryParameters['kind'];
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      if (failBooksFrom != null && offset >= failBooksFrom!) {
        return _json({'detail': 'Broken'}, 500);
      }
      final limit = int.parse(request.url.queryParameters['limit'] ?? '50');
      final all = [
        for (final b in books.values)
          if ((kind == null || b['kind'] == kind) &&
              ('${b['title']} ${b['author']}'.toLowerCase().contains(q)))
            {...b, 'progress': progress[b['id']]},
      ];
      return _json({
        'total': all.length,
        'books': all.skip(offset).take(limit).toList(),
      });
    }
    if (parts.length == 5 && parts[2] == 'books' && parts[4] == 'file') {
      final data = files[parts[3]];
      if (data == null) return _json({'detail': 'No such book.'}, 404);
      if (downloadStatus != null) return _json({'detail': 'Broken'}, downloadStatus!);
      return http.Response.bytes(data, 200);
    }
    if (parts.length == 5 && parts[2] == 'books' && parts[4] == 'tracks') {
      final list = tracks[parts[3]];
      if (list == null) return _json({'detail': 'No such book.'}, 404);
      return _json({
        'tracks': [
          for (var i = 0; i < list.length; i++)
            {'index': i, 'name': 'Part ${i + 1}.mp3', 'size': list[i].length, 'durationMs': 1000},
        ],
      });
    }
    if (parts.length == 7 && parts[4] == 'tracks' && parts[6] == 'file') {
      final list = tracks[parts[3]];
      final index = int.tryParse(parts[5]);
      if (list == null || index == null || index >= list.length) {
        return _json({'detail': 'No such track.'}, 404);
      }
      if (downloadStatus != null) return _json({'detail': 'Broken'}, downloadStatus!);
      return http.Response.bytes(list[index], 200);
    }
    if (parts.length == 4 && parts[2] == 'progress') {
      final id = parts[3];
      if (!books.containsKey(id)) return _json({'detail': 'No such book.'}, 404);
      if (request.method == 'GET') return _json({'progress': progress[id]});
      final body = jsonDecode(request.body) as Map;
      return _json(save(
        id,
        (body['fraction'] as num).toDouble(),
        body['position'] as String,
        reset: body['reset'] == true,
        base: body['base'] as String?,
      ));
    }
    if (path == '/v1/progress') {
      return _json({'progress': progress.values.toList()});
    }
    if (parts.length == 5 && parts[2] == 'books' && parts[4] == 'bookmarks') {
      final id = parts[3];
      if (!books.containsKey(id)) return _json({'detail': 'No such book.'}, 404);
      final marks = bookmarks.putIfAbsent(id, () => {});
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map;
        for (final raw in body['bookmarks'] as List) {
          final mark = Map<String, Object?>.from(raw as Map);
          mark['updatedAt'] ??= _stamp();
          final old = marks[mark['addedAt']];
          if (old != null &&
              !DateTime.parse(mark['updatedAt'] as String)
                  .isAfter(DateTime.parse(old['updatedAt'] as String))) {
            continue;
          }
          marks[mark['addedAt'] as String] = {'deletedAt': null, ...mark};
        }
      }
      return _json({'bookmarks': marks.values.toList()});
    }
    return _json({'detail': 'Not found'}, 404);
  }

  static http.Response _json(Object? data, [int status = 200]) => http.Response(
        jsonEncode(data),
        status,
        headers: {'content-type': 'application/json'},
      );
}
