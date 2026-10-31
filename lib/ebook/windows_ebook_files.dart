import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../audio/audio_files.dart';
import 'ebook_files.dart';

/// Book files on Windows: picked with the Open dialog and copied into
/// Chapterly's own folder.
class WindowsEbookFiles implements EbookFiles {
  const WindowsEbookFiles();

  @override
  Future<PickedFile?> pickBook() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Books (EPUB, PDF)', extensions: ['epub', 'pdf']),
      ],
    );
    if (file == null) return null;
    return PickedFile(location: file.path, name: file.name);
  }

  @override
  Future<int> copy(PickedFile picked, String path) async {
    final copy = await File(picked.location).copy(path);
    return copy.length();
  }

  @override
  Future<void> release(PickedFile picked) async {}
}
