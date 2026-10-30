import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;
import 'dart:io';
import 'dart:math';

import 'sync_protocol.dart';

/// The largest sync message the phone will read. Thousands of books fit easily.
const _maxBodyBytes = 50 * 1024 * 1024;

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

/// A small HTTP server on the home network. The PC uses two requests:
///
/// - `GET /v1/ping` (no code needed) says whether this is a Chapterly phone.
/// - `POST /v1/sync` with `Authorization: Bearer <code>` and the PC's library
///   as the body. The reply is the merged library.
class SyncServer {
  SyncServer({required this.token, required this.handleSync});

  final String token;
  final Future<String> Function(String body) handleSync;
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

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method == 'GET' && request.uri.path == '/v1/ping') {
        _json(response, 200, {
          'app': 'chapterly',
          'protocol': syncProtocolVersion,
        });
      } else if (request.method == 'POST' && request.uri.path == '/v1/sync') {
        if (request.headers.value('authorization') != 'Bearer $token') {
          _json(response, 401, {'error': 'Wrong or missing pairing code.'});
        } else {
          final body = await _readBody(request);
          final reply = await handleSync(body);
          response.statusCode = 200;
          response.headers.contentType = ContentType.json;
          response.write(reply);
        }
      } else {
        _json(response, 404, {'error': 'Not found.'});
      }
    } on FormatException catch (error) {
      _json(response, 400, {'error': error.message});
    } catch (_) {
      _json(response, 500, {'error': 'Sync failed on the phone.'});
    } finally {
      await response.close();
    }
  }

  Future<String> _readBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > _maxBodyBytes) {
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
