import 'dart:convert';

import 'package:chapterly/data/sync_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> b) => [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
List<int> _unhex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

// Computed with Python's `cryptography` (HKDF-SHA256 + AESGCM), so both
// apps are checked against the same independent result.
const _code = 'K7QX2M9PZR4TB6WN';
const _key = 'b4dbdaae88d4223c8111037b1c0f148a832cae47af5b0a580fa853dd85f974a3';
const _sealed = '000102030405060708090a0b87b2abe9899ea3c5d37e2c8e8ff080cea67dcd1447eed96efc153d37e204527f5e';

void main() {
  test('key matches the shared test vector', () async {
    final key = await SyncKey.fromCode(_code);
    expect(_hex(await key.keyBytes()), _key);
  });

  test('sealing matches the shared test vector', () async {
    final key = await SyncKey.fromCode(_code);
    final sealed = await key.seal(utf8.encode('{"hello":"world"}'), 'POST /v2/sync abc123',
        nonce: List.generate(12, (i) => i));
    expect(_hex(sealed), _sealed);
    expect(utf8.decode(await key.open(_unhex(_sealed), 'POST /v2/sync abc123')), '{"hello":"world"}');
  });

  test('wrong context, wrong code or a changed byte is refused', () async {
    final key = await SyncKey.fromCode(_code);
    final other = await SyncKey.fromCode('AAAAAAAAAAAAAAAA');
    final sealed = _unhex(_sealed);
    await expectLater(key.open(sealed, 'POST /v2/sync other'), throwsA(isA<SyncAuthException>()));
    await expectLater(other.open(sealed, 'POST /v2/sync abc123'), throwsA(isA<SyncAuthException>()));
    final changed = [...sealed]..[20] ^= 1;
    await expectLater(key.open(changed, 'POST /v2/sync abc123'), throwsA(isA<SyncAuthException>()));
    await expectLater(key.open([1, 2, 3], 'x'), throwsA(isA<SyncAuthException>()));
  });
}
