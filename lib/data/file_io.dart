import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Hands files to and from the PC: save a file with the Save dialog, and pick
/// a file to open. (The phone app shares files instead; the method names are
/// the same so the screens work on both.)
class FileIo {
  const FileIo();

  /// Asks where to save [content] and writes it there. Does nothing if the
  /// dialog is cancelled.
  Future<void> shareText({
    required String fileName,
    required String content,
    required String mimeType,
    String? subject,
  }) async {
    final location = await getSaveLocation(suggestedName: fileName);
    if (location == null) return;
    await File(location.path).writeAsString(content);
  }

  /// Asks where to save the PNG [bytes] and writes them there.
  Future<void> shareImage({
    required String fileName,
    required List<int> bytes,
    String? subject,
  }) async {
    final location = await getSaveLocation(suggestedName: fileName);
    if (location == null) return;
    await File(location.path).writeAsBytes(bytes);
  }

  /// Lets the user pick any file and returns its text, or null if cancelled.
  Future<String?> pickTextFile() async {
    final file = await openFile();
    return file?.readAsString();
  }
}
