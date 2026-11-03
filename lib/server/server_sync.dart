import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/book_repository.dart';
import '../ebook/ebook_library.dart';
import '../models/audio_bookmark.dart';
import '../models/audio_progress.dart';
import 'server_client.dart';
import 'server_platform.dart';
import 'server_state.dart';

// The same file is in the Android app.

// ---- Places, as the server keeps them ----

const _pdfKind = 'pdf-page';
const _audioKind = 'audio';

/// A place in an ebook as text for the server: "pdf-page:12", or the EPUB
/// location with the name of the reader that wrote it.
String encodeEbookPosition(EbookFormat format, EbookPosition position) =>
    format == EbookFormat.pdf
        ? '$_pdfKind:${position.locator}'
        : '$localEpubPositionKind:${position.locator}';

/// A place from the server this app's reader can jump to, or null (another
/// device's reader, or another kind of file).
EbookPosition? decodeEbookPosition(
  EbookFormat format,
  String text,
  double fraction,
) {
  final kind = format == EbookFormat.pdf ? _pdfKind : localEpubPositionKind;
  if (!text.startsWith('$kind:')) return null;
  final locator = text.substring(kind.length + 1);
  if (locator.isEmpty) return null;
  if (format == EbookFormat.pdf && int.tryParse(locator) == null) return null;
  return EbookPosition(locator: locator, progress: fraction);
}

/// Audiobook places mean the same on every device.
String encodeAudioPosition(AudioProgress progress) =>
    '$_audioKind:${jsonEncode(progress.toJson())}';

AudioProgress? decodeAudioPosition(String text) {
  if (!text.startsWith('$_audioKind:')) return null;
  try {
    return AudioProgress.fromJson(jsonDecode(text.substring(_audioKind.length + 1)));
  } on FormatException {
    return null;
  }
}

/// Where you are in a book on this device.
typedef Place = ({double fraction, String position});

// ---- Bookmarks ----

String bookmarkKey(AudioBookmark mark) => mark.addedAt.toIso8601String();

Map<String, Object?> _markJson(AudioBookmark mark) => {
      'track': mark.track,
      'trackMs': mark.trackMs,
      'positionMs': mark.positionMs,
      'note': mark.note,
    };

/// What changed in this device's bookmarks since the last sync ([base]), as
/// bookmarks to send. On the first sync ([base] null) every bookmark goes,
/// dated when it was added, so changes made elsewhere since then win.
List<ServerBookmark> bookmarkChanges({
  required Map<String, Map<String, Object?>>? base,
  required List<AudioBookmark> local,
  required String now,
}) {
  final changes = <ServerBookmark>[];
  final here = {for (final mark in local) bookmarkKey(mark): mark};
  for (final entry in here.entries) {
    final mark = entry.value;
    final before = base?[entry.key];
    if (before != null && mapEquals(before, _markJson(mark))) continue;
    changes.add(ServerBookmark(
      track: mark.track,
      trackMs: mark.trackMs,
      positionMs: mark.positionMs,
      addedAt: entry.key,
      note: mark.note,
      // New since the last sync: as old as the bookmark. Edited: now.
      updatedAt: before == null ? _utc(mark.addedAt) : now,
    ));
  }
  for (final entry in (base ?? const <String, Map<String, Object?>>{}).entries) {
    if (here.containsKey(entry.key)) continue;
    final old = entry.value;
    changes.add(ServerBookmark(
      track: old['track'] is int ? old['track'] as int : 0,
      trackMs: old['trackMs'] is int ? old['trackMs'] as int : 0,
      positionMs: old['positionMs'] is int ? old['positionMs'] as int : 0,
      addedAt: entry.key,
      note: old['note'] is String ? old['note'] as String : '',
      updatedAt: now,
      deletedAt: now,
    ));
  }
  return changes;
}

/// The server's merged list as this device's bookmarks.
List<AudioBookmark> bookmarksFromServer(List<ServerBookmark> merged) => [
      for (final mark in merged)
        if (mark.deletedAt == null)
          if (DateTime.tryParse(mark.addedAt) case final added?)
            AudioBookmark(
              track: mark.track,
              trackMs: mark.trackMs,
              positionMs: mark.positionMs,
              addedAt: added,
              note: mark.note,
            ),
    ];

Map<String, Map<String, Object?>> bookmarkBase(List<AudioBookmark> marks) =>
    {for (final mark in marks) bookmarkKey(mark): _markJson(mark)};

String _utc(DateTime time) => time.toUtc().toIso8601String();

bool _newer(String a, String b) {
  final x = DateTime.tryParse(a);
  final y = DateTime.tryParse(b);
  if (x == null || y == null) return a != b;
  return x.isAfter(y);
}

// ---- Syncing ----

/// Keeps your places in books from the server the same on every device:
/// sends a place when you move on here, and takes a further place saved on
/// another device. Downloads live in server_downloads.dart.
class ServerSync extends ChangeNotifier {
  ServerSync({
    required this.state,
    required this.repository,
    this.ebooks,
    this.isOpen,
    ServerClient Function(Uri address, String token)? clientFor,
    this.sendAfter = const Duration(seconds: 10),
    DateTime Function()? now,
  })  : _clientFor = clientFor ?? _defaultClient,
        _now = now ?? DateTime.now;

  static ServerClient _defaultClient(Uri address, String token) =>
      ServerClient(address: address, token: token);

  final ServerState state;
  final BookRepository repository;
  final EbookLibrary? ebooks;

  /// Whether a book is open in the reader or the player right now. Its
  /// place is not changed under you.
  final bool Function(String bookId)? isOpen;
  final Duration sendAfter;
  final ServerClient Function(Uri, String) _clientFor;
  final DateTime Function() _now;

  ServerClient? _client;
  Uri? _clientAddress;
  String? _clientToken;
  Timer? _timer;
  bool _busy = false;
  bool _sending = false;
  bool _started = false;
  String? _problem;

  /// Why the last sync did not work, or null.
  String? get problem => _problem;

  bool get busy => _busy;

  /// A client for [address], for checking an address and token before
  /// connecting.
  ServerClient clientFor(Uri address, String token) => _clientFor(address, token);

  /// The client for the server you are connected to, or null.
  ServerClient? get client {
    final address = state.address;
    final token = state.token;
    if (address == null || token == null) return null;
    if (_client == null || address != _clientAddress || token != _clientToken) {
      _client?.close();
      _client = _clientFor(address, token);
      _clientAddress = address;
      _clientToken = token;
    }
    return _client;
  }

  /// Starts watching for new places to send.
  void start() {
    if (_started) return;
    _started = true;
    repository.addListener(_changed);
    ebooks?.addListener(_changed);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_started) {
      repository.removeListener(_changed);
      ebooks?.removeListener(_changed);
    }
    _client?.close();
    super.dispose();
  }

  void _changed() {
    if (!state.connected) return;
    for (final entry in state.links.entries) {
      if (_needsSending(entry.key, entry.value)) {
        _timer?.cancel();
        _timer = Timer(sendAfter, () => unawaited(send()));
        return;
      }
    }
  }

  /// Where you are in a linked book on this device, or null.
  Place? placeOf(String bookId) {
    final link = state.linkFor(bookId);
    if (link == null) return null;
    if (link.isAudiobook) {
      final progress = repository.byId(bookId)?.audio;
      if (progress == null) return null;
      final length = progress.lengthMs ?? link.durationMs;
      if (length == null || length <= 0) return null;
      final fraction = (progress.positionMs / length).clamp(0.0, 1.0);
      return (fraction: fraction, position: encodeAudioPosition(progress));
    }
    final file = ebooks?.linkFor(bookId);
    final position = file?.position;
    if (file == null || position == null) return null;
    return (
      fraction: position.progress,
      position: encodeEbookPosition(file.format, position),
    );
  }

  bool _needsSending(String bookId, ServerLink link) {
    final place = placeOf(bookId);
    if (place == null) return false;
    final pushed = link.pushed;
    return link.dirty || pushed == null || (place.fraction - pushed).abs() >= 0.0005;
  }

  /// Sends the places that changed here. Stops at the first sign the server
  /// can't be reached; they go next time.
  Future<void> send() async {
    final client = this.client;
    if (client == null || _sending) return;
    _sending = true;
    try {
      await _sendAll(client);
    } finally {
      _sending = false;
    }
  }

  Future<void> _sendAll(ServerClient client) async {
    for (final entry in state.links.entries.toList()) {
      final bookId = entry.key;
      final link = entry.value;
      if (!_needsSending(bookId, link)) continue;
      final place = placeOf(bookId)!;
      final pushed = link.pushed;
      // Starting a finished book again: go back on purpose.
      final reset = pushed != null && pushed >= 0.9 && place.fraction < 0.1;
      try {
        final saved = await client.putProgress(
          link.serverId,
          fraction: place.fraction,
          position: place.position,
          reset: reset,
        );
        await state.update(
          bookId,
          (l) => l.copyWith(pushed: place.fraction, seen: saved.updatedAt, dirty: false),
        );
      } on ServerFailure catch (failure) {
        await state.update(bookId, (l) => l.copyWith(dirty: true));
        if (failure.unreachable) {
          _setProblem(failure.message);
          return;
        }
      }
    }
  }

  /// Takes places saved on another device that are further than yours
  /// here. Returns how many books moved on.
  Future<int> receive() async {
    final client = this.client;
    if (client == null) return 0;
    final saved = await client.allProgress();
    var moved = 0;
    for (final remote in saved) {
      final serverId = remote.bookId;
      if (serverId == null) continue;
      final bookId = state.bookIdFor(serverId);
      if (bookId == null || (isOpen?.call(bookId) ?? false)) continue;
      if (await applyRemote(bookId, remote)) moved++;
    }
    return moved;
  }

  /// Takes [remote] as your place in [bookId] if another device saved it
  /// and it is further on than here. Returns whether the place moved.
  Future<bool> applyRemote(String bookId, ServerProgress remote) async {
    final link = state.linkFor(bookId);
    if (link == null || repository.byId(bookId) == null) return false;
    final seen = link.seen;
    // Saved by this device, or already looked at.
    if (seen != null && !_newer(remote.updatedAt, seen)) return false;
    final here = placeOf(bookId);
    if (here != null && remote.fraction <= here.fraction + 0.001) {
      await state.update(bookId, (l) => l.copyWith(seen: remote.updatedAt));
      return false;
    }
    if (link.isAudiobook) {
      final progress = decodeAudioPosition(remote.position);
      if (progress == null) return false;
      await repository.setAudioProgress(bookId, progress);
    } else {
      final library = ebooks;
      final file = library?.linkFor(bookId);
      if (library == null || file == null) return false;
      final position =
          decodeEbookPosition(file.format, remote.position, remote.fraction);
      if (position == null) return false;
      await library.setPosition(bookId, position);
    }
    await state.update(
      bookId,
      (l) => l.copyWith(pushed: remote.fraction, seen: remote.updatedAt, dirty: false),
    );
    return true;
  }

  /// Just before a book opens: takes a further place saved on another
  /// device, waiting at most [wait] so a server that's away never holds the
  /// book up. Returns whether the place moved.
  Future<bool> takeLatest(
    String bookId, {
    Duration wait = const Duration(seconds: 3),
  }) async {
    final client = this.client;
    final link = state.linkFor(bookId);
    if (client == null || link == null) return false;
    try {
      final remote = await client.progressFor(link.serverId).timeout(wait);
      if (remote == null) return false;
      return await applyRemote(bookId, remote);
    } on ServerFailure {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// Sends bookmark changes for an audiobook and takes those made elsewhere.
  Future<void> syncBookmarks(String bookId) async {
    final client = this.client;
    final link = state.linkFor(bookId);
    if (client == null || link == null || !link.isAudiobook) return;
    if (repository.byId(bookId) == null) return;
    final local = repository.bookmarksFor(bookId);
    final changes = bookmarkChanges(
      base: link.marks,
      local: local,
      now: _utc(_now()),
    );
    final merged = changes.isEmpty
        ? await client.bookmarks(link.serverId)
        : await client.putBookmarks(link.serverId, changes);
    final result = bookmarksFromServer(merged);
    final fresh = bookmarkBase(result);
    if (!mapEquals(
      {for (final e in fresh.entries) e.key: jsonEncode(e.value)},
      {for (final e in bookmarkBase(local).entries) e.key: jsonEncode(e.value)},
    )) {
      await repository.replaceBookmarks(bookId, result);
    }
    await state.update(bookId, (l) => l.copyWith(marks: fresh));
  }

  /// Sends, then takes, then syncs audiobook bookmarks. Returns how many
  /// books moved on to a place saved elsewhere.
  Future<int> syncNow() async {
    if (_busy || !state.connected) return 0;
    _busy = true;
    notifyListeners();
    var moved = 0;
    try {
      await send();
      moved = await receive();
      for (final entry in state.links.entries.toList()) {
        if (entry.value.isAudiobook) await syncBookmarks(entry.key);
      }
      _setProblem(null);
    } on ServerFailure catch (failure) {
      _setProblem(failure.message);
    } finally {
      _busy = false;
      notifyListeners();
    }
    return moved;
  }

  void _setProblem(String? problem) {
    if (_problem == problem) return;
    _problem = problem;
    notifyListeners();
  }
}
