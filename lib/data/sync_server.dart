import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder, Uint8List;
import 'dart:io';
import 'dart:math';

import 'sync_covers.dart';
import 'sync_crypto.dart';
import 'sync_profiles.dart';
import 'sync_protocol.dart';

/// The largest sync message the phone will read. Thousands of books fit
/// easily: covers are not in it, they have their own requests.
const _maxBodyBytes = 50 * 1024 * 1024;

/// The largest list of profiles to add.
const _maxProfilesBytes = 64 * 1024;

/// The largest cover picture, and the largest list of cover names.
const _maxCoverBytes = 2 * 1024 * 1024;
const _maxHashListBytes = 2 * 1024 * 1024;
const _maxHashes = 50000;

/// How long a challenge from `/v2/hello` can be used, and how many are kept.
const challengeLifetime = Duration(minutes: 5);
const _maxChallenges = 32;

/// How long a used nonce is remembered, so the same request can't be sent
/// twice, and how many are kept.
const _nonceMemory = Duration(minutes: 10);
const _maxNonces = 10000;

/// After this many messages that don't open within a minute, the phone
/// stops answering sealed requests for a minute.
const _maxFailures = 20;
const _failureWindow = Duration(minutes: 1);

/// The version of the sealed sync (see SYNC_V2.md), told in the ping.
const syncSealVersion = 2;

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

/// One profile's sync on the phone: its library and its covers.
abstract interface class SyncEndpoint implements SyncCovers {
  /// Merges the PC's library ([body]) and returns the merged one.
  Future<String> handleSync(String body);
}

/// A profile that has a PIN and isn't open on the phone.
class ProfileLocked implements Exception {
  const ProfileLocked();
}

/// Every profile on the phone, for a PC that syncs them all with one
/// pairing.
abstract interface class SyncProfileHost {
  /// Adds the profiles the PC asks for ([body], see encodeProfileRequest)
  /// and returns the list of profiles (see encodeProfileList).
  Future<String> profiles(String body);

  /// The sync of profile [id], or null when there is no such profile.
  /// Throws [ProfileLocked] for a profile that has a PIN and isn't open.
  Future<SyncEndpoint?> endpoint(String id);
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

/// The answer to a sealed request, before it is sealed.
class _Reply {
  const _Reply(this.status, this.body);

  final int status;
  final String body;
}

/// A request that was refused before it could be opened, answered in plain
/// JSON.
class _Refused implements Exception {
  const _Refused(this.status, this.error);

  final int status;
  final String error;
}

/// A small HTTP server on the home network. The pairing code never goes
/// over the network: requests and answers are sealed with a key made from
/// it (see sync_crypto.dart and SYNC_V2.md). The PC uses these requests:
///
/// - `GET /v1/ping` (no code needed) says whether this is a Chapterly phone.
/// - `GET /v2/hello` (no code needed) gives a challenge, which every sealed
///   request of one sync names in `X-Chapterly-Challenge`.
/// - `POST /v2/sync` with the PC's library, sealed. The reply is the merged
///   library, sealed. Books carry cover references (see sync_covers.dart),
///   never the pictures.
/// - `POST /v2/covers/missing`, `PUT /v2/covers/<name>` and
///   `GET /v2/covers/<name>` (sealed) move the cover pictures.
/// - With [profiles]: `POST /v2/profiles` (sealed) lists the profiles and
///   adds the ones the PC asks for, and `/v2/p/<id>/sync` and
///   `/v2/p/<id>/covers/...` are the same requests for one profile. A profile
///   with a PIN answers only while it is open (423 "locked").
class SyncServer {
  SyncServer({
    required this.token,
    required this.handleSync,
    this.covers,
    this.profiles,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// The normalized pairing code.
  final String token;

  final Future<String> Function(String body) handleSync;
  final SyncCovers? covers;
  final SyncProfileHost? profiles;
  final DateTime Function() _now;
  HttpServer? _server;
  SyncKey? _key;

  /// Challenges given out, oldest first, with when they were given.
  final _challenges = <String, DateTime>{};

  /// Nonces of requests already answered, oldest first.
  final _nonces = <String, DateTime>{};

  /// When recent messages failed to open.
  final _failures = <DateTime>[];
  DateTime? _blockedUntil;

  bool get running => _server != null;

  /// The port in use. Useful when [start] was given port 0 (tests).
  int? get boundPort => _server?.port;

  Future<void> start({int port = defaultSyncPort}) async {
    if (_server != null) return;
    _key ??= await SyncKey.fromCode(token);
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    server.listen((request) => unawaited(_serve(request)));
  }

  /// Stops listening. With [force] false, a sync already running is
  /// finished first.
  Future<void> stop({bool force = true}) async {
    final server = _server;
    _server = null;
    await server?.close(force: force);
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/ping') {
        _json(response, 200, {
          'app': 'chapterly',
          'protocol': syncProtocolVersion,
          'sync': syncSealVersion,
          if (profiles != null) 'profiles': syncProfilesVersion,
        });
      } else if (request.method == 'GET' && path == '/v2/hello') {
        _json(response, 200, {'challenge': _newChallenge()});
      } else if (path == '/v1/sync' || path.startsWith('/v1/covers')) {
        await _drain(request);
        _json(response, 426, {
          'error': 'Update Chapterly on your PC to sync with this phone.',
        });
      } else if (path == '/v2/sync' ||
          (path.startsWith('/v2/covers/') && covers != null) ||
          (profiles != null &&
              (path == '/v2/profiles' || splitProfilePath(path) != null))) {
        await _serveSealed(request);
      } else {
        await _drain(request);
        _json(response, 404, {'error': 'Not found.'});
      }
    } on _Refused catch (refused) {
      _json(response, refused.status, {'error': refused.error});
    } catch (_) {
      _json(response, 500, {'error': 'Sync failed on the phone.'});
    } finally {
      await response.close();
    }
  }

  String _newChallenge() {
    final now = _now();
    _challenges.removeWhere(
      (_, given) => now.difference(given) > challengeLifetime,
    );
    while (_challenges.length >= _maxChallenges) {
      _challenges.remove(_challenges.keys.first);
    }
    final challenge = newChallenge();
    _challenges[challenge] = now;
    return challenge;
  }

  bool _knownChallenge(String challenge) {
    final given = _challenges[challenge];
    if (given == null) return false;
    if (_now().difference(given) > challengeLifetime) {
      _challenges.remove(challenge);
      return false;
    }
    return true;
  }

  /// Remembers [nonce]; false if it was already used.
  bool _freshNonce(String nonce) {
    final now = _now();
    while (_nonces.isNotEmpty &&
        now.difference(_nonces.values.first) > _nonceMemory) {
      _nonces.remove(_nonces.keys.first);
    }
    if (_nonces.containsKey(nonce)) return false;
    while (_nonces.length >= _maxNonces) {
      _nonces.remove(_nonces.keys.first);
    }
    _nonces[nonce] = now;
    return true;
  }

  void _failed() {
    final now = _now();
    _failures
      ..add(now)
      ..removeWhere((at) => now.difference(at) > _failureWindow);
    if (_failures.length >= _maxFailures) {
      _blockedUntil = now.add(_failureWindow);
      _failures.clear();
    }
  }

  /// The most plain content a sealed request to [path] may carry.
  int _limitFor(String method, String path) {
    if (path == '/v2/profiles') return _maxProfilesBytes;
    final split = splitProfilePath(path);
    if (split != null) return _limitFor(method, split.path);
    if (path == '/v2/sync') return _maxBodyBytes;
    if (path == '/v2/covers/missing') return _maxHashListBytes;
    if (method == 'PUT') return _maxCoverBytes;
    return 0;
  }

  Future<void> _serveSealed(HttpRequest request) async {
    final response = request.response;
    final method = request.method.toUpperCase();
    final path = request.uri.path;
    final blocked = _blockedUntil;
    if (blocked != null && _now().isBefore(blocked)) {
      await _drain(request);
      throw const _Refused(429, 'Too many wrong tries. Wait a minute.');
    }
    final sealed = await _readBytes(
      request,
      _limitFor(method, path) + SyncKey.overhead,
    );
    final given = request.headers.value('x-chapterly-challenge');
    if (given == null || !_knownChallenge(given)) {
      throw const _Refused(401, 'challenge');
    }
    final challenge = given;
    final key = _key!;
    final Uint8List plain;
    try {
      plain = await key.open(
        sealed,
        requestContext(method, path, challenge),
      );
    } on SyncAuthException {
      _failed();
      throw const _Refused(401, 'code');
    }
    if (!_freshNonce(SyncKey.nonceOf(sealed))) {
      throw const _Refused(401, 'replay');
    }
    final reply = await _answer(method, path, plain);
    final body = await key.seal(
      utf8.encode(reply.body),
      responseContext(method, path, challenge),
    );
    response.statusCode = reply.status;
    response.headers.contentType = ContentType.binary;
    response.contentLength = body.length;
    response.add(body);
  }

  /// The answer to an opened request, as JSON or the cover picture.
  Future<_Reply> _answer(String method, String path, List<int> plain) async {
    try {
      final body = utf8.decode(plain);
      final profiles = this.profiles;
      if (profiles != null && path == '/v2/profiles') {
        if (method != 'POST') return _error(404, 'Not found.');
        return _Reply(200, await profiles.profiles(body));
      }
      final split = profiles == null ? null : splitProfilePath(path);
      if (split != null) {
        final SyncEndpoint? endpoint;
        try {
          endpoint = await profiles!.endpoint(split.id);
        } on ProfileLocked {
          return _error(423, 'locked');
        }
        if (endpoint == null) return _error(404, 'No such profile.');
        return await _answerFor(
          endpoint.handleSync,
          endpoint,
          method,
          split.path,
          body,
        );
      }
      return await _answerFor(handleSync, covers, method, path, body);
    } on MissingCovers catch (error) {
      return _Reply(
        409,
        jsonEncode({
          'error': 'Some covers are missing.',
          'missing': error.hashes,
        }),
      );
    } on FormatException catch (error) {
      return _error(400, error.message);
    } catch (_) {
      return _error(500, 'Sync failed on the phone.');
    }
  }

  Future<_Reply> _answerFor(
    Future<String> Function(String body) handleSync,
    SyncCovers? covers,
    String method,
    String path,
    String body,
  ) async {
    if (path == '/v2/sync') {
      if (method != 'POST') return _error(404, 'Not found.');
      return _Reply(200, await handleSync(body));
    }
    if (covers == null || !path.startsWith('/v2/covers/')) {
      return _error(404, 'Not found.');
    }
    return _answerCovers(covers, method, path, body);
  }

  Future<_Reply> _answerCovers(
    SyncCovers covers,
    String method,
    String path,
    String body,
  ) async {
    if (method == 'POST' && path == '/v2/covers/missing') {
      final data = jsonDecode(body);
      final list = data is Map ? data['hashes'] : null;
      if (list is! List || list.length > _maxHashes) {
        throw const FormatException('Not a list of covers.');
      }
      final hashes = [
        for (final item in list)
          if (item is String && isCoverHash(item)) item,
      ];
      return _Reply(200, jsonEncode({'missing': await covers.missing(hashes)}));
    }
    final hash = path.substring('/v2/covers/'.length);
    if (!isCoverHash(hash)) return _error(404, 'Not found.');
    if (method == 'GET') {
      final picture = await covers.get(hash);
      if (picture == null) return _error(404, 'No such cover.');
      return _Reply(200, picture);
    }
    if (method == 'PUT') {
      await covers.put(hash, body);
      // 200 with a sealed empty answer rather than 204, which can't carry
      // the sealed answer that proves the phone has the code.
      return const _Reply(200, '');
    }
    return _error(404, 'Not found.');
  }

  _Reply _error(int status, String message) =>
      _Reply(status, jsonEncode({'error': message}));

  /// The request's body, refused with 413 once it has more than [limit]
  /// bytes.
  Future<Uint8List> _readBytes(HttpRequest request, int limit) async {
    const tooLarge = _Refused(413, 'The sync message is too large.');
    if (request.contentLength > limit) throw tooLarge;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > limit) throw tooLarge;
    }
    return builder.takeBytes();
  }

  /// Reads and drops a body that won't be used, so the PC can finish
  /// sending it and hear the answer.
  Future<void> _drain(HttpRequest request) async {
    try {
      var read = 0;
      await for (final chunk in request) {
        read += chunk.length;
        if (read > _maxBodyBytes) break;
      }
    } catch (_) {
      // The answer is sent anyway.
    }
  }

  void _json(HttpResponse response, int status, Map<String, Object?> data) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
  }
}
