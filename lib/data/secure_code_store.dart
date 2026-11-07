import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_settings.dart';
import 'pc_sync.dart';
import 'profiles.dart';

/// Keeps the pairing code in Windows' protected storage, not in a plain file.
/// The code is a password for your library.
class SecureCodeStore implements CodeStore {
  const SecureCodeStore({this.storageKey = _key});

  static const _key = 'chapterly_sync_code';

  /// Before 1.43.0 each profile paired with the phone on its own. Now one
  /// pairing, saved under the first profile's name, syncs every profile.
  static String keyFor(String profileId) =>
      profileId == mainProfileId ? _key : '${_key}_$profileId';

  /// The name the code is saved under.
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
  Future<void> write(String code) => _storage.write(key: storageKey, value: code);

  @override
  Future<void> delete() => _storage.delete(key: storageKey);
}

/// Keeps a profile's Google Books key and Hardcover token in Windows'
/// protected storage.
class SecureSecretStore implements SecretStore {
  const SecureSecretStore(this.profileId);

  final String profileId;

  String _key(String name) => profileId == mainProfileId
      ? 'chapterly_$name'
      : 'chapterly_${name}_$profileId';

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  @override
  Future<String?> read(String name) async {
    try {
      return await _storage.read(key: _key(name));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String name, String value) =>
      _storage.write(key: _key(name), value: value);

  @override
  Future<void> delete(String name) => _storage.delete(key: _key(name));
}
