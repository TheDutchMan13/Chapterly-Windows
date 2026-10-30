import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pc_sync.dart';

/// Keeps the pairing code in Windows' protected storage, not in a plain file.
/// The code is a password for your library.
class SecureCodeStore implements CodeStore {
  const SecureCodeStore();

  static const _key = 'chapterly_sync_code';

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
  Future<void> write(String code) => _storage.write(key: _key, value: code);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
