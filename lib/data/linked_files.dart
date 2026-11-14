import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Which file or folder on this PC's drives belongs to which book. The file
/// stays where it is: Chapterly keeps only the path, and opens it with the
/// program Windows uses for that kind of file. The links belong to this PC
/// and are not synced or put in backups.
class LinkedFiles extends ChangeNotifier {
  LinkedFiles._(this._file, this._paths);

  final File? _file;
  final Map<String, String> _paths;

  /// Set up in main.dart. Null in tests and until set up, and the card on
  /// the book page stays hidden then.
  static LinkedFiles? shared;

  /// An empty set that is not saved anywhere, for tests.
  factory LinkedFiles.inMemory([Map<String, String> paths = const {}]) =>
      LinkedFiles._(null, {...paths});

  /// Reads the links from [file]. A missing or damaged file gives no links.
  static Future<LinkedFiles> load(File file) async {
    final paths = <String, String>{};
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map) {
        for (final entry in data.entries) {
          final value = entry.value;
          if (entry.key is String && value is String && value.isNotEmpty) {
            paths[entry.key as String] = value;
          }
        }
      }
    } on Object {
      // No file yet, or it can't be read: start with no links.
    }
    return LinkedFiles._(file, paths);
  }

  /// The path linked to the book, or null.
  String? pathFor(String bookId) => _paths[bookId];

  int get count => _paths.length;

  /// Every link, book id to path.
  Map<String, String> get paths => Map.unmodifiable(_paths);

  Future<void> link(String bookId, String path) async {
    _paths[bookId] = path;
    notifyListeners();
    await _save();
  }

  Future<void> unlink(String bookId) async {
    if (_paths.remove(bookId) == null) return;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_paths));
    } on Object {
      // The link still works until the app closes.
    }
  }
}

/// What a linked path is on disk right now.
enum LinkedKind { file, folder, missing }

LinkedKind linkedKindOf(String path) {
  try {
    if (FileSystemEntity.isDirectorySync(path)) return LinkedKind.folder;
    if (FileSystemEntity.isFileSync(path)) return LinkedKind.file;
  } on Object {
    // Treated as missing.
  }
  return LinkedKind.missing;
}

/// The file's name, or the folder's, without the folders above it.
String linkedName(String path) {
  final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
  final cut = trimmed.lastIndexOf(RegExp(r'[\\/]'));
  return cut < 0 ? trimmed : trimmed.substring(cut + 1);
}
