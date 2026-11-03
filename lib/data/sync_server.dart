import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;
import 'dart:io';
import 'dart:math';

import 'sync_covers.dart';
import 'sync_protocol.dart';

/// The largest sync message the phone will read. Thousands of books fit
/// easily: covers are not in it, they have their own requests.
const _maxBodyBytes = 50 * 1024 * 1024;

/// The largest cover picture, and the largest list of cover names.
const _maxCoverBytes = 2 * 1024 * 1024;
const _maxHashListBytes = 2 * 1024 * 1024;
const _maxHashes = 50000;

/// The cover pictures this device keeps for a sync, which a PC reads and
/// adds to over `/v1/covers`.
abstract interface class SyncCovers {
  /// Which of [hashes] this device does not have.
  Future<List<String>> missing(List<String> hashes);

  /// Keeps a picture. Throws a [FormatException] if it is not that cover.
  Future<void> put(String hash, String dataUrl);

  /// The picture named [hash], or null.
  Future<String?> get(String hash);
}

const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// A random 16-character pairing code. Letters that look alike (0, O, 1, I)
/// are left out so it is easy to read and type.
String newSyncCode([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(
    16,
    (_) => _codeChars[source.nextInt(_codeChars.length)],
  ).join();
}

/// Addresses this phone has on the home network, such as 192.168.1.20.
Future<List<String>> localAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: false,
  );
  return [
    for (final interface in interfaces)
      for (final address in interface.addresses)
        if (!address.isLoopback) address.address,
  ];
}

/// A small HTTP server on the home network. The PC uses these requests:
///
/// - `GET /v1/ping` (no code needed) says whether this is a Chapterly phone.
/// - `POST /v1/sync` with `Authorization: Bearer <code>` and the PC's library
///   as the body. The reply is the merged library. Books carry cover
///   references (see sync_covers.dart), never the pictures.
/// - `POST /v1/covers/missing`, `PUT /v1/covers/<name>` and
///   `GET /v1/covers/<name>` (with the code) move the cover pictures.
class SyncServer {
  SyncServer({required this.token, required this.handleSync, this.covers});

  final String token;
  final Future<String> Function(String body) handleSync;
  final SyncCovers? covers;
  HttpServer? _server;

  bool get running => _server != null;

  /// The port in use. Useful when [start] was given port 0 (tests).
  int? get boundPort => _server?.port;

  Future<void> start({int port = defaultSyncPort}) async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen((request) => unawaited(_serve(request)));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  bool _authorized(HttpRequest request) =>
      request.headers.value('authorization') == 'Bearer $token';

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/ping') {
        _json(response, 200, {
          'app': 'chapterly',
          'protocol': syncProtocolVersion,
        });
      } else if (request.method == 'POST' && path == '/v1/sync') {
        if (!_authorized(request)) {
          _json(response, 401, {'error': 'Wrong or missing pairing code.'});
        } else {
          final body = await _readBody(request, _maxBodyBytes);
          final reply = await handleSync(body);
          response.statusCode = 200;
          response.headers.contentType = ContentType.json;
          response.write(reply);
        }
      } else if (path.startsWith('/v1/covers') && covers != null) {
        await _serveCovers(request);
      } else {
        _json(response, 404, {'error': 'Not found.'});
      }
    } on MissingCovers catch (error) {
      _json(response, 409, {
        'error': 'Some covers are missing.',
        'missing': error.hashes,
      });
    } on FormatException catch (error) {
      _json(response, 400, {'error': error.message});
    } catch (_) {
      _json(response, 500, {'error': 'Sync failed on the phone.'});
    } finally {
      await response.close();
    }
  }

  Future<void> _serveCovers(HttpRequest request) async {
    final response = request.response;
    final covers = this.covers!;
    if (!_authorized(request)) {
      _json(response, 401, {'error': 'Wrong or missing pairing code.'});
      return;
    }
    final path = request.uri.path;
    if (request.method == 'POST' && path == '/v1/covers/missing') {
      final data = jsonDecode(await _readBody(request, _maxHashListBytes));
      final list = data is Map ? data['hashes'] : null;
      if (list is! List || list.length > _maxHashes) {
        throw const FormatException('Not a list of covers.');
      }
      final hashes = [
        for (final item in list)
          if (item is String && isCoverHash(item)) item,
      ];
      _json(response, 200, {'missing': await covers.missing(hashes)});
      return;
    }
    final hash = path.startsWith('/v1/covers/')
        ? path.substring('/v1/covers/'.length)
        : '';
    if (!isCoverHash(hash)) {
      _json(response, 404, {'error': 'Not found.'});
    } else if (request.method == 'GET') {
      final picture = await covers.get(hash);
      if (picture == null) {
        _json(response, 404, {'error': 'No such cover.'});
      } else {
        response.statusCode = 200;
        response.headers.contentType = ContentType.text;
        response.write(picture);
      }
    } else if (request.method == 'PUT') {
      await covers.put(hash, await _readBody(request, _maxCoverBytes));
      response.statusCode = 204;
    } else {
      _json(response, 404, {'error': 'Not found.'});
    }
  }

  Future<String> _readBody(HttpRequest request, int limit) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > limit) {
        throw const FormatException('The sync message is too large.');
      }
    }
    return utf8.decode(builder.takeBytes());
  }

  void _json(HttpResponse response, int status, Map<String, Object?> data) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
  }
}
