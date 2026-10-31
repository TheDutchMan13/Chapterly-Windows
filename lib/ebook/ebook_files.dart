import 'dart:io';

import '../audio/audio_files.dart';
import 'ebook_library.dart';

/// Picking a book file and copying it into Chapterly's own folder.
abstract interface class EbookFiles {
  /// One EPUB or PDF file, or null if cancelled.
  Future<PickedFile?> pickBook();

  /// Copies the picked file to [path]. Returns the number of bytes.
  Future<int> copy(PickedFile picked, String path);

  /// Lets go of the permission to read the picked file once it is copied.
  Future<void> release(PickedFile picked);
}

/// Adds [picked] as the book file of [bookId]: copies it into [booksDir]
/// and remembers it. Any earlier file for the book is replaced and its
/// copy deleted. Returns a problem to show, or null when it worked.
Future<String?> addBookFile({
  required EbookLibrary library,
  required EbookFiles files,
  required Directory booksDir,
  required String bookId,
  required PickedFile picked,
  DateTime Function() now = DateTime.now,
}) async {
  final format = ebookFormatOf(picked.name);
  if (format == null) {
    return 'Chapterly can open EPUB and PDF files. '
        '"${picked.name}" is neither.';
  }
  final old = library.linkFor(bookId);
  // A new name each time, so replacing a file never overwrites the one
  // that is open.
  final stamp = now().millisecondsSinceEpoch;
  final safeId = bookId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final path = '${booksDir.path}/$safeId-$stamp.${format.fileExtension}';
  try {
    await booksDir.create(recursive: true);
    final bytes = await files.copy(picked, path);
    if (bytes <= 0) {
      await _deleteQuietly(path);
      return 'The file could not be copied. Is it empty?';
    }
    await library.setLink(
      bookId,
      EbookLink(
        path: path,
        name: picked.name,
        bytes: bytes,
        format: format,
        addedAt: now(),
      ),
    );
  } catch (_) {
    await _deleteQuietly(path);
    return 'The file could not be copied. Is there room on this device?';
  } finally {
    await files.release(picked);
  }
  if (old != null && old.path != path) await _deleteQuietly(old.path);
  return null;
}

/// Forgets the book's file and deletes Chapterly's copy (not the original
/// you picked).
Future<void> removeBookFile(EbookLibrary library, String bookId) async {
  final link = await library.remove(bookId);
  if (link != null) await _deleteQuietly(link.path);
}

/// Deletes a copy, and the reader's page index saved beside it.
Future<void> _deleteQuietly(String path) async {
  for (final name in [path, '$path.locations']) {
    try {
      final file = File(name);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Left behind; it does no harm.
    }
  }
}
