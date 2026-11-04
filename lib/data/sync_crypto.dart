import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// Shared by the Android and Windows apps: keep both copies the same.

/// A sync message that was not sealed with the pairing code: someone else,
/// a changed code, or a damaged message.
class SyncAuthException implements Exception {
  const SyncAuthException([this.message = 'Not sealed with this sync code']);
  final String message;
  @override
  String toString() => message;
}

/// Seals and opens sync messages with a key made from the pairing code, so
/// the code itself never goes over the network and nobody on the Wi-Fi can
/// read or change the library on its way. AES-256-GCM; a message is
/// nonce (12 bytes), then the encrypted text, then the tag (16 bytes).
class SyncKey {
  SyncKey._(this._key);

  final SecretKey _key;

  static final _aes = AesGcm.with256bits();

  /// Bytes a sealed message adds to its content.
  static const overhead = 28;

  /// The key for [code], the normalized pairing code.
  static Future<SyncKey> fromCode(String code) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(code)),
      nonce: utf8.encode('chapterly-sync-v2'),
      info: utf8.encode('sync key'),
    );
    return SyncKey._(key);
  }

  /// For tests.
  Future<List<int>> keyBytes() => _key.extractBytes();

  /// [plain] sealed for [context] (the request line it belongs to). A
  /// message sealed for one context can't be opened for another.
  Future<Uint8List> seal(
    List<int> plain,
    String context, {
    List<int>? nonce,
  }) async {
    final box = await _aes.encrypt(
      plain,
      secretKey: _key,
      nonce: nonce ?? _aes.newNonce(),
      aad: utf8.encode(context),
    );
    return Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// The content of [sealed], or [SyncAuthException].
  Future<Uint8List> open(List<int> sealed, String context) async {
    if (sealed.length < overhead) throw const SyncAuthException();
    final box = SecretBox(
      sealed.sublist(12, sealed.length - 16),
      nonce: sealed.sublist(0, 12),
      mac: Mac(sealed.sublist(sealed.length - 16)),
    );
    try {
      return Uint8List.fromList(
        await _aes.decrypt(box, secretKey: _key, aad: utf8.encode(context)),
      );
    } on SecretBoxAuthenticationError {
      throw const SyncAuthException();
    }
  }

  /// The nonce of a sealed message, to refuse one that is sent twice.
  static String nonceOf(List<int> sealed) =>
      base64Url.encode(sealed.sublist(0, min(12, sealed.length)));
}

/// The context a request is sealed for.
String requestContext(String method, String path, String challenge) =>
    '$method $path $challenge';

/// The context the phone's answer to that request is sealed for.
String responseContext(String method, String path, String challenge) =>
    'response $method $path $challenge';

/// A fresh random challenge (16 bytes, base64url without padding).
String newChallenge([Random? random]) {
  final r = random ?? Random.secure();
  return base64Url
      .encode([for (var i = 0; i < 16; i++) r.nextInt(256)])
      .replaceAll('=', '');
}
