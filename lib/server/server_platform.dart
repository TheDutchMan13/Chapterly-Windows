import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  const SecureTokenStore();

  static const _key = 'chapterly_server_token';

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
