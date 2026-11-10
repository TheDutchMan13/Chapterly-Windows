import 'dart:convert';
import 'dart:io';

import '../models/book.dart';
import 'sync_covers.dart';

/// Writes a backup to [file] one book at a time, reading each book's
/// picture only while that book is written. The file is the same, byte for
/// byte, as [encodeBackup] of the books with their pictures, so every
/// version of the app reads it, but the whole library (a hundred megabytes
/// with pictures) is never held in memory at once, and the app keeps
/// drawing while it is written.
///
/// It is written next to [file] first and only then put in its place, so a
/// backup cut short (the app closed, the disk full) never replaces a good
/// one or leaves half a file behind.
Future<void> writeBackupFile(
  File file,
  List<Book> books, {
  required Future<String?> Function(String hash) readCover,
  DateTime? now,
}) async {
  final part = File('${file.path}.part');
  final sink = part.openWrite();
  var closed = false;
  try {
    const indent = JsonEncoder.withIndent('  ');
    final exportedAt = jsonEncode((now ?? DateTime.now()).toIso8601String());
    sink.write('{\n'
        '  "app": "chapterly",\n'
        '  "version": 2,\n'
        '  "exportedAt": $exportedAt,\n'
        '  "books": [');
    if (books.isEmpty) {
      sink.write(']\n}');
    } else {
      var written = 0;
      for (final book in books) {
        final hash = hashOfCoverRef(book.coverUrl);
        sink.write(written == 0 ? '\n    ' : ',\n    ');
        final json = indent.convert(
          hash == null ? book.toJson() : await _withPicture(book, hash, readCover),
        );
        sink.write(json.replaceAll('\n', '\n    '));
        written++;
        // Let the screen draw and the written part leave memory.
        if (written % 20 == 0) {
          await sink.flush();
          await Future<void>.delayed(Duration.zero);
        }
      }
      sink.write('\n  ]\n}');
    }
    await sink.flush();
    await sink.close();
    closed = true;
    if (await file.exists()) await file.delete();
    await part.rename(file.path);
  } catch (_) {
    if (!closed) {
      try {
        await sink.close();
      } catch (_) {}
    }
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
    rethrow;
  }
}

Future<Map<String, dynamic>> _withPicture(
  Book book,
  String hash,
  Future<String?> Function(String) readCover,
) async {
  final picture = await readCover(hash);
  return book.copyWith(coverUrl: () => picture).toJson();
}
