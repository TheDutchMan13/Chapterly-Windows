import 'dart:io';

import 'package:chapterly/data/backup.dart';
import 'package:chapterly/data/backup_writer.dart';
import 'package:chapterly/data/sync_covers.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(String id, {String? cover, String notes = ''}) => Book(
      id: id,
      title: 'Title "$id" ünïcode ✓',
      author: 'Author $id',
      shelf: Shelf.forLater,
      addedAt: DateTime(2025, 1, 2),
      updatedAt: DateTime(2025, 3, 4, 5, 6, 7),
      coverUrl: cover,
      notes: notes,
    );

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('backup_writer'));
  tearDown(() => temp.deleteSync(recursive: true));

  final pictures = {
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa': 'data:image/jpeg;base64,${'QUJD' * 5000}',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb': 'data:image/png;base64,${'WFla' * 300}',
  };
  Future<String?> readCover(String hash) async => pictures[hash];

  // What the app wrote before: the whole backup built in memory.
  Future<String> oldWay(List<Book> books, DateTime now) async => encodeBackup(
        [
          for (final b in books)
            if (hashOfCoverRef(b.coverUrl) case final hash?)
              b.copyWith(coverUrl: () => pictures[hash])
            else
              b,
        ],
        now: now,
      );

  test('the file is the same, byte for byte, as before', () async {
    final now = DateTime(2026, 11, 10, 11, 30);
    final books = [
      for (var i = 0; i < 45; i++)
        _book(
          '$i',
          cover: i % 3 == 0
              ? 'cover:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
              : i % 3 == 1
                  ? 'cover:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
                  : null,
          notes: 'line one\nline two\n\ttab',
        ),
      // A picture that is gone, and a web address, stay as they were.
      _book('lost', cover: 'cover:cccccccccccccccccccccccccccccccc'),
      _book('web', cover: 'https://covers.example/x.jpg'),
    ];
    final file = File('${temp.path}/b.json');
    await writeBackupFile(file, books, readCover: readCover, now: now);
    expect(await file.readAsString(), await oldWay(books, now));
    final restored = decodeBackup(await file.readAsString());
    expect(restored.length, books.length);
    expect(restored.first.coverUrl, pictures['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa']);
    expect(restored.last.coverUrl, 'https://covers.example/x.jpg');
  });

  test('an empty library is the same as before too', () async {
    final now = DateTime(2026, 1, 1);
    final file = File('${temp.path}/empty.json');
    await writeBackupFile(file, const [], readCover: readCover, now: now);
    expect(await file.readAsString(), await oldWay(const [], now));
  });

  test('a backup that fails leaves the old file and no half file', () async {
    final file = File('${temp.path}/b.json');
    await file.writeAsString('old good backup');
    var reads = 0;
    Future<String?> failing(String hash) async {
      if (++reads == 3) throw const FileSystemException('disk gone');
      return pictures[hash];
    }

    await expectLater(
      writeBackupFile(
        file,
        [for (var i = 0; i < 10; i++) _book('$i', cover: 'cover:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')],
        readCover: failing,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), 'old good backup');
    expect(File('${file.path}.part').existsSync(), isFalse);
  });

  test('a file of the same name is replaced', () async {
    final file = File('${temp.path}/b.json');
    await file.writeAsString('older');
    await writeBackupFile(file, [_book('1')], readCover: readCover);
    expect(decodeBackup(await file.readAsString()).single.id, '1');
  });
}
