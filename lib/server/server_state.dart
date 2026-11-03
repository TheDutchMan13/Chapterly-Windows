import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'server_client.dart';

// The same file is in the Android app.

/// A book on this device that came from (or matches) a book on the server.
@immutable
class ServerLink {
  const ServerLink({
    required this.serverId,
    required this.kind,
    this.durationMs,
    this.pushed,
    this.seen,
    this.dirty = false,
    this.marks,
  });

  final String serverId;

  /// "ebook" or "audiobook": which of this device's files the place is in.
  final String kind;

  /// The audiobook's length from the server, for when the player does not
  /// know it yet.
  final int? durationMs;

  /// The fraction last sent to the server, so the same place isn't sent
  /// again and again.
  final double? pushed;

  /// The server's time on the place last sent or taken from it. A place on
  /// the server that is newer was saved by another device.
  final String? seen;

  /// A place changed here and could not be sent yet.
  final bool dirty;

  /// Bookmarks as they were after the last sync, keyed by when they were
  /// added: what tells a bookmark deleted here from one added elsewhere.
  final Map<String, Map<String, Object?>>? marks;

  bool get isAudiobook => kind == 'audiobook';

  ServerLink copyWith({
    double? pushed,
    String? seen,
    bool? dirty,
    Map<String, Map<String, Object?>>? marks,
  }) =>
      ServerLink(
        serverId: serverId,
        kind: kind,
        durationMs: durationMs,
        pushed: pushed ?? this.pushed,
        seen: seen ?? this.seen,
        dirty: dirty ?? this.dirty,
        marks: marks ?? this.marks,
      );

  Map<String, Object?> toJson() => {
        'serverId': serverId,
        'kind': kind,
        if (durationMs != null) 'durationMs': durationMs,
        if (pushed != null) 'pushed': pushed,
        if (seen != null) 'seen': seen,
        if (dirty) 'dirty': true,
        if (marks != null) 'marks': marks,
      };

  static ServerLink? fromJson(Object? value) {
    if (value is! Map) return null;
    final serverId = value['serverId'];
    final kind = value['kind'];
    if (serverId is! String || (kind != 'ebook' && kind != 'audiobook')) {
      return null;
    }
    final duration = value['durationMs'];
    final pushed = value['pushed'];
    final seen = value['seen'];
    final marks = value['marks'];
    return ServerLink(
      serverId: serverId,
      kind: kind as String,
      durationMs: duration is int ? duration : null,
      pushed: pushed is num ? pushed.toDouble() : null,
      seen: seen is String ? seen : null,
      dirty: value['dirty'] == true,
      marks: marks is Map
          ? {
              for (final entry in marks.entries)
                if (entry.key is String && entry.value is Map)
                  entry.key as String:
                      Map<String, Object?>.from(entry.value as Map),
            }
          : null,
    );
  }
}

/// Where your token is kept, when not in the state file: the PC keeps it in
/// Windows' protected storage. The phone keeps it in the state file, in the
/// app's own folder, which other apps can't read.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// Your book server on this device: its address, your token, and which
/// books here belong to which books there. Kept in a file in the app's own
/// folder.
class ServerState extends ChangeNotifier {
  ServerState({this.file, this.tokens});

  final File? file;
  final TokenStore? tokens;
  Uri? _address;
  String? _token;
  String? _name;
  final _links = <String, ServerLink>{};

  static Future<ServerState> load(File file, {TokenStore? tokens}) async {
    final state = ServerState(file: file, tokens: tokens);
    try {
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) state._read(data);
      }
    } catch (_) {
      // A damaged file: start again; you connect once more.
    }
    if (tokens != null && state._address != null) {
      try {
        state._token = await tokens.read();
      } catch (_) {
        state._token = null;
      }
    }
    if (state._token == null || state._token!.isEmpty) {
      state._token = null;
      state._address = null;
    }
    return state;
  }

  void _read(Map data) {
    final address = data['address'];
    final token = data['token'];
    final name = data['name'];
    if (address is String) {
      _address = parseServerAddress(address);
      _token = tokens == null && token is String ? token : null;
      _name = name is String ? name : null;
    }
    final links = data['links'];
    if (links is Map) {
      for (final entry in links.entries) {
        final link = ServerLink.fromJson(entry.value);
        if (entry.key is String && link != null) {
          _links[entry.key as String] = link;
        }
      }
    }
  }

  bool get connected => _address != null && _token != null;
  Uri? get address => _address;
  String? get token => _token;

  /// Your name on the server.
  String? get name => _name;

  Map<String, ServerLink> get links => Map.unmodifiable(_links);

  ServerLink? linkFor(String bookId) => _links[bookId];

  /// The book on this device for a book on the server.
  String? bookIdFor(String serverId) {
    for (final entry in _links.entries) {
      if (entry.value.serverId == serverId) return entry.key;
    }
    return null;
  }

  Future<void> connect(Uri address, String token, String name) async {
    final changedServer = _address != null && _address != address;
    await tokens?.write(token);
    _address = address;
    _token = token;
    _name = name;
    // Books on another server have other ids.
    if (changedServer) _links.clear();
    await _save();
  }

  /// Forgets the server and your token. Downloaded books stay.
  Future<void> disconnect() async {
    try {
      await tokens?.delete();
    } catch (_) {
      // Gone already.
    }
    _address = null;
    _token = null;
    _name = null;
    _links.clear();
    await _save();
  }

  Future<void> setLink(String bookId, ServerLink link) async {
    // One book here per book there.
    _links.removeWhere((id, l) => l.serverId == link.serverId && id != bookId);
    _links[bookId] = link;
    await _save();
  }

  Future<void> unlink(String bookId) async {
    if (_links.remove(bookId) != null) await _save();
  }

  Future<void> update(String bookId, ServerLink Function(ServerLink) change) async {
    final link = _links[bookId];
    if (link == null) return;
    _links[bookId] = change(link);
    await _save();
  }

  Future<void> _writing = Future.value();

  /// Writes one change at a time, so two quick changes can't race for the
  /// file.
  Future<void> _save() {
    notifyListeners();
    final file = this.file;
    if (file == null) return Future.value();
    final data = jsonEncode({
      if (_address != null) 'address': _address.toString(),
      if (_token != null && tokens == null) 'token': _token,
      if (_name != null) 'name': _name,
      'links': {for (final e in _links.entries) e.key: e.value.toJson()},
    });
    return _writing = _writing.then((_) => _write(file, data));
  }

  static Future<void> _write(File file, String data) async {
    try {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(data, flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // Kept in memory; written with the next change.
    }
  }
}
