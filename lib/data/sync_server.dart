import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;
import 'dart:io';
import 'dart:math';

import 'sync_covers.dart';
import 'sync_crypto.dart';
import 'sync_protocol.dart';

/// The largest sync message the phone will read. Thousands of books fit
/// easily: covers are not in it, they have their own requests.
const _maxBodyBytes = 50 * 1024 * 1024;

/// The largest cover picture, and the largest list of cover names.
const _maxCoverBytes = 2 * 1024 * 1024;
const _maxHashListBytes = 2 * 1024 * 1024;
const _maxHashes = 50000;

/// The cover pictures this device keeps for a sync, which a PC reads and
/// adds to over `/v2/covers`.
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

/// A small HTTP server on the home network, speaking sync version 2 (the phone
/// app follows the same rules). The PC uses:
///
/// - `GET /v1/ping` (no code needed) says whether this is a Chapterly phone.
/// - `GET /v2/hello` (no code needed) gives a challenge.
/// - `POST /v2/sync`, `POST /v2/covers/missing`, `PUT /v2/covers/<name>` and
///   `GET /v2/covers/<name>`: sealed with a key made from the pairing code
///   and the challenge (see sync_crypto.dart). The answers are sealed too.
///   Books carry cover references (see sync_covers.dart), never the pictures.
class SyncServer {
  SyncServer({
    required this.token,
    required this.handleSync,
    this.covers,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String token;
  final Future<String> Function(String body) handleSync;
  final SyncCovers? covers;
  final DateTime Function() _now;
  HttpServer? _server;
  SyncKey? _key;

  /// Challenges given out, oldest first, with when they were given.
  final _challenges = <String, DateTime>{};

  /// Nonces of the requests already taken, with when they came.
  final _nonces = <String, DateTime>{};

  /// When requests failed to open, for the last minute.
  final _failures = <DateTime>[];
  DateTime? _blockedUntil;

  bool get running => _server != null;

  /// The port in use. Useful when [start] was given port 0 (tests).
  int? get boundPort => _server?.port;

  Future<void> start({int port = defaultSyncPort}) async {
    if (_server != null) return;
    _key = await SyncKey.fromCode(token);
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen((request) => unawaited(_serve(request)));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  String _challenge() {
    final now = _now();
    _challenges.removeWhere(
      (_, at) => now.difference(at) > const Duration(minutes: 5),
    );
    while (_challenges.length >= 32) {
      _challenges.remove(_challenges.keys.first);
    }
    final challenge = newChallenge();
    _challenges[challenge] = now;
    return challenge;
  }

  bool _knownChallenge(String challenge) {
    final at = _challenges[challenge];
    return at != null && _now().difference(at) <= const Duration(minutes: 5);
  }

  /// Remembers [nonce]; false when it was already used.
  bool _freshNonce(String nonce) {
    final now = _now();
    _nonces.removeWhere(
      (_, at) => now.difference(at) > const Duration(minutes: 10),
    );
    if (_nonces.containsKey(nonce)) return false;
    while (_nonces.length >= 2000) {
      _nonces.remove(_nonces.keys.first);
    }
    _nonces[nonce] = now;
    return true;
  }

  void _failedOpen() {
    final now = _now();
    _failures
      ..removeWhere((at) => now.difference(at) > const Duration(minutes: 1))
      ..add(now);
    if (_failures.length >= 20) {
      _blockedUntil = now.add(const Duration(minutes: 1));
      _failures.clear();
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/ping') {
        _json(response, 200, {
          'app': 'chapterly',
          'protocol': syncProtocolVersion,
          'sync': 2,
        });
      } else if (request.method == 'GET' && path == '/v2/hello') {
        _json(response, 200, {'challenge': _challenge()});
      } else if (path == '/v1/sync' || path.startsWith('/v1/covers')) {
        await request.drain<void>();
        _json(response, 426, {
          'error': 'Update Chapterly on your PC to sync with this phone.',
        });
      } else if (_isSealedRoute(request.method, path)) {
        await _serveSealed(request);
      } else {
        await request.drain<void>();
        _json(response, 404, {'error': 'Not found.'});
      }
    } catch (_) {
      // The PC went away.
    } finally {
      try {
        await response.close();
      } catch (_) {
        // Already gone.
      }
    }
  }

  bool _isSealedRoute(String method, String path) {
    if (method == 'POST' && path == '/v2/sync') return true;
    if (covers == null) return false;
    if (method == 'POST' && path == '/v2/covers/missing') return true;
    return (method == 'GET' || method == 'PUT') &&
        path.startsWith('/v2/covers/') &&
        path != '/v2/covers/missing';
  }

  int _limitFor(String method, String path) {
    if (path == '/v2/sync') return _maxBodyBytes;
    if (path == '/v2/covers/missing') return _maxHashListBytes;
    if (method == 'PUT') return _maxCoverBytes;
    return 0;
  }

  Future<void> _serveSealed(HttpRequest request) async {
    final response = request.response;
    final method = request.method;
    final path = request.uri.path;
    final blocked = _blockedUntil;
    if (blocked != null && _now().isBefore(blocked)) {
      await request.drain<void>();
      _json(response, 429, {'error': 'Too many tries. Wait a minute.'});
      return;
    }
    final header = request.headers.value('x-chapterly-challenge');
    if (header == null || !_knownChallenge(header)) {
      await request.drain<void>();
      _json(response, 401, {'error': 'challenge'});
      return;
    }
    final limit = _limitFor(method, path) + SyncKey.overhead;
    final sealed = await _readBytes(request, limit);
    if (sealed == null) {
      _json(response, 413, {'error': 'The sync message is too large.'});
      return;
    }
    final challenge = header;
    final key = _key!;
    final List<int> plain;
    try {
      plain = await key.open(sealed, requestContext(method, path, challenge));
    } on SyncAuthException {
      _failedOpen();
      _json(response, 401, {'error': 'code'});
      return;
    }
    if (!_freshNonce(SyncKey.nonceOf(sealed))) {
      _json(response, 401, {'error': 'replay'});
      return;
    }
    var status = 200;
    String reply;
    try {
      (status, reply) = await _answer(method, path, utf8.decode(plain));
    } on MissingCovers catch (error) {
      status = 409;
      reply = jsonEncode({
        'error': 'Some covers are missing.',
        'missing': error.hashes,
      });
    } on FormatException catch (error) {
      status = 400;
      reply = jsonEncode({'error': error.message});
    } catch (_) {
      status = 500;
      reply = jsonEncode({'error': 'Sync failed on the phone.'});
    }
    response.statusCode = status;
    if (status == 204) return;
    response.headers.contentType = ContentType.binary;
    response.add(
      await key.seal(
        utf8.encode(reply),
        responseContext(method, path, challenge),
      ),
    );
  }

  /// The status and the plain answer to a request that opened.
  Future<(int, String)> _answer(String method, String path, String body) async {
    if (path == '/v2/sync') return (200, await handleSync(body));
    final covers = this.covers!;
    if (path == '/v2/covers/missing') {
      final data = jsonDecode(body);
      final list = data is Map ? data['hashes'] : null;
      if (list is! List || list.length > _maxHashes) {
        throw const FormatException('Not a list of covers.');
      }
      final hashes = [
        for (final item in list)
          if (item is String && isCoverHash(item)) item,
      ];
      return (200, jsonEncode({'missing': await covers.missing(hashes)}));
    }
    final hash = path.substring('/v2/covers/'.length);
    if (!isCoverHash(hash)) return (404, jsonEncode({'error': 'Not found.'}));
    if (method == 'GET') {
      final picture = await covers.get(hash);
      if (picture == null) {
        return (404, jsonEncode({'error': 'No such cover.'}));
      }
      return (200, picture);
    }
    await covers.put(hash, body);
    return (204, '');
  }

  /// The request's body, or null when it is larger than [limit] bytes.
  Future<List<int>?> _readBytes(HttpRequest request, int limit) async {
    if (request.contentLength > limit) {
      await request.drain<void>();
      return null;
    }
    final builder = BytesBuilder(copy: false);
    var tooLarge = false;
    await for (final chunk in request) {
      if (tooLarge) continue;
      builder.add(chunk);
      if (builder.length > limit) tooLarge = true;
    }
    return tooLarge ? null : builder.takeBytes();
  }

  void _json(HttpResponse response, int status, Map<String, Object?> data) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
  }
}
