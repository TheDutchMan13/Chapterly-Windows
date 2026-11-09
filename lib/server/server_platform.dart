import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/profiles.dart';
import 'server_state.dart';

// What differs between the phone and the PC for the book server.

/// How this app's reader writes a place in an EPUB: a chapter and a spot in
/// its text, which the phone's reader can't use. Each kind is named, and an
/// app only jumps to places it understands. (The phone uses "epub-cfi".)
const localEpubPositionKind = 'epub-win';

/// Where the player finds a downloaded audio file at [path].
String audioLocationFor(String path) => path;

/// Keeps your book server token in Windows' protected storage, not in a
/// plain file, like the pairing code for syncing with the phone.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore({this.storageKey = _key});

  static const _key = 'chapterly_server_token';

  /// Each profile has its own book server account. The first profile keeps
  /// the token it had before profiles.
  static String keyFor(String profileId) =>
      profileId == mainProfileId ? _key : '${_key}_$profileId';

  /// The name the token is saved under.
  final String storageKey;

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: storageKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String token) => _storage.write(key: storageKey, value: token);

  @override
  Future<void> delete() => _storage.delete(key: storageKey);
}

/// How this device is named in the book server's list of devices.
String serverDeviceName() {
  var host = '';
  try {
    host = Platform.localHostname;
  } catch (_) {
    // No name: the list just says Windows PC.
  }
  return host.isEmpty ? 'Windows PC' : 'Windows PC ($host)';
}
