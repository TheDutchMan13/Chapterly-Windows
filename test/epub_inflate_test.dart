import 'dart:io';
import 'dart:typed_data';

import 'package:chapterly/ebook/epub_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unpacks normal entries and refuses ones that grow too big', () {
    final plain = Uint8List(200000);
    for (var i = 0; i < plain.length; i++) {
      plain[i] = i % 7;
    }
    final packed = Uint8List.fromList(ZLibCodec(raw: true).encode(plain));
    expect(inflateForTest(packed, 1 << 20), plain);
    // Zeros pack very small, so a few KB could unpack to far more.
    final bomb = Uint8List.fromList(
      ZLibCodec(raw: true).encode(Uint8List(5 << 20)),
    );
    expect(bomb.length, lessThan(64 * 1024));
    expect(inflateForTest(bomb, 1 << 20), isNull);
    expect(inflateForTest(Uint8List.fromList([1, 2, 3, 4]), 1 << 20), isNull);
  });
}
