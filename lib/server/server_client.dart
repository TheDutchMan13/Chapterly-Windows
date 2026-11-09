import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/sync_covers.dart';

// The same file is in the Android app.

/// Something went wrong talking to the book server, in words to show.
class ServerFailure implements Exception {
  const ServerFailure(
    this.message, {
    this.unreachable = false,
    this.notFound = false,
    this.conflict = false,
  });

  final String message;

  /// The server could not be reached at all (as opposed to an answer that
  /// said no). Syncing stops trying for now when this happens.
  final bool unreachable;

  /// The book is no longer on the server.
  final bool notFound;

  /// Another device saved first (the library): merge again and retry.
  final bool conflict;

  @override
  String toString() => message;
}

/// What to tell the user about a "not found" answer. The server says which
/// of three things it is, so the message can say what to look at.
String notFoundMessage(String? detail) {
  final text = (detail ?? '').toLowerCase();
  if (text.contains('folder is no longer served')) {
    return 'The server no longer serves the folder this book is in. Check '
        'books_dir and books_dirs in config.toml on the server, then restart '
        'it.';
  }
  if (text.contains('file is gone')) {
    return 'The server cannot find this book\'s file. The file or its folder '
        'may have been moved, or the drive is not connected. Ask the server '
        'to scan again.';
  }
  return 'That book is no longer on the server.';
}

const _serverNeedsUpdate = ServerFailure(
  'Your book server is older than this app and cannot sync covers. Copy the '
  'new server files to the PC and restart the server.',
);

const _unreachable = ServerFailure(
  'Chapterly cannot reach your book server. Turn on Tailscale on this device '
  'and check the PC with the server is on and online.',
  unreachable: true,
);

/// The PC answered, but nothing is listening: the server is not running.
const _notRunning = ServerFailure(
  'Your PC is there, but the book server is not running on it. Start it '
  '(on the PC: Start-ScheduledTask -TaskName "Chapterly Server").',
  unreachable: true,
);

/// The address does not lead anywhere.
const _noSuchAddress = ServerFailure(
  'This address was not found. Check the book server address, and that '
  'Tailscale is on.',
  unreachable: true,
);

/// What a failed connection means, from the system's words for it. Only
/// what the system says for certain is named; anything else is the general
/// "cannot reach" message.
ServerFailure unreachableBecause(Object error) {
  var text = error.toString().toLowerCase();
  var code = 0;
  if (error is SocketException) {
    code = error.osError?.errorCode ?? 0;
    text = '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
  }
  // 111 and 61: refused on Android and Linux/macOS, 10061 on Windows.
  if (code == 111 || code == 61 || code == 10061 || text.contains('refused')) {
    return _notRunning;
  }
  if (text.contains('host lookup') ||
      text.contains('no address associated') ||
      text.contains('nodename nor servname') ||
      code == 11001) {
    return _noSuchAddress;
  }
  return _unreachable;
}

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
    this.trackCount = 1,
    this.originalName,
    this.addedAt,
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

  /// How many files: an audiobook can be one file per chapter.
  final int trackCount;

  /// The name of the book's file (or audiobook folder) on the server, without
  /// its folders. Null from a server older than 1.5.
  final String? originalName;

  /// When the server first found the book. Null from an old server.
  final DateTime? addedAt;

  bool get isAudiobook => kind == 'audiobook';

  /// An audiobook of several files, downloaded one by one.
  bool get isMultiTrack => isAudiobook && trackCount > 1;

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
    final tracks = value['trackCount'];
    final original = value['fileName'];
    final added = value['addedAt'];
    return ServerBook(
      addedAt: added is String ? DateTime.tryParse(added) : null,
      originalName: original is String && original.trim().isNotEmpty
          ? original
          : null,
      trackCount: tracks is int && tracks > 0 ? tracks : 1,
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

/// One file of an audiobook.
class ServerTrack {
  const ServerTrack({
    required this.index,
    required this.name,
    required this.size,
    this.durationMs,
  });

  final int index;
  final String name;
  final int size;
  final int? durationMs;

  static ServerTrack? fromJson(Object? value) {
    if (value is! Map) return null;
    final index = value['index'];
    final name = value['name'];
    final size = value['size'];
    final duration = value['durationMs'];
    if (index is! int || name is! String) return null;
    return ServerTrack(
      index: index,
      name: name,
      size: size is int ? size : 0,
      durationMs: duration is int && duration > 0 ? duration : null,
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
    this.device,
    this.deviceName,
  }) : _client = client ?? http.Client();

  final Uri address;
  final String token;

  /// Which app this is, shown in the server's list of devices. Optional.
  final String? device;
  final String? deviceName;
  final Duration timeout;
  final http.Client _client;

  /// Headers that sign in, also for loading covers.
  Map<String, String> get authHeaders => {
        'Authorization': 'Bearer $token',
        'X-Chapterly-Device': ?device,
        if (device != null && deviceName != null)
          'X-Chapterly-Device-Name': _headerSafe(deviceName!),
      };

  /// Header values are plain characters only.
  static String _headerSafe(String text) => String.fromCharCodes([
        for (final unit in text.codeUnits)
          if (unit >= 32 && unit < 127) unit else 63,
      ]);

  Uri _uri(String path, [Map<String, String>? query]) => address.replace(
        path: path,
        queryParameters: query == null || query.isEmpty ? null : query,
      );

  Uri coverUri(String bookId) => _uri('/v1/books/$bookId/cover');

  /// A whole library can take a while over a slow link.
  static const libraryTimeout = Duration(minutes: 3);

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    Duration? wait,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(wait ?? timeout);
    } on TimeoutException {
      throw _unreachable;
    } on SocketException catch (error) {
      throw unreachableBecause(error);
    } on http.ClientException catch (error) {
      throw unreachableBecause(error);
    }
    _check(response.statusCode, response.body);
    return response;
  }

  /// The server's own explanation in an error answer, if it sent one.
  static String? _detailOf(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['detail'] is String) return data['detail'] as String;
    } on FormatException {
      // Not JSON.
    }
    return null;
  }

  static void _check(int status, String body) {
    if (status >= 200 && status < 300) return;
    if (status == 401) {
      throw const ServerFailure(
        'The server did not accept the token. Check it, or make a new one '
        'with "new-token" on the server.',
      );
    }
    if (status == 409) {
      throw const ServerFailure(
        'Another device saved at the same time.',
        conflict: true,
      );
    }
    if (status == 404) {
      throw ServerFailure(notFoundMessage(_detailOf(body)), notFound: true);
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

  /// The apps that have signed in as you, newest first. An owner's list has
  /// everybody's.
  Future<List<ServerDevice>> devices() async {
    final data = _json(await _send(
      () => _client.get(_uri('/v1/devices'), headers: authHeaders),
    ));
    final list = data is Map ? data['devices'] : null;
    if (list is! List) {
      throw const ServerFailure('The server sent something Chapterly cannot read.');
    }
    return [
      for (final item in list)
        if (item is Map) ServerDevice.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  /// Takes a device off the server's list. It comes back if it signs in again.
  Future<void> forgetDevice(ServerDevice device) async {
    await _send(() => _client.delete(
          _uri('/v1/devices/${device.id}', {'person': device.person}),
          headers: authHeaders,
        ));
  }

  /// One book, with its corrections.
  Future<ServerBook> book(String bookId) async {
    final book = ServerBook.fromJson(_json(await _send(
      () => _client.get(_uri('/v1/books/$bookId'), headers: authHeaders),
    )));
    if (book == null) {
      throw const ServerFailure('The server sent something Chapterly cannot read.');
    }
    return book;
  }

  /// The cover picture the server has for a book (from its file), or null
  /// when it has none.
  Future<Uint8List?> bookCover(String bookId) async {
    try {
      final response = await _send(
        () => _client.get(coverUri(bookId), headers: authHeaders),
      );
      return response.bodyBytes.isEmpty ? null : response.bodyBytes;
    } on ServerFailure catch (failure) {
      if (failure.notFound) return null;
      rethrow;
    }
  }

  /// Corrects a book's title, author and series on the server, for every
  /// device and person using it. The book's file is not changed.
  Future<ServerBook> correctBook(
    String bookId, {
    required String title,
    required String author,
    String? series,
    double? seriesIndex,
  }) async {
    final book = ServerBook.fromJson(_json(await _send(
      () => _client.patch(
        _uri('/v1/books/$bookId'),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'author': author,
          'series': series,
          'seriesIndex': series == null ? null : seriesIndex,
        }),
      ),
    )));
    if (book == null) {
      throw const ServerFailure('The server sent something Chapterly cannot read.');
    }
    return book;
  }

  Future<ServerPage> books({
    String query = '',
    String? kind,
    int offset = 0,
    int limit = 50,
    String? sort,
  }) async {
    final data = _json(await _send(
      () => _client.get(
        _uri('/v1/books', {
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'kind': ?kind,
          'sort': ?sort,
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

  /// Your whole library as your devices last saved it: its version, and
  /// the library as sync text (null before the first save).
  Future<({int version, String? library})> getLibrary() async {
    final data = _json(await _send(
      () => _client.get(_uri('/v1/library'), headers: authHeaders),
      wait: libraryTimeout,
    ));
    if (data is! Map || data['version'] is! int) {
      throw const ServerFailure('The server sent something Chapterly cannot read.');
    }
    final library = data['library'];
    return (
      version: data['version'] as int,
      library: library is Map ? jsonEncode(library) : null,
    );
  }

  /// Saves the merged library, merged from [version]. Throws a failure with
  /// [ServerFailure.conflict] when another device saved in between.
  Future<int> putLibrary(int version, String library) async {
    final data = _json(await _send(
      () => _client.put(
        _uri('/v1/library'),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        // The library is sync text already; it goes in as it is.
        body: '{"version":$version,"library":$library}',
      ),
      wait: libraryTimeout,
    ));
    final saved = data is Map ? data['version'] : null;
    if (saved is! int) {
      throw const ServerFailure('The server sent something Chapterly cannot read.');
    }
    return saved;
  }

  /// Which of [hashes] (cover names, see sync_covers.dart) the server does
  /// not have a picture for.
  Future<List<String>> missingCovers(List<String> hashes) async {
    if (hashes.isEmpty) return const [];
    try {
      final data = _json(await _send(
        () => _client.post(
          _uri('/v1/covers/missing'),
          headers: {...authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode({'hashes': hashes}),
        ),
        wait: libraryTimeout,
      ));
      final list = data is Map ? data['missing'] : null;
      return [
        if (list is List)
          for (final item in list)
            if (item is String && isCoverHash(item)) item,
      ];
    } on ServerFailure catch (failure) {
      if (failure.notFound) throw _serverNeedsUpdate;
      rethrow;
    }
  }

  /// Gives the server one cover picture under its name.
  Future<void> putCover(String hash, String dataUrl) async {
    try {
      await _send(
        () => _client.put(
          _uri('/v1/covers/$hash'),
          headers: authHeaders,
          body: dataUrl,
        ),
      );
    } on ServerFailure catch (failure) {
      if (failure.notFound) throw _serverNeedsUpdate;
      rethrow;
    }
  }

  /// One cover picture from the server, or null when it has none by that
  /// name.
  Future<String?> getCover(String hash) async {
    try {
      final response = await _send(
        () => _client.get(_uri('/v1/covers/$hash'), headers: authHeaders),
      );
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } on ServerFailure catch (failure) {
      if (failure.notFound) return null;
      rethrow;
    }
  }

  /// Puts a book on your other devices: each downloads it the next time it
  /// syncs. [device] is this one, which doesn't.
  Future<void> sendBook(String bookId, String device) async {
    await _send(
      () => _client.post(
        _uri('/v1/sends'),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'bookId': bookId, 'device': device}),
      ),
    );
  }

  /// Books your other devices sent to this one.
  Future<List<ServerBook>> waitingSends(String device) async {
    final data = _json(await _send(
      () => _client.get(_uri('/v1/sends', {'device': device}), headers: authHeaders),
    ));
    final list = data is Map ? data['sends'] : null;
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map) ?ServerBook.fromJson(item['book']),
    ];
  }

  /// Tells the server [device] has a sent book; your other devices still
  /// get it.
  Future<void> doneSend(String bookId, String device) async {
    await _send(
      () => _client.delete(
        _uri('/v1/sends/$bookId', {'device': device}),
        headers: authHeaders,
      ),
    );
  }

  /// The files of an audiobook, in playing order.
  Future<List<ServerTrack>> tracks(String bookId) async {
    final data = _json(await _send(
      () => _client.get(_uri('/v1/books/$bookId/tracks'), headers: authHeaders),
    ));
    final list = data is Map ? data['tracks'] : null;
    if (list is! List) return const [];
    return [for (final item in list) ?ServerTrack.fromJson(item)]
      ..sort((a, b) => a.index.compareTo(b.index));
  }

  /// Downloads a book's file to [target]. It is written beside it first and
  /// only takes [target]'s name once it is complete. Returns the size.
  Future<int> download(
    String bookId,
    File target, {
    void Function(int received, int? total)? onProgress,
  }) =>
      _fetch(_uri('/v1/books/$bookId/file'), target, onProgress);

  /// Downloads one file of an audiobook of several.
  Future<int> downloadTrack(
    String bookId,
    int index,
    File target, {
    void Function(int received, int? total)? onProgress,
  }) =>
      _fetch(_uri('/v1/books/$bookId/tracks/$index/file'), target, onProgress);

  Future<int> _fetch(
    Uri uri,
    File target,
    void Function(int received, int? total)? onProgress,
  ) async {
    final partial = File('${target.path}.part');
    final request = http.Request('GET', uri)..headers.addAll(authHeaders);
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
    } on SocketException catch (error) {
      throw unreachableBecause(error);
    } on http.ClientException catch (error) {
      throw unreachableBecause(error);
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

/// One app that has signed in to the book server.
class ServerDevice {
  const ServerDevice({
    required this.id,
    required this.name,
    required this.person,
    required this.lastSeen,
    required this.thisDevice,
  });

  factory ServerDevice.fromJson(Map<String, dynamic> json) => ServerDevice(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unnamed device',
        person: json['person'] as String? ?? '',
        lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '')?.toLocal(),
        thisDevice: json['thisDevice'] == true,
      );

  final String id;
  final String name;

  /// Whose it is on the server.
  final String person;
  final DateTime? lastSeen;

  /// Whether this is the app that asked.
  final bool thisDevice;
}
