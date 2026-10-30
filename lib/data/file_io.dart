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

  /// Asks where to save [bytes] (a PDF, for example) and writes them there.
  /// Returns where it was saved, or null if the dialog was cancelled.
  Future<String?> saveBytes({
    required String fileName,
    required List<int> bytes,
    required String typeLabel,
    required List<String> extensions,
  }) async {
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [
        XTypeGroup(label: typeLabel, extensions: extensions),
      ],
    );
    if (location == null) return null;
    await File(location.path).writeAsBytes(bytes);
    return location.path;
  }

  /// Lets the user pick any file and returns its text, or null if cancelled.
  Future<String?> pickTextFile() async {
    final file = await openFile();
    return file?.readAsString();
  }
}
