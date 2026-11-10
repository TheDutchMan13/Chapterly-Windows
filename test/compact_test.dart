import 'dart:io';

import 'package:chapterly/data/sqlite_book_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temp;
  setUp(() {
    sqfliteFfiInit();
    temp = Directory.systemTemp.createTempSync('compact');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('space left by removed pictures goes back to the disk', () async {
    final path = '${temp.path}/chapterly.db';
    final store = await SqliteBookStore.open(path);
    final picture = 'data:image/jpeg;base64,${'A' * 200000}';
    await store.writeCovers({
      for (var i = 0; i < 40; i++) i.toRadixString(16).padLeft(32, '0'): picture,
    });
    await store.removeCoversExcept({});
    final full = File(path).lengthSync();
    expect(full, greaterThan(7000000));

    // The first time rewrites the file and switches on giving space back.
    expect(await store.compact(), greaterThan(7000000));
    final small = File(path).lengthSync();
    expect(small, lessThan(full ~/ 10));

    // From then on, removed space is trimmed without a rewrite.
    await store.writeCovers({
      for (var i = 0; i < 40; i++) 'b${i.toRadixString(16).padLeft(31, '0')}': picture,
    });
    await store.removeCoversExcept({});
    expect(await store.compact(), greaterThan(7000000));
    expect(File(path).lengthSync(), lessThan(full ~/ 10));

    // Nothing to give back: nothing happens.
    expect(await store.compact(), 0);
    await store.close();
  });

  test('the library is the same after tidying', () async {
    final path = '${temp.path}/chapterly.db';
    final store = await SqliteBookStore.open(path);
    await store.writeCovers({'a' * 32: 'data:image/png;base64,QUJD'});
    await store.compact();
    expect(await store.readCover('a' * 32), 'data:image/png;base64,QUJD');
    await store.close();
  });
}
