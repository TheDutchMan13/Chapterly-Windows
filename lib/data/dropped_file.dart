import 'backup.dart';
import 'kindle_clippings.dart';

/// What kind of file was dropped on the window.
enum DroppedFileKind { backup, csv, kindle, unknown }

/// [text] without the invisible mark some Windows apps put at the start.
String stripBom(String text) =>
    text.startsWith('﻿') ? text.substring(1) : text;

/// Works out what a dropped file is from its name and contents.
DroppedFileKind detectDroppedFile(String name, String text) {
  final body = stripBom(text);
  if (body.contains('==========') && parseKindleClippings(body).isNotEmpty) {
    return DroppedFileKind.kindle;
  }
  if (body.trimLeft().startsWith('{')) {
    try {
      decodeBackup(body);
      return DroppedFileKind.backup;
    } catch (_) {
      return DroppedFileKind.unknown;
    }
  }
  if (name.toLowerCase().endsWith('.csv')) return DroppedFileKind.csv;
  return DroppedFileKind.unknown;
}
