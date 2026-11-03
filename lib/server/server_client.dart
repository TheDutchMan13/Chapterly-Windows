import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// The same file is in the Android app.

/// Something went wrong talking to the book server, in words to show.
class ServerFailure implements Exception {
  const ServerFailure(
    this.message, {
    this.unreachable = false,
    this.notFound = false,
  });

  final String message;

  /// The server could not be reached at all (as opposed to an answer that
  /// said no). Syncing stops trying for now when this happens.
  final bool unreachable;

  /// The book is no longer on the server.
  final bool notFound;

  @override
  String toString() => message;
}

const _unreachable = ServerFailure(
  'Chapterly cannot reach your book server. Is it running, and is '
  'Tailscale on?',
  unreachable: true,
);

/// The port the server uses when the address has none.
const defaultServerPort = 8780;

/// What you typed as the server's address, as a web address:
/// "100.72.1.2:8780" and "http://100.72.1.2:8780/" both give
/// http://100.72.1.2:8780. Null when it is not an address.
Uri? parseServerAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort
        ? uri.port
        : (uri.scheme == 'http' ? defaultServerPort : 443),
  );
}

double? _double(Object? value) => value is num ? value.toDouble() : null;

/// A saved place in a book on the server.
class ServerProgress {
  const ServerProgress({
    required this.fraction,
    required this.position,
    required this.updatedAt,
    this.bookId,
    this.resetAt,
  });

  /// From 0 to 1.
  final double fraction;

  /// Where exactly, in words only the app that wrote it understands.
  final String position;

  /// When it was saved, as the server wrote it.
  final String updatedAt;

  /// The server's id of the book, in a list of all your places.
  final String? bookId;

  /// When someone last went back on purpose: a place lower than yours
  /// that is meant.
  final String? resetAt;

  static ServerProgress? fromJson(Object? value) {
    if (value is! Map) return null;
    final fraction = _double(value['fraction']);
    final updatedAt = value['updatedAt'];
    if (fraction == null || updatedAt is! String) return null;
    final position = value['position'];
    final bookId = value['bookId'];
    final resetAt = value['resetAt'];
    return ServerProgress(
      fraction: fraction.clamp(0, 1).toDouble(),
      position: position is String ? position : '',
      updatedAt: updatedAt,
      bookId: bookId is String ? bookId : null,
      resetAt: resetAt is String ? resetAt : null,
    );
  }
}

/// A book in the server's library.
class ServerBook {
  const ServerBook({
    required this.id,
    required this.title,
    required this.author,
    required this.kind,
    required this.format,
    required this.size,
    this.series,
    this.seriesIndex,
    this.durationMs,
    this.hasCover = false,
    this.progress,
  });

  final String id;
  final String title;
  final String author;

  /// "ebook" or "audiobook".
  final String kind;

  /// The file's type: "epub", "pdf", "m4b", "m4a" or "mp3".
  final String format;
  final int size;
  final String? series;
  final double? seriesIndex;
  final int? durationMs;
  final bool hasCover;

  /// Your saved place, if you have one.
  final ServerProgress? progress;

  bool get isAudiobook => kind == 'audiobook';

  /// A file name for the download.
  String get fileName {
    final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    return '${clean.isEmpty ? 'book' : clean}.$format';
  }

  static ServerBook? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final kind = value['kind'];
    final format = value['format'];
    if (id is! String || title is! String || kind is! String) return null;
    if (format is! String) return null;
    final author = value['author'];
    final series = value['series'];
    final size = value['size'];
    final duration = value['durationMs'];
    return ServerBook(
      id: id,
      title: title,
      author: author is String ? author : '',
      kind: kind,
      format: format.toLowerCase(),
      size: size is int ? size : 0,
      series: series is String && series.isNotEmpty ? series : null,
      seriesIndex: _double(value['seriesIndex']),
      durationMs: duration is int && duration > 0 ? duration : null,
      hasCover: value['hasCover'] == true,
      progress: ServerProgress.fromJson(value['progress']),
    );
  }
}

/// One page of the library.
class ServerPage {
  const ServerPage(this.total, this.books);

  final int total;
  final List<ServerBook> books;
}

/// An audiobook bookmark as the server keeps it. A deleted one is kept for
/// a while with [deletedAt], so every device learns it was deleted.
class ServerBookmark {
  const ServerBookmark({
    required this.track,
    required this.trackMs,
    required this.positionMs,
    required this.addedAt,
    this.note = '',
    this.updatedAt,
    this.deletedAt,
  });

  final int track;
  final int trackMs;
  final int positionMs;

  /// What tells two bookmarks apart, as text.
  final String addedAt;
  final String note;
  final String? updatedAt;
  final String? deletedAt;

  Map<String, Object?> toJson() => {
        'track': track,
        'trackMs': trackMs,
        'positionMs': positionMs,
        'addedAt': addedAt,
        'note': note,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (deletedAt != null) 'deletedAt': deletedAt,
      };

  static ServerBookmark? fromJson(Object? value) {
    if (value is! Map) return null;
    final track = value['track'];
    final trackMs = value['trackMs'];
    final positionMs = value['positionMs'];
    final addedAt = value['addedAt'];
    if (track is! int || trackMs is! int || positionMs is! int) return null;
    if (addedAt is! String) return null;
    final note = value['note'];
    final updatedAt = value['updatedAt'];
    final deletedAt = value['deletedAt'];
    return ServerBookmark(
      track: track,
      trackMs: trackMs,
      positionMs: positionMs,
      addedAt: addedAt,
      note: note is String ? note : '',
      updatedAt: updatedAt is String ? updatedAt : null,
      deletedAt: deletedAt is String ? deletedAt : null,
    );
  }
}

/// Talks to your Chapterly book server (see the Chapterly-Server project).
class ServerClient {
  ServerClient({
    required this.address,
    required this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final Uri address;
  final String token;
  final Duration timeout;
  final http.Client _client;

  /// Headers that sign in, also for loading covers.
  Map<String, String> get authHeaders => {'Authorization': 'Bearer $token'};

  Uri _uri(String path, [Map<String, String>? query]) => address.replace(
        path: path,
        queryParameters: query == null || query.isEmpty ? null : query,
      );

  Uri coverUri(String bookId) => _uri('/v1/books/$bookId/cover');

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw _unreachable;
    } on SocketException {
      throw _unreachable;
    } on http.ClientException {
      throw _unreachable;
    }
    _check(response.statusCode, response.body);
    return response;
  }

  static void _check(int status, String body) {
    if (status >= 200 && status < 300) return;
    if (status == 401) {
      throw const ServerFailure(
        'The server did not accept the token. Check it, or make a new one '
        'with "new-token" on the server.',
      );
    }
    if (status == 404) {
      throw const ServerFailure(
        'That book is no longer on the server.',
        notFound: true,
      );
    }
    String? detail;
    try {
      final data = jsonDecode(body);
      if (data is Map && data['detail'] is String) detail = data['detail'];
    } on FormatException {
      // Not JSON.
    }
    throw ServerFailure(detail ?? 'The server could not do that ($status).');
  }

  Object? _json(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ServerFailure('The server sent something Chapterly cannot read.');
    }
  }

  /// Checks the address is a Chapterly server. Needs no token.
  Future<void> ping() async {
    final http.Response response;
    try {
      response = await _send(() => _client.get(_uri('/v1/ping')));
    } on ServerFailure catch (failure) {
      if (failure.unreachable) rethrow;
      throw const ServerFailure('That address is not a Chapterly book server.');
    }
    final data = _json(response);
    if (data is! Map || data['app'] != 'chapterly-server') {
      throw const ServerFailure('That address is not a Chapterly book server.');
    }
  }

  /// Your name on the server, which also checks the token.
  Future<String> me() async {
    final data = _json(await _send(
      () => _client.get(_uri('/v1/me'), headers: authHeaders),
    ));
    if (data is Map && data['name'] is String) return data['name'] as String;
    throw const ServerFailure('The server sent something Chapterly cannot read.');
  }

  Future<ServerPage> books({
    String query = '',
    String? kind,
    int offset = 0,
    int limit = 50,
  }) async {
    final data = _json(await _send(
      () => _client.get(
        _uri('/v1/books', {
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'kind': ?kind,
          'offset': '$offset',
          'limit': '$limit',
        }),
        headers: authHeaders,
      ),
    ));
    if (data is! Map || data['books'] is! List) {
      throw const ServerFailure('The server sent something Chapterly cannot read.');
    }
    final total = data['total'];
    return ServerPage(
      total is int ? total : 0,
      [for (final item in data['books'] as List) ?ServerBook.fromJson(item)],
    );
  }

  /// Saves a place. The server keeps the furthest one unless [reset] says
  /// you went back on purpose; [base] is the server time of the last place
  /// this device saw, so a device that missed someone going back can't undo
  /// it. Returns whether the server took it, and the place it now has.
  Future<({bool applied, ServerProgress progress})> putProgress(
    String bookId, {
    required double fraction,
    required String position,
    bool reset = false,
    String? base,
  }) async {
    final data = _json(await _send(
      () => _client.put(
        _uri('/v1/progress/$bookId'),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'fraction': fraction.clamp(0, 1),
          'position': position,
          if (reset) 'reset': true,
          'base': ?base,
        }),
      ),
    ));
    final progress = data is Map ? ServerProgress.fromJson(data['progress']) : null;
    if (progress == null) {
      throw const ServerFailure('The server sent something Chapterly cannot read.');
    }
    return (applied: (data as Map)['applied'] == true, progress: progress);
  }

  /// Your saved place in one book, or null.
  Future<ServerProgress?> progressFor(String bookId) async {
    final data = _json(await _send(
      () => _client.get(_uri('/v1/progress/$bookId'), headers: authHeaders),
    ));
    return data is Map ? ServerProgress.fromJson(data['progress']) : null;
  }

  /// All your saved places.
  Future<List<ServerProgress>> allProgress() async {
    final data = _json(await _send(
      () => _client.get(_uri('/v1/progress'), headers: authHeaders),
    ));
    final list = data is Map ? data['progress'] : null;
    if (list is! List) return const [];
    return [for (final item in list) ?ServerProgress.fromJson(item)];
  }

  Future<List<ServerBookmark>> bookmarks(String bookId) async =>
      _bookmarkList(await _send(
        () => _client.get(
          _uri('/v1/books/$bookId/bookmarks'),
          headers: authHeaders,
        ),
      ));

  /// Sends changed bookmarks and returns the merged list.
  Future<List<ServerBookmark>> putBookmarks(
    String bookId,
    List<ServerBookmark> changes,
  ) async =>
      _bookmarkList(await _send(
        () => _client.put(
          _uri('/v1/books/$bookId/bookmarks'),
          headers: {...authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'bookmarks': [for (final mark in changes) mark.toJson()],
          }),
        ),
      ));

  List<ServerBookmark> _bookmarkList(http.Response response) {
    final data = _json(response);
    final list = data is Map ? data['bookmarks'] : null;
    if (list is! List) return const [];
    return [for (final item in list) ?ServerBookmark.fromJson(item)];
  }

  /// Downloads a book's file to [target]. It is written beside it first and
  /// only takes [target]'s name once it is complete. Returns the size.
  Future<int> download(
    String bookId,
    File target, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final partial = File('${target.path}.part');
    final request = http.Request('GET', _uri('/v1/books/$bookId/file'))
      ..headers.addAll(authHeaders);
    IOSink? sink;
    try {
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        _check(response.statusCode, body);
      }
      final total = response.contentLength;
      await partial.parent.create(recursive: true);
      sink = partial.openWrite();
      var received = 0;
      // A download that stops for a minute has failed.
      await for (final chunk
          in response.stream.timeout(const Duration(minutes: 1))) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
      sink = null;
      if (total != null && received != total) throw _unreachable;
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      return received;
    } on TimeoutException {
      throw _unreachable;
    } on SocketException {
      throw _unreachable;
    } on http.ClientException {
      throw _unreachable;
    } finally {
      await sink?.close();
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {
          // Left behind; cleaned up with the folder.
        }
      }
    }
  }

  void close() => _client.close();
}
